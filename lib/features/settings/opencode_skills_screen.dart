import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/repositories/settings_repository.dart';
import '../../ui/theme/cmyke_chrome.dart';

class OpenCodeSkillsScreen extends StatefulWidget {
  const OpenCodeSkillsScreen({super.key, required this.settingsRepository});

  final SettingsRepository settingsRepository;

  @override
  State<OpenCodeSkillsScreen> createState() => _OpenCodeSkillsScreenState();
}

class _OpenCodeSkillsScreenState extends State<OpenCodeSkillsScreen> {
  _OpenCodeSkillsScreenState({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  final _gitUrlController = TextEditingController();
  final _gitRefController = TextEditingController(text: 'main');
  final _gitRootController = TextEditingController(text: 'skills');
  final _ultimateFilterController = TextEditingController();
  bool _ultimateLoading = false;
  String? _ultimateError;
  List<String> _ultimateRepos = const [];

  bool _busy = false;
  String? _status;
  List<String> _installed = const [];

  Uri _buildGatewayUri(String baseUrl, String path) {
    var normalized = baseUrl.trim();
    if (!normalized.contains('://')) {
      normalized = 'http://$normalized';
    }
    final uri = Uri.parse(normalized);
    if (uri.path.isEmpty || uri.path == '/') {
      return uri.replace(path: path);
    }
    return uri.replace(path: '${uri.path}$path');
  }

  void _setStatus(String message) {
    if (!mounted) return;
    setState(() => _status = message);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshInstalled() async {
    final settings = widget.settingsRepository.settings;
    if (!settings.toolGatewayEnabled) {
      _setStatus('工具网关未启用。');
      return;
    }
    if (settings.toolGatewayBaseUrl.trim().isEmpty) {
      _setStatus('工具网关地址未配置。');
      return;
    }
    if (settings.toolGatewayPairingToken.trim().isEmpty) {
      _setStatus('Pairing Token 未配置。');
      return;
    }

    setState(() => _busy = true);
    try {
      final uri = _buildGatewayUri(
        settings.toolGatewayBaseUrl,
        '/api/v1/opencode/skills/installed',
      );
      final resp = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pairing_token': settings.toolGatewayPairingToken.trim(),
        }),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _setStatus('读取失败：HTTP ${resp.statusCode}');
        return;
      }
      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic> || data['ok'] != true) {
        _setStatus('读取失败：响应异常。');
        return;
      }
      final skills = (data['skills'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList()
        ..sort();
      setState(() => _installed = skills);
      _setStatus('已读取：${skills.length} 个 skills。');
    } catch (e) {
      _setStatus('读取失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installFromGit({required bool overwrite}) async {
    final settings = widget.settingsRepository.settings;
    if (!settings.toolGatewayEnabled) {
      _setStatus('工具网关未启用。');
      return;
    }
    final url = _gitUrlController.text.trim();
    if (url.isEmpty) {
      _setStatus('请填写 Git 仓库 URL。');
      return;
    }
    if (settings.toolGatewayBaseUrl.trim().isEmpty) {
      _setStatus('工具网关地址未配置。');
      return;
    }
    if (settings.toolGatewayPairingToken.trim().isEmpty) {
      _setStatus('Pairing Token 未配置。');
      return;
    }

    setState(() => _busy = true);
    try {
      final uri = _buildGatewayUri(
        settings.toolGatewayBaseUrl,
        '/api/v1/opencode/skills/install',
      );
      final resp = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pairing_token': settings.toolGatewayPairingToken.trim(),
          'overwrite': overwrite,
          'limit': 2000,
          'source': {
            'type': 'git',
            'url': url,
            'ref': _gitRefController.text.trim().isEmpty
                ? null
                : _gitRefController.text.trim(),
            'root': _gitRootController.text.trim().isEmpty
                ? null
                : _gitRootController.text.trim(),
          },
        }),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _setStatus('安装失败：HTTP ${resp.statusCode}');
        return;
      }
      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) {
        _setStatus('安装失败：响应异常。');
        return;
      }
      final errors = (data['errors'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final installed = (data['installed'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final skipped = (data['skipped'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (errors.isNotEmpty) {
        _setStatus('安装完成但有错误：${errors.length} 条（已安装 ${installed.length}）。');
      } else {
        _setStatus('安装完成：已安装 ${installed.length}，跳过 ${skipped.length}。');
      }
      await _refreshInstalled();
    } catch (e) {
      _setStatus('安装失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const String _ultimateReadmeRawUrl =
      'https://raw.githubusercontent.com/ZhanlinCui/Ultimate-Agent-Skills-Collection/main/README.zh-CN.md';

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
      final re = RegExp(r'https?://github\\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)');
      final repos = <String>{};
      for (final m in re.allMatches(text)) {
        final owner = m.group(1);
        final repo = m.group(2);
        if (owner == null || repo == null) continue;
        // Exclude obvious non-repo pseudo targets.
        if (repo.endsWith('.md')) continue;
        repos.add('$owner/$repo');
      }
      final list = repos.toList()..sort();
      setState(() => _ultimateRepos = list);
      _setStatus('Ultimate collection：解析到 ${list.length} 个 GitHub 仓库。');
    } catch (e) {
      setState(() => _ultimateError = e.toString());
    } finally {
      if (mounted) setState(() => _ultimateLoading = false);
    }
  }

  Future<void> _installFromOwnerRepo(String ownerRepo) async {
    final parts = ownerRepo.split('/');
    if (parts.length != 2) return;
    _gitUrlController.text = 'https://github.com/${parts[0]}/${parts[1]}.git';
    _gitRootController.text = '.';
    _gitRefController.text = '';
    await _installFromGit(overwrite: false);
  }

  Future<void> _installFromLocalOpenclawSkills({required bool overwrite}) async {
    final settings = widget.settingsRepository.settings;
    if (!settings.toolGatewayEnabled) {
      _setStatus('工具网关未启用。');
      return;
    }
    if (settings.toolGatewayBaseUrl.trim().isEmpty) {
      _setStatus('工具网关地址未配置。');
      return;
    }
    if (settings.toolGatewayPairingToken.trim().isEmpty) {
      _setStatus('Pairing Token 未配置。');
      return;
    }

    setState(() => _busy = true);
    try {
      final uri = _buildGatewayUri(
        settings.toolGatewayBaseUrl,
        '/api/v1/opencode/skills/install',
      );
      final resp = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pairing_token': settings.toolGatewayPairingToken.trim(),
          'overwrite': overwrite,
          'limit': 2000,
          'source': {
            'type': 'local',
            'path': 'Studying/deep_research/openclaw-skills',
            'root': 'skills',
          },
        }),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _setStatus('导入失败：HTTP ${resp.statusCode}');
        return;
      }
      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) {
        _setStatus('导入失败：响应异常。');
        return;
      }
      final installed = (data['installed'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final errors = (data['errors'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (errors.isNotEmpty) {
        _setStatus('导入完成但有错误：${errors.length} 条（已安装 ${installed.length}）。');
      } else {
        _setStatus('导入完成：已安装 ${installed.length}。');
      }
      await _refreshInstalled();
    } catch (e) {
      _setStatus('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _client.close();
    _gitUrlController.dispose();
    _gitRefController.dispose();
    _gitRootController.dispose();
    _ultimateFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final hasLocalOpenclaw = !kReleaseMode &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
        Directory('Studying/deep_research/openclaw-skills').existsSync();

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
            '这些 skills 会安装到 workspace 的共享目录 `_shared/opencode/.opencode/skill/`，对基础模式与深度研究都生效。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: chrome.textSecondary,
                ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ultimate Agent Skills Collection',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '从合集 README 解析出 GitHub 仓库列表，然后你可以逐个安装（安装会扫描仓库内的 SKILL.md/skill.md 目录并导入）。',
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
                            hintText: '例如：search / web / crawl / ppt / pdf / cite',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _ultimateLoading ? null : _loadUltimateCollection,
                        icon: _ultimateLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
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
                  if (_ultimateRepos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ..._ultimateRepos
                        .where((entry) {
                          final f = _ultimateFilterController.text.trim().toLowerCase();
                          if (f.isEmpty) return true;
                          return entry.toLowerCase().contains(f);
                        })
                        .take(40)
                        .map((entry) {
                          return Card(
                            child: ListTile(
                              title: Text(entry),
                              subtitle: const Text('点击安装会从该仓库扫描 SKILL.md/skill.md 并导入。'),
                              trailing: FilledButton(
                                onPressed: _busy ? null : () => _installFromOwnerRepo(entry),
                                child: const Text('安装'),
                              ),
                            ),
                          );
                        }),
                  ],
                ],
              ),
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(
              _status!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: chrome.textSecondary,
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
                    '已安装（${_installed.length}）',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_installed.isEmpty)
                    Text(
                      _busy ? '读取中...' : '暂无（或尚未刷新）。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: chrome.textSecondary,
                          ),
                    )
                  else
                    ..._installed.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SelectableText(s),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '从 Git 导入',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
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
                        onPressed: _busy ? null : () => _installFromGit(overwrite: false),
                        icon: const Icon(Icons.download),
                        label: const Text('导入（不覆盖）'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _installFromGit(overwrite: true),
                        icon: const Icon(Icons.system_update_alt),
                        label: const Text('导入（覆盖）'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '说明：网关会克隆仓库并扫描 `${_gitRootController.text.trim().isEmpty ? 'skills' : _gitRootController.text.trim()}` 下面所有包含 SKILL.md/skill.md 的目录。',
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
                      '开发用：从本仓库 Studying/openclaw-skills 导入',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _installFromLocalOpenclawSkills(overwrite: false),
                          child: const Text('导入（不覆盖）'),
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _installFromLocalOpenclawSkills(overwrite: true),
                          child: const Text('导入（覆盖）'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
