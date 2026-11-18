import 'package:material_ui/material_ui.dart';
import '../../core/presets.dart';
import '../../onyx_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class PresetsPage extends StatefulWidget {
  final OnyxController controller;
  const PresetsPage({super.key, required this.controller});
  @override
  State<PresetsPage> createState() => _PresetsPageState();
}

class _PresetsPageState extends State<PresetsPage> {
  final _range = TextEditingController(text: '1-80');
  final _prefix = TextEditingController(text: 'P');
  final Set<int> _selected = {};
  PresetBank? _displayed;
  OnyxController get controller => widget.controller;

  @override
  void dispose() {
    _range.dispose();
    _prefix.dispose();
    super.dispose();
  }

  void _setRange() {
    try {
      final slots = parsePresetSlots(_range.text);
      setState(() {
        _selected.clear();
        _selected.addAll(
          slots.where((slot) => controller.bank?.presets[slot] != null),
        );
      });
    } catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  Future<void> _restore() async {
    final slots = _selected.toList()..sort();
    if (slots.isEmpty) return;
    if (!await confirmAction(
      context,
      title: '${slots.length}개 프리셋 복원',
      message:
          '${controller.isDemo ? '데모 앰프' : controller.deviceName}의 선택한 슬롯을 백업 데이터로 덮어씁니다. 기존 톤은 복원 후 되돌릴 수 없으니 먼저 백업해 주세요.\n\n프리셋이 사용하는 NAM·IR 파일은 별도로 기기에 있어야 합니다.',
      action: '복원',
      destructive: true,
    )) {
      return;
    }
    if (mounted) {
      await runAction(context, () => controller.restorePresets(slots));
    }
  }

  Future<void> _save() async {
    final bank = controller.bank;
    if (bank == null) return;
    if (await controller.files.save(bank, controller.bankName)) {
      controller.announce('프리셋 백업을 파일로 저장했습니다.');
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final bank = controller.bank;
    if (bank == null) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    await controller.files.share(bank, controller.bankName, origin);
  }

  void _convert({bool? chain, bool? ampLevel, String? prefix}) {
    final options = controller.conversionOptions;
    controller.convertBank(
      BankConversionOptions(
        preserveChain: chain ?? options.preserveChain,
        copyAmpLevel: ampLevel ?? options.copyAmpLevel,
        namePrefix: prefix ?? options.namePrefix,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bank = controller.bank;
    if (!identical(_displayed, bank)) {
      _displayed = bank;
      _selected.clear();
      if (bank != null) {
        _selected.addAll([
          for (var slot = 0; slot < 80; slot++)
            if (bank.presets[slot] != null) slot,
        ]);
      }
    }
    return PageScroll(
      id: 'presets',
      children: [
        const PageIntro(
          eyebrow: 'PRESET VAULT',
          title: '프리셋 보관함',
          description: '80개의 톤을 백업하고 공유하세요. 필요한 슬롯만 선택해 복원할 수도 있습니다.',
        ),
        Panel(
          title: '백업과 가져오기',
          icon: Icons.inventory_2_outlined,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('read-presets'),
                  onPressed: controller.canEdit
                      ? () => runAction(context, controller.readPresets)
                      : null,
                  icon: const Icon(Icons.bluetooth, size: 18),
                  label: const Text('기기에서 읽기'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('import-presets'),
                  onPressed: controller.busy
                      ? null
                      : () => runAction(context, controller.importBank),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('파일 가져오기'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('export-presets'),
                  onPressed: bank == null || controller.busy
                      ? null
                      : () => runAction(context, _save),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('파일 저장'),
                ),
                Builder(
                  builder: (buttonContext) => OutlinedButton.icon(
                    onPressed: bank == null || controller.busy
                        ? null
                        : () => runAction(context, () => _share(buttonContext)),
                    icon: const Icon(Icons.ios_share, size: 17),
                    label: const Text('공유'),
                  ),
                ),
              ],
            ),
            const HelpNote(
              'Onyx JSON 백업과 순정 .abkx 파일을 가져올 수 있습니다. 기기에서 읽기는 Onyx 1.08 이상, 검증을 포함한 복원은 1.13 이상이 필요합니다.',
            ),
          ],
        ),
        if (controller.canConvertBank) ...[
          const SizedBox(height: 16),
          Panel(
            title: '순정 백업 변환',
            icon: Icons.transform,
            children: [
              ToggleRow(
                label: '원본 체인 순서 유지',
                value: controller.conversionOptions.preserveChain,
                onChanged: controller.busy
                    ? null
                    : (value) => _convert(chain: value),
              ),
              ToggleRow(
                label: '원본 앰프 레벨 복사',
                description: '끄면 변환된 앰프 MASTER를 50으로 설정',
                value: controller.conversionOptions.copyAmpLevel,
                onChanged: controller.busy
                    ? null
                    : (value) => _convert(ampLevel: value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _prefix,
                enabled: !controller.busy,
                maxLength: 16,
                decoration: const InputDecoration(labelText: '프리셋 이름 접두어'),
                onChanged: (value) => _convert(prefix: value),
              ),
              const HelpNote(
                '순정 모델을 Onyx 모델로 대응시킵니다. 순정과 커스텀 펌웨어의 소리가 완전히 같지는 않으므로 복원 후 확인하세요.',
              ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        if (bank == null)
          Panel(
            children: [
              const SizedBox(height: 20),
              const Icon(
                Icons.library_music_outlined,
                size: 44,
                color: OnyxColors.accent,
              ),
              const SizedBox(height: 18),
              const Text(
                '톤을 담아두는 공간',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                '앰프에서 프리셋을 읽거나\n저장해 둔 백업 파일을 가져오세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: OnyxColors.muted,
                  height: 1.7,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
            ],
          )
        else ...[
          Text(
            controller.bankName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            '${bank.readableCount}개 프리셋${bank.unreadable.isNotEmpty ? ' · 읽기 실패 ${bank.unreadable.length}개' : ''}',
            style: const TextStyle(color: OnyxColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Panel(
            title: '복원할 슬롯 선택',
            icon: Icons.checklist,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('restore-range'),
                      controller: _range,
                      enabled: !controller.busy,
                      decoration: const InputDecoration(
                        labelText: '슬롯 범위',
                        hintText: '예: 1-10,15',
                      ),
                      onSubmitted: (_) => _setRange(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: controller.busy ? null : _setRange,
                    child: const Text('선택'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: controller.busy
                        ? null
                        : () => setState(() {
                            _selected.clear();
                            _selected.addAll([
                              for (var slot = 0; slot < 80; slot++)
                                if (bank.presets[slot] != null) slot,
                            ]);
                          }),
                    child: const Text('전체 선택', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: controller.busy
                        ? null
                        : () => setState(_selected.clear),
                    child: const Text('선택 해제', style: TextStyle(fontSize: 12)),
                  ),
                  const Spacer(),
                  Text(
                    '${_selected.length}개',
                    style: const TextStyle(
                      color: OnyxColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                key: const ValueKey('restore-presets'),
                onPressed: controller.canEdit && _selected.isNotEmpty
                    ? _restore
                    : null,
                icon: const Icon(Icons.restore, size: 19),
                label: Text('${_selected.length}개 복원·검증'),
              ),
              if (bank.unreadable.isNotEmpty)
                const HelpNote(
                  '읽기에 실패한 슬롯은 복원에서 제외합니다. 다른 백업으로 데이터를 보완한 뒤 복원하세요.',
                ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, bounds) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 80,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: bounds.maxWidth >= 900
                    ? 5
                    : bounds.maxWidth >= 600
                    ? 4
                    : 2,
                mainAxisExtent: 84,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, slot) {
                final preset = bank.presets[slot],
                    selected = _selected.contains(slot),
                    unreadable = bank.unreadable.contains(slot);
                return Semantics(
                  button: preset != null,
                  selected: selected,
                  label:
                      'P${slot + 1} ${preset?.name ?? (unreadable ? '읽기 실패' : '데이터 없음')}',
                  child: Material(
                    color: selected
                        ? OnyxColors.accent.withValues(alpha: .08)
                        : OnyxColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: selected
                            ? OnyxColors.accent.withValues(alpha: .55)
                            : OnyxColors.border,
                      ),
                    ),
                    child: InkWell(
                      key: ValueKey('preset-slot-$slot'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: preset == null || controller.busy
                          ? null
                          : () => setState(() {
                              if (!_selected.add(slot)) _selected.remove(slot);
                            }),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'P${(slot + 1).toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      color: OnyxColors.muted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Icon(
                                  selected
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  size: 15,
                                  color: selected
                                      ? OnyxColors.accent
                                      : OnyxColors.border,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              preset?.name.isNotEmpty == true
                                  ? preset!.name
                                  : unreadable
                                  ? '읽기 실패'
                                  : preset?.empty == true
                                  ? '빈 프리셋'
                                  : '데이터 없음',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: unreadable
                                    ? OnyxColors.danger
                                    : preset == null
                                    ? OnyxColors.muted
                                    : OnyxColors.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
