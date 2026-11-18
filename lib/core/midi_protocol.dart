// SPDX-License-Identifier: GPL-3.0-only
// Ported from Pocket-Onyx. Copyright (C) 2026 The Onyx Authors (@28spawn).
import 'dart:typed_data';

const midiServiceUuid = '03b80e5a-ede8-4b33-a751-6ce34ec4c700';
const midiCharacteristicUuid = '7772e5db-3868-4112-a1a9-f2669d106bf3';
const slotNames = ['DYN', 'DRIVE', 'AMP', 'CAB', 'EQ', 'MOD', 'DLY', 'REV'];
const slotModules = [0, 6, 1, 5, 7, 2, 3, 4];
const maxPayload = 256;

List<int> pack8To7(List<int> data) {
  final output = <int>[];
  var bits = 0, count = 0;
  for (final byte in data) {
    bits |= (byte & 0xff) << count;
    count += 8;
    while (count >= 7) {
      output.add(bits & 0x7f);
      bits >>= 7;
      count -= 7;
    }
  }
  if (count > 0) output.add(bits & 0x7f);
  return output;
}

List<int> unpack7To8(List<int> data) {
  final output = <int>[];
  var bits = 0, count = 0;
  for (final byte in data) {
    bits |= (byte & 0x7f) << count;
    count += 7;
    if (count >= 8) {
      output.add(bits & 0xff);
      bits >>= 8;
      count -= 8;
    }
  }
  return output;
}

List<int> buildFrame(int command, [List<int> payload = const []]) {
  if (command < 0 || command > 255 || payload.length > maxPayload) {
    throw ArgumentError('Invalid Onyx command or payload length.');
  }
  final length = payload.length;
  final inner = [
    0,
    0x59,
    command,
    length & 255,
    (length >> 8) & 255,
    (length >> 16) & 255,
    ...payload,
  ];
  final sum = inner.skip(2).fold<int>(0, (sum, byte) => sum + byte);
  inner.add((~sum) & 255);
  return [0xf0, ...pack8To7(inner), 0xf7];
}

class MidiReply {
  final int type;
  final Uint8List data;
  MidiReply(this.type, List<int> data) : data = Uint8List.fromList(data);
}

MidiReply? parseFrame(List<int> frame) {
  if (frame.length < 3 || frame.first != 0xf0 || frame.last != 0xf7) {
    return null;
  }
  final packed = frame.sublist(1, frame.length - 1);
  if (packed.any((byte) => byte < 0 || byte > 127)) return null;
  final inner = unpack7To8(packed);
  if (inner.length < 7 || inner[0] != 0 || inner[1] != 0x59) return null;
  final length = inner[3] | inner[4] << 8 | inner[5] << 16;
  if (length > maxPayload || inner.length != length + 7) return null;
  final sum = inner
      .sublist(2, length + 6)
      .fold<int>(0, (sum, byte) => sum + byte);
  if (inner[length + 6] != ((~sum) & 255)) return null;
  return MidiReply(inner[2], inner.sublist(6, length + 6));
}

List<List<int>> blePackets(
  List<int> message, {
  int packetSize = 20,
  int? timestamp,
}) {
  if (packetSize < 6) {
    throw ArgumentError('BLE packet size must be at least 6.');
  }
  final time = (timestamp ?? DateTime.now().millisecondsSinceEpoch) & 0x1fff;
  final header = 0x80 | (time >> 7), low = 0x80 | (time & 0x7f);
  if (message.isEmpty) throw ArgumentError('Empty MIDI message.');
  if (message.first != 0xf0) {
    if (message.length + 2 > packetSize) {
      throw ArgumentError('Channel message exceeds BLE packet size.');
    }
    return [
      [header, low, ...message],
    ];
  }
  if (message.last != 0xf7) throw ArgumentError('Incomplete SysEx frame.');
  final body = message.sublist(0, message.length - 1);
  final packets = <List<int>>[];
  var offset = 0;
  while (offset < body.length) {
    final head = packets.isEmpty ? [header, low] : [header];
    final count = (packetSize - head.length - 2).clamp(0, body.length - offset);
    packets.add([...head, ...body.sublist(offset, offset + count)]);
    offset += count;
  }
  packets.last.addAll([low, 0xf7]);
  return packets;
}

class BleUnframer {
  final List<int> _buffer = [];
  bool _inFrame = false;

  List<List<int>> push(List<int> packet) {
    final output = <List<int>>[];
    if (packet.length < 2 || packet.first & 0xc0 != 0x80) return output;
    for (var index = 1; index < packet.length; index++) {
      final byte = packet[index];
      if (byte >= 0x80) {
        // High bytes in the BLE stream are timestamps followed by a MIDI status.
        // A timestamp may itself be F0/F7: interpreting it as SysEx corrupts a frame.
        if (index + 1 >= packet.length || packet[index + 1] < 0x80) continue;
        final status = packet[++index];
        if (status == 0xf0) {
          _buffer.clear();
          _buffer.add(status);
          _inFrame = true;
        } else if (status == 0xf7) {
          if (_inFrame) output.add([..._buffer, status]);
          _buffer.clear();
          _inFrame = false;
        } else if (status < 0xf8) {
          _buffer.clear();
          _inFrame = false;
        }
      } else if (_inFrame) {
        _buffer.add(byte);
        if (_buffer.length > 2048) {
          _buffer.clear();
          _inFrame = false;
        }
      }
    }
    return output;
  }
}

List<int> controlChange(int controller, int value) => [
  0xb0,
  controller & 127,
  value & 127,
];
List<int> programChange(int preset) => [0xc0, preset & 127];

List<int> nrpn(int module, int parameter, int value, {bool raw = false}) {
  final output = [
    ...controlChange(99, module),
    ...controlChange(98, parameter),
  ];
  if (raw) {
    if (value < 128) {
      output.addAll(controlChange(6, value));
    } else {
      output.addAll([
        ...controlChange(6, value >> 7),
        ...controlChange(38, value & 127),
      ]);
    }
  } else {
    final scaled = (value.clamp(0, 100) * 16383 / 100).round();
    output.addAll([
      ...controlChange(6, scaled >> 7),
      ...controlChange(38, scaled & 127),
    ]);
  }
  return output;
}

List<List<int>> splitChannelMessages(List<int> bytes) {
  final messages = <List<int>>[];
  for (var offset = 0; offset < bytes.length;) {
    final status = bytes[offset];
    if (status < 0x80 || status >= 0xf0) {
      throw ArgumentError('Unsupported MIDI status.');
    }
    final kind = status & 0xf0;
    final length = kind == 0xc0 || kind == 0xd0 ? 2 : 3;
    if (offset + length > bytes.length) {
      throw ArgumentError('Truncated MIDI message.');
    }
    final message = bytes.sublist(offset, offset + length);
    if (message.skip(1).any((byte) => byte < 0 || byte > 127)) {
      throw ArgumentError('Invalid MIDI data.');
    }
    messages.add(message);
    offset += length;
  }
  return messages;
}

bool isSlotOrder(List<int> order) =>
    order.length == 8 &&
    order.toSet().length == 8 &&
    order.every((slot) => slot >= 0 && slot < 8);

List<int> moveSlot(List<int> order, int slot, int position) {
  final result = List<int>.of(order);
  final from = result.indexOf(slot);
  if (from < 0 || position < 0 || position > 7 || from == position) {
    return result;
  }
  result.removeAt(from);
  result.insert(position, slot);
  return result;
}

List<int> moveSlotMessage(int slot, int position) =>
    nrpn(10, 7, slot * 8 + position, raw: true);
