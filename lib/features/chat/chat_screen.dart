import 'package:flutter/material.dart';

import '../../core/models/chat_message.dart';
import '../../core/models/memory_record.dart';
import '../../core/models/memory_tier.dart';
import '../../core/repositories/chat_repository.dart';
import '../../core/repositories/memory_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/chat_export_service.dart';
import '../../core/services/chat_engine.dart';
import '../memory/memory_tier_screen.dart';
import '../settings/provider_config_screen.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_header.dart';
import 'widgets/avatar_stage.dart';
import 'widgets/message_bubble.dart';
import 'widgets/session_sidebar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatRepository,
    required this.memoryRepository,
    required this.settingsRepository,
    this.embeddingConfigMissing = false,
  });

  final ChatRepository chatRepository;
  final MemoryRepository memoryRepository;
  final SettingsRepository settingsRepository;
  final bool embeddingConfigMissing;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatExportService _exportService = ChatExportService();
  late final ChatEngine _chatEngine;

  @override
  void initState() {
    super.initState();
    _chatEngine = ChatEngine(
      chatRepository: widget.chatRepository,
      memoryRepository: widget.memoryRepository,
      settingsRepository: widget.settingsRepository,
    );
  }

  @override
  void dispose() {
    _composerController.dispose();
    _scrollController.dispose();
    _chatEngine.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _composerController.clear();
    await _chatEngine.sendText(text);
    _scrollToBottom();
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

  Future<void> _exportActiveSession() async {
    final session = widget.chatRepository.activeSession;
    if (session == null) {
      return;
    }
    final path = await _exportService.exportSession(session);
    _showSnack('会话日志已导出: $path');
  }

  Future<void> _exportAllSessions() async {
    final path =
        await _exportService.exportAll(widget.chatRepository.sessions);
    _showSnack('全部会话已导出: $path');
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _saveMessageToMemory(
    ChatMessage message,
    MemoryTier tier,
  ) async {
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
                await widget.memoryRepository.addRecord(
                  tier: selectedTier,
                  record: MemoryRecord(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    tier: selectedTier,
                    content: content,
                    createdAt: DateTime.now(),
                  ),
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

  Future<void> _openAvatarSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFDFCF9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: AvatarStage(compact: false),
        );
      },
    );
  }

  void _openMemoryTier(MemoryTier tier) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryTierScreen(
          tier: tier,
          memoryRepository: widget.memoryRepository,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProviderConfigScreen(
          settingsRepository: widget.settingsRepository,
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
                        dense: true,
                        onSelect: () => Navigator.of(context).pop(),
                      ),
                    ),
              body: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFF7F3ED), Color(0xFFF1F4F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      if (isWide)
                        SizedBox(
                          width: 280,
                          child: SessionSidebar(
                            chatRepository: widget.chatRepository,
                            memoryRepository: widget.memoryRepository,
                            onAddMemory: _openManualMemoryDialog,
                            onOpenTier: _openMemoryTier,
                            onOpenSettings: _openSettings,
                          ),
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            ChatHeader(
                              sessionTitle:
                                  session?.title ?? 'New chat',
                              onExportSession: () => _exportActiveSession(),
                              onExportAll: () => _exportAllSessions(),
                              onCreateSession: () =>
                                  widget.chatRepository.createSession(),
                              showMenuButton: !isWide,
                              onOpenAvatar: isWide ? null : _openAvatarSheet,
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
                                          color: const Color(0xFF1B9B7B),
                                        ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: session == null
                                  ? const Center(
                                      child: Text('暂无会话'),
                                    )
                                  : ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      itemCount: session.messages.length,
                                      itemBuilder: (context, index) {
                                        final message = session.messages[index];
                                        return MessageBubble(
                                          message: message,
                                          onSaveToMemory: _saveMessageToMemory,
                                        );
                                      },
                                    ),
                            ),
                            ChatComposer(
                              controller: _composerController,
                              onSend: _handleSend,
                              onToggleListening: _chatEngine.toggleListening,
                              isListening: _chatEngine.isListening,
                              isStreaming: _chatEngine.isStreaming,
                              partialTranscript:
                                  _chatEngine.partialTranscript,
                            ),
                          ],
                        ),
                      ),
                      if (isWide)
                        SizedBox(
                          width: 280,
                          child: const AvatarStage(),
                        ),
                    ],
                  ),
                ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF2D1A6)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFB96B00),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '未配置 Embedding 模型，向量检索已停用。请前往模型与能力配置补全。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF7A4E00),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onOpenSettings,
            child: const Text('去配置'),
          ),
        ],
      ),
    );
  }
}
