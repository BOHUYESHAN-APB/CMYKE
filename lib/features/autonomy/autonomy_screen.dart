import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';

import '../../core/models/app_settings.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/autonomy_service.dart';
import '../../core/services/workspace_service.dart';
import '../../ui/theme/cmyke_chrome.dart';

class AutonomyScreen extends StatelessWidget {
  const AutonomyScreen({
    super.key,
    required this.settingsRepository,
    required this.autonomyService,
    required this.workspaceService,
  });

  final SettingsRepository settingsRepository;
  final AutonomyService autonomyService;
  final WorkspaceService workspaceService;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([settingsRepository, autonomyService]),
      builder: (context, _) {
        final settings = settingsRepository.settings;
        final chrome = context.chrome;
        final enabled = settings.autonomyEnabled;
        final readiness = autonomyService.readiness;
        return Scaffold(
          appBar: AppBar(title: const Text('自主模式')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '总开关',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用自主模式'),
                        subtitle: const Text('闲置时允许 AI 主动探索与搭话'),
                        value: settings.autonomyEnabled,
                        onChanged: (value) {
                          settingsRepository.updateSettings(
                            settings.copyWith(autonomyEnabled: value),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '最近一次主动搭话：${_formatTime(autonomyService.lastProactiveRun)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: chrome.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '最近一次草稿生成：${_formatTime(autonomyService.lastExploreRun)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: chrome.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: '运行状态',
                children: [
                  _StatusLine(
                    label: '主动搭话',
                    ok: readiness.canProactive,
                    issues: readiness.issuesForProactive(),
                  ),
                  const SizedBox(height: 8),
                  _StatusLine(
                    label: '自主探索',
                    ok: readiness.canExplore,
                    issues: readiness.issuesForExplore(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: '主动搭话',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('闲置时主动发送消息'),
                    subtitle: const Text('会在对话框里主动提问或提醒'),
                    value: settings.autonomyProactiveEnabled,
                    onChanged: enabled
                        ? (value) {
                            settingsRepository.updateSettings(
                              settings.copyWith(
                                autonomyProactiveEnabled: value,
                              ),
                            );
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  _IntervalDropdown(
                    enabled: enabled && settings.autonomyProactiveEnabled,
                    label: '搭话间隔（分钟）',
                    value: settings.autonomyProactiveIntervalMinutes,
                    onChanged: (value) {
                      settingsRepository.updateSettings(
                        settings.copyWith(
                          autonomyProactiveIntervalMinutes: value,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: enabled && readiness.canProactive
                        ? () => autonomyService.runProactiveNow()
                        : null,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('立即搭话'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: '自主探索与草稿',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('闲置时生成草稿'),
                    subtitle: const Text('自动选题并生成草稿文件'),
                    value: settings.autonomyExploreEnabled,
                    onChanged: enabled
                        ? (value) {
                            settingsRepository.updateSettings(
                              settings.copyWith(autonomyExploreEnabled: value),
                            );
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  _IntervalDropdown(
                    enabled: enabled && settings.autonomyExploreEnabled,
                    label: '探索间隔（分钟）',
                    value: settings.autonomyExploreIntervalMinutes,
                    onChanged: (value) {
                      settingsRepository.updateSettings(
                        settings.copyWith(
                          autonomyExploreIntervalMinutes: value,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '草稿格式策略',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<DraftFormatStrategy>(
                    value: settings.draftFormatStrategy,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items:
                        DraftFormatStrategy.values
                            .map(
                              (strategy) => DropdownMenuItem(
                                value: strategy,
                                child: Text(_formatStrategyLabel(strategy)),
                              ),
                            )
                            .toList(),
                    onChanged: enabled
                        ? (value) {
                            if (value == null) return;
                            settingsRepository.updateSettings(
                              settings.copyWith(draftFormatStrategy: value),
                            );
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '平台选择',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...AutonomyPlatform.values.map((platform) {
                    final selected =
                        settings.autonomyPlatforms.contains(platform);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_platformLabel(platform)),
                      value: selected,
                      onChanged: enabled
                          ? (value) {
                              final next = List<AutonomyPlatform>.from(
                                settings.autonomyPlatforms,
                              );
                              if (value == true) {
                                if (!next.contains(platform)) {
                                  next.add(platform);
                                }
                              } else {
                                next.remove(platform);
                              }
                              if (next.isEmpty) {
                                next.add(AutonomyPlatform.x);
                              }
                              settingsRepository.updateSettings(
                                settings.copyWith(autonomyPlatforms: next),
                              );
                            }
                          : null,
                    );
                  }),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: enabled && readiness.canExplore
                        ? () => autonomyService.runExploreNow()
                        : null,
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('立即生成草稿'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: '草稿存储',
                children: [
                  FutureBuilder(
                    future: workspaceService.rootDirectory(),
                    builder: (context, snapshot) {
                      final path = snapshot.data?.path ?? '...';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '根目录：$path',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                                  color: chrome.textSecondary,
                                ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: snapshot.hasData
                                ? () => _openFolder(snapshot.data!.path)
                                : null,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('打开文件夹'),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatStrategyLabel(DraftFormatStrategy strategy) {
    switch (strategy) {
      case DraftFormatStrategy.platformDefault:
        return '按平台默认';
      case DraftFormatStrategy.markdown:
        return '固定 Markdown';
      case DraftFormatStrategy.text:
        return '固定 TXT';
    }
  }

  static String _platformLabel(AutonomyPlatform platform) {
    switch (platform) {
      case AutonomyPlatform.x:
        return 'X / Twitter';
      case AutonomyPlatform.xiaohongshu:
        return '小红书';
      case AutonomyPlatform.bilibili:
        return '哔哩哔哩';
      case AutonomyPlatform.wechat:
        return '微信公众号';
    }
  }

  static String _formatTime(DateTime? time) {
    if (time == null) return '未执行';
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  static Future<void> _openFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', [path]);
        return;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [path]);
        return;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [path]);
      }
    } catch (_) {}
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.ok,
    required this.issues,
  });

  final String label;
  final bool ok;
  final List<String> issues;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final statusColor = ok ? Colors.green : Theme.of(context).colorScheme.error;
    final statusLabel = ok ? '可运行' : '阻塞';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                statusLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (!ok) ...[
          const SizedBox(height: 6),
          ...issues.map(
            (issue) => Text(
              '• $issue',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: chrome.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _IntervalDropdown extends StatelessWidget {
  const _IntervalDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const options = [5, 10, 15, 20, 30, 45, 60, 90, 120];
    final items = options
        .map((v) => DropdownMenuItem(value: v, child: Text('$v 分钟')))
        .toList();
    return DropdownButtonFormField<int>(
      value: options.contains(value) ? value : 20,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        enabled: enabled,
      ),
      items: items,
      onChanged: enabled ? (value) => onChanged(value ?? 20) : null,
    );
  }
}
