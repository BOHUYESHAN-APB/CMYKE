import 'package:flutter/material.dart';

import '../../../ui/theme/cmyke_chrome.dart';
import '../../../ui/widgets/frosted_surface.dart';

class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.sessionTitle,
    required this.onExportSession,
    required this.onExportAll,
    required this.onCreateSession,
    required this.showMenuButton,
    required this.estimatedTokens,
    this.tokenLimit,
    this.isCompressing = false,
    this.onOpenDrawer,
    this.onOpenAvatar,
  });

  final String sessionTitle;
  final VoidCallback onExportSession;
  final VoidCallback onExportAll;
  final VoidCallback onCreateSession;
  final bool showMenuButton;
  final int estimatedTokens;
  final int? tokenLimit;
  final bool isCompressing;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onOpenAvatar;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final brandStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: chrome.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          if (showMenuButton)
            IconButton(
              tooltip: '会话列表',
              icon: const Icon(Icons.menu),
              onPressed:
                  onOpenDrawer ?? () => Scaffold.of(context).openDrawer(),
            ),
          if (showMenuButton) const SizedBox(width: 4),
          Text('CMYKE', style: brandStyle),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              sessionTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: chrome.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          _TokenStatus(
            estimatedTokens: estimatedTokens,
            tokenLimit: tokenLimit,
            isCompressing: isCompressing,
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: onCreateSession,
            icon: const Icon(Icons.add),
            label: const Text('新对话'),
          ),
          const SizedBox(width: 6),
          if (onOpenAvatar != null)
            IconButton(
              tooltip: 'Avatar 展示区',
              onPressed: onOpenAvatar,
              icon: const Icon(Icons.face_retouching_natural_outlined),
            ),
          PopupMenuButton<_ExportAction>(
            tooltip: '导出',
            icon: const Icon(Icons.download_outlined),
            onSelected: (action) {
              switch (action) {
                case _ExportAction.session:
                  onExportSession();
                  break;
                case _ExportAction.all:
                  onExportAll();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ExportAction.session,
                child: Text('导出当前会话'),
              ),
              PopupMenuItem(value: _ExportAction.all, child: Text('导出全部会话')),
            ],
          ),
        ],
      ),
    );
  }
}

class _TokenStatus extends StatelessWidget {
  const _TokenStatus({
    required this.estimatedTokens,
    required this.tokenLimit,
    required this.isCompressing,
  });

  final int estimatedTokens;
  final int? tokenLimit;
  final bool isCompressing;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final label = tokenLimit == null
        ? 'Tokens $estimatedTokens'
        : 'Tokens $estimatedTokens / $tokenLimit';
    final ratio = (tokenLimit == null || tokenLimit == 0)
        ? null
        : estimatedTokens / tokenLimit!;
    final accent = _accentColor(chrome, ratio);
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
    );
    return FrostedSurface(
      borderRadius: BorderRadius.circular(999),
      blurSigma: chrome.blurSigma * 0.7,
      shadows: const [],
      highlight: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: textStyle),
          if (isCompressing) ...[
            const SizedBox(width: 8),
            Icon(Icons.autorenew, size: 14, color: chrome.accent),
            const SizedBox(width: 4),
            Text(
              '压缩中',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: chrome.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _accentColor(CmykeChrome chrome, double? ratio) {
    if (ratio == null) {
      return chrome.accent;
    }
    if (ratio >= 0.92) {
      return const Color(0xFFC24A3A);
    }
    if (ratio >= 0.7) {
      return const Color(0xFFB67A00);
    }
    return chrome.accent;
  }
}

enum _ExportAction { session, all }
