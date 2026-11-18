import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx_mobile/core/effect_catalog.dart';
import 'package:onyx_mobile/core/midi_protocol.dart';
import 'package:onyx_mobile/onyx_controller.dart';
import 'package:onyx_mobile/services/demo_transport.dart';
import 'package:onyx_mobile/services/midi_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OnyxController controller;
  setUp(() async {
    controller = OnyxController(catalog: await EffectCatalog.load());
    controller.setLiveSync(false);
  });
  tearDown(() async {
    await controller.disconnect(silent: true);
    controller.dispose();
  });

  test(
    'demo supports editing and saving the latest slider value immediately',
    () async {
      await controller.startDemo();
      expect(controller.state!.name, 'Amber Clean');
      expect(controller.isDemo, isTrue);
      controller.setKnob(2, 0, 91);
      controller.setKnob(2, 1, 68);
      await controller.saveCurrent();
      await controller.readPresets();
      expect(
        controller.bank!.presets[0]!.params[2][0],
        (91 * 65535 / 100).round(),
      );
      expect(
        controller.bank!.presets[0]!.params[2][1],
        (68 * 65535 / 100).round(),
      );
      await controller.nextPreset();
      expect(controller.state!.preset, 1);
      await controller.previousPreset();
      expect(controller.state!.effect(2).knobs[0], 91);
    },
  );

  test(
    'preset change flushes pending controls and blocks edits until state arrives',
    () async {
      final transport = RecordingTransport();
      await controller.connectTransport(() async => transport);
      controller.setKnob(2, 0, 98);
      final change = controller.selectPreset(1);
      expect(controller.busy, isTrue);
      controller.setKnob(2, 0, 2);
      await change;
      expect(transport.controls, [nrpn(1, 0x60, 98), programChange(1)]);
      expect(controller.state!.preset, 1);
      expect(controller.state!.effect(2).knobs[0], 42);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(transport.controls.length, 2);
    },
  );

  test(
    'backup and selective restore verifies byte-for-byte readback',
    () async {
      await controller.startDemo();
      await controller.readPresets();
      final original = controller.bank!,
          originalRecord = original.presets[0]!.toRecord();
      controller.setKnob(2, 0, 84);
      await controller.saveCurrent();
      await controller.readPresets();
      expect(controller.bank!.presets[0]!.toRecord(), isNot(originalRecord));
      controller.bank = original;
      await controller.restorePresets([0]);
      expect(controller.state!.effect(2).knobs[0], 42);
      await controller.readPresets();
      expect(controller.bank!.presets[0]!.toRecord(), originalRecord);
      expect(controller.logs.any((line) => line.contains('일치함을 확인')), isTrue);
      expect(controller.busy, isFalse);
    },
  );

  test(
    'restore stops at a corrupt readback rather than overwriting the next slot',
    () async {
      final transport = RecordingTransport();
      await controller.connectTransport(() async => transport);
      await controller.readPresets();
      transport.commands.clear();
      transport.tamper = true;
      await expectLater(controller.restorePresets([0, 1]), throwsStateError);
      expect(
        transport.commands
            .where((command) => command.type == 25)
            .map((command) => command.data[4]),
        [0],
      );
      expect(controller.busy, isFalse);
    },
  );

  test('cancelled opening cannot attach a stale transport', () async {
    final opening = Completer<MidiTransport>();
    final future = controller.connectTransport(() => opening.future);
    final expectation = expectLater(future, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await controller.disconnect(silent: true);
    final transport = DemoTransport();
    opening.complete(transport);
    await expectation;
    expect(controller.connected, isFalse);
    expect(transport.isOpen, isFalse);
  });

  test('background transition flushes the last pending slider value', () async {
    final transport = RecordingTransport();
    await controller.connectTransport(() async => transport);
    controller.setKnob(2, 0, 93);
    controller.setForeground(false);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(transport.controls, [nrpn(1, 0x60, 93)]);
    controller.setForeground(true);
    await controller.refresh();
    expect(controller.state!.effect(2).knobs[0], 93);
  });

  test(
    'backgrounding a transfer cancels the request and closes the transport',
    () async {
      final transport = RecordingTransport();
      await controller.connectTransport(() async => transport);
      await controller.readPresets();
      transport.uploadGate = Completer<void>();
      final restore = controller.restorePresets([0]);
      final expectation = expectLater(restore, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      controller.setForeground(false);
      await expectation;
      expect(transport.isOpen, isFalse);
      expect(controller.connected, isFalse);
      expect(controller.busy, isFalse);
      transport.uploadGate!.complete();
    },
  );
}

class RecordingTransport implements MidiTransport {
  final delegate = DemoTransport();
  final controls = <List<int>>[], commands = <MidiReply>[];
  bool tamper = false;
  Completer<void>? uploadGate;
  @override
  String get name => delegate.name;
  @override
  bool get isDemo => true;
  @override
  bool get isOpen => delegate.isOpen;
  @override
  int get uploadChunk => delegate.uploadChunk;
  @override
  Stream<List<int>> get frames => delegate.frames.map((frame) {
    final reply = parseFrame(frame);
    if (tamper && reply?.type == 0x63) {
      final data = reply!.data.toList()..[12] ^= 1;
      return buildFrame(0x63, data);
    }
    return frame;
  });
  @override
  Stream<String> get disconnectReasons => delegate.disconnectReasons;
  @override
  Future<void> send(List<int> bytes) {
    controls.add(bytes);
    return delegate.send(bytes);
  }

  @override
  Future<void> sendFrame(List<int> frame) {
    commands.add(parseFrame(frame)!);
    if (uploadGate != null && parseFrame(frame)!.type == 25) {
      return uploadGate!.future;
    }
    return delegate.sendFrame(frame);
  }

  @override
  Future<void> close() => delegate.close();
}
