import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../repositories/settings_repository.dart';

class ToolGatewayBootstrapper {
  ToolGatewayBootstrapper({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Process? _sidecar;

  Future<void> dispose() async {
    _client.close();
    // Best-effort cleanup: do not hard-kill by default (gateway might be shared).
    _sidecar = null;
  }

  Future<void> ensureReady({
    required SettingsRepository settingsRepository,
    required bool allowAutoStartLocal,
    required bool allowAutoPairing,
  }) async {
    final settings = settingsRepository.settings;
    if (!settings.toolGatewayEnabled) return;

    final baseUrl = _normalizeBaseUrl(settings.toolGatewayBaseUrl);
    if (await _isHealthyGateway(baseUrl)) {
      if (allowAutoPairing && _isLoopbackBaseUrl(baseUrl)) {
        await _ensurePairingToken(settingsRepository, baseUrl);
      }
      return;
    }

    if (!allowAutoStartLocal) {
      return;
    }
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return;
    }

    final resolved = await _resolveBundledBackendExecutable();
    if (resolved == null) {
      return;
    }

    final port = _extractPort(baseUrl) ?? 4891;
    await _startSidecarIfNeeded(resolved, port: port);

    // Wait for it to come up.
    for (var i = 0; i < 12; i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (await _isHealthyGateway(baseUrl)) {
        if (allowAutoPairing && _isLoopbackBaseUrl(baseUrl)) {
          await _ensurePairingToken(settingsRepository, baseUrl);
        }
        return;
      }
    }
  }

  String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'http://127.0.0.1:4891';
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  int? _extractPort(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return null;
    final port = uri.hasPort ? uri.port : null;
    return port == 0 ? null : port;
  }

  bool _isLoopbackBaseUrl(String baseUrl) {
    try {
      final uri = Uri.parse(_normalizeBaseUrl(baseUrl));
      final host = uri.host.trim().toLowerCase();
      return host == '127.0.0.1' || host == 'localhost' || host == '::1';
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isHealthyGateway(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/health');
      final resp = await _client
          .get(uri)
          .timeout(const Duration(milliseconds: 900));
      if (resp.statusCode != 200) return false;
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) return false;
      return decoded['service']?.toString() == 'cmyke-backend';
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensurePairingToken(
    SettingsRepository settingsRepository,
    String baseUrl,
  ) async {
    final settings = settingsRepository.settings;
    if (settings.toolGatewayPairingToken.trim().isNotEmpty) {
      return;
    }
    try {
      final uri = Uri.parse('$baseUrl/api/v1/gateway/pairing/create');
      final payload = jsonEncode({
        'mode': 'desktop',
        'label': 'auto',
        'expires_in_sec': 60 * 60 * 24 * 365, // 1 year
      });
      final resp = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return;
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) return;
      final pairing = decoded['pairing'];
      if (pairing is! Map) return;
      final token = pairing['token']?.toString().trim() ?? '';
      if (token.isEmpty) return;
      await settingsRepository.updateSettings(
        settings.copyWith(toolGatewayPairingToken: token),
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<String?> _resolveBundledBackendExecutable() async {
    final appDir = p.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      if (Platform.isWindows) p.join(appDir, 'cmyke-backend.exe'),
      if (Platform.isWindows) p.join(appDir, 'backend', 'cmyke-backend.exe'),
      if (Platform.isWindows) p.join(appDir, 'server.exe'),
      if (!Platform.isWindows) p.join(appDir, 'cmyke-backend'),
      if (!Platform.isWindows) p.join(appDir, 'backend', 'cmyke-backend'),
    ];
    for (final path in candidates) {
      try {
        if (await File(path).exists()) {
          return path;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _startSidecarIfNeeded(
    String executable, {
    required int port,
  }) async {
    if (_sidecar != null) return;
    try {
      final workspaceRoot = await _resolveDocumentsWorkspaceRoot();
      _sidecar = await Process.start(
        executable,
        const [],
        runInShell: false,
        environment: {
          ...Platform.environment,
          'CMYKE_BACKEND_HOST': '127.0.0.1',
          'CMYKE_BACKEND_PORT': port.toString(),
          if (workspaceRoot != null) 'CMYKE_WORKSPACE_ROOT': workspaceRoot,
        },
      );
    } catch (_) {
      _sidecar = null;
    }
  }

  Future<String?> _resolveDocumentsWorkspaceRoot() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      return p.join(base.path, 'cmyke', 'workspace');
    } catch (_) {
      return null;
    }
  }
}

bool shouldAutoStartToolGateway(AppSettings settings) {
  // Keep it conservative: only auto-start when the user opted-in by enabling
  // the gateway in settings (first-run UX may enable it for desktop releases).
  return settings.toolGatewayEnabled;
}
