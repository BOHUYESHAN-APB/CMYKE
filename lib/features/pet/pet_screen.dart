import 'package:flutter/material.dart';

import '../../core/models/app_settings.dart';
import '../../core/repositories/chat_repository.dart';
import '../../core/repositories/memory_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/runtime_hub.dart';
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

  @override
  void initState() {
    super.initState();
    _settings = widget.settingsRepository.settings;
    widget.settingsRepository.addListener(_handleSettingsChanged);
    _applyCursorFollow();
  }

  @override
  void dispose() {
    widget.settingsRepository.removeListener(_handleSettingsChanged);
    RuntimeHub.instance.live3dBridge.setCursorFollow(false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2EEE6),
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Live3DPreview(
                  height: constraints.maxHeight,
                  compact: true,
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
              child: Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _exitPetMode,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('返回聊天'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '视线跟随鼠标（窗口内）',
                    onPressed: _toggleCursorFollow,
                    icon: Icon(
                      _settings.petFollowCursor
                          ? Icons.center_focus_strong
                          : Icons.center_focus_weak,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
