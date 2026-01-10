import 'package:flutter/material.dart';

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
  });

  final ChatRepository chatRepository;
  final MemoryRepository? memoryRepository;
  final VoidCallback? onAddMemory;
  final void Function(MemoryTier tier)? onOpenTier;
  final VoidCallback? onOpenSettings;
  final bool dense;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final sessions = chatRepository.sessions;
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
                      onPressed: () => chatRepository.createSession(),
                      icon: const Icon(Icons.add),
                      label: const Text('新建对话'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  final isActive =
                      session.id == chatRepository.activeSessionId;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    title: Text(
                      session.title,
                      maxLines: dense ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w500,
                          ),
                    ),
                    subtitle: Text(
                      '消息 ${session.messages.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF6B6F7A),
                          ),
                    ),
                    trailing: IconButton(
                      tooltip: '删除会话',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => chatRepository.removeSession(session.id),
                    ),
                    selected: isActive,
                    selectedTileColor: const Color(0xFFE7F4EF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onTap: () {
                      chatRepository.setActive(session.id);
                      onSelect?.call();
                    },
                  );
                },
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
