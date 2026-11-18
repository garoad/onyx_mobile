// SPDX-License-Identifier: GPL-3.0-only
// Dart port of Pocket-Onyx's preset records and .abkx converter.
// Copyright (C) 2026 The Onyx Authors (@28spawn).
import 'dart:convert';
import 'dart:typed_data';
import 'midi_protocol.dart';

const presetSize = 164;
const presetCount = 80;
const presetMagic = 0x32504d50;

int crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (~crc) & 0xffffffff;
}

bool recordValid(List<int> bytes) {
  if (bytes.length != presetSize) return false;
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return view.getUint32(0, Endian.little) == presetMagic &&
      view.getUint32(160, Endian.little) == crc32(bytes.sublist(0, 160));
}

class OnyxPreset {
  final Map<String, dynamic> _data;
  const OnyxPreset._(this._data);
  int get slot => _data['slot'] as int;
  String get name => _data['name'] as String;
  bool get empty => _data['empty'] as bool;
  int get ampModel => _data['amp_model'] as int;
  int get cabModel => _data['cab_model'] as int;
  int get enabledMask => _data['slot_enable_mask'] as int;
  List<int> get order => _data['slot_order'] as List<int>;
  List<int> get models => _data['slot_type'] as List<int>;
  List<int> get stompMap => _data['stomp_map'] as List<int>;
  List<List<int>> get params => _data['params'] as List<List<int>>;
  int value(String key) => _data[key] as int;

  factory OnyxPreset.fromJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.of(json);
    int integer(String key, int min, int max) {
      final value = data[key];
      if (value is! int || value < min || value > max) {
        throw FormatException('$key 값이 올바른 범위를 벗어났습니다.');
      }
      return value;
    }

    integer('slot', 1, 80);
    integer('seq', 0, 0xffffffff);
    integer('bpm', 0, 65535);
    integer('input_trim_db', -128, 127);
    for (final key in [
      'genre',
      'custom_cab_idx',
      'custom_cab_blend',
      'gate_threshold_pct',
      'slot_enable_mask',
      'amp_model',
      'cab_model',
      'preset_vol',
      'flags',
    ]) {
      integer(key, 0, 255);
    }
    final name = data['name'];
    if (name is! String ||
        name.length > 23 ||
        name.codeUnits.any((unit) => unit < 32 || unit > 255)) {
      throw const FormatException('프리셋 이름은 기기가 지원하는 영문·숫자·기호 23자 이내여야 합니다.');
    }
    if (data['empty'] is! bool) {
      throw const FormatException('empty 값은 true 또는 false여야 합니다.');
    }
    List<int> numbers(Object? input, int length, int max) {
      if (input is! List ||
          input.length != length ||
          input.any((value) => value is! int || value < 0 || value > max)) {
        throw const FormatException('프리셋 이펙트 데이터가 잘못되었습니다.');
      }
      return List<int>.unmodifiable(input.cast<int>());
    }

