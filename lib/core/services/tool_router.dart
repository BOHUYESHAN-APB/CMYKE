import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/tool_gateway_skill.dart';
import '../models/tool_intent.dart';

class ToolGatewayConfig {
  const ToolGatewayConfig({
    required this.enabled,
    required this.baseUrl,
    required this.pairingToken,
  });

  final bool enabled;
  final String baseUrl;
  final String pairingToken;

  static const disabled = ToolGatewayConfig(
    enabled: false,
    baseUrl: '',
    pairingToken: '',
  );
}

class ToolGatewayProbeResult {
  const ToolGatewayProbeResult({
    required this.ok,
    required this.enabled,
    required this.supportsRun,
    required this.supportsCancel,
    required this.routes,
    required this.features,
    required this.activeRuns,
    required this.checkedAt,
    this.error,
  });

  final bool ok;
  final bool enabled;
  final bool supportsRun;
  final bool supportsCancel;
  final Set<String> routes;
  final Set<String> features;
  final int activeRuns;
  final DateTime checkedAt;
  final String? error;

  bool supportsFeature(String feature) => features.contains(feature);
}

class ToolGatewayCancelResult {
  const ToolGatewayCancelResult({
    required this.ok,
    required this.accepted,
    required this.activeRunsSignaled,
    this.error,
  });

  final bool ok;
  final bool accepted;
  final int activeRunsSignaled;
  final String? error;
}

class ToolRouter {
  ToolRouter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  ToolGatewayConfig _config = ToolGatewayConfig.disabled;
  ToolGatewayProbeResult? _probeCache;
  static const Duration _probeCacheTtl = Duration(seconds: 10);

  String _sanitizeRelSegment(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'trace';
    final buffer = StringBuffer();
    for (final rune in trimmed.runes) {
      final c = String.fromCharCode(rune);
      final ok = RegExp(r'[A-Za-z0-9_-]').hasMatch(c);
      buffer.write(ok ? c : '_');
    }
    final out = buffer.toString().replaceAll(RegExp(r'_+'), '_');
    final normalized = out.replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'trace' : normalized;
  }

  String _deriveCwd(ToolIntent intent) {
    final traceId = intent.traceId?.trim();
    final tracePart = (traceId != null && traceId.isNotEmpty)
        ? _sanitizeRelSegment(traceId)
        : null;
    switch (intent.action) {
      case ToolAction.search:
      case ToolAction.crawl:
      case ToolAction.analyze:
      case ToolAction.summarize:
        return tracePart == null ? 'scratch/tools' : 'scratch/tools/$tracePart';
      case ToolAction.code:
      case ToolAction.imageGen:
      case ToolAction.imageAnalyze:
        return 'scratch';
    }
  }

  bool _isDeepResearchRouting(String? routing) {
    final value = routing?.trim().toLowerCase();
    if (value == null || value.isEmpty) {
      return false;
    }
    return value == 'deep_research' ||
        value == 'deepresearch' ||
        value == 'research' ||
        value == 'deep_research_screen';
  }

  void updateGatewayConfig(ToolGatewayConfig config) {
    _config = config;
    _probeCache = null;
  }

  Future<void> dispose() async {
    _client.close();
  }

