import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx_mobile/core/presets.dart';

void main() {
  final golden = File('test/fixtures/golden-pmp2.bin').readAsBytesSync();
  test('PMP2 fixture roundtrips without losing Q16 precision', () {
    expect(crc32(ascii.encode('123456789')), 0xcbf43926);
    expect(recordValid(golden), isTrue);
    final preset = OnyxPreset.fromRecord(0, golden);
    expect(preset.name, 'Golden Clean');
    expect(preset.value('seq'), 0x12345678);
    expect(preset.value('input_trim_db'), -7);
    expect(preset.value('bpm'), 137);
    expect(preset.params[2], [0, 1, 65535, 32768, 65534, 12345]);
    expect(preset.toRecord(), golden);
    expect(OnyxPreset.fromJson(preset.toJson()).toRecord(), golden);
    final corrupt = Uint8List.fromList(golden)..[84] ^= 1;
    expect(recordValid(corrupt), isFalse);
  });

  test('bank validates duplicates, invalid values and unreadable slots', () {
    final slots = List<OnyxPreset?>.filled(80, null)
      ..[0] = OnyxPreset.fromRecord(0, golden);
    final bank = PresetBank(slots, unreadable: {1});
    final next = PresetBank.fromJson(jsonDecode(bank.encode()));
    expect(next.presets[0]!.toRecord(), golden);
    expect(next.unreadable, {1});
    expect(next.readableCount, 1);
    expect(next.presets[2], isNull);
    final json = bank.toJson();
    expect(
      () => PresetBank.fromJson({
        ...json,
        'presets': [slots[0]!.toJson(), slots[0]!.toJson()],
      }),
      throwsFormatException,
    );
    expect(
      () => OnyxPreset.fromJson({
        ...slots[0]!.toJson(),
        'slot_order': [0, 0, 2, 3, 4, 5, 6, 7],
      }),
      throwsFormatException,
    );
    expect(
      () => OnyxPreset.fromJson({...slots[0]!.toJson(), 'preset_vol': 256}),
      throwsFormatException,
    );
  });

  test('slot range parsing never silently accepts an unsafe range', () {
    expect(parsePresetSlots('1-3,3,80'), [0, 1, 2, 79]);
    expect(parsePresetSlots(''), List.generate(80, (index) => index));
    for (final input in ['0', '81', '5-1', '1-100', '1,', '-1', 'a', '1--2']) {
      expect(
        () => parsePresetSlots(input),
        throwsFormatException,
        reason: input,
      );
    }
  });

  test('ABKX conversion follows the stock mappings and extension bytes', () {
    final bytes = stockBank();
    final defaultPreset = convertAbkx(bytes).presets[0]!;
    expect(defaultPreset.models, [4, 3, 7, 8, 2, 2, 5, 6]);
    expect(defaultPreset.enabledMask, 255);
    expect(defaultPreset.params[2][5], 32768);
    expect(defaultPreset.value('input_trim_db'), -11);
    expect(defaultPreset.params[5].take(4), [15728, 32768, 26214, 13107]);
    final original = convertAbkx(
      bytes,
      options: const BankConversionOptions(
        preserveChain: true,
        copyAmpLevel: true,
        namePrefix: 'Stock ',
      ),
    ).presets[0]!;
    expect(original.order, [3, 4, 7, 6, 5, 1, 2, 0]);
    expect(original.name, 'Stock 01');
    expect(original.params[1].take(3), [16384, 29491, 49151]);
    expect(original.params[4].take(5), [13762, 14418, 15073, 15728, 16384]);
    expect(recordValid(original.toRecord()), isTrue);
    bytes[7360] = 0;
    expect(() => convertAbkx(bytes), throwsFormatException);
  });
}

Uint8List stockBank() {
  final bytes = Uint8List(7370), view = ByteData.sublistView(bytes);
  for (var slot = 0; slot < 80; slot++) {
    final base = slot * 92;
    bytes[base] = 70;
    bytes.setRange(base + 2, base + 8, [5, 4, 3, 2, 1, 0]);
    bytes.fillRange(base + 8, base + 14, 1);
    bytes.setRange(base + 14, base + 20, [2, 7, 3, 3, 4, 8]);
    for (final block in [0x14, 0x20, 0x2c, 0x38, 0x44, 0x50]) {
      for (var knob = 0; knob < 6; knob++) {
        view.setUint16(
          base + block + knob * 2,
          [24, 50, 20, 40, 60, 0][knob],
          Endian.little,
        );
      }
    }
  }
  bytes[1] = 0x80 | 0x20 | 21;
  bytes[0x2a] = 88;
  bytes[0x2b] = 39;
  bytes[0x36] = 53;
  bytes[0x4e] = 52;
  bytes[0x56] = 25;
  bytes[0x58] = 45;
  bytes[0x5a] = 75;
  bytes[0x37] = 21;
  bytes[0x4f] = 22;
  bytes[0x57] = 23;
  bytes[0x59] = 24;
  bytes[0x5b] = 25;
  bytes.setRange(7360, 7368, ascii.encode('PATCHEND'));
  return bytes;
}
