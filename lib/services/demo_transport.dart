import 'dart:async';
import 'dart:typed_data';
import '../core/midi_protocol.dart';
import '../core/presets.dart';
import 'midi_transport.dart';

const _ampNames = ['US Deluxe', 'Brit 800', 'Class A 30', 'Jazz Clean'];
const _cabNames = ['1x12 Open', '4x12 Vintage', '2x12 Blue', '1x12 Jazz'];
const _presetNames = [
  'Amber Clean',
  'Velvet Drive',
  'Midnight Lead',
  'Glass Chorus',
];
const _knobs = [
  [36, 55, 20, 100, 50, 50],
  [35, 48, 65, 50, 50, 50],
  [42, 55, 48, 62, 45, 68],
  [100, 15, 82, 50, 50, 50],
  [50, 50, 50, 50, 50, 50],
  [24, 36, 18, 0, 50, 50],
  [32, 25, 20, 12, 50, 50],
  [38, 20, 58, 22, 50, 50],
];

/// An entirely local virtual amp. It never creates a native Bluetooth connection or plays audio.
class DemoTransport implements MidiTransport {
  final _frames = StreamController<List<int>>.broadcast();
  final _disconnects = StreamController<String>.broadcast();
  final _state = Uint8List(128);
  late final List<Uint8List> _bank;
  bool _open = true;
  int _module = 0, _parameter = 0, _high = 0;
  _Upload? _upload;

  DemoTransport() {
    _bank = List.generate(80, (index) => _preset(index).toRecord());
    _state[0] = 1;
    _state[5] = 80;
    _state[86] = 12;
    _state[89] = 1;
    _state[90] = 1;
    _state[92] = 75;
    _state[94] = 50;
    _state.fillRange(96, 101, 12);
    _state[101] = 10;
    _state[102] = 1;
    _state[109] = 40;
    _state[110] = 1;
    _state[126] = 10;
    _state[127] = 15;
    _load(0);
  }

  OnyxPreset _preset(int index) => OnyxPreset.fromJson({
    'slot': index + 1,
    'name': index < 4
        ? _presetNames[index]
        : 'Demo ${(index + 1).toString().padLeft(2, '0')}',
    'empty': false,
    'seq': 1,
    'bpm': 120,
    'genre': 0,
    'custom_cab_idx': 255,
    'custom_cab_blend': 100,
    'input_trim_db': 0,
    'gate_threshold_pct': 0,
    'slot_enable_mask': 0xed,
    'slot_order': List.generate(8, (slot) => slot),
    'amp_model': index % 4,
    'cab_model': index % 4,
    'preset_vol': 72,
    'flags': 0,
    'slot_type': [0, 0, index % 4, index % 4, 0, 0, 0, 0],
    'stomp_map': [2, 3, 1, 4],
    'params': _knobs
        .map(
          (row) => row.map((value) => (value * 65535 / 100).round()).toList(),
        )
        .toList(),
  });

  void _load(int index) {
    final preset = OnyxPreset.fromRecord(index, _bank[index]);
    _state[2] = index;
    _state[4] = preset.value('preset_vol');
    _state.fillRange(6, 22, 0);
    final name = preset.name.codeUnits.take(16).toList();
    _state.setRange(6, 6 + name.length, name);
    for (var slot = 0; slot < 8; slot++) {
      final offset = 22 + slot * 8;
      _state[offset] = (preset.enabledMask >> slot) & 1;
      _state[offset + 1] = preset.models[slot];
      _state.setRange(
        offset + 2,
        offset + 8,
        preset.params[slot].map((value) => (value * 100 / 65535).round()),
      );
    }
    _state[106] = preset.value('bpm') & 255;
    _state[107] = preset.value('bpm') >> 8;
    _state.setRange(111, 115, preset.stompMap);
    _state.setRange(117, 125, preset.order);
  }

  void _save() {
    final index = _state[2],
        previous = OnyxPreset.fromRecord(_state[2], _bank[_state[2]]);
    _bank[index] = OnyxPreset.fromJson({
      ...previous.toJson(),
      'seq': previous.value('seq') + 1,
      'preset_vol': _state[4],
      'amp_model': _state[39],
      'cab_model': _state[47],
      'slot_order': _state.sublist(117, 125),
      'slot_type': List.generate(8, (slot) => _state[23 + slot * 8]),
      'slot_enable_mask': List.generate(
        8,
        (slot) => _state[22 + slot * 8] << slot,
      ).fold<int>(0, (a, b) => a | b),
      'stomp_map': _state.sublist(111, 115),
      'params': List.generate(
        8,
        (slot) => _state
            .sublist(24 + slot * 8, 30 + slot * 8)
            .map((value) => (value * 65535 / 100).round())
            .toList(),
      ),
    }).toRecord();
  }

