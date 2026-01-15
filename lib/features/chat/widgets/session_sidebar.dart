import 'package:flutter/material.dart';

import '../../../core/models/chat_session.dart';
import '../../../core/models/memory_tier.dart';
import '../../../core/repositories/chat_repository.dart';
import '../../../core/repositories/memory_repository.dart';
import 'memory_panel.dart';

class SessionSidebar extends StatelessWidget {
  const SessionSidebar({
    super.key,
    required this.chatRepository,
    this.memoryRepository,
    this.onAddMemory,
    this.onOpenTier,
    this.onOpenSettings,
    this.dense = false,
    this.onSelect,
    this.onRemoveSession,
    this.onCreateSession,
  });

  final ChatRepository chatRepository;
  final MemoryRepository? memoryRepository;
  final VoidCallback? onAddMemory;
  final void Function(MemoryTier tier)? onOpenTier;
  final VoidCallback? onOpenSettings;
  final bool dense;
  final VoidCallback? onSelect;
  final Future<void> Function(String sessionId)? onRemoveSession;
  final VoidCallback? onCreateSession;

  @override
  Widget build(BuildContext context) {
    final sessions = chatRepository.sessions;
    final grouped = {
      ChatSessionMode.standard: <ChatSession>[],
      ChatSessionMode.realtime: <ChatSession>[],
      ChatSessionMode.universal: <ChatSession>[],
    };
    for (final session in sessions) {
      grouped[session.mode]?.add(session);
    }
    final sessionTiles = <Widget>[];

    void addSection(String title, List<ChatSession> items) {
      if (items.isEmpty) {
        return;
      }
      sessionTiles.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF6B6F7A),
                ),
          ),
        ),
      );
      for (final session in items) {
        sessionTiles.add(_SessionTile(
          session: session,
          isActive: session.id == chatRepository.activeSessionId,
          dense: dense,
          subtitle: '${_modeLabel(session.mode)} · 消息 ${session.messages.length}',
          onTap: () {
            chatRepository.setActive(session.id);
            onSelect?.call();
          },
          onDelete: () {
            if (onRemoveSession != null) {
              onRemoveSession!(session.id);
            } else {
              chatRepository.removeSession(session.id);
            }
          },
        ));
      }
    }

    addSection('基础对话', grouped[ChatSessionMode.standard] ?? []);
    addSection('实时对话', grouped[ChatSessionMode.realtime] ?? []);
    addSection('通用 Agent', grouped[ChatSessionMode.universal] ?? []);

    if (sessionTiles.isEmpty) {
      sessionTiles.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Text(
            '暂无会话',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B6F7A),
                ),
          ),
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFDFCF9),
        border: Border(
          right: BorderSide(color: Color(0xFFE4DDD2)),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '会话',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        if (onCreateSession != null) {
                          onCreateSession!();
                        } else {
                          chatRepository.createSession();
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('新建对话'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: sessionTiles,
              ),
            ),
            if (memoryRepository != null) const Divider(height: 1),
            if (memoryRepository != null)
              SizedBox(
                height: dense ? 210 : 250,
                child: MemoryPanel(
                  memoryRepository: memoryRepository!,
                  onAddMemory: onAddMemory ?? () {},
                  onOpenTier: onOpenTier,
                  sessionId: chatRepository.activeSessionId,
                  dense: true,
                ),
              ),
            if (onOpenSettings != null) const Divider(height: 1),
            if (onOpenSettings != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('设置与信息'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.isActive,
    required this.dense,
    required this.subtitle,
    required this.onTap,
    required this.onDelete,
  });

  final ChatSession session;
  final bool isActive;
  final bool dense;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      title: Text(
        session.title,
        maxLines: dense ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF6B6F7A),
            ),
      ),
      trailing: IconButton(
        tooltip: '删除会话',
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: onDelete,
      ),
      selected: isActive,
      selectedTileColor: const Color(0xFFE7F4EF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      onTap: onTap,
    );
  }
}

String _modeLabel(ChatSessionMode mode) {
  switch (mode) {
    case ChatSessionMode.standard:
      return '基础';
    case ChatSessionMode.realtime:
      return '实时';
    case ChatSessionMode.universal:
      return '通用Agent';
  }
}
