// SPDX-License-Identifier: GPL-3.0-only
// Conversion rules ported from Pocket-Onyx, Copyright (C) 2026 The Onyx Authors (@28spawn).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class SoundFile {
  final Uint8List bytes;
  final String name;
  final String description;
  final int? taps;
  const SoundFile({
    required this.bytes,
    required this.name,
    required this.description,
    this.taps,
  });
}

int _round(double value) => (value + 0.5).floor();

SoundFile readCapture(Uint8List bytes, String filename) {
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    start = 3;
  }
  while (start < bytes.length && [9, 10, 13, 32].contains(bytes[start])) {
    start++;
  }
  if (start < bytes.length && bytes[start] == 123) {
    return _convertNam(bytes, filename);
  }
  final magic = String.fromCharCodes(bytes.take(4));
  if (magic == 'WAVE' && bytes.length <= 8192) {
    return SoundFile(
      bytes: bytes,
      name: filename,
      description: 'WaveNet 원본 · ${bytes.length} B · USB 전송',
    );
  }
  if (bytes.length == 3852 || bytes.length == 4040) {
    return SoundFile(
      bytes: Uint8List.fromList(bytes.take(3852).toList()),
      name: filename,
      description: 'NAM 원본 모델 · 3852 B · USB 전송',
    );
  }
  if (magic.startsWith('@M') || magic == 'NAM\u0000') {
    final offset = bytes.length >= 6204 + 3852 ? 6204 : 0;
    if (bytes.length >= offset + 3852) {
      return SoundFile(
        bytes: bytes.sublist(offset, offset + 3852),
        name: filename,
        description: '.namb 모델 추출 · 3852 B · USB 전송',
      );
    }
  }
  throw const FormatException(
    '지원하는 NAM 파일이 아닙니다. A2 Lite .nam, .namb, 원본 모델 또는 WAVE 파일을 선택해 주세요.',
  );
}

double _number(Object? value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  if (number == null || !number.isFinite) {
    throw const FormatException('NAM 모델에 숫자가 아닌 값이 있습니다.');
  }
  return number;
}

