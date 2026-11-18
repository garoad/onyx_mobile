import 'dart:async';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:material_ui/material_ui.dart';
import '../onyx_controller.dart';
import 'about.dart';
import 'connection_sheet.dart';
import 'pages/effects_page.dart';
import 'pages/files_page.dart';
import 'pages/play_page.dart';
import 'pages/presets_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';
import 'welcome.dart';
import 'widgets.dart';

class OnyxApp extends StatefulWidget {
  final OnyxController controller;
  final bool ownsController;
  const OnyxApp({
    super.key,
    required this.controller,
    this.ownsController = false,
  });
  @override
  State<OnyxApp> createState() => _OnyxAppState();
}

class _OnyxAppState extends State<OnyxApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _messages;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messages = widget.controller.messages.listen((message) {
      final messenger = _messenger.currentState;
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    });
    unawaited(
      widget.controller.loadPreferences().catchError((Object error) {
        widget.controller.log('기기 기록을 읽을 수 없습니다.');
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.setForeground(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.controller.setForeground(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_messages?.cancel());
    if (widget.ownsController) widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Onyx Mobile',
    debugShowCheckedModeBanner: false,
    theme: onyxTheme(),
    scaffoldMessengerKey: _messenger,
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: _AppShell(controller: widget.controller),
  );
}

class _AppShell extends StatefulWidget {
  final OnyxController controller;
  const _AppShell({required this.controller});
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _tab = 0;
  bool _showingConnection = false;
  OnyxController get controller => widget.controller;
  static const _labels = ['톤', '설정', '연주', 'NAM·IR', '프리셋'];
  static const _icons = [
    Icons.tune,
    Icons.settings_outlined,
    Icons.music_note_outlined,
    Icons.speaker_group_outlined,
    Icons.inventory_2_outlined,
  ];

  Future<void> _connect() async {
    if (_showingConnection || controller.phase == ConnectionPhase.connecting) {
      return;
    }
    _showingConnection = true;
    try {
      final device = await showModalBottomSheet<DiscoveredDevice>(
        context: context,
        isScrollControlled: true,
        builder: (context) => ConnectionSheet(controller: controller),
      );
      if (device != null && mounted) {
        await runAction(context, () => controller.connectDevice(device));
      }
    } finally {
      _showingConnection = false;
    }
  }

  Future<void> _connectionMenu() async {
    if (!controller.connected) {
      await _connect();
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                controller.deviceName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                controller.isDemo
                    ? '로컬 데모 · 소리는 출력되지 않습니다'
                    : 'Onyx ${controller.firmwareBuild.isEmpty ? '커스텀 펌웨어' : controller.firmwareBuild}',
                style: const TextStyle(color: OnyxColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bluetooth_searching),
                title: const Text('다른 앰프 연결'),
                onTap: controller.busy
                    ? null
                    : () => Navigator.pop(context, 'connect'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_off),
                title: Text(controller.isDemo ? '데모 종료' : '연결 해제'),
                onTap: () => Navigator.pop(context, 'disconnect'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (controller.busy &&
        !await confirmAction(
          context,
          title: '작업을 중단할까요?',
          message: '연결을 해제하면 진행 중인 작업이 중단됩니다. 다시 연결한 뒤 앰프의 상태를 확인해 주세요.',
          action: '연결 해제',
        )) {
      return;
    }
    if (!mounted) return;
    await runAction(context, () => controller.disconnect());
    if (action == 'connect' && mounted) await _connect();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 760 && bounds.maxHeight >= 600;
        final connected = controller.connected;
        final pages = [
          connected
              ? EffectsPage(controller: controller)
              : WelcomePage(controller: controller, onConnect: _connect),
          connected
              ? SettingsPage(controller: controller)
              : WelcomePage(controller: controller, onConnect: _connect),
          connected
              ? PlayPage(controller: controller)
              : WelcomePage(controller: controller, onConnect: _connect),
          FilesPage(controller: controller),
          PresetsPage(controller: controller),
        ];
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            titleSpacing: 20,
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OnyxMark(size: 28),
                SizedBox(width: 9),
                Text(
                  'ONYX',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: controller.phase == ConnectionPhase.connecting
                    ? null
                    : _connectionMenu,
                icon: Icon(
                  connected ? Icons.bluetooth_connected : Icons.bluetooth,
                  size: 17,
                ),
                label: Text(
                  controller.isDemo
                      ? '데모'
                      : connected
                      ? '연결됨'
                      : '연결',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: '앱 정보',
                onPressed: () => showOnyxAbout(context, controller),
                icon: const Icon(Icons.more_horiz),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: wide,
            child: Column(
              children: [
                if (controller.isDemo)
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    decoration: BoxDecoration(
                      color: OnyxColors.accent.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.science_outlined,
                          size: 17,
                          color: OnyxColors.accent,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '데모 · 소리는 출력되지 않습니다',
                            style: TextStyle(
                              color: OnyxColors.accent,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: controller.busy ? null : _connect,
                          child: const Text(
                            '앰프 연결',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (connected)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 12, 2),
                    child: Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: OnyxColors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${controller.deviceName}${controller.firmwareBuild.isNotEmpty ? ' · ${controller.firmwareBuild}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: OnyxColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '기기 상태 새로고침',
                          icon: const Icon(Icons.sync, size: 17),
                          onPressed: controller.canEdit
                              ? () => runAction(context, controller.refresh)
                              : null,
                        ),
                      ],
                    ),
                  ),
                if (controller.busy)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                controller.operation,
                                style: const TextStyle(
                                  color: OnyxColors.accent,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (controller.progress > 0)
                              Text(
                                '${(controller.progress * 100).round()}%',
                                style: const TextStyle(
                                  color: OnyxColors.accent,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: controller.progress > 0
                                ? controller.progress
                                : null,
                            minHeight: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      if (wide)
                        NavigationRail(
                          selectedIndex: _tab,
                          labelType: NavigationRailLabelType.all,
                          onDestinationSelected: (value) => setState(() {
                            _tab = value;
                          }),
                          destinations: [
                            for (var index = 0; index < 5; index++)
                              NavigationRailDestination(
                                icon: Icon(_icons[index]),
                                label: Text(_labels[index]),
                              ),
                          ],
                        ),
                      if (wide) const VerticalDivider(width: 1),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1280),
                            child: IndexedStack(index: _tab, children: pages),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: OnyxColors.border)),
                  ),
                  child: NavigationBar(
                    selectedIndex: _tab,
                    onDestinationSelected: (value) => setState(() {
                      _tab = value;
                    }),
                    destinations: [
                      for (var index = 0; index < 5; index++)
                        NavigationDestination(
                          icon: Icon(_icons[index]),
                          label: _labels[index],
                        ),
                    ],
                  ),
                ),
        );
      },
    ),
  );
}
