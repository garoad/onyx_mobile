import 'package:flutter_test/flutter_test.dart';
import 'package:onyx_mobile/core/amp_state.dart';
import 'package:onyx_mobile/core/midi_protocol.dart';

void main() {
  test('state query matches the firmware wire format', () {
    expect(buildFrame(80), [0xf0, 0, 50, 65, 2, 0, 0, 64, 87, 0xf7]);
    expect(pack8To7([0, 255, 128, 127, 1, 2, 3]), [
      0,
      126,
      3,
      124,
      23,
      64,
      64,
      1,
    ]);
    expect(unpack7To8([0, 126, 3, 124, 23, 64, 64, 1]), [
      0,
      255,
      128,
      127,
      1,
      2,
      3,
    ]);
    final reply = parseFrame(buildFrame(0x63, [79, 0, 128, 255]));
    expect(reply?.type, 0x63);
    expect(reply?.data, [79, 0, 128, 255]);
  });

  test('corrupt, truncated and oversized messages are rejected', () {
    final frame = buildFrame(80)..[4] ^= 1;
    expect(parseFrame(frame), isNull);
    expect(parseFrame(buildFrame(80).sublist(1)), isNull);
    expect(parseFrame([0xf0, 128, 0xf7]), isNull);
    expect(() => buildFrame(25, List.filled(257, 0)), throwsArgumentError);
  });

  test('BLE fragments reassemble at every timestamp, including F0 and F7', () {
    final frame = buildFrame(0x63, List.generate(166, (index) => index & 255));
    for (final time in [0, 111, 112, 119, 127, 8191]) {
      for (final packetSize in [6, 20, 64]) {
        final packets = blePackets(
          frame,
          packetSize: packetSize,
          timestamp: time,
        );
        expect(packets.every((packet) => packet.length <= packetSize), isTrue);
        final unframer = BleUnframer();
        final result = packets.expand(unframer.push).toList();
        expect(result, [
          frame,
        ], reason: 'timestamp=$time packetSize=$packetSize');
      }
    }
    final unframer = BleUnframer();
    expect(unframer.push([0, 0, 0xf0]), isEmpty);
    expect(unframer.push([0x80, 0xf0, 0xf0, 1, 2, 0xf7, 0xf7]), [
      [0xf0, 1, 2, 0xf7],
    ]);
  });

  test('CC, PC and NRPN retain their native module and value encodings', () {
    expect(programChange(79), [0xc0, 79]);
    expect(nrpn(1, 0x60, 100), [
      0xb0,
      99,
      1,
      0xb0,
      98,
      96,
      0xb0,
      6,
      127,
      0xb0,
      38,
      127,
    ]);
    expect(nrpn(9, 1, 220, raw: true), [
      0xb0,
      99,
      9,
      0xb0,
      98,
      1,
      0xb0,
      6,
      1,
      0xb0,
      38,
      92,
    ]);
    expect(nrpn(8, 0, 12, raw: true), [0xb0, 99, 8, 0xb0, 98, 0, 0xb0, 6, 12]);
    expect(
      splitChannelMessages([...programChange(79), ...controlChange(88, 127)]),
      [
        [0xc0, 79],
        [0xb0, 88, 127],
      ],
    );
    expect(() => splitChannelMessages([0xb0, 6]), throwsArgumentError);
    expect(moveSlotMessage(2, 0), nrpn(10, 7, 16, raw: true));
  });

  test('state layout and deleted model indices remain intact', () {
    final raw = List.filled(128, 0);
    raw[0] = 1;
    raw[2] = 79;
    raw[3] = 0x2e;
    raw[4] = 73;
    raw.setRange(6, 11, 'Clean'.codeUnits);
    raw[38] = 1;
    raw[39] = 22;
    raw[40] = 81;
    raw[106] = 4;
    raw[107] = 1;
    raw[115] = 4;
    raw[125] = 2;
    raw[126] = 6;
    raw[127] = 13;
    raw.setRange(117, 125, [0, 2, 1, 3, 4, 5, 6, 7]);
    final state = AmpState.decode(raw);
    expect(state.name, 'Clean');
    expect(state.preset, 79);
    expect(state.bpm, 260);
    expect(state.effect(2).model, 22);
    expect(state.effect(2).knobs[0], 81);
    expect(state.loopback && state.groovePlaying && state.tunerOpen, isTrue);
    expect(state.usbMode, 1);
    expect(state.patch({40: 91}).effect(2).knobs[0], 91);
    expect(state.effect(2).knobs[0], 81);
    final old = AmpState.decode(raw.take(117).toList());
    expect(old.freeCaptures, 6);
    expect(old.order, [0, 1, 2, 3, 4, 5, 6, 7]);
    final models = ModelDirectory(
      amps: ['Factory', 'First', '', 'Third'],
      firstCapture: 1,
    );
    expect(models.stored(0).map((model) => model.index), [0, 2]);
    expect(models.stored(0).map((model) => model.type), [1, 3]);
  });
}
