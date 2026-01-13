import 'package:flutter/material.dart';

import '../../common/live3d_preview.dart';

class AvatarStage extends StatelessWidget {
  const AvatarStage({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final stageHeight = compact ? 120.0 : 180.0;
    return Padding(
      padding: EdgeInsets.all(compact ? 8 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Live3D Stage',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              _ModeChip(label: 'Live3D 准备中'),
            ],
          ),
          const SizedBox(height: 8),
          Live3DPreview(height: stageHeight),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        // 0x1F ~= 12% alpha.
        color: const Color(0x1F1B9B7B),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF1B9B7B),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
