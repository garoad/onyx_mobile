// SPDX-License-Identifier: GPL-3.0-only
// State layout from Pocket-Onyx, Copyright (C) 2026 The Onyx Authors (@28spawn).
import 'dart:typed_data';
import 'midi_protocol.dart';

class EffectState {
  final int slot;
  final bool enabled;
  final int model;
  final List<int> knobs;
  const EffectState({
    required this.slot,
    required this.enabled,
    required this.model,
    required this.knobs,
  });
}

class AmpState {
  final Uint8List _raw;
  AmpState._(this._raw);

  static AmpState decode(List<int> bytes) {
    if (bytes.length < 117 || bytes[0] != 1) {
      throw const FormatException(
        'Onyx 상태 정보를 읽을 수 없습니다. Bluetooth를 지원하는 Onyx 펌웨어를 확인해 주세요.',
      );
    }
    final raw = Uint8List(128)..setRange(0, bytes.length.clamp(0, 128), bytes);
    if (bytes.length < 125 || !isSlotOrder(raw.sublist(117, 125))) {
      raw.setRange(117, 125, List.generate(8, (index) => index));
    }
    if (bytes.length < 128) {
      raw[126] = (10 - raw[115]).clamp(0, 10);
      raw[127] = (15 - raw[125]).clamp(0, 15);
    }
    return AmpState._(raw);
  }

  List<int> get bytes => List.unmodifiable(_raw);
  int byte(int offset) => _raw[offset];
  int get preset => _raw[2];
  int get flags => _raw[3];
  String get name => String.fromCharCodes(
    _raw.sublist(6, 22).where((byte) => byte != 0),
  ).trim();
  int get presetVolume => _raw[4];
  int get outputLevel => _raw[5];
  bool get tunerOpen => flags & 2 != 0;
  bool get groovePlaying => flags & 4 != 0;
  bool get loopback => flags & 8 != 0;
  int get usbMode => (flags >> 5) & 3;
  int get bpm => _raw[106] | _raw[107] << 8;
  int get pattern => _raw[108];
  int get grooveVolume => _raw[109];
  bool get drumsEnabled => _raw[110] != 0;
  int get captureCount => _raw[115];
  bool get temporaryCabinet => _raw[116] != 0;
  int get cabinetCount => _raw[125];
  int get freeCaptures => _raw[126];
  int get freeCabinets => _raw[127];
  List<int> get order => _raw.sublist(117, 125);
  List<int> get stompSlots => _raw.sublist(111, 115);

  EffectState effect(int slot) {
    final offset = 22 + slot * 8;
    return EffectState(
      slot: slot,
      enabled: _raw[offset] != 0,
      model: _raw[offset + 1],
      knobs: _raw.sublist(offset + 2, offset + 8),
    );
  }

  AmpState patch(Map<int, int> values) {
    final bytes = Uint8List.fromList(_raw);
    values.forEach((offset, value) => bytes[offset] = value);
    return AmpState.decode(bytes);
  }

  AmpState withOrder(List<int> value) => patch({
    for (var index = 0; index < 8; index++) 117 + index: value[index],
  });
}

class ModelDirectory {
  final List<String> amps;
  final List<String> cabinets;
  final int firstCapture;
  final int firstCabinet;
  const ModelDirectory({
    this.amps = const [],
    this.cabinets = const [],
    this.firstCapture = 20,
    this.firstCabinet = 20,
  });

  List<StoredModel> stored(int kind) {
    final list = kind == 0 ? amps : cabinets;
    final first = kind == 0 ? firstCapture : firstCabinet;
    return [
      for (var type = first; type < list.length; type++)
        if (list[type].isNotEmpty)
          StoredModel(type: type, index: type - first, name: list[type]),
    ];
  }
}

class StoredModel {
  final int type;
  final int index;
  final String name;
  const StoredModel({
    required this.type,
    required this.index,
    required this.name,
  });
}
