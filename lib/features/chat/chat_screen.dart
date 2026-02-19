import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/chat_session.dart';
import '../../core/models/memory_record.dart';
import '../../core/models/memory_tier.dart';
import '../../core/models/research_job.dart';
import '../../core/repositories/chat_repository.dart';
import '../../core/repositories/memory_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/chat_export_service.dart';
import '../../core/services/chat_engine.dart';
import '../../core/services/autonomy_service.dart';
import '../../core/services/draft_service.dart';
import '../../core/services/workspace_service.dart';
import '../../ui/theme/cmyke_chrome.dart';
import '../common/live3d_preview.dart';
import '../memory/memory_tier_screen.dart';
import '../settings/provider_config_screen.dart';
import '../deep_research/deep_research_screen.dart';
import '../autonomy/autonomy_screen.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_header.dart';
import 'widgets/message_bubble.dart';
import 'widgets/session_sidebar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatRepository,
    required this.memoryRepository,
    required this.settingsRepository,
    required this.workspaceService,
    this.embeddingConfigMissing = false,
  });

  final ChatRepository chatRepository;
  final MemoryRepository memoryRepository;
  final SettingsRepository settingsRepository;
  final WorkspaceService workspaceService;
  final bool embeddingConfigMissing;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatExportService _exportService = ChatExportService();
  late final ChatEngine _chatEngine;
  late final AutonomyService _autonomyService;
  late final DraftService _draftService;
  double _sidebarWidth = 280.0;
  double _rightPanelWidth = 380.0;
  bool _showRightPanel = true;
  bool _layoutEditing = false;
  LayoutPreset _layoutPreset = LayoutPreset.balanced;
  Timer? _layoutPersistTimer;

  @override
  void initState() {
    super.initState();
    _chatEngine = ChatEngine(
      chatRepository: widget.chatRepository,
      memoryRepository: widget.memoryRepository,
      settingsRepository: widget.settingsRepository,
    );
    _draftService = DraftService(workspaceService: widget.workspaceService);
    _autonomyService = AutonomyService(
      settingsRepository: widget.settingsRepository,
      chatRepository: widget.chatRepository,
      draftService: _draftService,
      isBusy: () =>
          _chatEngine.isStreaming ||
          _chatEngine.isSpeaking ||
          _chatEngine.isListening ||
          _chatEngine.isCompressing,
      onSpeak: (text) => _chatEngine.speakAssistant(text),
    );
    _autonomyService.start();
    _composerController.addListener(_handleComposerChanged);
    _syncLayoutFromSettings(widget.settingsRepository.settings, force: true);
    widget.settingsRepository.addListener(_handleSettingsChanged);
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settingsRepository != widget.settingsRepository) {
      oldWidget.settingsRepository.removeListener(_handleSettingsChanged);
      widget.settingsRepository.addListener(_handleSettingsChanged);
      _syncLayoutFromSettings(widget.settingsRepository.settings, force: true);
    }
  }

  @override
  void dispose() {
    widget.settingsRepository.removeListener(_handleSettingsChanged);
    _composerController.removeListener(_handleComposerChanged);
    _composerController.dispose();
    _scrollController.dispose();
    _layoutPersistTimer?.cancel();
    _autonomyService.dispose();
    _chatEngine.dispose();
    super.dispose();
  }

  void _handleComposerChanged() {
    if (_composerController.text.trim().isEmpty) {
      return;
    }
    _autonomyService.noteUserActivity();
  }

  void _handleSettingsChanged() {
    if (!mounted) return;
    _syncLayoutFromSettings(widget.settingsRepository.settings);
  }

  void _syncLayoutFromSettings(AppSettings settings, {bool force = false}) {
    final presetChanged = _layoutPreset != settings.layoutPreset;
    final sidebarChanged = _sidebarWidth != settings.layoutSidebarWidth;
    final rightChanged = _rightPanelWidth != settings.layoutRightPanelWidth;
    final showChanged = _showRightPanel != settings.layoutShowRightPanel;
    if (!force &&
        !presetChanged &&
        !sidebarChanged &&
        !rightChanged &&
        !showChanged) {
      return;
    }
    setState(() {
      _layoutPreset = settings.layoutPreset;
      _sidebarWidth = settings.layoutSidebarWidth;
      _rightPanelWidth = settings.layoutRightPanelWidth;
      _showRightPanel = settings.layoutShowRightPanel;
    });
  }

  void _scheduleLayoutPersist() {
    _layoutPersistTimer?.cancel();
    _layoutPersistTimer = Timer(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      final settings = widget.settingsRepository.settings;
      if (settings.layoutSidebarWidth == _sidebarWidth &&
          settings.layoutRightPanelWidth == _rightPanelWidth &&
          settings.layoutShowRightPanel == _showRightPanel) {
        return;
      }
      widget.settingsRepository.updateSettings(
        settings.copyWith(
          layoutSidebarWidth: _sidebarWidth,
          layoutRightPanelWidth: _rightPanelWidth,
          layoutShowRightPanel: _showRightPanel,
        ),
      );
    });
  }

  Future<void> _handleSend() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _composerController.clear();
    _autonomyService.noteUserActivity();
    await _chatEngine.sendText(text);
    _scrollToBottom();
  }

  Future<void> _createSessionForRoute() async {
    final route = widget.settingsRepository.settings.route;
    final mode = _sessionModeForRoute(route);
    await widget.chatRepository.createSession(mode: mode);
  }

  ChatSessionMode _sessionModeForRoute(ModelRoute route) {
    switch (route) {
      case ModelRoute.standard:
        return ChatSessionMode.standard;
      case ModelRoute.realtime:
        return ChatSessionMode.realtime;
      case ModelRoute.omni:
        return ChatSessionMode.standard;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  void _resetLayout() {
    final defaults = _layoutDefaultsForPreset(_layoutPreset);
    setState(() {
      _sidebarWidth = defaults.sidebar;
      _rightPanelWidth = defaults.rightPanel;
      _showRightPanel = defaults.showRightPanel;
      _layoutEditing = false;
    });
    _scheduleLayoutPersist();
  }

  Future<void> _exportActiveSession() async {
    final session = widget.chatRepository.activeSession;
    if (session == null) {
      return;
    }
    final path = await _exportService.exportSession(
      session,
      memoryCollections: widget.memoryRepository.collections,
    );
    _showSnack('会话日志已导出: $path（同时生成 .md）');
  }

  Future<void> _exportAllSessions() async {
    final path = await _exportService.exportAll(
      widget.chatRepository.sessions,
      memoryCollections: widget.memoryRepository.collections,
    );
    _showSnack('全部会话已导出: $path（同时生成 .md）');
  }

  Future<void> _removeSession(String sessionId) async {
    await widget.memoryRepository.removeContextForSession(sessionId);
    await widget.chatRepository.removeSession(sessionId);
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveMessageToMemory(
    ChatMessage message,
    MemoryTier tier,
  ) async {
    final sessionId = widget.chatRepository.activeSessionId;
    final record = MemoryRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      tier: tier,
      content: message.content,
      createdAt: DateTime.now(),
      sourceMessageId: message.id,
    );
    await widget.memoryRepository.addRecord(
      tier: tier,
      record: record,
      sessionId: sessionId,
    );
    _showSnack('已写入 ${tier.label}');
  }

  Future<void> _openManualMemoryDialog() async {
    final controller = TextEditingController();
    MemoryTier selectedTier = MemoryTier.crossSession;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新增记忆'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<MemoryTier>(
                value: selectedTier,
                decoration: const InputDecoration(labelText: '记忆层级'),
                items: MemoryTier.values
                    .map(
                      (tier) => DropdownMenuItem(
                        value: tier,
                        child: Text(tier.label),
                      ),
                    )
                    .toList(),
                onChanged: (tier) {
                  if (tier != null) {
                    selectedTier = tier;
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '内容',
                  hintText: '输入需要沉淀的内容',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final content = controller.text.trim();
                if (content.isEmpty) {
                  return;
                }
                final navigator = Navigator.of(context);
                final sessionId = widget.chatRepository.activeSessionId;
                await widget.memoryRepository.addRecord(
                  tier: selectedTier,
                  record: MemoryRecord(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    tier: selectedTier,
                    content: content,
                    createdAt: DateTime.now(),
                  ),
                  sessionId: sessionId,
                );
                navigator.pop();
              },
              child: const Text('写入'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  Future<void> _openUniversalAgentDialog() async {
    final controller = TextEditingController();
    ResearchDeliverable deliverable = ResearchDeliverable.report;
    ResearchDepth depth = ResearchDepth.deep;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('通用 Agent 任务'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '目标',
                  hintText: '例如：整理近期 AI 通用 Agent 的趋势并输出报告',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ResearchDeliverable>(
                value: deliverable,
                decoration: const InputDecoration(labelText: '交付形式'),
                items: ResearchDeliverable.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(_deliverableLabel(item)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    deliverable = value;
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ResearchDepth>(
                value: depth,
                decoration: const InputDecoration(labelText: '研究深度'),
                items: ResearchDepth.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(_depthLabel(item)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    depth = value;
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final goal = controller.text.trim();
                if (goal.isEmpty) {
                  return;
                }
                Navigator.of(context).pop();
                await _chatEngine.runUniversalAgent(
                  goal: goal,
                  deliverable: deliverable,
                  depth: depth,
                );
                _scrollToBottom();
              },
              child: const Text('开始'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  void _openMemoryTier(MemoryTier tier) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryTierScreen(
          tier: tier,
          memoryRepository: widget.memoryRepository,
          settingsRepository: widget.settingsRepository,
          sessionId: widget.chatRepository.activeSessionId,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ProviderConfigScreen(settingsRepository: widget.settingsRepository),
      ),
    );
  }

  void _openDeepResearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeepResearchScreen(
          settingsRepository: widget.settingsRepository,
          memoryRepository: widget.memoryRepository,
        ),
      ),
    );
  }

  void _openAutonomy() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AutonomyScreen(
          settingsRepository: widget.settingsRepository,
          autonomyService: _autonomyService,
          workspaceService: widget.workspaceService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.chatRepository,
        widget.memoryRepository,
        _chatEngine,
      ]),
      builder: (context, _) {
        final session = widget.chatRepository.activeSession;
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1000;
            final minSidebar = 240.0;
            final maxSidebar = (constraints.maxWidth * 0.34).clamp(
              240.0,
              360.0,
            );
            final preset = widget.settingsRepository.settings.layoutPreset;
            final minRight = 300.0;
            final rightScale = preset == LayoutPreset.focusPresentation
                ? 0.48
                : 0.38;
            final maxRight = (constraints.maxWidth * rightScale).clamp(
              320.0,
              620.0,
            );
            final sidebarWidth = _sidebarWidth.clamp(minSidebar, maxSidebar);
            final rightPanelWidth = _rightPanelWidth.clamp(minRight, maxRight);
            final showRightPanel =
                isWide &&
                (preset == LayoutPreset.focusChat
                    ? false
                    : preset == LayoutPreset.focusPresentation
                    ? true
                    : _showRightPanel);
            return Scaffold(
              drawer: isWide
                  ? null
                  : Drawer(
                      child: SessionSidebar(
                        chatRepository: widget.chatRepository,
                        memoryRepository: widget.memoryRepository,
                        onAddMemory: _openManualMemoryDialog,
                        onOpenTier: _openMemoryTier,
                        onOpenSettings: _openSettings,
                        onRemoveSession: _removeSession,
                        onCreateSession: () => _createSessionForRoute(),
                        dense: true,
                        onSelect: () => Navigator.of(context).pop(),
                      ),
                    ),
              body: Builder(
                builder: (context) {
                  final chrome = context.chrome;
                  final settings = widget.settingsRepository.settings;
                  final showVoiceChannel =
                      !kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.windows &&
                      settings.voiceChannelEnabled;
                  final accentGlow = chrome.accent.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.12
                        : 0.08,
                  );
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [chrome.background0, chrome.background1],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(-0.7, -0.8),
                                radius: 1.1,
                                colors: [accentGlow, Colors.transparent],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -160,
                        right: -120,
                        child: _GlowOrb(
                          size: 280,
                          color: chrome.accent.withValues(alpha: 0.16),
                        ),
                      ),
                      Positioned(
                        bottom: -180,
                        left: -140,
                        child: _GlowOrb(
                          size: 320,
                          color: chrome.accent.withValues(alpha: 0.12),
                        ),
                      ),
                      SafeArea(
                        child: Row(
                          children: [
                            if (isWide)
                              SizedBox(
                                width: sidebarWidth,
                                child: SessionSidebar(
                                  chatRepository: widget.chatRepository,
                                  memoryRepository: widget.memoryRepository,
                                  onAddMemory: _openManualMemoryDialog,
                                  onOpenTier: _openMemoryTier,
                                  onOpenSettings: _openSettings,
                                  onRemoveSession: _removeSession,
                                  onCreateSession: () =>
                                      _createSessionForRoute(),
                                ),
                              ),
                            if (isWide && _layoutEditing)
                              _ResizeHandle(
                                onDrag: (delta) {
                                  setState(() {
                                    _sidebarWidth = (_sidebarWidth + delta)
                                        .clamp(minSidebar, maxSidebar);
                                  });
                                  _scheduleLayoutPersist();
                                },
                              ),
                            Expanded(
                              child: Column(
                                children: [
                                  ChatHeader(
                                    sessionTitle: session?.title ?? 'New chat',
                                    onExportSession: () =>
                                        _exportActiveSession(),
                                    onExportAll: () => _exportAllSessions(),
                                    onCreateSession: () =>
                                        _createSessionForRoute(),
                                    onOpenDeepResearch: _openDeepResearch,
                                    onOpenAutonomy: _openAutonomy,
                                    showMenuButton: !isWide,
                                    estimatedTokens:
                                        _chatEngine.estimatedTokens,
                                    tokenLimit: _chatEngine.tokenLimit,
                                    isCompressing: _chatEngine.isCompressing,
                                    onToggleLayout: isWide
                                        ? () {
                                            setState(() {
                                              _layoutEditing = !_layoutEditing;
                                            });
                                          }
                                        : null,
                                    onResetLayout: isWide ? _resetLayout : null,
                                    onToggleRightPanel:
                                        (isWide &&
                                            preset != LayoutPreset.focusChat &&
                                            preset !=
                                                LayoutPreset.focusPresentation)
                                        ? () {
                                            setState(() {
                                              _showRightPanel =
                                                  !_showRightPanel;
                                            });
                                            _scheduleLayoutPersist();
                                          }
                                        : null,
                                    layoutEditing: _layoutEditing,
                                    rightPanelVisible: showRightPanel,
                                  ),
                                  if (widget.embeddingConfigMissing)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 8,
                                      ),
                                      child: _EmbeddingWarning(
                                        onOpenSettings: _openSettings,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  if (_chatEngine.partialTranscript.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 6,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '🎙️ ${_chatEngine.partialTranscript}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                color: chrome.accent,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ),
                                  if (_chatEngine.sttLastError.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 2,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'STT 错误: ${_chatEngine.sttLastError}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ),
                                  if (showVoiceChannel &&
                                      _chatEngine
                                          .voiceChannelPartialTranscript
                                          .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 2,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '🎧 ${_chatEngine.voiceChannelPartialTranscript}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                color: chrome.textSecondary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ),
                                  if (showVoiceChannel &&
                                      _chatEngine
                                          .voiceChannelHistory
                                          .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 4,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Wrap(
                                          spacing: 10,
                                          runSpacing: 6,
                                          children: _chatEngine
                                              .voiceChannelHistory
                                              .reversed
                                              .take(3)
                                              .map(
                                                (e) => Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest
                                                        .withValues(
                                                          alpha: 0.55,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                    border: Border.all(
                                                      color: Theme.of(context)
                                                          .dividerColor
                                                          .withValues(
                                                            alpha: 0.35,
                                                          ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '🎧 ${e.text}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelMedium
                                                        ?.copyWith(
                                                          color: chrome
                                                              .textSecondary,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: session == null
                                        ? const Center(child: Text('暂无会话'))
                                        : ListView.builder(
                                            controller: _scrollController,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                              vertical: 12,
                                            ),
                                            itemCount: session.messages.length,
                                            itemBuilder: (context, index) {
                                              final message =
                                                  session.messages[index];
                                              return MessageBubble(
                                                message: message,
                                                onSaveToMemory:
                                                    _saveMessageToMemory,
                                              );
                                            },
                                          ),
                                  ),
                                  ChatComposer(
                                    controller: _composerController,
                                    onSend: _handleSend,
                                    onToggleListening:
                                        _chatEngine.toggleListening,
                                    onToggleVoiceChannelMonitoring: _chatEngine
                                        .toggleVoiceChannelMonitoring,
                                    isListening: _chatEngine.isListening,
                                    isVoiceChannelMonitoring:
                                        _chatEngine.isVoiceChannelMonitoring,
                                    isStreaming: _chatEngine.isStreaming,
                                    partialTranscript:
                                        _chatEngine.partialTranscript,
                                    showVoiceChannelButton: showVoiceChannel,
                                    onOpenAgent: _openUniversalAgentDialog,
                                  ),
                                ],
                              ),
                            ),
                            if (showRightPanel && _layoutEditing)
                              _ResizeHandle(
                                onDrag: (delta) {
                                  setState(() {
                                    _rightPanelWidth =
                                        (_rightPanelWidth - delta).clamp(
                                          minRight,
                                          maxRight,
                                        );
                                  });
                                  _scheduleLayoutPersist();
                                },
                              ),
                            if (showRightPanel)
                              SizedBox(
                                width: rightPanelWidth,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final height =
                                          constraints.maxHeight.isFinite
                                          ? constraints.maxHeight
                                          : 360.0;
                                      final bubbleText =
                                          preset ==
                                              LayoutPreset.focusPresentation
                                          ? _latestAssistantText(session)
                                          : null;
                                      return Live3DPreview(
                                        height: height,
                                        settingsRepository:
                                            widget.settingsRepository,
                                        speechText: bubbleText,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            if (isWide &&
                                !showRightPanel &&
                                preset != LayoutPreset.focusChat)
                              _RightPanelRestoreStrip(
                                onTap: () {
                                  setState(() => _showRightPanel = true);
                                  _scheduleLayoutPersist();
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _EmbeddingWarning extends StatelessWidget {
  const _EmbeddingWarning({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF2A2316).withValues(alpha: 0.72)
        : const Color(0xFFFFF4E5);
    final border = isDark ? const Color(0xFF5A4520) : const Color(0xFFF2D1A6);
    final warningIcon = isDark
        ? const Color(0xFFFFC266)
        : const Color(0xFFB96B00);
    final warningText = isDark
        ? const Color(0xFFFFD9A6)
        : const Color(0xFF7A4E00);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: warningIcon),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '未配置 Embedding 模型，向量检索已停用（将使用关键词召回）。建议前往模型与能力配置补全。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: warningText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onOpenSettings, child: const Text('去配置')),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: 8,
          child: Center(
            child: Container(
              width: 2,
              height: 36,
              decoration: BoxDecoration(
                color: chrome.separatorStrong.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RightPanelRestoreStrip extends StatelessWidget {
  const _RightPanelRestoreStrip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 30,
          decoration: BoxDecoration(
            color: chrome.surfaceElevated,
            border: Border(left: BorderSide(color: chrome.separatorStrong)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Icon(
                Icons.face_retouching_natural_outlined,
                size: 18,
                color: chrome.accent,
              ),
              const Spacer(),
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  'Avatar',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: chrome.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayoutDefaults {
  const _LayoutDefaults({
    required this.sidebar,
    required this.rightPanel,
    required this.showRightPanel,
  });

  final double sidebar;
  final double rightPanel;
  final bool showRightPanel;
}

_LayoutDefaults _layoutDefaultsForPreset(LayoutPreset preset) {
  switch (preset) {
    case LayoutPreset.focusChat:
      return const _LayoutDefaults(
        sidebar: 260.0,
        rightPanel: 380.0,
        showRightPanel: false,
      );
    case LayoutPreset.focusPresentation:
      return const _LayoutDefaults(
        sidebar: 220.0,
        rightPanel: 520.0,
        showRightPanel: true,
      );
    case LayoutPreset.balanced:
      return const _LayoutDefaults(
        sidebar: 280.0,
        rightPanel: 380.0,
        showRightPanel: true,
      );
  }
}

String? _latestAssistantText(ChatSession? session) {
  if (session == null) {
    return null;
  }
  for (final message in session.messages.reversed) {
    if (message.role != ChatRole.assistant) {
      continue;
    }
    final trimmed = message.content.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

String _deliverableLabel(ResearchDeliverable deliverable) {
  switch (deliverable) {
    case ResearchDeliverable.summary:
      return '摘要';
    case ResearchDeliverable.report:
      return '报告';
    case ResearchDeliverable.table:
      return '表格';
    case ResearchDeliverable.slides:
      return 'PPT 大纲';
  }
}

String _depthLabel(ResearchDepth depth) {
  switch (depth) {
    case ResearchDepth.quick:
      return '快速';
    case ResearchDepth.deep:
      return '深度';
  }
}