  Future<ToolGatewayProbeResult> probeCapabilities({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh && _probeCache != null) {
      final age = now.difference(_probeCache!.checkedAt);
      if (age <= _probeCacheTtl) {
        return _probeCache!;
      }
    }
    final error = _gatewayConfigError();
    if (error != null) {
      return _cacheProbe(
        ToolGatewayProbeResult(
          ok: false,
          enabled: _config.enabled,
          supportsRun: false,
          supportsCancel: false,
          routes: const <String>{},
          features: const <String>{},
          activeRuns: 0,
          checkedAt: now,
          error: error,
        ),
      );
    }
    final uri = _buildGatewayUri(
      _config.baseUrl,
      '/api/v1/gateway/capabilities',
    );
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 2));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _cacheProbe(
          ToolGatewayProbeResult(
            ok: false,
            enabled: true,
            supportsRun: false,
            supportsCancel: false,
            routes: const <String>{},
            features: const <String>{},
            activeRuns: 0,
            checkedAt: now,
            error: '工具网关错误：HTTP ${response.statusCode}',
          ),
        );
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        return _cacheProbe(
          ToolGatewayProbeResult(
            ok: false,
            enabled: true,
            supportsRun: false,
            supportsCancel: false,
            routes: const <String>{},
            features: const <String>{},
            activeRuns: 0,
            checkedAt: now,
            error: '工具网关响应异常。',
          ),
        );
      }
      final routes = ((data['routes'] as List<dynamic>? ?? const <dynamic>[]))
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toSet();
      final features =
          ((data['features'] as List<dynamic>? ?? const <dynamic>[]))
              .map((entry) => entry.toString().trim())
              .where((entry) => entry.isNotEmpty)
              .toSet();
      final runtime = data['runtime'] as Map<String, dynamic>?;
      return _cacheProbe(
        ToolGatewayProbeResult(
          ok: data['ok'] == true,
          enabled: true,
          supportsRun: routes.contains('/api/v1/opencode/run'),
          supportsCancel: routes.contains('/api/v1/opencode/cancel'),
          routes: routes,
          features: features,
          activeRuns: (runtime?['active_runs'] as num?)?.toInt() ?? 0,
          checkedAt: now,
          error: data['ok'] == true ? null : '工具网关能力探测失败。',
        ),
      );
    } on TimeoutException {
      return _cacheProbe(
        ToolGatewayProbeResult(
          ok: false,
          enabled: true,
          supportsRun: false,
          supportsCancel: false,
          routes: const <String>{},
          features: const <String>{},
          activeRuns: 0,
          checkedAt: now,
          error: '工具网关能力探测超时。',
        ),
      );
    } catch (error) {
      return _cacheProbe(
        ToolGatewayProbeResult(
          ok: false,
          enabled: true,
          supportsRun: false,
          supportsCancel: false,
          routes: const <String>{},
          features: const <String>{},
          activeRuns: 0,
          checkedAt: now,
          error: '工具网关请求失败：$error',
        ),
      );
    }
  }

  Future<ToolGatewayCancelResult> cancelActiveRun({
    String? sessionId,
    String? cancelGroup,
    String? reason,
  }) async {
    final error = _gatewayConfigError();
    if (error != null) {
      return ToolGatewayCancelResult(
        ok: false,
        accepted: false,
        activeRunsSignaled: 0,
        error: error,
      );
    }
    final probe = await probeCapabilities();
    if (!probe.ok || !probe.supportsCancel) {
      return ToolGatewayCancelResult(
        ok: false,
        accepted: false,
        activeRunsSignaled: 0,
        error: probe.error ?? '工具网关不支持取消。',
      );
    }
    final trimmedSessionId = sessionId?.trim();
    final trimmedCancelGroup = cancelGroup?.trim();
    if ((trimmedSessionId == null || trimmedSessionId.isEmpty) &&
        (trimmedCancelGroup == null || trimmedCancelGroup.isEmpty)) {
      return const ToolGatewayCancelResult(
        ok: false,
        accepted: false,
        activeRunsSignaled: 0,
        error: 'session_id or cancel_group required',
      );
    }
    final payload = <String, dynamic>{
      'pairing_token': _config.pairingToken.trim(),
      if (trimmedSessionId != null && trimmedSessionId.isNotEmpty)
        'session_id': trimmedSessionId,
      if (trimmedCancelGroup != null && trimmedCancelGroup.isNotEmpty)
        'cancel_group': trimmedCancelGroup,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    };
    final uri = _buildGatewayUri(_config.baseUrl, '/api/v1/opencode/cancel');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ToolGatewayCancelResult(
          ok: false,
          accepted: false,
          activeRunsSignaled: 0,
          error: '工具网关错误：HTTP ${response.statusCode}',
        );
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        return const ToolGatewayCancelResult(
          ok: false,
          accepted: false,
          activeRunsSignaled: 0,
          error: '工具网关响应异常。',
        );
      }
      return ToolGatewayCancelResult(
        ok: data['ok'] == true,
        accepted: data['accepted'] == true,
        activeRunsSignaled:
            (data['active_runs_signaled'] as num?)?.toInt() ?? 0,
        error: data['ok'] == true ? null : data['error']?.toString(),
      );
    } catch (error) {
      return ToolGatewayCancelResult(
        ok: false,
        accepted: false,
        activeRunsSignaled: 0,
        error: '工具网关请求失败：$error',
      );
    }
  }

  Future<ToolGatewaySkillsCatalogResult> fetchInstalledSkills({
    String? workspace,
  }) async {
    await _ensureGatewayOperationAvailable(
      route: '/api/v1/opencode/skills/installed',
      feature: 'skills_catalog',
      label: 'skills 目录读取',
    );
    final data = await _postGatewayJson(
      path: '/api/v1/opencode/skills/installed',
      payload: _buildSkillPayload(workspace: workspace),
    );
    if (data['ok'] != true) {
      throw Exception(_gatewayMessageFromBody(data, '读取已安装 skills 失败。'));
    }
    return ToolGatewaySkillsCatalogResult.fromJson(data);
  }

  Future<ToolGatewaySkillsPreviewResult> previewSkillsImport({
    required ToolGatewaySkillImportSource source,
    bool overwrite = false,
    int limit = 2000,
    String? workspace,
  }) async {
    await _ensureGatewayOperationAvailable(
      route: '/api/v1/opencode/skills/preview',
      feature: 'skills_preview',
      label: 'skills 预览',
    );
    final data = await _postGatewayJson(
      path: '/api/v1/opencode/skills/preview',
      payload: _buildSkillImportPayload(
        source: source,
        overwrite: overwrite,
        limit: limit,
        workspace: workspace,
      ),
    );
    if (data['ok'] != true) {
      throw Exception(_gatewayMessageFromBody(data, 'skills 预览失败。'));
    }
    return ToolGatewaySkillsPreviewResult.fromJson(data);
  }

  Future<ToolGatewaySkillsInstallResult> installSkills({
    required ToolGatewaySkillImportSource source,
    bool overwrite = false,
    int limit = 2000,
    String? workspace,
  }) async {
    await _ensureGatewayOperationAvailable(
      route: '/api/v1/opencode/skills/install',
      feature: 'skills_install',
      label: 'skills 安装',
    );
    final data = await _postGatewayJson(
      path: '/api/v1/opencode/skills/install',
      payload: _buildSkillImportPayload(
        source: source,
        overwrite: overwrite,
        limit: limit,
        workspace: workspace,
      ),
    );
    if (data['ok'] != true) {
      throw Exception(_gatewayMessageFromBody(data, 'skills 安装失败。'));
    }
    return ToolGatewaySkillsInstallResult.fromJson(data);
  }

  Future<String> dispatch(ToolIntent intent) async {
    final error = _gatewayConfigError();
    if (error != null) {
      return error;
    }
    switch (intent.action) {
      case ToolAction.code:
      case ToolAction.search:
      case ToolAction.crawl:
      case ToolAction.analyze:
      case ToolAction.summarize:
        return _dispatchViaOpenCode(intent);
      case ToolAction.imageGen:
      case ToolAction.imageAnalyze:
        return '该工具类型尚未接入网关。';
    }
  }

  Future<String> _dispatchViaOpenCode(ToolIntent intent) async {
    final probe = await probeCapabilities();
    if (!probe.ok) {
      return probe.error ?? '工具网关能力探测失败。';
    }
    if (!probe.supportsRun) {
      return '当前工具网关未暴露 `/api/v1/opencode/run`。';
    }
    final sessionId = intent.sessionId?.trim().isNotEmpty == true
        ? intent.sessionId!
        : 'default';
    final payload = <String, dynamic>{
      'pairing_token': _config.pairingToken.trim(),
      'session_id': sessionId,
      'message': _buildMessage(intent),
      // Run inside the per-session workspace sandbox. We default to scratch and
      // further scope search/crawl/analyze/summarize to a per-trace subdir so
      // tools can safely write JSON artifacts without polluting other runs.
      'cwd': _deriveCwd(intent),
    };
    if (intent.traceId != null && intent.traceId!.trim().isNotEmpty) {
      payload['trace_id'] = intent.traceId!.trim();
    }
    if (intent.cancelGroup != null && intent.cancelGroup!.trim().isNotEmpty) {
      payload['cancel_group'] = intent.cancelGroup!.trim();
    }
    payload['interruptible'] = intent.interruptible;
    final uri = _buildGatewayUri(_config.baseUrl, '/api/v1/opencode/run');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return '工具网关错误：HTTP ${response.statusCode}';
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        return '工具网关响应异常。';
      }
      if (data['ok'] != true) {
        final error = data['stderr']?.toString().trim();
        return error == null || error.isEmpty ? '工具执行失败。' : '工具执行失败：$error';
      }
      final stdout = data['stdout']?.toString().trim() ?? '';
      final stderr = data['stderr']?.toString().trim() ?? '';
      if (stdout.isNotEmpty) {
        return stdout;
      }
      if (stderr.isNotEmpty) {
        return stderr;
      }
      return '工具执行完成。';
    } catch (error) {
      return '工具网关请求失败：$error';
    }
  }

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

  ToolGatewayProbeResult _cacheProbe(ToolGatewayProbeResult result) {
    _probeCache = result;
    return result;
  }

  Future<void> _ensureGatewayOperationAvailable({
    required String route,
    required String label,
    String? feature,
  }) async {
    final probe = await probeCapabilities();
    if (!probe.ok) {
      throw Exception(probe.error ?? '工具网关能力探测失败。');
    }
    if (probe.routes.contains(route)) {
      return;
    }
    if (feature != null && probe.supportsFeature(feature)) {
      return;
    }
    throw Exception('当前工具网关未暴露 `$route`，无法执行$label。');
  }

  Future<Map<String, dynamic>> _postGatewayJson({
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    final error = _gatewayConfigError();
    if (error != null) {
      throw Exception(error);
    }
    final uri = _buildGatewayUri(_config.baseUrl, path);
    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
      final data = _tryDecodeJsonMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _gatewayMessageFromBody(data, '工具网关错误：HTTP ${response.statusCode}'),
        );
      }
      if (data == null) {
        throw Exception('工具网关响应异常。');
      }
      return data;
    } on TimeoutException {
      throw Exception('工具网关请求超时。');
    } on Exception {
      rethrow;
    } catch (error) {
      throw Exception('工具网关请求失败：$error');
    }
  }

  Map<String, dynamic>? _tryDecodeJsonMap(String body) {
    try {
      final data = jsonDecode(body);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  String _gatewayMessageFromBody(Map<String, dynamic>? data, String fallback) {
    final message = data?['error']?.toString().trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    final errors = (data?['errors'] as List<dynamic>? ?? const <dynamic>[])
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    if (errors.isNotEmpty) {
      return errors.first;
    }
    return fallback;
  }

  Map<String, dynamic> _buildSkillPayload({String? workspace}) {
    return <String, dynamic>{
      'pairing_token': _config.pairingToken.trim(),
      if (workspace != null && workspace.trim().isNotEmpty)
        'workspace': workspace.trim(),
    };
  }

  Map<String, dynamic> _buildSkillImportPayload({
    required ToolGatewaySkillImportSource source,
    required bool overwrite,
    required int limit,
    String? workspace,
  }) {
    return <String, dynamic>{
      ..._buildSkillPayload(workspace: workspace),
      'overwrite': overwrite,
      'limit': limit,
      'source': source.toJson(),
    };
  }

  String? _gatewayConfigError() {
    if (!_config.enabled) {
      return '工具网关未启用。';
    }
    if (_config.baseUrl.trim().isEmpty) {
      return '工具网关地址未配置。';
    }
    if (_config.pairingToken.trim().isEmpty) {
      return '工具网关 pairing token 未配置。';
    }
    return null;
  }

  String _buildMessage(ToolIntent intent) {
    final primary = intent.query?.trim();
    final isDeepResearch = _isDeepResearchRouting(intent.routing);
    if (primary != null && primary.isNotEmpty) {
      switch (intent.action) {
        case ToolAction.search:
          if (isDeepResearch) {
            return '''
You are running as a tool for a Deep Research agent.

Task: Use web search to find reliable, up-to-date sources for:
$primary

Hard rules:
- Do NOT output [SPLIT].
- Do NOT use Markdown code fences (no ```).
- Prefer primary/official sources and reputable outlets.
- If you cannot verify something, say "unverified" instead of guessing.

Return (plain text):
1) Key facts (succinct)
2) Sources list (each with URL + title + publication date if available)
3) For each source, include a 1-2 sentence excerpt/claim summary that supports a key fact
'''
                .trim();
          }
          return 'Use web search to find reliable, up-to-date sources for:\n$primary\n\nReturn:\n- key facts\n- source links (URLs)\n- publication dates when available';
        case ToolAction.crawl:
          if (isDeepResearch) {
            return '''
You are running as a tool for a Deep Research agent.

Task: Fetch and extract the main content from this URL:
$primary

Hard rules:
- Do NOT output [SPLIT].
- Do NOT use Markdown code fences (no ```).

Return (plain text):
- title
- publication date (if available)
- main text (cleaned)
- key images (URLs + alt text + width/height/bytes if available; prefer content images, avoid icons/logos)
'''
                .trim();
          }
          return 'Fetch and extract the main content from this URL:\n$primary\n\nReturn:\n- title\n- main text\n- key images (URLs + alt)\n- publication date if available';
        case ToolAction.analyze:
          if (isDeepResearch) {
            return '''
Deep Research tool task: analyze the following content for evidence and extract verifiable claims.

Hard rules:
- Do NOT output [SPLIT].
- Do NOT use Markdown code fences (no ```).

Content:
$primary
'''
                .trim();
          }
          return 'Analyze the following content:\n$primary';
        case ToolAction.summarize:
          if (isDeepResearch) {
            return '''
Deep Research tool task: summarize the following content into evidence-carrying bullets.

Hard rules:
- Do NOT output [SPLIT].
- Do NOT use Markdown code fences (no ```).

Content:
$primary
'''
                .trim();
          }
          return 'Summarize the following content:\n$primary';
        case ToolAction.code:
        case ToolAction.imageGen:
        case ToolAction.imageAnalyze:
          return primary;
      }
    }
    final fallback = intent.context?.trim();
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    return 'Run tool action: ${intent.action.name}.';
  }
}
