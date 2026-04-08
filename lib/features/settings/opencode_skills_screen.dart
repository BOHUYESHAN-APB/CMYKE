import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/models/tool_gateway_skill.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/tool_router.dart';
import '../../ui/theme/cmyke_chrome.dart';

class OpenCodeSkillsScreen extends StatefulWidget {
  const OpenCodeSkillsScreen({
    super.key,
    required this.settingsRepository,
    required this.toolRouter,
  });

  final SettingsRepository settingsRepository;
  final ToolRouter toolRouter;

  @override
  State<OpenCodeSkillsScreen> createState() => _OpenCodeSkillsScreenState();
}

class _OpenCodeSkillsScreenState extends State<OpenCodeSkillsScreen> {
  final http.Client _client = http.Client();
  final _gitUrlController = TextEditingController();
  final _gitRefController = TextEditingController(text: 'main');
  final _gitRootController = TextEditingController(text: 'skills');
  final _installedFilterController = TextEditingController();
  final _ultimateFilterController = TextEditingController();

  bool _ultimateLoading = false;
  String? _ultimateError;
  List<String> _ultimateRepos = const [];

  bool _busy = false;
  String? _status;
  ToolGatewaySkillsCatalogResult? _catalog;
  ToolGatewaySkillsPreviewResult? _preview;
  ToolGatewaySkillImportSource? _previewSource;
  String? _previewLabel;
  bool _previewOverwrite = false;

  static const String _ultimateReadmeRawUrl =
      'https://raw.githubusercontent.com/ZhanlinCui/Ultimate-Agent-Skills-Collection/main/README.zh-CN.md';
  static const String _localOpenclawPath =
      'Studying/deep_research/openclaw-skills';

