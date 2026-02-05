import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/memory_tier.dart';
import '../../../ui/theme/cmyke_chrome.dart';
import '../../../ui/widgets/frosted_surface.dart';

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
    final chrome = context.chrome;
    final isUser = message.role == ChatRole.user;
    final textColor = isUser ? Colors.white : chrome.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _Avatar(label: 'L', color: chrome.accent),
          if (!isUser) const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: isUser
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(chrome.radiusL),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              chrome.accent.withValues(alpha: 0.92),
                              chrome.accent.withValues(alpha: 0.78),
                            ],
                          ),
                          boxShadow: chrome.elevationShadow,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                          child: _BubbleBody(
                            message: message,
                            textColor: textColor,
                            onSaveToMemory: onSaveToMemory,
                          ),
                        ),
                      )
                    : FrostedSurface(
                        borderRadius: BorderRadius.circular(chrome.radiusL),
                        blurSigma: chrome.blurSigma * 0.85,
                        shadows: const [],
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                        child: _BubbleBody(
                          message: message,
                          textColor: textColor,
                          onSaveToMemory: onSaveToMemory,
                        ),
                      ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 10),
          if (isUser) _Avatar(label: 'You', color: chrome.textSecondary),
        ],
      ),
    );
  }
}

class _BubbleBody extends StatelessWidget {
  const _BubbleBody({
    required this.message,
    required this.textColor,
    required this.onSaveToMemory,
  });

  final ChatMessage message;
  final Color textColor;
  final Future<void> Function(ChatMessage, MemoryTier) onSaveToMemory;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message.content,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: textColor, height: 1.5),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _roleLabel(message.role),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: textColor.withValues(alpha: isUser ? 0.7 : 0.7),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<MemoryTier>(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.bookmark_add_outlined,
                size: 18,
                color: textColor.withValues(alpha: isUser ? 0.9 : 0.7),
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
    );
  }
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: 0.16),
      foregroundColor: color,
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
