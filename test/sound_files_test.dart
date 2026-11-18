import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx_mobile/core/sound_files.dart';

void main() {
  test(
    'PCM and float WAV variants convert to bounded Q18 cabinet impulses',
    () {
      for (final encoding in [(1, 16), (1, 24), (1, 32), (3, 32), (3, 64)]) {
        final cabinet = readCabinet(
          makeWav(code: encoding.$1, bits: encoding.$2),
          'test.wav',
        );
        expect(cabinet.taps, 1024);
        expect(cabinet.bytes.length, 4096);
        final view = ByteData.sublistView(cabinet.bytes);
        expect(view.getInt32(0, Endian.little), 0);
        expect(view.getInt32(4 * 4, Endian.little), closeTo(.9 * 262144, 1));
      }
    },
  );

  test('extensible WAV subformat is read relative to its fmt chunk', () {
    final result = readCabinet(
      makeWav(code: 1, bits: 24, extensible: true, junk: true),
      'extensible.wav',
    );
    expect(result.taps, 1024);
    expect(result.bytes.length, 4096);
    final resampled = readCabinet(makeWav(rate: 48000), '48k.wav');
    expect(resampled.taps, 1024);
    expect(resampled.description, contains('48000 Hz → 44.1 kHz'));
  });

  test('empty IR, corrupt WAV and nonfinite audio fail before any upload', () {
    expect(
      () => readCabinet(Uint8List(64), 'silent.cab'),
      throwsFormatException,
    );
    expect(() => readCabinet(Uint8List(63), 'bad.cab'), throwsFormatException);
    final corrupt = makeWav()..[40] = 255;
    expect(() => readCabinet(corrupt, 'bad.wav'), throwsFormatException);
    final nan = makeWav(code: 3, bits: 32);
    ByteData.sublistView(
      nan,
    ).setFloat32(44 + 16 * 4, double.nan, Endian.little);
    expect(() => readCabinet(nan, 'nan.wav'), throwsFormatException);
  });

  test('NAM A2 Lite extracts weights, calibration and cabinet metadata', () {
    final model = {
      'architecture': 'WaveNet',
      'config': {'head_scale': .87},
      'weights': List.filled(1870, .001),
    };
    final nam = {
      'architecture': 'SlimmableContainer',
      'metadata': {
        'name': 'My Full Rig',
        'input_level_dbu': 4,
        'loudness': -25,
      },
      'config': {
        'submodels': [
          {'model': model},
        ],
      },
    };
    final result = readCapture(
      Uint8List.fromList(utf8.encode(jsonEncode(nam))),
      'capture.nam',
    );
    final view = ByteData.sublistView(result.bytes);
    expect(String.fromCharCodes(result.bytes.take(4)), 'WAVE');
    expect(result.bytes.length, 7504);
    expect(view.getUint32(4, Endian.little), 1871);
    expect(view.getFloat32(8, Endian.little), closeTo(.87, 1e-6));
    expect(view.getFloat32(16, Endian.little), 1);
    expect(view.getUint32(12, Endian.little), 3 | 22 << 8);
    expect(view.getFloat32(20 + 1870 * 4, Endian.little), closeTo(.87, 1e-6));
    final full = {...model, 'weights': List.filled(10000, 0)};
    expect(
      () => readCapture(
        Uint8List.fromList(utf8.encode(jsonEncode(full))),
        'full.nam',
      ),
      throwsFormatException,
    );
  });
}

Uint8List makeWav({
  int code = 1,
  int bits = 16,
  int rate = 44100,
  bool extensible = false,
  bool junk = false,
}) {
  final width = bits ~/ 8,
      fmtSize = extensible ? 40 : 16,
      junkSize = junk ? 12 : 0;
  const frames = 1200;
  final bytes = Uint8List(12 + junkSize + 8 + fmtSize + 8 + frames * width),
      view = ByteData.sublistView(bytes);
  void text(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, ascii.encode(value));
  text(0, 'RIFF');
  view.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVE');
  var offset = 12;
  if (junk) {
    text(offset, 'JUNK');
    view.setUint32(offset + 4, 4, Endian.little);
    offset += 12;
  }
  text(offset, 'fmt ');
  view.setUint32(offset + 4, fmtSize, Endian.little);
  final body = offset + 8;
  view.setUint16(body, extensible ? 0xfffe : code, Endian.little);
  view.setUint16(body + 2, 1, Endian.little);
  view.setUint32(body + 4, rate, Endian.little);
  view.setUint32(body + 8, rate * width, Endian.little);
  view.setUint16(body + 12, width, Endian.little);
  view.setUint16(body + 14, bits, Endian.little);
  if (extensible) {
    view.setUint16(body + 16, 22, Endian.little);
    view.setUint16(body + 18, bits, Endian.little);
    view.setUint16(body + 24, code, Endian.little);
  }
  offset = body + fmtSize;
  text(offset, 'data');
  view.setUint32(offset + 4, frames * width, Endian.little);
  final signal = offset + 8 + 16 * width;
  if (code == 3) {
    if (bits == 32) {
      view.setFloat32(signal, 1, Endian.little);
    } else {
      view.setFloat64(signal, 1, Endian.little);
    }
  } else if (bits == 16) {
    view.setInt16(signal, 32767, Endian.little);
  } else if (bits == 24) {
    bytes.setRange(signal, signal + 3, [255, 255, 127]);
  } else {
    view.setInt32(signal, 2147483647, Endian.little);
  }
  return bytes;
}
