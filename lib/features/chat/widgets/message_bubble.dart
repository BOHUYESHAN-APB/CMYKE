import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/models/chat_attachment.dart';
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
    final sourceLabel = _sourceLabel(message);
    final sourceColor = _sourceColor(context, message);
    final extracted = _extractImageTokens(message.content);
    final displayText = _stripImageTokens(message.content).trimRight();
    final allImageItems = <_ImageItem>[
      ...message.attachments
          .where((a) => a.kind == ChatAttachmentKind.image)
          .map(
            (a) => _ImageItem(
              label: a.caption?.trim().isNotEmpty == true ? a.caption : null,
              uri: Uri.file(a.localPath),
            ),
          ),
      ...extracted,
    ];
    final fileAttachments = message.attachments
        .where((a) => a.kind == ChatAttachmentKind.file)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (displayText.isNotEmpty)
          Text(
            displayText,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: textColor, height: 1.5),
          ),
        if (allImageItems.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: allImageItems
                .take(6)
                .map((item) => _ImageThumb(item: item))
                .toList(growable: false),
          ),
        ],
        if (fileAttachments.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: fileAttachments
                .take(8)
                .map(
                  (a) => Chip(
                    label: Text(a.fileName),
                    avatar: const Icon(Icons.insert_drive_file_outlined),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        if (sourceLabel != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: sourceColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                sourceLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: sourceColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
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

String? _sourceLabel(ChatMessage message) {
  final kind = message.sourceKind;
  if (kind == null || kind == ChatSourceKind.user) {
    return null;
  }
  switch (kind) {
    case ChatSourceKind.mic:
      return '麦克风输入';
    case ChatSourceKind.voiceChannel:
      return '语音频道';
    case ChatSourceKind.barrage:
      return '弹幕';
    case ChatSourceKind.plugin:
      return '插件';
    case ChatSourceKind.system:
      return '系统';
    case ChatSourceKind.tool:
      return '工具结果';
    case ChatSourceKind.autonomy:
      return '自主模式';
    case ChatSourceKind.user:
      return null;
  }
}

Color _sourceColor(BuildContext context, ChatMessage message) {
  final chrome = context.chrome;
  switch (message.sourceKind) {
    case ChatSourceKind.voiceChannel:
      return Colors.tealAccent.shade400;
    case ChatSourceKind.barrage:
      return Colors.orangeAccent.shade200;
    case ChatSourceKind.autonomy:
      return chrome.accent;
    case ChatSourceKind.tool:
      return Colors.indigoAccent.shade100;
    case ChatSourceKind.mic:
      return Colors.lightBlueAccent.shade200;
    case ChatSourceKind.plugin:
      return Colors.pinkAccent.shade100;
    case ChatSourceKind.system:
      return chrome.textSecondary;
    case ChatSourceKind.user:
    case null:
      return chrome.textSecondary;
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

class _ImageItem {
  const _ImageItem({required this.uri, this.label});

  final Uri uri;
  final String? label;
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.item});

  final _ImageItem item;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final uri = item.uri;
    final image = switch (uri.scheme) {
      'http' || 'https' => Image.network(
        uri.toString(),
        width: 160,
        height: 160,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _ImageError(uri: uri),
      ),
      'file' => Image.file(
        File(uri.toFilePath()),
        width: 160,
        height: 160,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _ImageError(uri: uri),
      ),
      _ => _ImageError(uri: uri),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(chrome.radiusL),
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Container(
                      color: Colors.black,
                      child: Center(
                        child: switch (uri.scheme) {
                          'http' || 'https' => Image.network(
                            uri.toString(),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => _ImageError(uri: uri),
                          ),
                          'file' => Image.file(
                            File(uri.toFilePath()),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => _ImageError(uri: uri),
                          ),
                          _ => _ImageError(uri: uri),
                        },
                      ),
                    ),
                  ),
                  if (item.label != null && item.label!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        item.label!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(chrome.radiusL),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: chrome.separatorStrong),
            borderRadius: BorderRadius.circular(chrome.radiusL),
          ),
          child: image,
        ),
      ),
    );
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return Container(
      width: 160,
      height: 160,
      color: chrome.surfaceElevated,
      alignment: Alignment.center,
      child: Icon(Icons.broken_image_outlined, color: chrome.textSecondary),
    );
  }
}

List<_ImageItem> _extractImageTokens(String text) {
  final reg = RegExp(r'\[IMAGE:\s*([^\]]+)\]', caseSensitive: false);
  final out = <_ImageItem>[];
  final seen = <String>{};
  for (final match in reg.allMatches(text)) {
    final raw = match.group(1)?.trim();
    if (raw == null || raw.isEmpty) continue;
    final key = raw.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    Uri? uri;
    try {
      uri = Uri.parse(raw);
    } catch (_) {
      continue;
    }
    if (uri.scheme.isEmpty) {
      uri = Uri.file(raw);
    }
    out.add(_ImageItem(uri: uri));
  }
  return out;
}

String _stripImageTokens(String text) {
  return text.replaceAll(RegExp(r'\[IMAGE:\s*[^\]]+\]'), '');
}