    data['slot_order'] = numbers(data['slot_order'], 8, 7);
    if (!isSlotOrder(data['slot_order'] as List<int>)) {
      throw const FormatException('이펙트 순서에 중복된 슬롯이 있습니다.');
    }
    data['slot_type'] = numbers(data['slot_type'], 8, 255);
    data['stomp_map'] = numbers(data['stomp_map'], 4, 7);
    final params = data['params'];
    if (params is! List || params.length != 8) {
      throw const FormatException('params는 8개 이펙트의 값이어야 합니다.');
    }
    data['params'] = List<List<int>>.unmodifiable(
      params.map((row) => numbers(row, 6, 65535)),
    );
    return OnyxPreset._(Map.unmodifiable(data));
  }

  factory OnyxPreset.fromRecord(int slot, List<int> bytes) {
    if (!recordValid(bytes)) {
      throw const FormatException('프리셋 레코드의 크기 또는 CRC가 잘못되었습니다.');
    }
    final raw = Uint8List.fromList(bytes),
        view = ByteData.sublistView(Uint8List.fromList(bytes));
    var end = 8;
    while (end < 32 && raw[end] != 0) {
      end++;
    }
    return OnyxPreset.fromJson({
      'slot': slot + 1,
      'name': String.fromCharCodes(raw.sublist(8, end)),
      'empty': raw[51] & 1 != 0,
      'seq': view.getUint32(4, Endian.little),
      'bpm': view.getUint16(32, Endian.little),
      'genre': raw[34],
      'custom_cab_idx': raw[35],
      'custom_cab_blend': raw[36],
      'input_trim_db': view.getInt8(37),
      'gate_threshold_pct': raw[38],
      'slot_enable_mask': raw[39],
      'slot_order': raw.sublist(40, 48),
      'amp_model': raw[48],
      'cab_model': raw[49],
      'preset_vol': raw[50],
      'flags': raw[51],
      'slot_type': raw.sublist(52, 60),
      'stomp_map': raw.sublist(60, 64),
      'params': List.generate(
        8,
        (slot) => List.generate(
          6,
          (knob) => view.getUint16(64 + (slot * 6 + knob) * 2, Endian.little),
        ),
      ),
    });
  }

  Uint8List toRecord() {
    final raw = Uint8List(presetSize);
    final view = ByteData.sublistView(raw);
    view.setUint32(0, presetMagic, Endian.little);
    view.setUint32(4, value('seq'), Endian.little);
    raw.setRange(8, 8 + name.length, name.codeUnits);
    view.setUint16(32, value('bpm'), Endian.little);
    raw[34] = value('genre');
    raw[35] = value('custom_cab_idx');
    raw[36] = value('custom_cab_blend');
    view.setInt8(37, value('input_trim_db'));
    raw[38] = value('gate_threshold_pct');
    raw[39] = enabledMask;
    raw.setRange(40, 48, order);
    raw[48] = ampModel;
    raw[49] = cabModel;
    raw[50] = value('preset_vol');
    raw[51] = (value('flags') & ~1) | (empty ? 1 : 0);
    raw.setRange(52, 60, models);
    raw.setRange(60, 64, stompMap);
    for (var slot = 0; slot < 8; slot++) {
      for (var knob = 0; knob < 6; knob++) {
        view.setUint16(
          64 + (slot * 6 + knob) * 2,
          params[slot][knob],
          Endian.little,
        );
      }
    }
    view.setUint32(160, crc32(raw.sublist(0, 160)), Endian.little);
    return raw;
  }

  Map<String, dynamic> toJson() => {
    ..._data,
    'params_pct': params
        .map(
          (row) => row.map((value) => (value * 100 / 65535).round()).toList(),
        )
        .toList(),
  };
}

class PresetBank {
  final List<OnyxPreset?> presets;
  final Set<int> unreadable;
  PresetBank(List<OnyxPreset?> presets, {Set<int> unreadable = const {}})
    : presets = List.unmodifiable(presets),
      unreadable = Set.unmodifiable(unreadable) {
    if (presets.length != 80) throw ArgumentError('A bank has 80 slots.');
  }

  int get readableCount => presets.whereType<OnyxPreset>().length;

  factory PresetBank.fromJson(Object? input) {
    if (input is! Map ||
        input['format'] != 'pocket-amp-presets' ||
        input['version'] != 1 ||
        input['record_size'] != presetSize) {
      throw const FormatException(
        'Onyx 프리셋 백업 형식이 아닙니다 (version 1, record_size 164).',
      );
    }
    final entries = input['presets'];
    if (entries is! List || entries.isEmpty || entries.length > 80) {
      throw const FormatException('프리셋 목록은 1~80개의 슬롯이어야 합니다.');
    }
    final presets = List<OnyxPreset?>.filled(80, null),
        unreadable = <int>{},
        seen = <int>{};
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('프리셋 항목이 잘못되었습니다.');
      }
      final slot = entry['slot'];
      if (slot is! int || slot < 1 || slot > 80 || !seen.add(slot)) {
        throw const FormatException('프리셋 슬롯 번호가 잘못되었거나 중복되었습니다.');
      }
      if (entry['unreadable'] == true) {
        unreadable.add(slot - 1);
        continue;
      }
      presets[slot - 1] = OnyxPreset.fromJson(entry);
    }
    return PresetBank(presets, unreadable: unreadable);
  }

  Map<String, dynamic> toJson() => {
    'format': 'pocket-amp-presets',
    'version': 1,
    'record_size': presetSize,
    'note':
        'Onyx Mobile backup. params are Q16 (0..65535 = 0..100%). Slot order: DYN DRIVE AMP CAB EQ MOD DLY REV.',
    'presets': [
      for (var slot = 0; slot < 80; slot++)
        if (presets[slot] != null)
          presets[slot]!.toJson()
        else if (unreadable.contains(slot))
          {'slot': slot + 1, 'unreadable': true},
    ],
  };

  String encode() => '${const JsonEncoder.withIndent(' ').convert(toJson())}\n';
}

