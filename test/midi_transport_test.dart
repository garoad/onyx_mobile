import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx_mobile/core/midi_protocol.dart';
import 'package:onyx_mobile/services/midi_transport.dart';

void main() {
  test('NRPN transactions do not interleave with controls or SysEx', () async {
    final packets = <List<int>>[];
    final writer = MidiWriter((packet) async {
      packets.add(packet);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }, pace: Duration.zero);
    final first = nrpn(1, 0x60, 91),
        second = nrpn(6, 0x62, 37),
        frame = buildFrame(80);
    await Future.wait([
      writer.send(first),
      writer.send(second),
      writer.send(frame, sysex: true),
    ]);
    final controlPackets = packets
        .take(8)
        .expand((packet) => packet.skip(2))
        .toList();
    expect(controlPackets, [...first, ...second]);
    expect(packets.skip(8).expand(BleUnframer().push).toList(), [frame]);
    writer.close();
  });

  test(
    'request queue serializes calls and ignores replies for another slot',
    () async {
      final transport = ManualTransport(),
          queue = MidiRequestQueue(() => transport);
      final first = queue.request(81, [0, 0], 0x61),
          second = queue.request(81, [1, 0], 0x61);
      await Future<void>.delayed(Duration.zero);
      expect(transport.sent.length, 1);
      queue.receive(buildFrame(0x61, [1, 0, 0, 0, 20]));
      await Future<void>.delayed(Duration.zero);
      expect(transport.sent.length, 1);
      queue.receive(buildFrame(0x61, [0, 0, 0, 0, 20]));
      expect(await first, [0, 0, 0, 0, 20]);
      await Future<void>.delayed(Duration.zero);
      expect(transport.sent.length, 2);
      queue.receive(buildFrame(0x61, [1, 0, 0, 0, 20]));
      expect(await second, [1, 0, 0, 0, 20]);
      queue.cancel();
      await transport.close();
    },
  );

  test(
    'cancellation immediately rejects a request even while native write waits',
    () async {
      final transport = ManualTransport()..writeGate = Completer<void>();
      final queue = MidiRequestQueue(() => transport);
      final first = queue.request(80, [], 0x60),
          second = queue.request(80, [], 0x60);
      final expectations = [
        expectLater(first, throwsStateError),
        expectLater(second, throwsStateError),
      ];
      await Future<void>.delayed(Duration.zero);
      queue.cancel('작업 취소');
      await Future.wait(expectations);
      expect(transport.sent.length, 1);
      transport.writeGate!.complete();
      await transport.close();
    },
  );

  test('a failed BLE writer closes and rejects subsequent writes', () async {
    var errors = 0;
    final writer = MidiWriter(
      (packet) async => throw StateError('link lost'),
      onError: (_) {
        errors++;
      },
    );
    await expectLater(writer.send(controlChange(88, 127)), throwsStateError);
    await expectLater(writer.send(programChange(0)), throwsStateError);
    expect(errors, 1);
  });
}

class ManualTransport implements MidiTransport {
  final sent = <List<int>>[];
  Completer<void>? writeGate;
  bool _open = true;
  @override
  String get name => 'Manual';
  @override
  bool get isDemo => false;
  @override
  bool get isOpen => _open;
  @override
  int get uploadChunk => 100;
  @override
  Stream<List<int>> get frames => const Stream.empty();
  @override
  Stream<String> get disconnectReasons => const Stream.empty();
  @override
  Future<void> send(List<int> bytes) async {
    sent.add(bytes);
    await writeGate?.future;
  }

  @override
  Future<void> sendFrame(List<int> frame) => send(frame);
  @override
  Future<void> close() async {
    _open = false;
  }
}
