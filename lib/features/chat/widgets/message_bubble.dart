import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/memory_tier.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onSaveToMemory,
  });

  final ChatMessage message;
  final Future<void> Function(ChatMessage, MemoryTier) onSaveToMemory;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final bubbleColor =
        isUser ? const Color(0xFF1B9B7B) : const Color(0xFFF2EEE6);
    final textColor = isUser ? Colors.white : const Color(0xFF1F2228);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _Avatar(label: 'L', color: const Color(0xFF1B9B7B)),
          if (!isUser) const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.content,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: textColor,
                                height: 1.5,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _roleLabel(message.role),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: textColor.withValues(
                                      alpha: isUser ? 0.7 : 0.6,
                                    ),
                                  ),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<MemoryTier>(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.bookmark_add_outlined,
                                size: 18,
                                color: textColor.withValues(
                                  alpha: isUser ? 0.8 : 0.6,
                                ),
                              ),
                              onSelected: (tier) => onSaveToMemory(message, tier),
                              itemBuilder: (context) => MemoryTier.values
                                  .map(
                                    (tier) => PopupMenuItem(
                                      value: tier,
                                      child: Text('写入 ${tier.label}'),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 10),
          if (isUser) _Avatar(label: 'You', color: const Color(0xFF2F3843)),
        ],
      ),
    );
  }

  String _roleLabel(ChatRole role) {
    switch (role) {
      case ChatRole.user:
        return 'You';
      case ChatRole.assistant:
        return 'Lumi';
      case ChatRole.system:
        return 'System';
    }
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: 0.15),
      foregroundColor: color,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
