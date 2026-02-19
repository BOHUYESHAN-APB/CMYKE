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
    this.onOpenDeepResearch,
    this.onOpenDrawer,
    this.onOpenAvatar,
    this.onOpenAutonomy,
    this.onToggleLayout,
    this.onResetLayout,
    this.onToggleRightPanel,
    this.layoutEditing = false,
    this.rightPanelVisible = true,
  });

  final String sessionTitle;
  final VoidCallback onExportSession;
  final VoidCallback onExportAll;
  final VoidCallback onCreateSession;
  final bool showMenuButton;
  final int estimatedTokens;
  final int? tokenLimit;
  final bool isCompressing;
  final VoidCallback? onOpenDeepResearch;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onOpenAvatar;
  final VoidCallback? onOpenAutonomy;
  final VoidCallback? onToggleLayout;
  final VoidCallback? onResetLayout;
  final VoidCallback? onToggleRightPanel;
  final bool layoutEditing;
  final bool rightPanelVisible;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 720;
          return Row(
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
              if (!isCompact) ...[
                const SizedBox(width: 12),
                _TokenStatus(
                  estimatedTokens: estimatedTokens,
                  tokenLimit: tokenLimit,
                  isCompressing: isCompressing,
                ),
                const SizedBox(width: 12),
                if (onToggleLayout != null)
                  IconButton(
                    tooltip: layoutEditing ? '完成布局' : '布局编辑',
                    onPressed: onToggleLayout,
                    icon: Icon(layoutEditing ? Icons.check : Icons.view_quilt),
                  ),
                if (layoutEditing && onResetLayout != null)
                  TextButton.icon(
                    onPressed: onResetLayout,
                    icon: const Icon(Icons.restore),
                    label: const Text('重置布局'),
                  ),
                if (layoutEditing && onToggleRightPanel != null)
                  TextButton.icon(
                    onPressed: onToggleRightPanel,
                    icon: Icon(
                      rightPanelVisible
                          ? Icons.close_fullscreen
                          : Icons.open_in_full,
                    ),
                    label: Text(rightPanelVisible ? '隐藏 Avatar' : '显示 Avatar'),
                  ),
                if (onOpenDeepResearch != null)
                  TextButton.icon(
                    onPressed: onOpenDeepResearch,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('深度研究'),
                  ),
                if (onOpenDeepResearch != null) const SizedBox(width: 6),
                if (onOpenAutonomy != null)
                  TextButton.icon(
                    onPressed: onOpenAutonomy,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('自主模式'),
                  ),
                if (onOpenAutonomy != null) const SizedBox(width: 6),
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
                    PopupMenuItem(
                      value: _ExportAction.all,
                      child: Text('导出全部会话'),
                    ),
                  ],
                ),
              ] else ...[
                PopupMenuButton<_HeaderAction>(
                  tooltip: '更多',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) {
                    switch (action) {
                      case _HeaderAction.newSession:
                        onCreateSession();
                        break;
                      case _HeaderAction.exportSession:
                        onExportSession();
                        break;
                      case _HeaderAction.exportAll:
                        onExportAll();
                        break;
                      case _HeaderAction.deepResearch:
                        onOpenDeepResearch?.call();
                        break;
                      case _HeaderAction.autonomy:
                        onOpenAutonomy?.call();
                        break;
                      case _HeaderAction.toggleLayout:
                        onToggleLayout?.call();
                        break;
                      case _HeaderAction.resetLayout:
                        onResetLayout?.call();
                        break;
                      case _HeaderAction.toggleRightPanel:
                        onToggleRightPanel?.call();
                        break;
                      case _HeaderAction.openAvatar:
                        onOpenAvatar?.call();
                        break;
                    }
                  },
                  itemBuilder: (context) {
                    final items = <PopupMenuEntry<_HeaderAction>>[];
                    items.add(
                      const PopupMenuItem(
                        value: _HeaderAction.newSession,
                        child: Text('新对话'),
                      ),
                    );
                    if (onOpenDeepResearch != null) {
                      items.add(
                        const PopupMenuItem(
                          value: _HeaderAction.deepResearch,
                          child: Text('深度研究'),
                        ),
                      );
                    }
                    if (onOpenAutonomy != null) {
                      items.add(
                        const PopupMenuItem(
                          value: _HeaderAction.autonomy,
                          child: Text('自主模式'),
                        ),
                      );
                    }
                    if (onToggleLayout != null) {
                      items.add(
                        PopupMenuItem(
                          value: _HeaderAction.toggleLayout,
                          child: Text(layoutEditing ? '完成布局' : '布局编辑'),
                        ),
                      );
                    }
                    if (layoutEditing && onResetLayout != null) {
                      items.add(
                        const PopupMenuItem(
                          value: _HeaderAction.resetLayout,
                          child: Text('重置布局'),
                        ),
                      );
                    }
                    if (layoutEditing && onToggleRightPanel != null) {
                      items.add(
                        PopupMenuItem(
                          value: _HeaderAction.toggleRightPanel,
                          child: Text(
                            rightPanelVisible ? '隐藏 Avatar' : '显示 Avatar',
                          ),
                        ),
                      );
                    }
                    if (onOpenAvatar != null) {
                      items.add(
                        const PopupMenuItem(
                          value: _HeaderAction.openAvatar,
                          child: Text('Avatar 展示区'),
                        ),
                      );
                    }
                    items.add(const PopupMenuDivider());
                    items.add(
                      const PopupMenuItem(
                        value: _HeaderAction.exportSession,
                        child: Text('导出当前会话'),
                      ),
                    );
                    items.add(
                      const PopupMenuItem(
                        value: _HeaderAction.exportAll,
                        child: Text('导出全部会话'),
                      ),
                    );
                    return items;
                  },
                ),
              ],
            ],
          );
        },
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

enum _HeaderAction {
  newSession,
  exportSession,
  exportAll,
  deepResearch,
  autonomy,
  toggleLayout,
  resetLayout,
  toggleRightPanel,
  openAvatar,
}
