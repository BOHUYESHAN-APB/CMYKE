import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/models/app_settings.dart';
import '../../core/repositories/chat_repository.dart';
import '../../core/repositories/memory_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/runtime_hub.dart';
import '../../ui/theme/cmyke_chrome.dart';
import '../../ui/widgets/frosted_surface.dart';
import '../../ui/windows/pet_desktop_controller.dart';
import '../../ui/windows/win_window.dart';
import '../common/live3d_preview.dart';

class PetScreen extends StatefulWidget {
  const PetScreen({
    super.key,
    required this.chatRepository,
    required this.memoryRepository,
    required this.settingsRepository,
  });

  final ChatRepository chatRepository;
  final MemoryRepository memoryRepository;
  final SettingsRepository settingsRepository;

  @override
  State<PetScreen> createState() => _PetScreenState();
}

class _PetScreenState extends State<PetScreen> {
  late AppSettings _settings;
  double _petZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _settings = widget.settingsRepository.settings;
    widget.settingsRepository.addListener(_handleSettingsChanged);
    _applyCursorFollow();
    RuntimeHub.instance.live3dBridge.setPetMode(true);
    _petZoom = RuntimeHub.instance.live3dBridge.petZoom;
    if (Platform.isWindows &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          PetDesktopController.instance.enterPetMode().catchError((_) {}),
        );
      });
    }
  }

  @override
  void dispose() {
    widget.settingsRepository.removeListener(_handleSettingsChanged);
    RuntimeHub.instance.live3dBridge.setCursorFollow(false);
    RuntimeHub.instance.live3dBridge.setPetMode(false);
    if (Platform.isWindows &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      unawaited(
        PetDesktopController.instance.leavePetMode().catchError((_) {}),
      );
    }
    super.dispose();
  }

  void _handleSettingsChanged() {
    final next = widget.settingsRepository.settings;
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = next;
    });
    _applyCursorFollow();
  }

  void _applyCursorFollow() {
    final enabled = _settings.petMode && _settings.petFollowCursor;
    RuntimeHub.instance.live3dBridge.setCursorFollow(enabled);
  }

  Future<void> _exitPetMode() async {
    RuntimeHub.instance.live3dBridge.setCursorFollow(false);
    await widget.settingsRepository.updateSettings(
      _settings.copyWith(petMode: false),
    );
  }

  Future<void> _toggleCursorFollow() async {
    await widget.settingsRepository.updateSettings(
      _settings.copyWith(petFollowCursor: !_settings.petFollowCursor),
    );
  }

  void _nudgeZoom(double delta) {
    final next = (_petZoom + delta).clamp(0.6, 2.2);
    setState(() => _petZoom = next);
    RuntimeHub.instance.live3dBridge.setPetZoom(next);
  }

  Future<void> _nudgePetWindow(int sign) async {
    if (!Platform.isWindows) return;
    await PetDesktopController.instance.nudgePetWindowSize(
      dWidth: 40 * sign,
      dHeight: 40 * sign,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Live3DPreview(
                  height: constraints.maxHeight,
                  compact: true,
                  transparentBackground: true,
                  petMode: true,
                  settingsRepository: widget.settingsRepository,
                );
              },
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: SafeArea(
              child: FrostedSurface(
                borderRadius: BorderRadius.circular(chrome.radiusXL),
                shadows: const [],
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 520;
                    final back = narrow
                        ? IconButton.filledTonal(
                            tooltip: '返回聊天',
                            onPressed: _exitPetMode,
                            icon: const Icon(
                              Icons.chat_bubble_outline,
                              size: 18,
                            ),
                          )
                        : FilledButton.tonalIcon(
                            onPressed: _exitPetMode,
                            icon: const Icon(
                              Icons.chat_bubble_outline,
                              size: 18,
                            ),
                            label: const Text('返回聊天'),
                          );

                    final dragHandle = Platform.isWindows
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (_) => WinWindow.startDragging(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                color: chrome.textSecondary,
                              ),
                            ),
                          )
                        : const SizedBox.shrink();

                    final clickThrough = Platform.isWindows
                        ? IconButton(
                            tooltip: PetDesktopController.instance.clickThrough
                                ? '关闭点击穿透（可交互）'
                                : '开启点击穿透（不挡鼠标）',
                            onPressed: () async {
                              await PetDesktopController.instance
                                  .toggleClickThrough();
                              if (mounted) {
                                setState(() {});
                              }
                            },
                            icon: Icon(
                              PetDesktopController.instance.clickThrough
                                  ? Icons.mouse_outlined
                                  : Icons.pan_tool_alt_outlined,
                            ),
                          )
                        : const SizedBox.shrink();

                    final follow = IconButton(
                      tooltip: '视线跟随鼠标（窗口内）',
                      onPressed: _toggleCursorFollow,
                      icon: Icon(
                        _settings.petFollowCursor
                            ? Icons.center_focus_strong
                            : Icons.center_focus_weak,
                      ),
                    );

                    if (!narrow) {
                      return Row(
                        children: [
                          dragHandle,
                          back,
                          const Spacer(),
                          clickThrough,
                          follow,
                        ],
                      );
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            dragHandle,
                            back,
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            clickThrough,
                            follow,
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: SafeArea(
              child: FrostedSurface(
                borderRadius: BorderRadius.circular(chrome.radiusL),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '模型缩小',
                      onPressed: () => _nudgeZoom(-0.1),
                      icon: const Icon(Icons.zoom_out),
                    ),
                    Text(
                      '${(_petZoom * 100).round()}%',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    IconButton(
                      tooltip: '模型放大',
                      onPressed: () => _nudgeZoom(0.1),
                      icon: const Icon(Icons.zoom_in),
                    ),
                    if (Platform.isWindows) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '窗口缩小',
                        onPressed: () => _nudgePetWindow(-1),
                        icon: const Icon(Icons.fullscreen_exit_rounded),
                      ),
                      IconButton(
                        tooltip: '窗口放大',
                        onPressed: () => _nudgePetWindow(1),
                        icon: const Icon(Icons.fullscreen_rounded),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
