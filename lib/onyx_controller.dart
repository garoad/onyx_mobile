import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/amp_state.dart';
import 'core/effect_catalog.dart';
import 'core/midi_protocol.dart';
import 'core/presets.dart';
import 'core/sound_files.dart';
import 'services/bluetooth_service.dart';
import 'services/demo_transport.dart';
import 'services/file_service.dart';
import 'services/midi_transport.dart';

enum ConnectionPhase { disconnected, connecting, connected }

class OnyxController extends ChangeNotifier {
  final EffectCatalog catalog;
  final BluetoothService bluetooth;
  final FileService files;
  late final MidiRequestQueue _requests;
  MidiTransport? _transport;
  StreamSubscription<List<int>>? _frames;
  StreamSubscription<String>? _lost;
  final _messages = StreamController<String>.broadcast();
  final Map<String, Timer> _throttles = {};
  final Map<String, List<int>> _pendingControls = {};
  Timer? _poll, _readSoon;
  bool _disposed = false, _foreground = true, _refreshing = false;
  bool _deviceOperation = false;
  int _generation = 0, _revision = 0, _refreshFailures = 0;
  Uint8List? _abkx;
  ConnectionPhase phase = ConnectionPhase.disconnected;
  AmpState? state;
  ModelDirectory models = const ModelDirectory();
  String firmwareBuild = '',
      status = '연결되지 않음',
      operation = '',
      bankName = 'onyx-presets.json';
  String? lastDeviceName, lastDeviceId;
  bool busy = false, liveSync = true;
  double progress = 0;
  PresetBank? bank;
  SoundFile? cabinetFile, captureFile;
  BankConversionOptions conversionOptions = const BankConversionOptions();
  final List<String> logs = [];

  OnyxController({
    required this.catalog,
    BluetoothService? bluetooth,
    FileService? files,
  }) : bluetooth = bluetooth ?? BluetoothService(),
       files = files ?? FileService() {
    _requests = MidiRequestQueue(() => _foreground ? _transport : null);
  }

  bool get connected => phase == ConnectionPhase.connected && state != null;
  bool get isDemo => _transport?.isDemo ?? false;
  bool get canEdit => connected && !busy && _foreground;
  String get deviceName => _transport?.name ?? '';
  Stream<String> get messages => _messages.stream;
  bool get canConvertBank => _abkx != null;

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    lastDeviceName = prefs.getString('last-device-name');
    lastDeviceId = prefs.getString('last-device-id');
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void log(String message) {
    logs.add('${DateTime.now().toIso8601String().substring(11, 19)}  $message');
    if (logs.length > 200) logs.removeRange(0, logs.length - 200);
  }

  void announce(String message) {
    log(message);
    if (!_messages.isClosed) _messages.add(message);
    _notify();
  }

