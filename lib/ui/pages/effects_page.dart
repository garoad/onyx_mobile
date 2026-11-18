import 'package:material_ui/material_ui.dart';
import '../../core/midi_protocol.dart';
import '../../onyx_controller.dart';
import '../theme.dart';
import '../widgets.dart';

const _effectTitles = [
  '다이내믹',
  '드라이브',
  '앰프',
  '캐비닛',
  '이퀄라이저',
  '모듈레이션',
  '딜레이',
  '리버브',
];
const _effectIcons = [
  Icons.graphic_eq,
  Icons.bolt,
  Icons.speaker,
  Icons.speaker_group,
  Icons.equalizer,
  Icons.waves,
  Icons.av_timer,
  Icons.blur_on,
];

class EffectsPage extends StatefulWidget {
  final OnyxController controller;
  const EffectsPage({super.key, required this.controller});
  @override
  State<EffectsPage> createState() => _EffectsPageState();
}

class _EffectsPageState extends State<EffectsPage> {
  int _selected = 2;
  OnyxController get controller => widget.controller;

  Future<void> _choosePreset() async {
    final slot = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: .65,
        maxChildSize: .9,
        minChildSize: .4,
        expand: false,
        builder: (context, scroll) => SafeArea(
          top: false,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 0, 22, 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '프리셋 선택',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemCount: 80,
                  itemBuilder: (context, slot) => ListTile(
                    leading: Text(
                      'P${(slot + 1).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: OnyxColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    title: Text(
                      controller.bank?.presets[slot]?.name ??
                          (controller.state?.preset == slot
                              ? controller.state!.name
                              : '프리셋 ${slot + 1}'),
                    ),
                    selected: controller.state?.preset == slot,
                    trailing: controller.state?.preset == slot
                        ? const Icon(Icons.check, color: OnyxColors.accent)
                        : null,
                    onTap: () => Navigator.pop(context, slot),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (slot != null && mounted) {
      await runAction(context, () => controller.selectPreset(slot));
    }
  }

  Future<void> _save() async {
    if (!await confirmAction(
      context,
      title: '현재 톤을 저장할까요?',
      message:
          'P${controller.state!.preset + 1}에 현재 이펙트 설정을 저장합니다. 기존 설정을 덮어씁니다.',
      action: '저장',
    )) {
      return;
    }
    if (mounted) await runAction(context, controller.saveCurrent);
  }

  Future<void> _reorder() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _OrderSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.state!;
    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 900;
        return PageScroll(
          id: 'effects',
          children: [
            const PageIntro(
              eyebrow: 'TONE STUDIO',
              title: '내 손안의 톤 스튜디오',
              description: '블록을 선택해 톤을 조절하세요. 변경한 톤은 저장 버튼으로 기기에 남길 수 있습니다.',
            ),
            Panel(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'CURRENT TONE',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.8,
                          color: OnyxColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('save-tone'),
                      onPressed: controller.canEdit ? _save : null,
                      icon: const Icon(Icons.save_outlined, size: 17),
                      label: const Text('저장', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: controller.canEdit ? _choosePreset : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'P${(state.preset + 1).toString().padLeft(2, '0')}${state.flags & 1 != 0 ? ' · STOMP' : ''}',
                                style: const TextStyle(
                                  color: OnyxColors.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                state.name.isEmpty ? '빈 프리셋' : state.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('previous-preset'),
                      tooltip: '이전 프리셋',
                      onPressed: controller.canEdit
                          ? () => runAction(context, controller.previousPreset)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      key: const ValueKey('next-preset'),
                      tooltip: '다음 프리셋',
                      onPressed: controller.canEdit
                          ? () => runAction(context, controller.nextPreset)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ParameterSlider(
                  label: '프리셋 볼륨',
                  value: state.presetVolume,
                  onChanged: controller.canEdit
                      ? controller.setPresetVolume
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '시그널 체인',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: controller.canEdit ? _reorder : null,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('순서 변경', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 8,
                separatorBuilder: (context, index) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    Icons.chevron_right,
                    size: 13,
                    color: OnyxColors.border,
                  ),
                ),
                itemBuilder: (context, position) {
                  final slot = state.order[position],
                      active = state.effect(slot).enabled,
                      selected = _selected == slot;
                  return Semantics(
                    button: true,
                    selected: selected,
                    label:
                        '${position + 1}번째 ${_effectTitles[slot]}, ${active ? '켜짐' : '바이패스'}',
                    child: InkWell(
                      key: ValueKey('chain-$slot'),
                      onTap: () => setState(() {
                        _selected = slot;
                      }),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width:
                            MediaQuery.textScalerOf(context).scale(11) * 6 + 12,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected
                              ? OnyxColors.slots[slot].withValues(alpha: .13)
                              : OnyxColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? OnyxColors.slots[slot]
                                : OnyxColors.border,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              slotNames[slot],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? OnyxColors.slots[slot]
                                    : OnyxColors.muted,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: active
                                    ? OnyxColors.slots[slot]
                                    : OnyxColors.border,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            if (wide)
              ResponsivePanels(
                children: [
                  for (final slot in state.order)
                    EffectPanel(controller: controller, slot: slot),
                ],
              )
            else
              EffectPanel(controller: controller, slot: _selected),
            const HelpNote(
              '연결된 동안 변경 사항은 앰프에 바로 적용됩니다. 저장하지 않고 다른 프리셋으로 이동하면 변경 사항이 사라집니다.',
            ),
          ],
        );
      },
    );
  }
}

class EffectPanel extends StatelessWidget {
  final OnyxController controller;
  final int slot;
  const EffectPanel({super.key, required this.controller, required this.slot});
  @override
  Widget build(BuildContext context) {
    final state = controller.state!,
        effect = state.effect(slot),
        color = OnyxColors.slots[slot];
    final list = slot == 2
        ? controller.models.amps
        : slot == 3
        ? controller.models.cabinets
        : controller.catalog.models(slot);
    final choices = {
      for (var type = 0; type < list.length; type++)
        if (list[type].isNotEmpty) type: list[type],
    };
    final labels = controller.catalog.parameters(slot, effect.model);
    return Panel(
      key: ValueKey('effect-panel-$slot'),
      borderColor: color.withValues(alpha: .4),
      children: [
        Row(
          children: [
            Icon(_effectIcons[slot], size: 25, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slotNames[slot],
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _effectTitles[slot],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              key: ValueKey('effect-enabled-$slot'),
              activeTrackColor: color,
              value: effect.enabled,
              onChanged: controller.canEdit
                  ? (_) =>
                        runAction(context, () => controller.toggleEffect(slot))
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (slot == 3 && state.temporaryCabinet)
          const HelpNote('임시 IR이 적용되어 있습니다. 다른 모델을 선택하면 임시 적용이 해제됩니다.'),
        ChoiceField(
          label: '모델',
          value: effect.model,
          choices: choices,
          onChanged: controller.canEdit
              ? (value) =>
                    runAction(context, () => controller.setModel(slot, value))
              : null,
        ),
        for (var knob = 0; knob < labels.length.clamp(0, 6); knob++)
          if (labels[knob] != '---' && labels[knob].isNotEmpty)
            ParameterSlider(
              label: labels[knob],
              value: effect.knobs[knob],
              onChanged: controller.canEdit
                  ? (value) => controller.setKnob(slot, knob, value)
                  : null,
            ),
        if (!effect.enabled)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '바이패스 · 설정을 조절한 뒤 켜서 들어보세요.',
              style: TextStyle(
                color: OnyxColors.muted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}

class _OrderSheet extends StatelessWidget {
  final OnyxController controller;
  const _OrderSheet({required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final order = controller.state?.order ?? List.generate(8, (slot) => slot);
      return DraggableScrollableSheet(
        initialChildSize: .76,
        minChildSize: .5,
        maxChildSize: .94,
        expand: false,
        builder: (context, scroll) => SafeArea(
          top: false,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '시그널 순서 변경',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 12, 22, 14),
                child: Text(
                  '핸들을 길게 눌러 이동하거나 화살표로 순서를 바꾸세요.',
                  style: TextStyle(color: OnyxColors.muted, fontSize: 12),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: scroll,
                  buildDefaultDragHandles: false,
                  itemCount: 8,
                  onReorderItem: (oldIndex, newIndex) {
                    if (controller.canEdit) {
                      runAction(
                        context,
                        () => controller.reorder(order[oldIndex], newIndex),
                      );
                    }
                  },
                  itemBuilder: (context, position) {
                    final slot = order[position];
                    return ListTile(
                      key: ValueKey('order-$slot'),
                      leading: Text(
                        '${position + 1}',
                        style: const TextStyle(color: OnyxColors.muted),
                      ),
                      title: Text(
                        slotNames[slot],
                        style: TextStyle(
                          color: OnyxColors.slots[slot],
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        _effectTitles[slot],
                        style: const TextStyle(
                          fontSize: 11,
                          color: OnyxColors.muted,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '앞으로 이동',
                            onPressed: controller.canEdit && position > 0
                                ? () => runAction(
                                    context,
                                    () =>
                                        controller.reorder(slot, position - 1),
                                  )
                                : null,
                            icon: const Icon(Icons.arrow_upward, size: 18),
                          ),
                          IconButton(
                            tooltip: '뒤로 이동',
                            onPressed: controller.canEdit && position < 7
                                ? () => runAction(
                                    context,
                                    () =>
                                        controller.reorder(slot, position + 1),
                                  )
                                : null,
                            icon: const Icon(Icons.arrow_downward, size: 18),
                          ),
                          ReorderableDelayedDragStartListener(
                            index: position,
                            enabled: controller.canEdit,
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(
                                Icons.drag_handle,
                                size: 20,
                                color: OnyxColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('완료'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
