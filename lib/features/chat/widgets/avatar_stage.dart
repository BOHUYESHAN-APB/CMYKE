import 'package:flutter/material.dart';

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
                'Avatar Stage',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              _ModeChip(label: 'Live2D / Live3D'),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: stageHeight,
            decoration: BoxDecoration(
              color: const Color(0xFFF2EEE6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE4DDD2)),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.face_retouching_natural,
                    size: 36,
                    color: Color(0xFF1B9B7B),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '预留 Live2D / Live3D 画布',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6B6F7A),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '表情联动：待接入',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF8B909C),
                        ),
                  ),
                ],
              ),
            ),
          ),
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
        color: const Color(0xFF1B9B7B).withOpacity(0.12),
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