SoundFile _convertNam(Uint8List bytes, String filename) {
  final decoded = jsonDecode(
    utf8.decode(bytes).replaceFirst(RegExp('^\ufeff'), ''),
  );
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('올바른 .nam JSON 파일이 아닙니다.');
  }
  Map<String, dynamic>? model;
  if (decoded['architecture'] == 'SlimmableContainer') {
    final children = (decoded['config'] as Map?)?['submodels'];
    if (children is List) {
      for (final child in children) {
        final candidate = child is Map ? child['model'] : null;
        final weights = candidate is Map ? candidate['weights'] : null;
        if (candidate is Map<String, dynamic> &&
            weights is List &&
            [1870, 1871].contains(weights.length)) {
          model = candidate;
          break;
        }
      }
    }
    if (model == null) {
      throw const FormatException(
        '이 캡처에는 A2 Lite 모델이 없습니다. Full 모델은 앰프의 8 KB 슬롯에 들어가지 않습니다.',
      );
    }
  } else if (decoded['architecture'] == 'WaveNet' &&
      decoded['weights'] is List &&
      [1870, 1871].contains((decoded['weights'] as List).length)) {
    model = decoded;
  }
  if (model == null) {
    throw const FormatException('1870/1871개 가중치의 A2 Lite WaveNet 모델이 필요합니다.');
  }
  final head = _number((model['config'] as Map?)?['head_scale'] ?? 1);
  final weights = (model['weights'] as List).map(_number).toList();
  if (weights.length == 1870) weights.add(head);
  final metadata =
      model['metadata'] as Map? ?? decoded['metadata'] as Map? ?? {};
  final name = (metadata['name'] ?? metadata['gear_model'] ?? filename)
      .toString();
  final gear = (metadata['gear_type'] ?? '').toString().toLowerCase();
  final text = '${name.toLowerCase()} ${filename.toLowerCase()}';
  final cabFree = RegExp(
    r'cab[ _\-]*free|no[ _\-]*cab|without[ _\-]*cab|w/o[ _\-]*cab|cabless|cab[ _\-]*less|amp[ _\-]*only|di[ _\-]*out|direct[ _\-]*out',
  ).hasMatch(text);
  final cabinet =
      !cabFree &&
      (gear.contains('cab') ||
          RegExp(
            r'cab|full[ _\-]*rig|^fr[ _\-]|\bsm ?5[78]\b|\bmd ?421\b|\be ?609\b|\br ?121\b|\bu ?87\b|\bmic(ed|\x27d)?\b',
          ).hasMatch(text));
  double? metadataValue(List<Map> maps, List<String> keys) {
    for (final map in maps) {
      for (final key in keys) {
        if (map[key] != null) return _number(map[key]);
      }
    }
    return null;
  }

  final maps = [
    metadata,
    if (decoded['metadata'] is Map) decoded['metadata'] as Map,
    if (decoded['config'] is Map) decoded['config'] as Map,
    decoded,
  ];
  final input = metadataValue(maps, [
    'input_level_dbu',
    'input_level',
    'input_dBu',
    'calibration_dBu',
  ]);
  final loudness = metadataValue(
    [
      metadata,
      if (decoded['metadata'] is Map) decoded['metadata'] as Map,
      decoded,
    ],
    ['loudness', 'output_loudness', 'loudness_db'],
  );
  final trim = input == null
      ? 1.0
      : double.parse(math.pow(10, (4 - input) / 20).toStringAsFixed(4));
  if (!trim.isFinite) throw const FormatException('NAM 입력 레벨이 잘못되었습니다.');
  final makeup = loudness == null
      ? 0.0
      : _round((-15.5 - loudness + (cabinet ? -4 : 0)).clamp(-12, 12) * 4) / 4;
  final flags =
      (cabinet ? 1 : 0) |
      (loudness == null ? 0 : 2 | (((makeup * 4).round() & 255) << 8));
  final raw = Uint8List(20 + weights.length * 4),
      view = ByteData(20 + weights.length * 4);
  raw.setRange(0, 4, ascii.encode('WAVE'));
  view.setUint32(4, weights.length, Endian.little);
  view.setFloat32(8, head, Endian.little);
  view.setUint32(12, flags, Endian.little);
  view.setFloat32(16, trim, Endian.little);
  for (var index = 0; index < weights.length; index++) {
    view.setFloat32(20 + index * 4, weights[index], Endian.little);
  }
  raw.setRange(4, raw.length, view.buffer.asUint8List(), 4);
  return SoundFile(
    bytes: raw,
    name: name,
    description:
        'A2 Lite · ${weights.length} 가중치 · ${raw.length} B${cabinet ? ' · 캐비닛 포함' : ''} · USB 전송',
  );
}

SoundFile readCabinet(Uint8List bytes, String filename) {
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF') {
    return _wavToCabinet(bytes, filename);
  }
  if (bytes.length < 64 || bytes.length > 4096 || bytes.length % 4 != 0) {
    throw const FormatException(
      '캐비닛 원본은 Q18 int32 16~1024 탭이어야 합니다 (64~4096 B).',
    );
  }
  final view = ByteData.sublistView(bytes);
  var peak = 0;
  for (var offset = 0; offset < bytes.length; offset += 4) {
    peak = math.max(peak, view.getInt32(offset, Endian.little).abs());
  }
  if (peak == 0) throw const FormatException('IR에 신호가 없습니다.');
  return SoundFile(
    bytes: bytes,
    name: filename,
    taps: bytes.length ~/ 4,
    description: 'Q18 원본 · ${bytes.length ~/ 4} 탭 · ${bytes.length} B',
  );
}

class _Wav {
  final Float64List samples;
  final int rate;
  const _Wav(this.samples, this.rate);
}

