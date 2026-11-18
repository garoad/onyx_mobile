import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../core/midi_protocol.dart';
import 'midi_transport.dart';

const _platform = MethodChannel('io.onyx.pocket.editor/platform');

class BluetoothService {
  FlutterReactiveBle? _client;
  NativeBleTransport? _opening;
  bool _requireLocationServices = false;
  FlutterReactiveBle get client => _client ??= FlutterReactiveBle();

  Future<void> prepare() async {
    if (Platform.isAndroid) {
      final sdk = await _platform.invokeMethod<int>('androidSdk') ?? 31;
      _requireLocationServices = sdk < 31;
      final granted =
          await _platform.invokeMethod<bool>('requestBluetoothPermissions') ??
          false;
      if (!granted) {
        throw StateError(
          'Bluetooth 검색 권한이 필요합니다. 앱 설정에서 근처 기기 권한을 허용해 주세요. Android 11 이하에서는 위치 권한도 필요합니다.',
        );
      }
    }
    var status = await client.statusStream
        .firstWhere((status) => status != BleStatus.unknown)
        .timeout(const Duration(seconds: 20));
    if (status == BleStatus.poweredOff && Platform.isAndroid) {
      final enabled =
          await _platform.invokeMethod<bool>('enableBluetooth') ?? false;
      if (enabled) {
        status = await client.statusStream
            .firstWhere(
              (status) =>
                  status != BleStatus.unknown && status != BleStatus.poweredOff,
            )
            .timeout(const Duration(seconds: 8));
      }
    }
    switch (status) {
      case BleStatus.ready:
        return;
      case BleStatus.unauthorized:
        throw StateError(
          'Bluetooth 접근 권한이 필요합니다. 앱 설정에서 Bluetooth·근처 기기 권한을 허용해 주세요.',
        );
      case BleStatus.poweredOff:
        throw StateError(
          'Bluetooth가 꺼져 있습니다. 휴대폰 설정에서 Bluetooth를 켜고 다시 검색해 주세요.',
        );
      case BleStatus.locationServicesDisabled:
        if (!_requireLocationServices) return;
        throw StateError('Android 11 이하에서는 Bluetooth 검색을 위해 위치 서비스를 켜야 합니다.');
      case BleStatus.unsupported:
        throw StateError(
          '이 기기에서는 Bluetooth LE를 사용할 수 없습니다. 실제 Android 휴대폰 또는 iPhone에서 실행해 주세요.',
        );
      case BleStatus.unknown:
        throw StateError('Bluetooth 상태를 확인할 수 없습니다. 다시 검색해 주세요.');
    }
  }

  Stream<DiscoveredDevice> scan({bool allDevices = false}) =>
      client.scanForDevices(
        withServices: allDevices ? [] : [Uuid.parse(midiServiceUuid)],
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: _requireLocationServices,
      );

