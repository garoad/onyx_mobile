import 'package:material_ui/material_ui.dart';
import '../../core/midi_protocol.dart';
import '../../onyx_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class PlayPage extends StatelessWidget {
  final OnyxController controller;
  const PlayPage({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final state = controller.state!;
    return PageScroll(
      id: 'play',
      children: [
        const PageIntro(
          eyebrow: 'PLAY & PRACTICE',
          title: '연주에 집중하세요',
          description: '리듬을 켜고, 스톰프 버튼을 지정하고, 튜너로 준비하세요.',
        ),
        ResponsivePanels(
          children: [
            Panel(
              title: '그루브',
              icon: Icons.music_note_outlined,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${state.bpm}',
                            style: const TextStyle(
                              fontSize: 50,
                              letterSpacing: -2,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Text(
                            'BEATS PER MINUTE',
                            style: TextStyle(
                              color: OnyxColors.muted,
                              fontSize: 9,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('toggle-groove'),
                      onPressed: controller.canEdit
                          ? () => runAction(context, controller.toggleGroove)
                          : null,
                      icon: Icon(
                        state.groovePlaying ? Icons.pause : Icons.play_arrow,
                      ),
                      label: Text(state.groovePlaying ? '정지' : '재생'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ParameterSlider(
                  label: '템포',
                  value: state.bpm,
                  min: 40,
                  max: 260,
                  format: (value) => '$value BPM',
                  onChanged: controller.canEdit
                      ? (value) => controller.setGroove(1, value - 40)
                      : null,
                ),
                ParameterSlider(
                  label: '리듬 패턴',
                  value: state.pattern,
                  max: 39,
                  format: (value) => '${value + 1} / 40',
                  onChanged: controller.canEdit
                      ? (value) => controller.setGroove(2, value)
                      : null,
                ),
                ParameterSlider(
                  label: '리듬 볼륨',
                  value: state.grooveVolume,
                  onChanged: controller.canEdit
                      ? (value) => controller.setGroove(3, value)
                      : null,
                ),
                ToggleRow(
                  label: '드럼 사용',
                  value: state.drumsEnabled,
                  onChanged: controller.canEdit
                      ? (value) => controller.setGroove(4, value ? 1 : 0)
                      : null,
                ),
              ],
            ),
            Panel(
              title: '스톰프 버튼',
              icon: Icons.touch_app_outlined,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Text(
                    '앰프의 STOMP 모드에서 각 버튼으로 켜고 끌 이펙트를 선택하세요.',
                    style: TextStyle(
                      color: OnyxColors.muted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ),
                for (var key = 0; key < 4; key++)
                  ChoiceField(
                    label: ['VOL −', 'VOL +', '이전 ‹', '다음 ›'][key],
                    value: state.stompSlots[key],
                    choices: {
                      for (var slot = 0; slot < 8; slot++)
                        slot: slotNames[slot],
                    },
                    onChanged: controller.canEdit
                        ? (slot) => runAction(
                            context,
                            () => controller.setStomp(key, slotModules[slot]),
                          )
                        : null,
                  ),
              ],
            ),
            Panel(
              title: '튜너',
              icon: Icons.tune,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: OnyxColors.elevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.music_note,
                        color: state.tunerOpen
                            ? OnyxColors.accent
                            : OnyxColors.muted,
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        state.tunerOpen ? '앰프 튜너가 열려 있습니다' : '튜닝할 준비가 되었나요?',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '음정은 Pocket AMP 화면에서 확인하세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: OnyxColors.muted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  key: const ValueKey('toggle-tuner'),
                  onPressed: controller.canEdit
                      ? () => runAction(context, controller.toggleTuner)
                      : null,
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(state.tunerOpen ? '앰프 튜너 닫기' : '앰프 튜너 열기'),
                ),
                const SizedBox(height: 16),
                ParameterSlider(
                  label: '기준 음정',
                  value: state.byte(101),
                  max: 20,
                  format: (value) => '${430 + value} Hz',
                  onChanged: controller.canEdit
                      ? (value) => controller.setGlobal(16, value)
                      : null,
                ),
                ToggleRow(
                  label: '튜닝 중 출력 음소거',
                  value: state.byte(102) != 0,
                  onChanged: controller.canEdit
                      ? (value) => controller.setGlobal(17, value ? 1 : 0)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
