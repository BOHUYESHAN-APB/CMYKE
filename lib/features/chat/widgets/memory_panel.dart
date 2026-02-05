import 'package:flutter/material.dart';

import '../../../core/models/memory_tier.dart';
import '../../../core/repositories/memory_repository.dart';
import '../../../ui/theme/cmyke_chrome.dart';

class MemoryPanel extends StatelessWidget {
  const MemoryPanel({
    super.key,
    required this.memoryRepository,
    required this.onAddMemory,
    this.dense = false,
    this.onOpenTier,
    this.sessionId,
  });

  final MemoryRepository memoryRepository;
  final VoidCallback onAddMemory;
  final bool dense;
  final void Function(MemoryTier tier)? onOpenTier;
  final String? sessionId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(dense ? 8 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '记忆层级',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onAddMemory,
                icon: const Icon(Icons.add),
                label: const Text('新增'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: MemoryTier.values
                  .map(
                    (tier) => _MemoryTierTile(
                      tier: tier,
                      count: memoryRepository.countByTier(
                        tier,
                        sessionId: sessionId,
                      ),
                      onTap: onOpenTier == null
                          ? null
                          : () => onOpenTier!(tier),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryTierTile extends StatelessWidget {
  const _MemoryTierTile({required this.tier, required this.count, this.onTap});

  final MemoryTier tier;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: chrome.accent.withValues(alpha: 0.12),
                foregroundColor: chrome.accent,
                child: Text(
                  tier.label.substring(0, 1),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tier.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tierHint(tier),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: chrome.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$count',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: chrome.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _tierHint(MemoryTier tier) {
    switch (tier) {
      case MemoryTier.context:
        return '会话上下文 / 摘要锚点';
      case MemoryTier.crossSession:
        return '核心记忆（稳定事实/偏好）';
      case MemoryTier.autonomous:
        return '日记记忆（按时间检索）';
      case MemoryTier.external:
        return '知识库（文档/资料）';
    }
  }
}
