import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:material_ui/material_ui.dart';
import '../onyx_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class ConnectionSheet extends StatefulWidget {
  final OnyxController controller;
  const ConnectionSheet({super.key, required this.controller});
  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  final Map<String, DiscoveredDevice> _devices = {};
  StreamSubscription<DiscoveredDevice>? _scan;
  Timer? _deadline;
  bool _preparing = false, _scanning = false, _allDevices = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  Future<void> _stop() async {
    _generation++;
    _deadline?.cancel();
    final scan = _scan;
    _scan = null;
    await scan?.cancel();
    if (mounted) {
      setState(() {
        _scanning = false;
        _preparing = false;
      });
    }
  }

  Future<void> _start() async {
    await _stop();
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _error = null;
      _devices.clear();
      _preparing = true;
    });
    try {
      await widget.controller.bluetooth.prepare();
      if (!mounted || generation != _generation) return;
      setState(() {
        _preparing = false;
        _scanning = true;
      });
      _scan = widget.controller.bluetooth
          .scan(allDevices: _allDevices)
          .listen(
            (device) {
              if (!mounted || generation != _generation) return;
              setState(() {
                _devices[device.id] = device;
              });
            },
            onError: (Object error) {
              if (!mounted || generation != _generation) return;
              setState(() {
                _error = friendlyError(error);
              });
              unawaited(_stop());
            },
          );
      _deadline = Timer(const Duration(seconds: 18), () {
        unawaited(_stop());
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = friendlyError(error);
        _preparing = false;
        _scanning = false;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _deadline?.cancel();
    unawaited(_scan?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()
      ..sort((a, b) {
        if (a.id == widget.controller.lastDeviceId) return -1;
        if (b.id == widget.controller.lastDeviceId) return 1;
        return b.rssi.compareTo(a.rssi);
      });
    return DraggableScrollableSheet(
      initialChildSize: .76,
      minChildSize: .45,
      maxChildSize: .94,
      expand: false,
      builder: (context, scroll) => SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 12, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pocket AMP 연결',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                '앰프의 전원을 켜고 MIDI 기기를 선택하세요. 다른 편집 앱에 연결되어 있다면 먼저 연결을 종료해 주세요.',
                style: TextStyle(
                  color: OnyxColors.muted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text(
                      '전체 BLE 기기',
                      style: TextStyle(fontSize: 12),
                    ),
                    selected: _allDevices,
                    onSelected: _preparing
                        ? null
                        : (value) {
                            setState(() {
                              _allDevices = value;
                            });
                            unawaited(_start());
                          },
                  ),
                  const Spacer(),
                  if (_scanning || _preparing)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Text(
                    _preparing
                        ? '권한 확인'
                        : _scanning
                        ? '검색 중'
                        : '${devices.length}개 발견',
                    style: const TextStyle(
                      color: OnyxColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 8,
                ),
                children: [
                  if (_error != null)
                    Panel(
                      borderColor: OnyxColors.danger.withValues(alpha: .4),
                      children: [
                        const Icon(
                          Icons.bluetooth_disabled,
                          color: OnyxColors.danger,
                          size: 30,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(fontSize: 13, height: 1.6),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => runAction(
                            context,
                            widget.controller.bluetooth.openSettings,
                          ),
                          child: const Text('앱 설정 열기'),
                        ),
                      ],
                    ),
                  if (devices.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 34),
                      child: Column(
                        children: [
                          Icon(
                            _scanning || _preparing
                                ? Icons.bluetooth_searching
                                : Icons.search_off,
                            size: 42,
                            color: OnyxColors.accent,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _scanning || _preparing
                                ? '주변의 앰프를 찾고 있어요'
                                : '앰프를 찾지 못했습니다',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '앰프를 가까이 두고 다시 검색해 보세요.\n목록에 없으면 전체 BLE 기기 검색을 켜세요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: OnyxColors.muted,
                              height: 1.7,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final device in devices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: const Icon(
                            Icons.bluetooth,
                            color: OnyxColors.accent,
                          ),
                          title: Text(
                            device.name.isEmpty ? '이름 없는 BLE 기기' : device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${device.rssi} dBm${device.id == widget.controller.lastDeviceId ? ' · 최근 연결' : ''}',
                            style: const TextStyle(
                              color: OnyxColors.muted,
                              fontSize: 11,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await _stop();
                            if (context.mounted) Navigator.pop(context, device);
                          },
                        ),
                      ),
                    ),
                  if (_allDevices)
                    const HelpNote(
                      '전체 검색에는 앰프 외의 BLE 기기도 표시됩니다. 선택한 기기가 BLE-MIDI를 지원하는지 연결 시 확인합니다.',
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _preparing
                      ? null
                      : () {
                          unawaited(_scanning ? _stop() : _start());
                        },
                  icon: Icon(_scanning ? Icons.stop : Icons.refresh),
                  label: Text(_scanning ? '검색 중지' : '다시 검색'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
