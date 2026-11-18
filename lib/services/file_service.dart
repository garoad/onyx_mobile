import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/presets.dart';

class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
}

class FileService {
  Future<PickedFile?> pick(List<String> extensions) async {
    // Native document pickers may not know .nam/.abkx MIME types; validate the extension after selection.
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return null;
    if (!extensions.any(
      (extension) => file.name.toLowerCase().endsWith(extension),
    )) {
      throw FormatException('지원하는 파일을 선택해 주세요: ${extensions.join(', ')}');
    }
    if ((file.lengthSync() ?? 0) > 16 * 1024 * 1024) {
      throw const FormatException('16 MB 이하의 파일을 선택해 주세요.');
    }
    final parts = BytesBuilder(copy: false);
    await for (final part in file.readAsByteStream()) {
      if (parts.length + part.length > 16 * 1024 * 1024) {
        throw const FormatException('16 MB 이하의 파일을 선택해 주세요.');
      }
      parts.add(part);
    }
    if (parts.isEmpty) throw const FormatException('선택한 파일이 비어 있습니다.');
    return PickedFile(file.name, parts.takeBytes());
  }

  Future<bool> save(PresetBank bank, String name) async {
    final bytes = Uint8List.fromList(utf8.encode(bank.encode()));
    return saveData(bytes, name, mimeType: 'application/json');
  }

  Future<bool> saveData(
    Uint8List bytes,
    String name, {
    String mimeType = 'application/octet-stream',
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: safeFileName(name),
      bytes: bytes,
      mimeType: mimeType,
    );
    return uri != null;
  }

  Future<void> share(PresetBank bank, String name, Rect origin) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/${DateTime.now().microsecondsSinceEpoch}-${safeFileName(name)}',
    );
    await file.writeAsString(bank.encode(), flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        title: 'Onyx 프리셋 백업',
        sharePositionOrigin: origin,
      ),
    );
  }
}

String safeFileName(String value) {
  final name = value
      .replaceAll(RegExp(r'[/\\\x00-\x1f:*?"<>|]'), '_')
      .replaceFirst(RegExp(r'^\.+'), '');
  final limited = name.substring(0, name.length.clamp(0, 100));
  return limited.isEmpty ? 'onyx-presets.json' : limited;
}
