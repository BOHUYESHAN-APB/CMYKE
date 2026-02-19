import 'dart:convert';

import 'package:http/http.dart' as http;

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

class ToolRouter {
  ToolRouter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  ToolGatewayConfig _config = ToolGatewayConfig.disabled;

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
  }

  Future<void> dispose() async {
    _client.close();
  }

  Future<String> dispatch(ToolIntent intent) async {
    if (!_config.enabled) {
      return '工具网关未启用。';
    }
    if (_config.baseUrl.trim().isEmpty) {
      return '工具网关地址未配置。';
    }
    if (_config.pairingToken.trim().isEmpty) {
      return '工具网关 pairing token 未配置。';
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
    final sessionId = intent.sessionId?.trim().isNotEmpty == true
        ? intent.sessionId!
        : 'default';
    final payload = <String, dynamic>{
      'pairing_token': _config.pairingToken.trim(),
      'session_id': sessionId,
      'message': _buildMessage(intent),
      // Run at the session workspace root. OpenCode config/skills are injected by
      // the gateway via OPENCODE_CONFIG/OPENCODE_CONFIG_DIR under `workspace/_shared/opencode/`.
      'cwd': '.',
    };
    if (intent.traceId != null && intent.traceId!.trim().isNotEmpty) {
      payload['trace_id'] = intent.traceId!.trim();
    }
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