  Future<void> connectDevice(DiscoveredDevice device) async {
    await connectTransport(() => bluetooth.connect(device));
    if (!connected) return;
    final name = deviceName;
    lastDeviceName = name;
    lastDeviceId = device.id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last-device-name', name);
      await prefs.setString('last-device-id', device.id);
    } catch (_) {
      /* Device history is optional. */
    }
  }

  Future<void> startDemo() => connectTransport(() async => DemoTransport());

  Future<void> connectTransport(Future<MidiTransport> Function() open) async {
    if (busy || phase == ConnectionPhase.connecting) {
      throw StateError('진행 중인 작업이 끝난 후 연결해 주세요.');
    }
    await disconnect(silent: true);
    final generation = ++_generation;
    phase = ConnectionPhase.connecting;
    status = '앰프 연결 중…';
    _notify();
    MidiTransport? link;
    try {
      link = await open();
      if (generation != _generation || !link.isOpen) {
        throw StateError('연결이 취소되었습니다.');
      }
      _transport = link;
      _frames = link.frames.listen(_requests.receive);
      _lost = link.disconnectReasons.listen((reason) {
        if (generation == _generation) {
          announce(reason);
          unawaited(disconnect(reason: reason, silent: true));
        }
      });
      status = 'Onyx 펌웨어 확인 중…';
      _notify();
      state = AmpState.decode(await _request(80, [], 0x60));
      await _readModels();
      try {
        final data = await _request(81, [255, 0], 0x61);
        firmwareBuild = String.fromCharCodes(data.skip(5).take(data[3]));
      } on TimeoutException {
        firmwareBuild = '';
      }
      if (generation != _generation || !link.isOpen) {
        throw StateError('연결이 취소되었습니다.');
      }
      phase = ConnectionPhase.connected;
      status = link.isDemo ? '데모 모드' : '연결됨';
      _refreshFailures = 0;
      _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        if (liveSync) unawaited(refresh());
      });
      announce(
        link.isDemo ? '데모 모드입니다. 자유롭게 톤을 조절해 보세요.' : '${link.name}에 연결되었습니다.',
      );
    } catch (error) {
      if (generation == _generation) {
        await disconnect(reason: friendlyError(error), silent: true);
      } else {
        await link?.close();
      }
      rethrow;
    }
  }

  Future<void> disconnect({
    String reason = '연결되지 않음',
    bool silent = false,
  }) async {
    _generation++;
    _revision++;
    _poll?.cancel();
    _readSoon?.cancel();
    for (final timer in _throttles.values) {
      timer.cancel();
    }
    _throttles.clear();
    _pendingControls.clear();
    _requests.cancel(reason);
    final previous = _transport;
    _transport = null;
    state = null;
    models = const ModelDirectory();
    firmwareBuild = '';
    phase = ConnectionPhase.disconnected;
    status = reason;
    _refreshing = false;
    await _frames?.cancel();
    _frames = null;
    await _lost?.cancel();
    _lost = null;
    _notify();
    await bluetooth.cancelOpening();
    if (previous != null) {
      await previous.close();
      if (!silent) announce(previous.isDemo ? '데모를 종료했습니다.' : '앰프 연결을 해제했습니다.');
    }
  }

  Future<List<int>> _request(int command, List<int> data, int reply) =>
      _requests.request(command, data, reply);

  Future<(List<String>, int)> _names(int kind) async {
    final names = <String>[];
    var first = 20, start = 0, total = 1;
    while (start < total) {
      final data = await _request(81, [kind, start], 0x61);
      total = data[1];
      final count = data[3];
      first = data[4];
      if (count == 0) {
        if (start < total) throw const FormatException('앰프의 모델 목록이 잘못되었습니다.');
        break;
      }
      if (data.length < 5 + count * 16 || start + count > total) {
        throw const FormatException('앰프의 모델 목록이 잘렸습니다.');
      }
      for (var index = 0; index < count; index++) {
        names.add(
          String.fromCharCodes(
            data
                .sublist(5 + index * 16, 21 + index * 16)
                .where((byte) => byte != 0),
          ),
        );
      }
      start += count;
    }
    return (names, first);
  }

  Future<void> _readModels() async {
    final amps = await _names(0), cabinets = await _names(1);
    models = ModelDirectory(
      amps: amps.$1,
      firstCapture: amps.$2,
      cabinets: cabinets.$1,
      firstCabinet: cabinets.$2,
    );
  }

  Future<void> _readState() async {
    final generation = _generation;
    final next = AmpState.decode(await _request(80, [], 0x60));
    if (generation != _generation) throw StateError('연결이 변경되었습니다.');
    state = next;
    _notify();
  }

  Future<void> refresh() async {
    if (!connected ||
        busy ||
        !_foreground ||
        _refreshing ||
        _throttles.isNotEmpty) {
      return;
    }
    _refreshing = true;
    final generation = _generation, revision = _revision;
    try {
      final next = AmpState.decode(await _request(80, [], 0x60));
      if (generation != _generation || !_foreground) return;
      if (revision == _revision) state = next;
      _refreshFailures = 0;
      _notify();
    } catch (error) {
      if (generation != _generation || !_foreground) return;
      log(friendlyError(error));
      if (++_refreshFailures >= 3) {
        announce('앰프가 응답하지 않습니다. 다시 연결해 주세요.');
        await disconnect(reason: '앰프 연결을 확인해 주세요', silent: true);
      }
    } finally {
      _refreshing = false;
    }
  }

  void _patch(Map<int, int> values) {
    if (state != null) {
      state = state!.patch(values);
      _revision++;
      _notify();
    }
  }

  void _throttle(String key, List<int> bytes) {
    _throttles.remove(key)?.cancel();
    _pendingControls[key] = bytes;
    _throttles[key] = Timer(const Duration(milliseconds: 45), () {
      unawaited(
        _control(const []).catchError((Object error) {
          if (!_disposed) announce(friendlyError(error));
        }),
      );
    });
  }

  List<int> _takePendingControls() {
    for (final timer in _throttles.values) {
      timer.cancel();
    }
    _throttles.clear();
    final bytes = _pendingControls.values.expand((message) => message).toList();
    _pendingControls.clear();
    return bytes;
  }

  Future<void> _control(List<int> bytes) async {
    if (!canEdit) return;
    final link = _transport!, generation = _generation;
    final transaction = [..._takePendingControls(), ...bytes];
    if (transaction.isEmpty) return;
    _revision++;
    await link.send(transaction);
    if (generation != _generation) return;
    _readSoon?.cancel();
    _readSoon = Timer(const Duration(milliseconds: 300), () {
      unawaited(refresh());
    });
  }

  void setKnob(int slot, int knob, int value) {
    if (!canEdit) return;
    _patch({24 + slot * 8 + knob: value});
    _throttle('slot:$slot:$knob', nrpn(slotModules[slot], 0x60 + knob, value));
  }

  Future<void> toggleEffect(int slot) async {
    if (!canEdit) return;
    final enabled = !state!.effect(slot).enabled;
    _patch({22 + slot * 8: enabled ? 1 : 0});
    await _control(controlChange(28 + slotModules[slot], enabled ? 127 : 0));
  }

  Future<void> setModel(int slot, int model) async {
    if (!canEdit) return;
    _patch({23 + slot * 8: model});
    await _control(nrpn(slotModules[slot], 0x40, model + 0x20, raw: true));
  }

  void setPresetVolume(int value) {
    if (canEdit) {
      _patch({4: value});
      _throttle('preset-volume', nrpn(10, 0, value, raw: true));
    }
  }

  void setGlobal(int parameter, int value) {
    if (!canEdit) return;
    const offsets = [
      86,
      87,
      5,
      88,
      89,
      90,
      91,
      92,
      93,
      94,
      95,
      96,
      97,
      98,
      99,
      100,
      101,
      102,
    ];
    if (parameter < offsets.length) _patch({offsets[parameter]: value});
    if (parameter == 18) {
      _patch({3: (state!.flags & ~8) | (value != 0 ? 8 : 0)});
    }
    if (parameter == 19) {
      _patch({3: (state!.flags & ~(3 << 5)) | ((value & 3) << 5)});
    }
    _throttle('global:$parameter', nrpn(8, parameter, value, raw: true));
  }

  void setGroove(int parameter, int value) {
    if (!canEdit) return;
    if (parameter == 1) {
      _patch({106: (40 + value) & 255, 107: (40 + value) >> 8});
    }
    if (parameter >= 2 && parameter <= 4) _patch({106 + parameter: value});
    _throttle('groove:$parameter', nrpn(9, parameter, value, raw: true));
  }

  Future<void> toggleGroove() async {
    if (canEdit) {
      final play = !state!.groovePlaying;
      _patch({3: (state!.flags & ~4) | (play ? 4 : 0)});
      await _control(controlChange(86, play ? 127 : 0));
    }
  }

  Future<void> toggleTuner() => _control(controlChange(85, 127));
  Future<void> _changePreset(List<int> command) =>
      _exclusive('프리셋 불러오는 중', () async {
        await _transport!.send(command);
        await _readState();
      });
  Future<void> selectPreset(int slot) => _changePreset(programChange(slot));
  Future<void> nextPreset() => _changePreset(controlChange(80, 127));
  Future<void> previousPreset() => _changePreset(controlChange(81, 127));
  Future<void> saveCurrent() => _exclusive('현재 톤 저장 중', () async {
    await _transport!.send(controlChange(88, 127));
    await _readState();
    announce(isDemo ? '데모 톤을 저장했습니다.' : '현재 톤의 저장 명령을 보냈습니다.');
  });
  Future<void> setStomp(int key, int module) async {
    if (canEdit) {
      _patch({111 + key: slotModules.indexOf(module)});
      await _control(nrpn(10, 3 + key, module, raw: true));
    }
  }

  Future<void> reorder(int slot, int position) async {
    if (!canEdit) return;
    state = state!.withOrder(moveSlot(state!.order, slot, position));
    _revision++;
    _notify();
    await _control(moveSlotMessage(slot, position));
  }

  void setLiveSync(bool value) {
    liveSync = value;
    _notify();
    if (value) unawaited(refresh());
  }

  Future<T> _exclusive<T>(
    String label,
    Future<T> Function() work, {
    bool requireDevice = true,
  }) async {
    if (busy) throw StateError('진행 중인 작업이 끝난 후 다시 시도해 주세요.');
    if (requireDevice && !connected) throw StateError('앰프를 먼저 연결해 주세요.');
    if (requireDevice && !_foreground) {
      throw StateError('앱으로 돌아온 뒤 다시 시도해 주세요.');
    }
    final pending = _takePendingControls(), link = _transport;
    _revision++;
    busy = true;
    _deviceOperation = requireDevice;
    operation = label;
    progress = 0;
    _notify();
    try {
      if (pending.isNotEmpty && link != null && link.isOpen) {
        await link.send(pending);
      }
      return await work();
    } finally {
      busy = false;
      _deviceOperation = false;
      operation = '';
      progress = 0;
      _notify();
    }
  }

  Future<void> readPresets() => _exclusive('80개 프리셋 읽는 중', () async {
    final presets = List<OnyxPreset?>.filled(80, null), unreadable = <int>{};
    for (var slot = 0; slot < 80; slot++) {
      final data = await _request(83, [slot], 0x63);
      final record = data.skip(2).take(presetSize).toList();
      if (data[1] == 0 && recordValid(record)) {
        presets[slot] = OnyxPreset.fromRecord(slot, record);
      } else {
        unreadable.add(slot);
      }
      progress = (slot + 1) / 80;
      _notify();
    }
    bank = PresetBank(presets, unreadable: unreadable);
    bankName = isDemo ? 'onyx-demo-presets.json' : 'onyx-presets.json';
    _abkx = null;
    announce(
      '${bank!.readableCount}개 프리셋을 읽었습니다${unreadable.isEmpty ? '' : ' · 읽기 실패 ${unreadable.length}개'}. 파일로 저장해 주세요.',
    );
  });

  Future<void> importBank() => _exclusive('프리셋 파일 읽는 중', () async {
    final file = await files.pick(['.json', '.abkx']);
    if (file == null) return;
    bank = null;
    _abkx = null;
    final next = await compute(_parseBank, (
      file.bytes,
      file.name,
      conversionOptions,
    ));
    bank = next;
    bankName = '${file.name.replaceFirst(RegExp(r'\.[^.]*$'), '')}.json';
    if (file.name.toLowerCase().endsWith('.abkx')) _abkx = file.bytes;
    announce('${file.name} · ${next.readableCount}개 프리셋을 가져왔습니다.');
  }, requireDevice: false);

  void convertBank(BankConversionOptions options) {
    conversionOptions = options;
    if (_abkx != null && !busy) {
      try {
        bank = convertAbkx(_abkx!, options: options);
      } catch (error) {
        bank = null;
        announce(friendlyError(error));
      }
    }
    _notify();
  }

  Future<void> pickCabinet() => _exclusive('IR 파일 변환 중', () async {
    final file = await files.pick(['.wav', '.bin', '.cab', '.q18', '.ir']);
    if (file == null) return;
    cabinetFile = null;
    cabinetFile = await compute(_parseCabinet, (file.bytes, file.name));
    announce(cabinetFile!.description);
  }, requireDevice: false);
  Future<void> pickCapture() => _exclusive('NAM 파일 확인 중', () async {
    final file = await files.pick([
      '.nam',
      '.namb',
      '.json',
      '.bin',
      '.am3',
      '.am4',
      '.wave',
    ]);
    if (file == null) return;
    captureFile = null;
    captureFile = await compute(_parseCapture, (file.bytes, file.name));
    announce(captureFile!.description);
  }, requireDevice: false);

  Future<void> restorePresets(List<int> slots) =>
      _exclusive('프리셋 복원·검증 중', () async {
        final source = bank;
        if (source == null) throw StateError('프리셋 백업 파일을 먼저 가져와 주세요.');
        final selected = slots
            .where((slot) => source.presets[slot] != null)
            .toList();
        if (selected.isEmpty) throw StateError('복원할 프리셋이 없습니다.');
        for (var index = 0; index < selected.length; index++) {
          final slot = selected[index],
              record = source.presets[selected[index]]!.toRecord();
          await _upload(record, 4, slot);
          final readback = await _request(83, [slot], 0x63);
          if (readback[1] != 0 || !listEquals(readback.sublist(2), record)) {
            throw StateError('P${slot + 1} 검증에 실패했습니다. 복원을 중단했습니다.');
          }
          progress = (index + 1) / selected.length;
          _notify();
        }
        final current = state!.preset;
        if (selected.contains(current)) {
          await _transport!.send(programChange(current));
        }
        await _readState();
        announce('${selected.length}개 프리셋을 복원했고, 다시 읽어 일치함을 확인했습니다.');
      });

  Future<void> _upload(
    Uint8List bytes,
    int target,
    int slot, {
    void Function(double)? onProgress,
  }) async {
    List<int> ack = [];
    for (var tries = 0; tries < 6; tries++) {
      try {
        ack = await _request(25, [
          bytes.length & 255,
          (bytes.length >> 8) & 255,
          (bytes.length >> 16) & 255,
          target,
          slot,
        ], 0x64);
      } on TimeoutException {
        throw StateError('데이터 전송에는 전송 확인을 지원하는 Onyx 1.13 이상이 필요합니다.');
      }
      if (ack.length < 4) throw const FormatException('전송 확인 데이터가 잘못되었습니다.');
      if (ack[3] != 2) break;
      if (tries == 5) throw StateError('앰프가 전송을 거부했습니다.');
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    int offsetOf(List<int> reply) {
      if (reply.length < 4) throw const FormatException('전송 확인 데이터가 잘렸습니다.');
      if (reply[3] > 3) throw const FormatException('알 수 없는 전송 확인 상태입니다.');
      final offset = reply[0] | reply[1] << 8 | reply[2] << 16;
      if (offset > bytes.length) {
        throw const FormatException('앰프의 전송 위치가 잘못되었습니다.');
      }
      return offset;
    }

    var offset = offsetOf(ack), losses = 0;
    if (ack[3] == 3) throw StateError('앰프가 전송을 시작할 수 없습니다.');
    while (offset < bytes.length) {
      final end = (offset + _transport!.uploadChunk).clamp(0, bytes.length);
      try {
        ack = await _request(34, bytes.sublist(offset, end), 0x64);
      } on TimeoutException {
        if (++losses > 8) throw StateError('앰프가 전송에 응답하지 않습니다.');
        ack = await _request(34, [], 0x64);
      }
      final got = offsetOf(ack);
      if (ack[3] == 2 || ack[3] == 3) {
        throw StateError('앰프가 데이터 전송을 거부했습니다 (${ack[3]}).');
      }
      if (ack[3] == 1) {
        if (got != bytes.length) throw StateError('앰프가 불완전한 전송을 완료했다고 보고했습니다.');
        onProgress?.call(1);
        return;
      }
      if (got != end && ++losses > 12) {
        throw StateError('앰프가 데이터를 계속 놓칩니다. 연결 상태를 확인해 주세요.');
      }
      offset = got;
      onProgress?.call(offset / bytes.length);
    }
    if (ack[3] != 1) throw StateError('앰프가 전송 완료를 확인하지 않았습니다.');
  }

  Future<void> uploadCabinet({
    bool temporary = false,
    int? replaceIndex,
    SoundFile? file,
  }) => _exclusive(temporary ? 'IR 임시 적용 중' : '캐비닛 IR 저장 중', () async {
    if (isDemo) throw StateError('데모에서는 IR 전송을 사용할 수 없습니다.');
    final source = file ?? cabinetFile;
    if (source == null) throw StateError('IR 파일을 먼저 선택해 주세요.');
    final previous = models.stored(1).map((model) => model.index).toSet();
    await _upload(
      source.bytes,
      2,
      temporary ? 0xfe : replaceIndex ?? 0xff,
      onProgress: (value) {
        progress = value;
        _notify();
      },
    );
    await _readModels();
    await _readState();
    if (temporary) {
      if (!state!.temporaryCabinet) throw StateError('앰프에 임시 IR이 적용되지 않았습니다.');
    } else if (replaceIndex == null) {
      final added = models
          .stored(1)
          .where((model) => !previous.contains(model.index))
          .firstOrNull;
      if (added == null) {
        throw StateError('앰프가 새 IR을 저장하지 않았습니다. 빈 슬롯과 파일을 확인해 주세요.');
      }
      final name = source.name
          .replaceFirst(RegExp(r'\.[^.]*$'), '')
          .replaceAll(RegExp(r'[^\x20-\x7e]'), '_')
          .trim();
      if (name.isNotEmpty) {
        await _userOperation(
          1,
          1,
          added.index,
          name.substring(0, name.length.clamp(0, 15)),
        );
        await _readModels();
      }
      await _transport!.send(nrpn(5, 0x40, added.type + 0x20, raw: true));
      await _readState();
    }
    announce(temporary ? '임시 IR이 적용되었습니다.' : '캐비닛 IR 전송이 확인되었습니다.');
  });

  Future<void> _userOperation(
    int operation,
    int kind,
    int index, [
    String name = '',
  ]) async {
    final data = await _request(82, [
      operation,
      kind,
      index,
      ...name.codeUnits,
    ], 0x62);
    if (data[3] != 0) throw StateError('앰프가 작업을 거부했습니다 (${data[3]}).');
  }

  Future<void> renameModel(int kind, StoredModel model, String name) =>
      _exclusive('모델 이름 변경 중', () async {
        final limit = kind == 0 ? 23 : 15;
        if (name.isEmpty ||
            name.length > limit ||
            name.codeUnits.any((unit) => unit < 32 || unit > 126)) {
          throw FormatException('이름은 영문·숫자·기호 $limit자 이내로 입력해 주세요.');
        }
        await _userOperation(1, kind, model.index, name);
        await _readModels();
        await _readState();
        announce('이름을 변경했습니다.');
      });
  Future<void> deleteModel(int kind, StoredModel model) =>
      _exclusive('모델 삭제 중', () async {
        await _userOperation(0, kind, model.index);
        await _readModels();
        await _readState();
        announce('${model.name}을 삭제했습니다.');
      });
  Future<void> clearModels(int kind) => _exclusive('모델 전체 삭제 중', () async {
    await _userOperation(2, kind, 0);
    await _readModels();
    await _readState();
    announce(kind == 0 ? '저장된 캡처를 모두 삭제했습니다.' : '저장된 캐비닛을 모두 삭제했습니다.');
  });

  void setForeground(bool active) {
    if (_disposed || active == _foreground) return;
    if (!active && canEdit && _pendingControls.isNotEmpty) {
      unawaited(
        _control(const []).catchError((Object error) {
          announce(friendlyError(error));
        }),
      );
    }
    _foreground = active;
    if (!active && busy && _deviceOperation) {
      const message = '앱이 백그라운드로 이동해 전송을 중단했습니다. 다시 연결한 뒤 기기의 상태를 확인해 주세요.';
      _requests.cancel(message);
      unawaited(_transport?.close());
      unawaited(disconnect(reason: message, silent: true));
      announce(message);
    }
    _notify();
    if (active) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _readSoon?.cancel();
    for (final timer in _throttles.values) {
      timer.cancel();
    }
    _requests.cancel();
    unawaited(_frames?.cancel());
    unawaited(_lost?.cancel());
    unawaited(_transport?.close());
    unawaited(_messages.close());
    super.dispose();
  }
}

PresetBank _parseBank((Uint8List, String, BankConversionOptions) input) =>
    input.$2.toLowerCase().endsWith('.abkx')
    ? convertAbkx(input.$1, options: input.$3)
    : PresetBank.fromJson(
        jsonDecode(utf8.decode(input.$1).replaceFirst(RegExp('^\ufeff'), '')),
      );
SoundFile _parseCabinet((Uint8List, String) input) =>
    readCabinet(input.$1, input.$2);
SoundFile _parseCapture((Uint8List, String) input) =>
    readCapture(input.$1, input.$2);
String friendlyError(Object error) => error.toString().replaceFirst(
  RegExp(r'^(Bad state: |FormatException: |TimeoutException: |Exception: )'),
  '',
);