  void _parameterValue(int value) {
    if (_module < 8) {
      final offset = 22 + slotModules.indexOf(_module) * 8;
      if (_parameter == 0x40) {
        _state[offset + 1] = value >= 0x20 ? value - 0x20 : value;
      } else if (_parameter == 0x41) {
        _state[offset] = value >= 64 ? 1 : 0;
      } else {
        final knob = _parameter >= 0x60 ? _parameter - 0x60 : _parameter;
        if (knob >= 0 && knob < 6) {
          _state[offset + 2 + knob] = (value * 100 / 16383).round();
        }
      }
    } else if (_module == 8) {
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
      if (_parameter < offsets.length) _state[offsets[_parameter]] = value;
      if (_parameter == 18) _state[3] = (_state[3] & ~8) | (value != 0 ? 8 : 0);
      if (_parameter == 19) {
        _state[3] = (_state[3] & ~(3 << 5)) | ((value & 3) << 5);
      }
    } else if (_module == 9) {
      if (_parameter == 1) {
        _state[106] = (40 + value) & 255;
        _state[107] = (40 + value) >> 8;
      }
      if (_parameter >= 2 && _parameter <= 4) _state[106 + _parameter] = value;
    } else if (_module == 10) {
      if (_parameter == 0) _state[4] = value;
      if (_parameter >= 3 && _parameter <= 6) {
        _state[108 + _parameter] = slotModules.indexOf(value);
      }
      if (_parameter == 7) {
        _state.setRange(
          117,
          125,
          moveSlot(_state.sublist(117, 125), value >> 3, value & 7),
        );
      }
    }
  }

  void _control(List<int> message) {
    if (message[0] == 0xc0) {
      _load(message[1] % 80);
      return;
    }
    if (message[0] != 0xb0) return;
    final controller = message[1], value = message[2];
    if (controller == 99) {
      _module = value;
    } else if (controller == 98) {
      _parameter = value;
    } else if (controller == 6) {
      _high = value;
      _parameterValue(
        _module < 8 && (_parameter < 0x40 || _parameter >= 0x60)
            ? value << 7
            : value,
      );
    } else if (controller == 38) {
      _parameterValue((_high << 7) | value);
    } else if (controller >= 28 && controller <= 35) {
      _state[22 + slotModules.indexOf(controller - 28) * 8] = value >= 64
          ? 1
          : 0;
    } else if (controller == 80 && value >= 64) {
      _load((_state[2] + 1) % 80);
    } else if (controller == 81 && value >= 64) {
      _load((_state[2] + 79) % 80);
    } else if (controller == 85 && value >= 64) {
      _state[3] ^= 2;
    } else if (controller == 86) {
      _state[3] = (_state[3] & ~4) | (value >= 64 ? 4 : 0);
    } else if (controller == 88 && value >= 64) {
      _save();
    }
  }

  void _reply(int type, List<int> data) {
    if (_open) _frames.add(buildFrame(type, data));
  }

  @override
  Future<void> send(List<int> bytes) async {
    if (!_open) throw StateError('데모가 종료되었습니다.');
    for (final message in splitChannelMessages(bytes)) {
      _control(message);
    }
  }

  @override
  Future<void> sendFrame(List<int> frame) async {
    if (!_open) throw StateError('데모가 종료되었습니다.');
    final command = parseFrame(frame);
    if (command == null) throw const FormatException('잘못된 프레임입니다.');
    final data = command.data;
    switch (command.type) {
      case 80:
        _reply(0x60, _state);
      case 81:
        if (data[0] == 255) {
          _reply(0x61, [255, 1, 0, 4, 0, ...'DEMO'.codeUnits]);
        } else {
          final list = data[0] == 0 ? _ampNames : _cabNames;
          final names = list.skip(data[1]).take(5).toList();
          _reply(0x61, [
            data[0],
            list.length,
            data[1],
            names.length,
            20,
            ...names.expand(
              (name) => List.generate(
                16,
                (index) => index < name.length ? name.codeUnitAt(index) : 0,
              ),
            ),
          ]);
        }
      case 83:
        _reply(0x63, [data[0], 0, ..._bank[data[0]]]);
      case 25:
        _upload = _Upload(
          length: data[0] | data[1] << 8 | data[2] << 16,
          target: data[3],
          slot: data[4],
        );
        _ack();
      case 34:
        _upload?.bytes.addAll(data);
        _ack();
      case 82:
        _reply(0x62, [...data.take(3), 255]);
    }
  }

  void _ack() {
    final upload = _upload;
    if (upload == null) {
      _reply(0x64, [0, 0, 0, 3]);
      return;
    }
    final offset = upload.bytes.length;
    var status = 0;
    if (offset >= upload.length) {
      if (upload.target == 4 && upload.slot < 80 && recordValid(upload.bytes)) {
        _bank[upload.slot] = Uint8List.fromList(upload.bytes);
        status = 1;
      } else {
        status = 2;
      }
    }
    _reply(0x64, [
      offset & 255,
      (offset >> 8) & 255,
      (offset >> 16) & 255,
      status,
    ]);
  }

  @override
  String get name => 'Onyx Demo';
  @override
  bool get isDemo => true;
  @override
  bool get isOpen => _open;
  @override
  int get uploadChunk => 100;
  @override
  Stream<List<int>> get frames => _frames.stream;
  @override
  Stream<String> get disconnectReasons => _disconnects.stream;
  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    _upload = null;
    await _frames.close();
    await _disconnects.close();
  }
}

class _Upload {
  final int length, target, slot;
  final bytes = <int>[];
  _Upload({required this.length, required this.target, required this.slot});
}
