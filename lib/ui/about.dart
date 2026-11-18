import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../onyx_controller.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> showOnyxAbout(
  BuildContext context,
  OnyxController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => DraggableScrollableSheet(
    initialChildSize: .73,
    maxChildSize: .92,
    minChildSize: .45,
    expand: false,
    builder: (context, scroll) => SafeArea(
      top: false,
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
        children: [
          const Center(child: OnyxMark(size: 64)),
          const SizedBox(height: 14),
          const Text(
            'Onyx Mobile',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            '0.1.0 · Pocket AMP 커스텀 펌웨어 에디터',
            textAlign: TextAlign.center,
            style: TextStyle(color: OnyxColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.code),
            title: const Text('Pocket-Onyx 원본 프로젝트'),
            subtitle: const Text(
              'The Onyx Authors · @28spawn',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => runAction(context, () async {
              if (!await launchUrl(
                Uri.parse('https://github.com/28spawn/Pocket-Onyx'),
                mode: LaunchMode.externalApplication,
              )) {
                throw StateError('프로젝트 페이지를 열 수 없습니다.');
              }
            }),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('개인정보 처리 안내'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const _PrivacyPage(),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('앱 소스 라이선스'),
            subtitle: const Text(
              'GPL-3.0-only',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const _SourceLicensePage(),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.article_outlined),
            title: const Text('오픈 소스 라이선스'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Onyx Mobile',
              applicationVersion: '0.1.0',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.terminal),
            title: const Text('연결·작업 기록'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (context) => _LogPage(controller: controller),
              ),
            ),
          ),
          const Divider(),
          const Text(
            'Copyright © 2026 The Onyx Authors (@28spawn).\nOnyx 웹 에디터의 통신 규격과 모델 정보를 사용했습니다.',
            style: TextStyle(
              color: OnyxColors.muted,
              height: 1.6,
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  ),
);

class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('개인정보 처리 안내')),
    body: const PageScroll(
      id: 'privacy',
      children: [
        PageIntro(
          eyebrow: 'PRIVACY',
          title: '기기 안에서 이루어지는 편집',
          description: 'Onyx Mobile은 로그인이나 서버 없이 동작합니다.',
        ),
        Panel(
          title: 'Bluetooth와 파일',
          children: [
            Text(
              'Bluetooth는 앰프 검색·연결·설정 전송에 사용합니다. Android 11 이하의 위치 권한은 OS가 BLE 검색에 요구하는 권한이며, 앱은 위치 정보를 읽거나 저장하지 않습니다.\n\n선택한 프리셋·NAM·IR 파일은 기기에서 처리합니다. 사용자가 저장 또는 공유를 선택하면 해당 OS 기능으로 내보냅니다. 공유 대상 앱의 처리는 그 앱의 정책을 따릅니다.',
              style: TextStyle(fontSize: 13, height: 1.8),
            ),
          ],
        ),
        SizedBox(height: 16),
        Panel(
          title: '기기에 남는 정보',
          children: [
            Text(
              '마지막으로 연결한 앰프의 이름과 Bluetooth 식별자를 앱 내부에 저장합니다. 최근 작업 기록은 실행 중에만 유지합니다. 공유용 임시 파일은 앱의 임시 저장소에 보관되며 OS 또는 앱 삭제 시 제거할 수 있습니다.\n\n분석 도구·광고·추적 기능을 사용하지 않습니다. 외부 프로젝트 링크는 사용자가 선택하면 브라우저로 열립니다.',
              style: TextStyle(fontSize: 13, height: 1.8),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SourceLicensePage extends StatelessWidget {
  const _SourceLicensePage();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('GPL-3.0-only')),
    body: FutureBuilder<String>(
      future: rootBundle.loadString('assets/LICENSE.txt'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: SelectableText(
            snapshot.data!,
            style: const TextStyle(fontSize: 12, height: 1.65),
          ),
        );
      },
    ),
  );
}

class _LogPage extends StatelessWidget {
  final OnyxController controller;
  const _LogPage({required this.controller});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('연결·작업 기록'),
      actions: [
        IconButton(
          tooltip: '기록 복사',
          onPressed: () => runAction(context, () async {
            await Clipboard.setData(
              ClipboardData(text: controller.logs.join('\n')),
            );
            controller.announce('작업 기록을 복사했습니다.');
          }),
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          if (controller.logs.isEmpty)
            const Text(
              '아직 기록이 없습니다.',
              style: TextStyle(color: OnyxColors.muted),
            )
          else
            SelectableText(
              controller.logs.reversed.join('\n\n'),
              style: const TextStyle(
                fontSize: 12,
                height: 1.6,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    ),
  );
}