  Future<MidiTransport> connect(DiscoveredDevice device) async {
    NativeBleTransport? opening;
    try {
      return await NativeBleTransport.open(
        client,
        device,
        onOpening: (link) {
          _opening = opening = link;
        },
      );
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  Future<void> cancelOpening() async {
    final opening = _opening;
    _opening = null;
    await opening?.close();
  }

  Future<void> openSettings() async {
    await _platform.invokeMethod<bool>('openAppSettings');
  }
}

class NativeBleTransport implements MidiTransport {
  final DiscoveredDevice _device;
  final StreamController<List<int>> _frames = StreamController.broadcast();
  final StreamController<String> _disconnects = StreamController.broadcast();
  final BleUnframer _unframer = BleUnframer();
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifications;
  MidiWriter? _writer;
  bool _open = true;
  bool _intentional = false;
  Future<void>? _closing;
  Completer<void>? _ready;

  NativeBleTransport._(this._device);

  static Future<NativeBleTransport> open(
    FlutterReactiveBle ble,
    DiscoveredDevice device, {
    void Function(NativeBleTransport)? onOpening,
  }) async {
    final transport = NativeBleTransport._(device);
    final connected = Completer<void>();
    transport._ready = connected;
    unawaited(connected.future.then<void>((_) {}, onError: (Object _) {}));
    onOpening?.call(transport);
    transport._connection = ble
        .connectToDevice(
          id: device.id,
          servicesWithCharacteristicsToDiscover: {
            Uuid.parse(midiServiceUuid): [Uuid.parse(midiCharacteristicUuid)],
          },
          connectionTimeout: const Duration(seconds: 15),
        )
        .listen(
          (update) {
            if (update.connectionState == DeviceConnectionState.connected &&
                !connected.isCompleted) {
              connected.complete();
            }
            if (update.connectionState == DeviceConnectionState.disconnected) {
              if (!connected.isCompleted) {
                connected.completeError(
                  StateError('앰프와 연결할 수 없습니다. 다른 편집 앱의 연결을 종료하고 다시 시도해 주세요.'),
                );
              }
              transport._lost('Bluetooth 연결이 끊어졌습니다. 다시 연결해 주세요.');
            }
          },
          onError: (Object error) {
            if (!connected.isCompleted) connected.completeError(error);
            transport._lost('Bluetooth 연결에 실패했습니다: $error');
          },
        );
    try {
      await connected.future.timeout(const Duration(seconds: 18));
      if (!transport._open) throw StateError('Bluetooth 연결이 끊어졌습니다.');
      final services = await ble
          .getDiscoveredServices(device.id)
          .timeout(const Duration(seconds: 10));
      Characteristic? midi;
      for (final service in services) {
        if (service.id != Uuid.parse(midiServiceUuid)) continue;
        for (final characteristic in service.characteristics) {
          if (characteristic.id == Uuid.parse(midiCharacteristicUuid)) {
            midi = characteristic;
          }
        }
      }
      if (midi == null ||
          !midi.isNotifiable ||
          !midi.isWritableWithoutResponse) {
        throw StateError(
          '이 기기는 Pocket AMP BLE-MIDI를 지원하지 않습니다. 앰프의 MIDI 기기를 선택해 주세요.',
        );
      }
      final characteristic = midi;
      transport._notifications = characteristic.subscribe().listen(
        (packet) {
          if (!transport._open) return;
          for (final frame in transport._unframer.push(packet)) {
            transport._frames.add(frame);
          }
        },
        onError: (Object error) {
          transport._lost('앰프의 Bluetooth 데이터를 읽을 수 없습니다. 다시 연결해 주세요.');
          unawaited(transport.close());
        },
      );
      transport._writer = MidiWriter(
        (packet) async {
          if (!transport._open) throw StateError('Bluetooth 연결이 끊어졌습니다.');
          await characteristic
              .write(packet, withResponse: false)
              .timeout(const Duration(seconds: 5));
        },
        onError: (error) {
          transport._lost('앰프로 전송할 수 없습니다. 다시 연결해 주세요.');
          unawaited(transport.close());
        },
      );
      // CCCD subscription is started by the native stream; allow one connection event before querying.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!transport._open) throw StateError('Bluetooth 연결이 끊어졌습니다.');
      return transport;
    } catch (_) {
      await transport.close();
      rethrow;
    }
  }

  void _lost(String reason) {
    if (!_open) return;
    _open = false;
    _writer?.close();
    if (!_intentional && !_disconnects.isClosed) _disconnects.add(reason);
  }

  @override
  String get name => _device.name.isEmpty ? 'Pocket AMP' : _device.name;
  @override
  bool get isDemo => false;
  @override
  bool get isOpen => _open;
  @override
  int get uploadChunk => 100;
  @override
  Stream<List<int>> get frames => _frames.stream;
  @override
  Stream<String> get disconnectReasons => _disconnects.stream;
  @override
  Future<void> send(List<int> bytes) => _writer!.send(bytes);
  @override
  Future<void> sendFrame(List<int> frame) => _writer!.send(frame, sysex: true);

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _intentional = true;
    _open = false;
    if (_ready != null && !_ready!.isCompleted) {
      _ready!.completeError(StateError('연결이 취소되었습니다.'));
    }
    _writer?.close();
    await _notifications?.cancel();
    await _connection?.cancel();
    await _frames.close();
    await _disconnects.close();
  }
}
