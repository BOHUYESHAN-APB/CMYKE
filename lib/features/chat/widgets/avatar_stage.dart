import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/runtime_hub.dart';
import '../../../core/repositories/settings_repository.dart';
import '../../common/live3d_preview.dart';

class AvatarStage extends StatelessWidget {
  const AvatarStage({
    super.key,
    this.compact = false,
    this.height,
    this.fill = false,
    this.settingsRepository,
  });

  final bool compact;
  final double? height;
  final bool fill;
  final SettingsRepository? settingsRepository;

  @override
  Widget build(BuildContext context) {
    final padding = compact ? 8.0 : 16.0;
    final headerHeight = compact ? 30.0 : 36.0;
    final baseHeight = compact ? 120.0 : 260.0;
    final debug = RuntimeHub.instance.live3dBridge.debug;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight.isFinite
            ? constraints.maxHeight - headerHeight - padding * 2 - 8
            : baseHeight;

        if (fill) {
          return Padding(
            padding: EdgeInsets.all(padding),
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
                    AnimatedBuilder(
                      animation: debug,
                      builder: (context, _) {
                        final kind = debug.currentMotionKind;
                        final label = kind == null || kind.isEmpty
                            ? (debug.currentMotionKey == null ? 'Live3D' : 'Playing')
                            : kind.toUpperCase();
                        return _ModeChip(label: label);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, inner) {
                      final h = inner.maxHeight.isFinite
                          ? inner.maxHeight
                          : available;
                      final viewerHeight = math.max(baseHeight, h * 0.46);
                      return Column(
                        children: [
                          Live3DPreview(
                            debug: true,
                            height: viewerHeight,
                            settingsRepository: settingsRepository,
                          ),
                          const SizedBox(height: 12),
                          const Expanded(child: _MotionDebugger()),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }

        final stageHeight = height ?? baseHeight;
        return Padding(
          padding: EdgeInsets.all(padding),
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
              Live3DPreview(
                debug: true,
                height: stageHeight,
                settingsRepository: settingsRepository,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MotionDebugger extends StatefulWidget {
  const _MotionDebugger();

  @override
  State<_MotionDebugger> createState() => _MotionDebuggerState();
}

class _MotionDebuggerState extends State<_MotionDebugger> {
  final TextEditingController _filterController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _query = '';

  int? _parseIndexQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    final q = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
    final n = int.tryParse(q);
    if (n == null || n <= 0) return null;
    return n;
  }

  bool _isAutoMotion(Map<String, dynamic> motion) {
    final auto = motion['auto'];
    if (auto is! Map) return false;
    return auto['talk'] == true || auto['idle'] == true || auto['hover'] == true;
  }

  String _agentTierOf(Map<String, dynamic> motion) {
    final raw = (motion['agent'] ?? '').toString().trim().toLowerCase();
    return (raw == 'common' || raw == 'rare') ? raw : '';
  }

  String _autoFlagsLabel(Map<String, dynamic> motion) {
    final auto = motion['auto'];
    if (auto is! Map) return '';
    final flags = <String>[];
    if (auto['talk'] == true) flags.add('talk');
    if (auto['idle'] == true) flags.add('idle');
    if (auto['hover'] == true) flags.add('hover');
    if (flags.isEmpty) return '';
    return 'auto:${flags.join(',')}';
  }

  Color _policyColor(Map<String, dynamic> motion) {
    if (_isAutoMotion(motion)) {
      return const Color(0xFF1B9B7B);
    }
    final tier = _agentTierOf(motion);
    if (tier == 'common') {
      return const Color(0xFF2E5AAC);
    }
    if (tier == 'rare') {
      return const Color(0xFFC25B00);
    }
    return const Color(0xFF6B6F7A);
  }

  String _formatMotionMeta(Map<String, dynamic> motion) {
    final id = (motion['id'] ?? '').toString().trim();
    final type = (motion['type'] ?? '').toString().trim();
    final parts = <String>[];
    if (id.isNotEmpty) parts.add(id);
    if (type.isNotEmpty) parts.add(type);
    final autoLabel = _autoFlagsLabel(motion);
    if (autoLabel.isNotEmpty) parts.add(autoLabel);
    final agentTier = _agentTierOf(motion);
    if (agentTier.isNotEmpty) parts.add('agent:$agentTier');
    return parts.join(' · ');
  }

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      final next = _filterController.text;
      if (next == _query) return;
      setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final debug = RuntimeHub.instance.live3dBridge.debug;
    return AnimatedBuilder(
      animation: debug,
      builder: (context, _) {
        final motions = _extractMotions(debug.vrmaCatalog);
        final total = motions.length;
        final autoCount = motions.where(_isAutoMotion).length;
        final agentCommonCount =
            motions.where((m) => _agentTierOf(m) == 'common').length;
        final agentRareCount =
            motions.where((m) => _agentTierOf(m) == 'rare').length;
        final agentCount = agentCommonCount + agentRareCount;
        final currentKey = debug.currentMotionKey;
        final currentIndex = _resolveIndex(currentKey, motions);
        final currentEntry = (currentIndex != null &&
                currentIndex > 0 &&
                currentIndex <= motions.length)
            ? motions[currentIndex - 1]
            : null;
        final nowPlayingLabel = _formatNowPlaying(
          kind: debug.currentMotionKind,
          index: currentIndex,
          key: currentKey,
          entry: currentEntry,
        );

        final query = _query.trim().toLowerCase();
        final indexQuery = _parseIndexQuery(query);
        final filtered = query.isEmpty
            ? motions
            : motions
                .asMap()
                .entries
                .where((entry) {
                  final fullIndex = entry.key + 1;
                  final m = entry.value;
                  if (indexQuery != null) {
                    return fullIndex == indexQuery;
                  }
                  final id = (m['id'] ?? '').toString().toLowerCase();
                  final name = (m['name'] ?? '').toString().toLowerCase();
                  final type = (m['type'] ?? '').toString().toLowerCase();
                  final url = (m['url'] ?? '').toString().toLowerCase();
                  final agent = _agentTierOf(m).toLowerCase();
                  final auto = _autoFlagsLabel(m).toLowerCase();
                  return id.contains(query) ||
                      name.contains(query) ||
                      type.contains(query) ||
                      url.contains(query) ||
                      agent.contains(query) ||
                      auto.contains(query);
                })
                .map((e) => e.value)
                .toList(growable: false);

        final recent = debug.motionHistory.take(10).toList(growable: false);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFDFCF9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4DDD2)),
          ),
          child: Scrollbar(
            controller: _scrollController,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Motion Debug',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 8),
                          if (debug.currentMotionKind != null)
                            _ModeChip(
                              label: debug.currentMotionKind!.toUpperCase(),
                            ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x1F1B9B7B),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$total',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF1B9B7B),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (autoCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x1F1B9B7B),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Auto: $autoCount',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: const Color(0xFF1B9B7B),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          if (agentCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x1F2E5AAC),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                agentRareCount > 0
                                    ? 'Agent: $agentCount (rare $agentRareCount)'
                                    : 'Agent: $agentCount',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: const Color(0xFF2E5AAC),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        nowPlayingLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1F2228),
                            ),
                      ),
                      if (debug.currentMotionRaw != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            debug.currentMotionRaw!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: const Color(0xFF6B6F7A),
                                ),
                          ),
                        ),
                      if (recent.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Recent',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: const Color(0xFF6B6F7A),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: recent
                              .map((raw) => _parseHistoryItem(raw))
                              .whereType<_MotionHistoryItem>()
                              .take(8)
                              .map((item) {
                            final index = _resolveIndex(item.key, motions);
                            final entry = (index != null &&
                                    index > 0 &&
                                    index <= motions.length)
                                ? motions[index - 1]
                                : null;
                            final label = _formatHistoryLabel(
                              item: item,
                              index: index,
                              entry: entry,
                            );
                            return ActionChip(
                              label: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: item.trigger.isEmpty
                                  ? null
                                  : () => RuntimeHub.instance.live3dBridge
                                      .playMotion(item.trigger),
                            );
                          }).toList(growable: false),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: _filterController,
                        decoration: const InputDecoration(
                          hintText: '过滤：输入 #序号 / id / name / type / url',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (total == 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '未加载动作列表（等待 Live3D 初始化）',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      else
                        const Divider(height: 1),
                    ],
                  ),
                ),
                if (total > 0)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final motion = filtered[index];
                        final fullIndex = motions.indexOf(motion) + 1;
                        final isPlaying = currentIndex == fullIndex;
                        final policyColor = _policyColor(motion);
                        final id = motion['id']?.toString() ?? '';
                        final name = motion['name']?.toString() ?? id;
                        final url = motion['url']?.toString() ?? '';
                        final trigger = id.isNotEmpty ? id : url;

                        return Column(
                          children: [
                            ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 0,
                              ),
                              tileColor:
                                  isPlaying ? const Color(0x1F1B9B7B) : null,
                              leading: Text(
                                '#${fullIndex.toString().padLeft(2, '0')}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: policyColor,
                                    ),
                              ),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                _formatMotionMeta(motion),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: const Color(0xFF6B6F7A)),
                              ),
                              trailing: IconButton(
                                tooltip: '播放',
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 18,
                                ),
                                onPressed: trigger.isEmpty
                                    ? null
                                    : () => RuntimeHub.instance.live3dBridge
                                        .playMotion(trigger),
                              ),
                            ),
                            if (index != filtered.length - 1)
                              const Divider(height: 1),
                          ],
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  _MotionHistoryItem? _parseHistoryItem(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    const vrmaPrefix = 'motion(vrma): ';
    const procPrefix = 'motion(procedural): ';

    if (trimmed == 'motion: Idle') {
      return const _MotionHistoryItem(
        kind: 'idle',
        key: 'idle_loop',
        trigger: 'idle',
        raw: 'motion: Idle',
      );
    }
    if (trimmed.startsWith(vrmaPrefix)) {
      final key = trimmed.substring(vrmaPrefix.length).trim();
      return _MotionHistoryItem(
        kind: 'vrma',
        key: key,
        trigger: key,
        raw: trimmed,
      );
    }
    if (trimmed.startsWith(procPrefix)) {
      final key = trimmed.substring(procPrefix.length).trim();
      return _MotionHistoryItem(
        kind: 'procedural',
        key: key,
        trigger: key,
        raw: trimmed,
      );
    }
    if (trimmed.startsWith('motion: unavailable')) {
      final start = trimmed.indexOf('(');
      final end = trimmed.lastIndexOf(')');
      final key = (start >= 0 && end > start)
          ? trimmed.substring(start + 1, end).trim()
          : trimmed;
      return _MotionHistoryItem(
        kind: 'unavailable',
        key: key,
        trigger: key,
        raw: trimmed,
      );
    }
    return null;
  }

  String _formatHistoryLabel({
    required _MotionHistoryItem item,
    required int? index,
    required Map<String, dynamic>? entry,
  }) {
    final prefix = index == null ? '' : '#${index.toString().padLeft(2, '0')} ';
    final name = entry?['name']?.toString().trim();
    if (name != null && name.isNotEmpty) {
      return '$prefix$name';
    }
    return '$prefix${item.key}';
  }

  List<Map<String, dynamic>> _extractMotions(Map<String, dynamic>? catalog) {
    if (catalog == null) return const [];
    final list = catalog['motions'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  int? _resolveIndex(String? key, List<Map<String, dynamic>> motions) {
    if (key == null) return null;
    final needle = key.trim().toLowerCase();
    if (needle.isEmpty) return null;

    for (var i = 0; i < motions.length; i++) {
      final m = motions[i];
      final id = (m['id'] ?? '').toString().trim().toLowerCase();
      final name = (m['name'] ?? '').toString().trim().toLowerCase();
      final url = (m['url'] ?? '').toString().trim().toLowerCase();
      final base = url.isEmpty ? '' : url.split('/').last;
      if (needle == id || needle == name || needle == url || needle == base) {
        return i + 1;
      }
    }
    return null;
  }

  String _formatNowPlaying({
    required String? kind,
    required int? index,
    required String? key,
    required Map<String, dynamic>? entry,
  }) {
    if (key == null || key.trim().isEmpty) {
      return 'Now Playing: -';
    }
    final kindLabel = (kind == null || kind.trim().isEmpty)
        ? null
        : kind.trim().toUpperCase();
    final kindSuffix = kindLabel == null ? '' : ' ($kindLabel)';
    final prefix = index == null ? '' : '#${index.toString().padLeft(2, '0')} ';
    final name = entry?['name']?.toString().trim();
    final id = entry?['id']?.toString().trim();
    if (name != null && name.isNotEmpty) {
      final suffix = (id != null && id.isNotEmpty) ? ' ($id)' : '';
      return 'Now Playing$kindSuffix: $prefix$name$suffix';
    }
    return 'Now Playing$kindSuffix: $prefix$key';
  }
}

class _MotionHistoryItem {
  const _MotionHistoryItem({
    required this.kind,
    required this.key,
    required this.trigger,
    required this.raw,
  });

  final String kind;
  final String key;
  final String trigger;
  final String raw;
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
