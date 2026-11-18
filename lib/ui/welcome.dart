import 'package:material_ui/material_ui.dart';
import '../onyx_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class WelcomePage extends StatelessWidget {
  final OnyxController controller;
  final VoidCallback onConnect;
  const WelcomePage({
    super.key,
    required this.controller,
    required this.onConnect,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (bounds.maxHeight - 56).clamp(0, double.infinity),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: OnyxMark(size: 116)),
                const SizedBox(height: 26),
                const Text(
                  'YOUR POCKET. YOUR TONE.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2.7,
                    fontWeight: FontWeight.w700,
                    color: OnyxColors.accent,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '작은 앰프,\n더 넓은 가능성.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    height: 1.3,
                    letterSpacing: -1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Pocket AMP를 연결하고\n이펙트부터 프리셋까지 손쉽게 조절하세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: OnyxColors.muted,
                    fontSize: 13,
                    height: 1.8,
                  ),
                ),
                const SizedBox(height: 30),
                if (controller.phase == ConnectionPhase.connecting) ...[
                  const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    controller.status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: OnyxColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => runAction(
                      context,
                      () => controller.disconnect(silent: true),
                    ),
                    child: const Text('연결 취소'),
                  ),
                ] else ...[
                  FilledButton.icon(
                    key: const ValueKey('connect-amp'),
                    onPressed: controller.busy ? null : onConnect,
                    icon: const Icon(Icons.bluetooth),
                    label: const Text('앰프 연결'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('start-demo'),
                    onPressed: controller.busy
                        ? null
                        : () => runAction(context, controller.startDemo),
                    icon: const Icon(Icons.tune),
                    label: const Text('데모로 둘러보기'),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    controller.status == '연결되지 않음'
                        ? 'Bluetooth를 지원하는 Onyx 커스텀 펌웨어가 필요합니다.'
                        : controller.status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: OnyxColors.muted,
                      height: 1.5,
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