_Wav _parseWav(Uint8List bytes) {
  if (bytes.length < 44 ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('올바른 WAV 파일이 아닙니다.');
  }
  final view = ByteData.sublistView(bytes);
  int? code, channels, rate, bits, dataOffset, dataLength;
  for (var offset = 12; offset + 8 <= bytes.length;) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4)),
        length = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (body + length > bytes.length) {
      throw const FormatException('WAV 파일이 잘렸습니다.');
    }
    if (id == 'fmt ') {
      if (length < 16) throw const FormatException('WAV fmt 데이터가 잘못되었습니다.');
      code = view.getUint16(body, Endian.little);
      channels = view.getUint16(body + 2, Endian.little);
      rate = view.getUint32(body + 4, Endian.little);
      bits = view.getUint16(body + 14, Endian.little);
      // WAVE_FORMAT_EXTENSIBLE stores the subformat at fmt body +24, after the channel mask.
      if (code == 0xfffe) {
        if (length < 40) throw const FormatException('확장 WAV 형식이 잘못되었습니다.');
        code = view.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data') {
      dataOffset = body;
      dataLength = length;
    }
    offset = body + length + (length & 1);
  }
  if (code == null ||
      channels == null ||
      rate == null ||
      bits == null ||
      dataOffset == null ||
      dataLength == null) {
    throw const FormatException('WAV의 fmt 또는 data 영역이 없습니다.');
  }
  if (channels < 1 || channels > 64 || rate < 1 || rate > 384000) {
    throw const FormatException('WAV 채널 수 또는 샘플레이트가 잘못되었습니다.');
  }
  if (!(code == 1 && [16, 24, 32].contains(bits) ||
      code == 3 && [32, 64].contains(bits))) {
    throw const FormatException('WAV는 16/24/32비트 PCM 또는 32/64비트 float를 지원합니다.');
  }
  final width = bits ~/ 8, frames = dataLength ~/ (channels * (bits ~/ 8));
  if (frames * 44100 / rate > 441000) {
    throw const FormatException('IR WAV는 10초 이하의 파일을 선택해 주세요.');
  }
  final samples = Float64List(frames);
  for (var frame = 0; frame < frames; frame++) {
    final offset = dataOffset + frame * channels * width;
    final value = code == 3
        ? (bits == 32
              ? view.getFloat32(offset, Endian.little)
              : view.getFloat64(offset, Endian.little))
        : bits == 16
        ? view.getInt16(offset, Endian.little) / 32768
        : bits == 24
        ? (view.getUint8(offset) |
                  view.getUint8(offset + 1) << 8 |
                  view.getInt8(offset + 2) << 16) /
              8388608
        : view.getInt32(offset, Endian.little) / 2147483648;
    if (!value.isFinite) throw const FormatException('WAV에 유효하지 않은 샘플이 있습니다.');
    samples[frame] = value;
  }
  return _Wav(samples, rate);
}

Float64List _resample(Float64List samples, int from) {
  if (from == 44100) return samples;
  final output = Float64List((samples.length * 44100 / from).floor());
  final ratio = from / 44100, filter = math.min(1.0, 44100 / from);
  double sinc(double value) =>
      value == 0 ? 1 : math.sin(math.pi * value) / (math.pi * value);
  for (var index = 0; index < output.length; index++) {
    final center = index * ratio;
    var sum = 0.0;
    for (
      var source = (center - 3 / filter).ceil();
      source <= (center + 3 / filter).floor();
      source++
    ) {
      if (source < 0 || source >= samples.length) continue;
      final distance = (center - source) * filter;
      sum += samples[source] * filter * sinc(distance) * sinc(distance / 3);
    }
    output[index] = sum;
  }
  return output;
}

SoundFile _wavToCabinet(Uint8List bytes, String filename) {
  final wav = _parseWav(bytes);
  final samples = _resample(wav.samples, wav.rate);
  var peak = 0.0, first = 0;
  for (final value in samples) {
    peak = math.max(peak, value.abs());
  }
  if (peak == 0) throw const FormatException('IR에 신호가 없습니다.');
  while (first < samples.length && samples[first].abs() < peak * 0.05) {
    first++;
  }
  first = math.max(0, first - 4);
  final taps = samples.sublist(first, math.min(first + 1024, samples.length));
  if (taps.length < 16) throw const FormatException('IR은 최소 16개 샘플이 필요합니다.');
  final fade = math.min(128, taps.length >> 2);
  for (var index = 0; index < fade; index++) {
    taps[taps.length - 1 - index] *=
        0.5 - 0.5 * math.cos(math.pi * index / fade);
  }
  final output = Uint8List(taps.length * 4),
      view = ByteData(taps.length * 4),
      gain = 0.9 * 262144 / peak;
  for (var index = 0; index < taps.length; index++) {
    view.setInt32(
      index * 4,
      _round(taps[index] * gain).clamp(-2147483648, 2147483647),
      Endian.little,
    );
  }
  output.setAll(0, view.buffer.asUint8List());
  return SoundFile(
    bytes: output,
    name: filename,
    taps: taps.length,
    description:
        'WAV ${wav.rate} Hz → 44.1 kHz · ${taps.length} 탭 · ${output.length} B',
  );
}
