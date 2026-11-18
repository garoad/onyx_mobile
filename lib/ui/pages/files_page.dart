import 'dart:math' as math;
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/amp_state.dart';
import '../../core/sound_files.dart';
import '../../onyx_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class FilesPage extends StatefulWidget {
  final OnyxController controller;
  const FilesPage({super.key, required this.controller});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  int _kind = 1;
  OnyxController get controller => widget.controller;

  Future<void> _replace() async {
    final model = await showDialog<StoredModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('교체할 IR 선택'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final model in controller.models.stored(1))
                ListTile(
                  title: Text(model.name),
                  subtitle: Text('저장 슬롯 ${model.index + 1}'),
                  onTap: () => Navigator.pop(context, model),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
    if (model == null || !mounted) return;
    if (!await confirmAction(
      context,
      title: 'IR을 교체할까요?',
      message: '${model.name}을 선택한 IR로 덮어씁니다. 이 슬롯을 사용하는 프리셋의 캐비닛 소리도 바뀝니다.',
      action: '교체',
      destructive: true,
    )) {
      return;
    }
    if (mounted) {
      await runAction(
        context,
        () => controller.uploadCabinet(replaceIndex: model.index),
      );
    }
  }

  Future<void> _rename(StoredModel model) async {
    final kind = _kind;
    final text = TextEditingController(text: model.name);
    final limit = kind == 0 ? 23 : 15;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이름 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: text,
              autofocus: true,
              maxLength: limit,
              decoration: const InputDecoration(labelText: '모델 이름'),
              onSubmitted: (value) => Navigator.pop(context, value.trim()),
            ),
            const Text(
              '기기가 지원하는 영문·숫자·기호를 사용하세요.',
              style: TextStyle(color: OnyxColors.muted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text.trim()),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    // The route animation can still reference its text field after the dialog future completes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
    if (name != null && mounted) {
      await runAction(context, () => controller.renameModel(kind, model, name));
    }
  }

  Future<void> _delete(StoredModel model) async {
    final kind = _kind;
    if (!await confirmAction(
      context,
      title: '${model.name} 삭제',
      message:
          '저장된 ${kind == 0 ? '캡처' : 'IR'}를 삭제합니다. 이 모델을 사용하는 프리셋의 소리가 달라질 수 있습니다.',
      action: '삭제',
      destructive: true,
    )) {
      return;
    }
    if (mounted) {
      await runAction(context, () => controller.deleteModel(kind, model));
    }
  }

  Future<void> _clear() async {
    final kind = _kind;
    if (!await confirmAction(
      context,
      title: kind == 0 ? '캡처 전체 삭제' : 'IR 전체 삭제',
      message:
          '기기에 저장된 ${kind == 0 ? '사용자 캡처' : '사용자 IR'}를 모두 삭제합니다. 이 작업은 되돌릴 수 없습니다.',
      action: '모두 삭제',
      destructive: true,
    )) {
      return;
    }
    if (mounted) await runAction(context, () => controller.clearModels(kind));
  }

  Future<void> _export(SoundFile file) async {
    final stem = file.name.replaceFirst(RegExp(r'\.[^.]*$'), '');
    final saved = await controller.files.saveData(
      file.bytes,
      '$stem.${_kind == 0 ? 'wave' : 'cab'}',
    );
    if (saved) controller.announce('변환한 파일을 저장했습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final file = _kind == 1 ? controller.cabinetFile : controller.captureFile;
    final stored = controller.models.stored(_kind);
    final free = _kind == 1
        ? controller.state?.freeCabinets
        : controller.state?.freeCaptures;
    final canUpload = controller.canEdit && !controller.isDemo && file != null;
    return PageScroll(
      id: 'files',
      children: [
        const PageIntro(
          eyebrow: 'SOUND LIBRARY',
          title: '캡처와 캐비닛',
          description: '나만의 NAM 캡처와 캐비닛 IR로 톤의 색깔을 바꿔보세요.',
        ),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.speaker_group, size: 18),
              label: Text('캐비닛 IR'),
            ),
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.memory, size: 18),
              label: Text('NAM 캡처'),
            ),
          ],
          selected: {_kind},
          onSelectionChanged: controller.busy
              ? null
              : (next) => setState(() {
                  _kind = next.single;
                }),
        ),
        const SizedBox(height: 22),
        ResponsivePanels(
          children: [
            Panel(
              title: _kind == 1 ? 'IR 파일 가져오기' : 'NAM 파일 변환',
              icon: _kind == 1 ? Icons.folder_open : Icons.memory,
              children: [
                Text(
                  _kind == 1
                      ? 'WAV 또는 Q18 캐비닛 파일을 선택하세요. WAV는 앰프용 44.1 kHz IR로 변환합니다.'
                      : 'A2 Lite .nam, .namb 또는 원본 모델을 선택해 USB 업로드용 파일로 변환할 수 있습니다.',
                  style: const TextStyle(
                    color: OnyxColors.muted,
                    fontSize: 12,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  key: ValueKey('pick-${_kind == 1 ? 'ir' : 'nam'}'),
                  onPressed: controller.busy
                      ? null
                      : () => runAction(
                          context,
                          _kind == 1
                              ? controller.pickCabinet
                              : controller.pickCapture,
                        ),
                  icon: const Icon(Icons.add, size: 19),
                  label: const Text('파일 선택'),
                ),
                if (file != null) ...[
                  const SizedBox(height: 22),
                  Text(
                    file.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    file.description,
                    style: const TextStyle(
                      color: OnyxColors.muted,
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                  if (_kind == 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: SizedBox(
                        height: 72,
                        child: CustomPaint(painter: _IrPainter(file.bytes)),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_kind == 1) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: canUpload
                              ? () => runAction(
                                  context,
                                  () =>
                                      controller.uploadCabinet(temporary: true),
                                )
                              : null,
                          icon: const Icon(Icons.play_arrow, size: 19),
                          label: const Text('임시 적용'),
                        ),
                        OutlinedButton.icon(
                          onPressed: canUpload && (free ?? 0) > 0
                              ? () => runAction(
                                  context,
                                  () => controller.uploadCabinet(),
                                )
                              : null,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('기기에 저장'),
                        ),
                        if (stored.isNotEmpty)
                          OutlinedButton(
                            onPressed: canUpload ? _replace : null,
                            child: const Text('기존 IR 교체'),
                          ),
                      ],
                    ),
                    HelpNote(
                      controller.isDemo
                          ? '데모에서는 IR 전송을 사용할 수 없습니다. 실제 앰프에 연결해 주세요.'
                          : !controller.connected
                          ? 'Bluetooth로 전송하려면 앰프를 연결하세요.'
                          : '임시 적용은 프리셋에 저장되지 않습니다. 기기 저장·교체에는 Onyx 1.13 이상이 필요합니다.',
                    ),
                  ],
                  TextButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () => runAction(context, () => _export(file)),
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('변환 파일 저장'),
                  ),
                ],
                if (_kind == 0) ...[
                  const HelpNote(
                    'NAM 업로드와 펌웨어 설치는 Onyx 펌웨어에서 USB로만 지원됩니다. 컴퓨터의 Onyx 에디터를 사용하세요.',
                  ),
                  TextButton.icon(
                    onPressed: () => runAction(context, () async {
                      if (!await launchUrl(
                        Uri.parse('https://github.com/28spawn/Pocket-Onyx'),
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw StateError('안내 페이지를 열 수 없습니다.');
                      }
                    }),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('PC 에디터 안내'),
                  ),
                ],
              ],
            ),
            Panel(
              title: _kind == 1 ? '기기에 저장된 IR' : '기기에 저장된 캡처',
              icon: Icons.inventory_2_outlined,
              children: [
                if (controller.connected)
                  Text(
                    '${stored.length}개 저장 · ${free ?? 0}개 슬롯 사용 가능',
                    style: const TextStyle(
                      color: OnyxColors.muted,
                      fontSize: 12,
                    ),
                  ),
                if (stored.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      controller.connected
                          ? '저장된 사용자 모델이 없습니다.'
                          : '앰프를 연결하면 저장된 모델이 표시됩니다.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: OnyxColors.muted,
                        fontSize: 12,
                        height: 1.65,
                      ),
                    ),
                  ),
                for (final model in stored)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: OnyxColors.elevated,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${model.index + 1}',
                        style: const TextStyle(
                          color: OnyxColors.accent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text(
                      model.name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: PopupMenuButton<String>(
                      enabled: controller.canEdit,
                      tooltip: '모델 관리',
                      onSelected: (action) {
                        if (action == 'rename') {
                          _rename(model);
                        } else {
                          _delete(model);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('이름 변경'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            '삭제',
                            style: TextStyle(color: OnyxColors.danger),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (stored.isNotEmpty) ...[
                  const Divider(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: OnyxColors.danger,
                    ),
                    onPressed: controller.canEdit ? _clear : null,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('모두 삭제'),
                  ),
                ],
                if (_kind == 1 && controller.state?.temporaryCabinet == true)
                  const HelpNote('지금은 임시 IR이 적용되어 있습니다.'),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _IrPainter extends CustomPainter {
  final Uint8List bytes;
  _IrPainter(this.bytes);
  @override
  void paint(Canvas canvas, Size size) {
    final data = ByteData.sublistView(bytes), count = bytes.length ~/ 4;
    var peak = 1;
    for (var index = 0; index < count; index++) {
      peak = math.max(peak, data.getInt32(index * 4, Endian.little).abs());
    }
    final mid = size.height / 2;
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = OnyxColors.border
        ..strokeWidth = 1,
    );
    final path = Path();
    for (var index = 0; index < count; index++) {
      final x = index * size.width / math.max(1, count - 1),
          y = mid - data.getInt32(index * 4, Endian.little) / peak * mid * .85;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = OnyxColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_IrPainter oldDelegate) =>
      !identical(bytes, oldDelegate.bytes);
}