List<int> parsePresetSlots(String input) {
  final slots = <int>{};
  for (final part in (input.trim().isEmpty ? '1-80' : input).split(',')) {
    final match = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(part.trim());
    if (match == null) {
      throw const FormatException('범위를 확인해 주세요. 예: 1-80 또는 1-10,15');
    }
    final first = int.parse(match[1]!), last = int.parse(match[2] ?? match[1]!);
    if (first < 1 || last > 80 || first > last) {
      throw const FormatException('프리셋 슬롯은 1~80 사이의 오름차순 범위여야 합니다.');
    }
    for (var slot = first; slot <= last; slot++) {
      slots.add(slot - 1);
    }
  }
  return slots.toList()..sort();
}

class BankConversionOptions {
  final bool preserveChain;
  final bool copyAmpLevel;
  final String namePrefix;
  const BankConversionOptions({
    this.preserveChain = false,
    this.copyAmpLevel = false,
    this.namePrefix = 'P',
  });
}

PresetBank convertAbkx(
  Uint8List bytes, {
  BankConversionOptions options = const BankConversionOptions(),
}) {
  if (bytes.length != 7370 ||
      ascii.decode(bytes.sublist(7360, 7368), allowInvalid: true) !=
          'PATCHEND' ||
      (bytes.last != 0 && bytes.last != 0x45)) {
    throw const FormatException('올바른 .abkx 뱅크가 아닙니다 (7370 바이트, PATCHEND).');
  }
  final presets = <OnyxPreset>[];
  for (var slot = 0; slot < 80; slot++) {
    final record = bytes.sublist(slot * 92, slot * 92 + 92);
    final order = record.sublist(2, 8);
    if (order.toSet().length != 6 || order.any((value) => value > 5)) {
      throw FormatException('P${slot + 1}: 이펙트 순서가 잘못되었습니다.');
    }
    presets.add(_convertStockRecord(record, slot, options));
  }
  return PresetBank(presets);
}

List<List<int>> _neutral() {
  final knobs = List.generate(8, (_) => List.filled(6, 50));
  knobs[0][3] = 100;
  knobs[3][0] = 100;
  knobs[3][1] = 0;
  knobs[3][2] = 0;
  knobs[5][2] = 12;
  knobs[6][1] = 15;
  knobs[6][2] = 10;
  knobs[7][1] = 0;
  return knobs;
}

