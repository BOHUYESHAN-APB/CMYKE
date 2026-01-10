import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.sessionTitle,
    required this.onExportSession,
    required this.onExportAll,
    required this.onCreateSession,
    required this.showMenuButton,
    this.onOpenDrawer,
    this.onOpenAvatar,
  });

  final String sessionTitle;
  final VoidCallback onExportSession;
  final VoidCallback onExportAll;
  final VoidCallback onCreateSession;
  final bool showMenuButton;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onOpenAvatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          if (showMenuButton)
            IconButton(
              tooltip: '会话列表',
              icon: const Icon(Icons.menu),
              onPressed: onOpenDrawer ?? () => Scaffold.of(context).openDrawer(),
            ),
          if (showMenuButton) const SizedBox(width: 4),
          Text(
            'CMYKE',
            style: GoogleFonts.notoSerifSc(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1F2228),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              sessionTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF4F5563),
                  ),
              overflow: TextOverflow.ellipsis,
            ),
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
              PopupMenuItem(
                value: _ExportAction.all,
                child: Text('导出全部会话'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _ExportAction { session, all }