  @override
  void initState() {
    super.initState();
    final settings = widget.settingsRepository.settings;
    if (settings.toolGatewayEnabled &&
        settings.toolGatewayBaseUrl.trim().isNotEmpty &&
        settings.toolGatewayPairingToken.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshInstalled(announce: false);
        }
      });
    }
  }

  void _setStatus(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _status = message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorMessage(Object error) {
    final message = error.toString();
    const prefix = 'Exception: ';
    return message.startsWith(prefix)
        ? message.substring(prefix.length)
        : message;
  }

  bool _syncGatewayConfig({bool announce = true}) {
    final settings = widget.settingsRepository.settings;
    widget.toolRouter.updateGatewayConfig(
      ToolGatewayConfig(
        enabled: settings.toolGatewayEnabled,
        baseUrl: settings.toolGatewayBaseUrl,
        pairingToken: settings.toolGatewayPairingToken,
      ),
    );
    if (!settings.toolGatewayEnabled) {
      if (announce) {
        _setStatus('工具网关未启用。');
      }
      return false;
    }
    if (settings.toolGatewayBaseUrl.trim().isEmpty) {
      if (announce) {
        _setStatus('工具网关地址未配置。');
      }
      return false;
    }
    if (settings.toolGatewayPairingToken.trim().isEmpty) {
      if (announce) {
        _setStatus('Pairing Token 未配置。');
      }
      return false;
    }
    return true;
  }

  Future<void> _refreshInstalled({bool announce = true}) async {
    await _loadInstalled(announce: announce, showBusy: true);
  }

  Future<void> _loadInstalled({
    required bool announce,
    required bool showBusy,
  }) async {
    if (!_syncGatewayConfig(announce: announce)) {
      return;
    }
    if (showBusy) {
      setState(() => _busy = true);
    }
    try {
      final result = await widget.toolRouter.fetchInstalledSkills();
      if (!mounted) {
        return;
      }
      setState(() => _catalog = result);
      if (announce) {
        _setStatus('已读取：${result.skills.length} 个 skills。');
      }
    } catch (error) {
      if (announce) {
        _setStatus('读取失败：${_errorMessage(error)}');
      } else if (mounted) {
        setState(() => _status = '读取失败：${_errorMessage(error)}');
      }
    } finally {
      if (showBusy && mounted) {
        setState(() => _busy = false);
      }
    }
  }

  ToolGatewaySkillImportSource? _buildGitSource() {
    final url = _gitUrlController.text.trim();
    if (url.isEmpty) {
      _setStatus('请填写 Git 仓库 URL。');
      return null;
    }
    return ToolGatewaySkillImportSource.git(
      url: url,
      ref: _gitRefController.text.trim().isEmpty
          ? null
          : _gitRefController.text.trim(),
      root: _gitRootController.text.trim().isEmpty
          ? null
          : _gitRootController.text.trim(),
    );
  }

  Future<void> _previewImport({
    required ToolGatewaySkillImportSource source,
    required bool overwrite,
    required String label,
  }) async {
    if (!_syncGatewayConfig()) {
      return;
    }
    setState(() => _busy = true);
    try {
      final preview = await widget.toolRouter.previewSkillsImport(
        source: source,
        overwrite: overwrite,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _preview = preview;
        _previewSource = source;
        _previewLabel = label;
        _previewOverwrite = overwrite;
      });
      if (preview.total == 0 && preview.errors.isEmpty) {
        _setStatus('预览完成：未扫描到可导入的 skill。');
      } else if (preview.errors.isNotEmpty) {
        _setStatus('预览完成：${preview.total} 个候选，${preview.errors.length} 条警告。');
      } else {
        _setStatus(
          '预览完成：待处理 ${preview.total} 个，冲突 ${preview.conflicts}，覆盖 ${preview.overwrites}。',
        );
      }
    } catch (error) {
      _setStatus('预览失败：${_errorMessage(error)}');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _previewFromGit({required bool overwrite}) async {
    final source = _buildGitSource();
    if (source == null) {
      return;
    }
    await _previewImport(
      source: source,
      overwrite: overwrite,
      label: 'Git：${_gitUrlController.text.trim()}',
    );
  }

  Future<void> _previewFromOwnerRepo(String ownerRepo) async {
    final parts = ownerRepo.split('/');
    if (parts.length != 2) {
      return;
    }
    _gitUrlController.text = 'https://github.com/${parts[0]}/${parts[1]}.git';
    _gitRootController.text = '.';
    _gitRefController.text = '';
    await _previewFromGit(overwrite: false);
  }

  Future<void> _previewLocalOpenclaw({required bool overwrite}) async {
    await _previewImport(
      source: ToolGatewaySkillImportSource.local(
        path: _localOpenclawPath,
        root: 'skills',
      ),
      overwrite: overwrite,
      label: '本地：$_localOpenclawPath',
    );
  }

  Future<void> _installPreviewedSource() async {
    final source = _previewSource;
    if (source == null || _preview == null) {
      _setStatus('请先完成一次预览。');
      return;
    }
    if (!_syncGatewayConfig()) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.toolRouter.installSkills(
        source: source,
        overwrite: _previewOverwrite,
      );
      if (mounted) {
        setState(() {
          _preview = null;
          _previewSource = null;
          _previewLabel = null;
          _previewOverwrite = false;
        });
      }
      await _loadInstalled(announce: false, showBusy: false);
      if (result.errors.isNotEmpty) {
        _setStatus(
          '导入完成但有警告：已安装 ${result.installed.length}，跳过 ${result.skipped.length}，警告 ${result.errors.length}。',
        );
      } else {
        _setStatus(
          '导入完成：已安装 ${result.installed.length}，跳过 ${result.skipped.length}。',
        );
      }
    } catch (error) {
      _setStatus('导入失败：${_errorMessage(error)}');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loadUltimateCollection() async {
    setState(() {
      _ultimateLoading = true;
      _ultimateError = null;
      _ultimateRepos = const [];
    });
    try {
      final resp = await _client.get(Uri.parse(_ultimateReadmeRawUrl));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        setState(() => _ultimateError = 'HTTP ${resp.statusCode}');
        return;
      }
      final text = resp.body;
      final re = RegExp(
        r'https?://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)',
      );
      final repos = <String>{};
      for (final match in re.allMatches(text)) {
        final owner = match.group(1);
        final repo = match.group(2);
        if (owner == null || repo == null || repo.endsWith('.md')) {
          continue;
        }
        repos.add('$owner/$repo');
      }
      final list = repos.toList()..sort();
      setState(() => _ultimateRepos = list);
      _setStatus('Ultimate collection：解析到 ${list.length} 个 GitHub 仓库。');
    } catch (error) {
      setState(() => _ultimateError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _ultimateLoading = false);
      }
    }
  }

  Iterable<ToolGatewaySkillItem> _filterSkills(
    List<ToolGatewaySkillItem> items,
    String query,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return items;
    }
    return items.where((item) {
      final haystacks = <String?>[
        item.name,
        item.displayName,
        item.description,
        item.author,
        item.version,
        item.relativePath,
        item.homepage,
        item.source?.label,
        item.source?.location,
        ...item.tags,
      ];
      return haystacks.any(
        (entry) => entry != null && entry.toLowerCase().contains(normalized),
      );
    });
  }

  void _clearPreview() {
    setState(() {
      _preview = null;
      _previewSource = null;
      _previewLabel = null;
      _previewOverwrite = false;
    });
  }

  @override
  void dispose() {
    _client.close();
    _gitUrlController.dispose();
    _gitRefController.dispose();
    _gitRootController.dispose();
    _installedFilterController.dispose();
    _ultimateFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final hasLocalOpenclaw =
        !kReleaseMode &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
        Directory(_localOpenclawPath).existsSync();
    final installedSkills = _catalog?.skills ?? const <ToolGatewaySkillItem>[];
    final filteredInstalled = _filterSkills(
      installedSkills,
      _installedFilterController.text,
    ).toList();
    final previewItems = _preview?.items ?? const <ToolGatewaySkillItem>[];
    final filteredUltimateRepos = _ultimateRepos
        .where((entry) {
          final filter = _ultimateFilterController.text.trim().toLowerCase();
          if (filter.isEmpty) {
            return true;
          }
          return entry.toLowerCase().contains(filter);
        })
        .take(40)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenCode Skills'),
        actions: [
          IconButton(
            tooltip: '刷新已安装',
            onPressed: _busy ? null : _refreshInstalled,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '现在的 skills 管理会先走预览，再写入共享目录 `_shared/opencode/.opencode/skill/`。这样可以在安装前看到来源、元数据、冲突和覆盖行为，后续也更容易做合并与升级。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
          ),
          if (_status != null) ...[
            const SizedBox(height: 10),
            Text(
              _status!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已安装（${installedSkills.length}）',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if ((_catalog?.skillDir ?? '').isNotEmpty)
                    SelectableText(
                      '目录：${_catalog!.skillDir}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _installedFilterController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: '过滤已安装 skills',
                      hintText: '按名字、作者、tag、来源检索',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (installedSkills.isEmpty)
                    Text(
                      _busy ? '读取中...' : '暂无（或尚未刷新）。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textSecondary,
                      ),
                    )
                  else ...[
                    Text(
                      '显示 ${filteredInstalled.length} / ${installedSkills.length}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...filteredInstalled
                        .take(40)
                        .map((item) => _SkillEntryCard(item: item)),
                    if (filteredInstalled.length > 40)
                      Text(
                        '仅展示前 40 项，请继续缩小过滤条件。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: chrome.textSecondary,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (_preview != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本次导入预览',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _previewLabel ?? '未命名来源',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if ((_preview?.skillDir ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SelectableText(
                        '目标目录：${_preview!.skillDir}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: chrome.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CountChip(label: '总计', value: _preview!.total),
                        _CountChip(label: '待安装', value: _preview!.ready),
                        _CountChip(label: '冲突', value: _preview!.conflicts),
                        _CountChip(label: '将覆盖', value: _preview!.overwrites),
                      ],
                    ),
                    if (_preview!.errors.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _preview!.errors
                              .take(5)
                              .map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '• $entry',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (previewItems.isEmpty)
                      Text(
                        '这次预览没有发现 `SKILL.md` / `skill.md`。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: chrome.textSecondary,
                        ),
                      )
                    else ...[
                      ...previewItems
                          .take(24)
                          .map((item) => _SkillEntryCard(item: item)),
                      if (previewItems.length > 24)
                        Text(
                          '仅展示前 24 项，实际预览总数为 ${previewItems.length}。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: chrome.textSecondary),
                        ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy || previewItems.isEmpty
                              ? null
                              : _installPreviewedSource,
                          icon: const Icon(Icons.system_update_alt),
                          label: Text(_previewOverwrite ? '按预览覆盖导入' : '按预览导入'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _clearPreview,
                          icon: const Icon(Icons.close),
                          label: const Text('清空预览'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '从 Git 导入',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _gitUrlController,
                    decoration: const InputDecoration(
                      labelText: '仓库 URL',
                      hintText: 'https://github.com/<owner>/<repo>.git',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _gitRefController,
                          decoration: const InputDecoration(
                            labelText: 'ref',
                            hintText: 'main',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _gitRootController,
                          decoration: const InputDecoration(
                            labelText: '扫描根目录',
                            hintText: 'skills',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _previewFromGit(overwrite: false),
                        icon: const Icon(Icons.visibility),
                        label: const Text('预览（不覆盖）'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _previewFromGit(overwrite: true),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('预览（覆盖）'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '说明：网关会克隆仓库并扫描 `${_gitRootController.text.trim().isEmpty ? 'skills' : _gitRootController.text.trim()}` 下所有包含 `SKILL.md/skill.md` 的目录，并把来源与元数据写入 manifest。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: chrome.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasLocalOpenclaw) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '开发用：预览本地 openclaw-skills',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '来源：$_localOpenclawPath（root: skills）',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _previewLocalOpenclaw(overwrite: false),
                          child: const Text('预览（不覆盖）'),
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _previewLocalOpenclaw(overwrite: true),
                          child: const Text('预览（覆盖）'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ultimate Agent Skills Collection',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '先从合集 README 解析仓库列表，再对感兴趣的仓库做预览。这样不会一上来就把不透明的第三方 skills 直接写入共享目录。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: chrome.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ultimateFilterController,
                          decoration: const InputDecoration(
                            labelText: '过滤（可选）',
                            hintText:
                                '例如：search / web / crawl / ppt / pdf / cite',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _ultimateLoading
                            ? null
                            : _loadUltimateCollection,
                        icon: _ultimateLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_download),
                        label: const Text('拉取列表'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _ultimateReadmeRawUrl,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: chrome.textSecondary,
                    ),
                  ),
                  if (_ultimateError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '拉取失败：$_ultimateError',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textSecondary,
                      ),
                    ),
                  ],
                  if (filteredUltimateRepos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...filteredUltimateRepos.map(
                      (entry) => Card(
                        child: ListTile(
                          title: Text(entry),
                          subtitle: const Text(
                            '先预览仓库中的 SKILL.md/skill.md，再决定是否导入。',
                          ),
                          trailing: FilledButton(
                            onPressed: _busy
                                ? null
                                : () => _previewFromOwnerRepo(entry),
                            child: const Text('预览'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label $value'));
  }
}

class _SkillEntryCard extends StatelessWidget {
  const _SkillEntryCard({required this.item});

  final ToolGatewaySkillItem item;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final metadata = <String>[
      if (item.author != null) '作者 ${item.author}',
      if (item.version != null) 'v${item.version}',
      if (item.userInvocable != null) item.userInvocable! ? '可直接唤起' : '仅自动调用',
      if (item.source != null && item.source!.label.trim().isNotEmpty)
        '来源 ${item.source!.label}',
    ];
    final requirementChips = <String>[
      ...item.requirements.bins.map((entry) => 'bin:$entry'),
      ...item.requirements.env.map((entry) => 'env:$entry'),
      ...item.requirements.os.map((entry) => 'os:$entry'),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (item.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.description!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Chip(label: Text(_statusLabel(item.status))),
              ],
            ),
            if (metadata.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: metadata
                    .map((entry) => Chip(label: Text(entry)))
                    .toList(),
              ),
            ],
            if (item.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: item.tags
                    .take(8)
                    .map((entry) => Chip(label: Text('#$entry')))
                    .toList(),
              ),
            ],
            if (requirementChips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: requirementChips
                    .take(8)
                    .map((entry) => Chip(label: Text(entry)))
                    .toList(),
              ),
            ],
            if (item.relativePath != null) ...[
              const SizedBox(height: 8),
              Text(
                '相对路径：${item.relativePath}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
              ),
            ],
            if (item.source != null &&
                item.source!.location.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '来源位置：${item.source!.location}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ready':
        return '可安装';
      case 'conflict':
        return '冲突';
      case 'will_overwrite':
        return '将覆盖';
      case 'installed':
        return '已安装';
      default:
        return status;
    }
  }
}
