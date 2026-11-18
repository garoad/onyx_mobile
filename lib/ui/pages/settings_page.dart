import 'package:material_ui/material_ui.dart';
import '../../onyx_controller.dart';
import '../widgets.dart';

class SettingsPage extends StatelessWidget {
  final OnyxController controller;
  const SettingsPage({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final state = controller.state!;
    ParameterSlider slider(
      String label,
      int offset,
      int parameter,
      int max, {
      String Function(int)? format,
    }) => ParameterSlider(
      label: label,
      value: state.byte(offset),
      max: max,
      format: format,
      onChanged: controller.canEdit
          ? (value) => controller.setGlobal(parameter, value)
          : null,
    );
    ToggleRow toggle(String label, int offset, int parameter) => ToggleRow(
      label: label,
      value: state.byte(offset) != 0,
      onChanged: controller.canEdit
          ? (value) => controller.setGlobal(parameter, value ? 1 : 0)
          : null,
    );
    ChoiceField choice(
      String label,
      int offset,
      int parameter,
      List<String> options,
    ) => ChoiceField(
      label: label,
      value: state.byte(offset),
      choices: {
        for (var index = 0; index < options.length; index++)
          index: options[index],
      },
      onChanged: controller.canEdit
          ? (value) => controller.setGlobal(parameter, value)
          : null,
    );
    String db(int value) => '${value - 12 > 0 ? '+' : ''}${value - 12} dB';
    return PageScroll(
      id: 'settings',
      children: [
        const PageIntro(
          eyebrow: 'AMP SETTINGS',
          title: '앰프 설정',
          description:
              '입력, 출력과 USB 오디오를 연주 환경에 맞추세요. 이 설정은 모든 프리셋에 공통으로 적용됩니다.',
        ),
        ResponsivePanels(
          children: [
            Panel(
              title: '입력',
              icon: Icons.input,
              children: [
                slider('입력 게인', 86, 0, 24, format: db),
                slider(
                  '입력 노이즈 게이트',
                  87,
                  1,
                  50,
                  format: (value) => value == 0 ? '꺼짐' : '${value - 80} dB',
                ),
              ],
            ),
            Panel(
              title: '출력',
              icon: Icons.volume_up_outlined,
              children: [
                slider('전체 출력 레벨', 5, 2, 100),
                choice('출력 모드', 88, 3, ['헤드폰', '라인 출력']),
                toggle('라인 출력에 캐비닛 적용', 89, 4),
                choice('리미터', 90, 5, ['브릭월', '소프트', '꺼짐']),
                slider('고역 Fizz 필터', 91, 6, 3),
              ],
            ),
            Panel(
              title: '스테레오',
              icon: Icons.surround_sound_outlined,
              children: [
                slider('스테레오 너비', 92, 7, 100),
                choice('출력 라우팅', 93, 8, ['스테레오', '모노', '왼쪽', '오른쪽', '좌우 교환']),
                slider(
                  '좌우 밸런스',
                  94,
                  9,
                  100,
                  format: (value) => value == 50
                      ? '중앙'
                      : '${value < 50 ? 'L' : 'R'} ${(value - 50).abs()}',
                ),
              ],
            ),
            Panel(
              title: '전체 EQ',
              icon: Icons.equalizer,
              children: [
                toggle('전체 EQ 사용', 95, 10),
                for (var band = 0; band < 5; band++)
                  slider(
                    ['100 Hz', '400 Hz', '1 kHz', '3 kHz', '8 kHz'][band],
                    96 + band,
                    11 + band,
                    24,
                    format: db,
                  ),
              ],
            ),
            Panel(
              title: 'USB 오디오',
              icon: Icons.usb,
              children: [
                ChoiceField(
                  label: 'USB 모드',
                  value: state.usbMode,
                  choices: const {0: '앰프', 1: '오디오 인터페이스', 2: '인터페이스 + 직접 모니터'},
                  onChanged: controller.canEdit
                      ? (value) => controller.setGlobal(19, value)
                      : null,
                ),
                HelpNote(
                  state.usbMode == 0
                      ? '앰프의 톤과 컴퓨터의 소리를 함께 듣습니다.'
                      : state.usbMode == 1
                      ? '컴퓨터의 소리만 듣고, 컴퓨터에는 드라이 기타 신호를 녹음합니다.'
                      : '드라이 기타 신호를 녹음하면서 직접 모니터링합니다.',
                ),
                ToggleRow(
                  label: 'USB 루프백',
                  description: '컴퓨터가 재생하는 소리도 녹음에 포함',
                  value: state.loopback,
                  onChanged: controller.canEdit
                      ? (value) => controller.setGlobal(18, value ? 1 : 0)
                      : null,
                ),
              ],
            ),
            Panel(
              title: '동기화',
              icon: Icons.sync,
              children: [
                ToggleRow(
                  label: '기기 상태 자동 읽기',
                  description: '앰프에서 바꾼 설정을 화면에도 반영',
                  value: controller.liveSync,
                  onChanged: controller.setLiveSync,
                ),
                OutlinedButton.icon(
                  onPressed: controller.canEdit
                      ? () => runAction(context, controller.refresh)
                      : null,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('지금 새로고침'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