OnyxPreset _convertStockRecord(
  List<int> r,
  int index,
  BankConversionOptions options,
) {
  const blocks = [0x14, 0x20, 0x2c, 0x38, 0x44, 0x50];
  List<int> values(int block) => List.generate(
    6,
    (knob) =>
        r[blocks[block] + knob * 2] | r[blocks[block] + knob * 2 + 1] << 8,
  );
  int pct(int value) => value.clamp(0, 100);
  final extended = r[1] & 0x80 != 0 && (r[1] >> 5) & 3 == 1;
  final extCode = r[1] & 0x1f;
  final driveOn = extended && r[0x36] ~/ 50 != 0,
      eqOn = extended && r[0x4e] ~/ 50 != 0;
  final enabled = r.sublist(8, 14), p = _neutral(), types = List.filled(8, 0);
  var mask = 0, amp = 0, cab = 0;
  final empty = enabled.every((value) => value == 0) && !driveOn && !eqOn;
  if (!empty) {
    var type = extended && extCode ~/ 15 == 1 ? 4 : r[0x0e];
    final dynValid = type <= 4;
    if (!dynValid) type = 0;
    var v = values(0);
    if (dynValid) {
      p[0][0] = pct(v[0]);
      if (type == 1) {
        p[0][3] = pct(v[1]);
      } else if (type == 2 || type == 4) {
        p[0][1] = pct(v[1]);
        p[0][2] = pct(v[2]);
        p[0][3] = pct(v[3] * 2);
      }
    }
    types[0] = type;
    if (enabled[0] != 0 && dynValid) mask |= 1;
    v = values(1);
    amp = r[15] < 20 ? r[15] : 0;
    p[2].setRange(0, 6, [
      pct(v[0]),
      pct(v[2]),
      pct(v[3]),
      pct(v[4]),
      extended ? pct(r[0x2a]) : 50,
      options.copyAmpLevel ? pct(v[1]) : 50,
    ]);
    types[2] = amp;
    if (enabled[1] != 0) mask |= 1 << 2;
    v = values(5);
    cab = r[19] < 20 ? r[19] : 0;
    p[3].setRange(0, 3, [pct(v[0]), pct(v[1]), pct(100 - v[2])]);
    types[3] = cab;
    if (enabled[5] != 0) mask |= 1 << 3;
    const modTypes = [0, 1, 3, 2, 4, 5, 6];
    final modValid = r[16] < modTypes.length;
    type = modValid ? modTypes[r[16]] : 0;
    v = values(2);
    if (modValid) {
      if (type == 0 || type == 5) {
        p[5].setRange(0, 3, [pct(v[0]), pct(v[1]), pct(v[2])]);
      } else if (type == 1) {
        p[5][0] = pct(v[0]);
        p[5][1] = pct(v[2]);
        p[5][3] = pct(v[3]);
      } else if (type == 2) {
        p[5].setRange(0, 4, [pct(v[0]), pct(v[1]), pct(v[3]), pct(v[2])]);
      } else if (type == 3 || type == 4) {
        p[5].setRange(0, 2, [pct(v[0]), pct(v[1])]);
      } else {
        p[5].setRange(0, 4, [
          pct(v[0]),
          pct((v[1] + v[2]) ~/ 2),
          pct(v[3]),
          pct(v[4]),
        ]);
      }
    }
    types[5] = type == 5 ? 1 : type;
    if (enabled[2] != 0 && modValid) mask |= 1 << 5;
    v = values(3);
    type = r[17];
    final delayExtension = extCode % 5;
    if (extended && delayExtension > 0) type = [0, 5, 6, 7, 8][delayExtension];
    if (type > 8) type = 0;
    p[6].setRange(0, 4, [
      pct(v[0]),
      pct(v[1]),
      pct(v[2]),
      type == 3 ? 0 : pct(v[3]),
    ]);
    types[6] = type;
    if (enabled[3] != 0) mask |= 1 << 6;
    v = values(4);
    type = r[18];
    final reverbExtension = (extCode ~/ 5) % 3;
    if (extended && reverbExtension > 0) type = [0, 6, 0][reverbExtension];
    if (type > 6) type = 0;
    if (type == 4) {
      p[7][0] = pct(v[0]);
      p[7][3] = pct(v[1]);
      p[7][2] = pct(v[2]);
    } else {
      p[7].setRange(0, 4, [pct(v[0]), pct(v[2]), pct(v[3]), pct(v[1])]);
    }
    types[7] = type;
    if (enabled[4] != 0) mask |= 1 << 7;
    if (driveOn) {
      types[1] = r[0x36] % 50 % 6;
      p[1].setRange(0, 3, [pct(r[0x56]), pct(r[0x58]), pct(r[0x5a])]);
      mask |= 1 << 1;
    }
    if (eqOn) {
      types[4] = r[0x4e] % 50 % 3;
      p[4].setRange(0, 5, [
        pct(r[0x37]),
        pct(r[0x4f]),
        pct(r[0x57]),
        pct(r[0x59]),
        pct(r[0x5b]),
      ]);
      mask |= 1 << 4;
    }
  } else {
    types[0] = 3;
  }
  var order = List.generate(8, (slot) => slot);
  if (options.preserveChain && !empty) {
    const mapping = [0, 2, 5, 6, 7, 3];
    order = [];
    for (final code in r.sublist(2, 8)) {
      final slot = mapping[code];
      if (slot == 2) order.add(1);
      order.add(slot);
      if (slot == 3) order.add(4);
    }
    for (var slot = 0; slot < 8; slot++) {
      if (!order.contains(slot)) order.add(slot);
    }
  }
  final name = '${options.namePrefix}${(index + 1).toString().padLeft(2, '0')}';
  return OnyxPreset.fromJson({
    'slot': index + 1,
    'name': empty ? 'EMPTY' : name.substring(0, name.length.clamp(0, 23)),
    'empty': empty,
    'seq': empty ? 1 : 2,
    'bpm': 120,
    'genre': 7,
    'custom_cab_idx': 255,
    'custom_cab_blend': 100,
    'input_trim_db': !empty && extended ? (r[0x2b] - 50).clamp(-12, 12) : 0,
    'gate_threshold_pct': 0,
    'slot_enable_mask': mask,
    'slot_order': order,
    'amp_model': amp,
    'cab_model': cab,
    'preset_vol': empty ? 70 : pct(r[0]),
    'flags': empty ? 1 : 0,
    'slot_type': types,
    'stomp_map': [1, 5, 6, 7],
    'params': p
        .map((row) => row.map((value) => (value * 65535 + 50) ~/ 100).toList())
        .toList(),
  });
}
