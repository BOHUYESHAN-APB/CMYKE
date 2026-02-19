import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/models/app_settings.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/runtime_hub.dart';
import '../../ui/theme/cmyke_chrome.dart';
import '../../ui/widgets/frosted_surface.dart';
import '../../ui/windows/win_window.dart';

/// Minimal Live3D preview using WebView:
/// - Windows: webview_windows (Edge WebView2)
/// - Other: fallback placeholder (todo: platform view)
class Live3DPreview extends StatefulWidget {
  const Live3DPreview({
    super.key,
    this.height = 180,
    this.compact = false,
    this.debug = false,
    this.transparentBackground = false,
    this.petMode = false,
    this.settingsRepository,
    this.speechText,
  });

  final double height;
  final bool compact;
  final bool debug;
  final bool transparentBackground;
  final bool petMode;
  final SettingsRepository? settingsRepository;
  final String? speechText;

  @override
  State<Live3DPreview> createState() => _Live3DPreviewState();
}

class _Live3DPreviewState extends State<Live3DPreview> {
  final _hub = RuntimeHub.instance;
  final bool _isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
  WebviewController? _winController;
  StreamSubscription<String?>? _modelSub;
  String? _status;
  String? _path;
  bool _winReady = false;
  bool _winInitFailed = false;
  bool _viewerReady = false;
  String? _bundlePath;
  List<String> _availableVrmaUrls = const [];
  String? _pendingModelPath;
  String? _lastRequestedPath;
  String? _lastLoadedPath;
  static HttpServer? _staticServer;
  static String? _staticBaseUrl;
  static bool _startupGreetingPlayed = false;
  Map<String, dynamic>? _vrmaCatalog;
  bool _autoEnabledCursorFollow = false;
  bool _petMode = false;
  String? _renderQuality;
  int? _fpsCap;

  void _handleHoverEnter() {
    if (!mounted) return;
    if (_petMode) {
      return;
    }
    final bridge = _hub.live3dBridge;
    if (!bridge.cursorFollowEnabled) {
      _autoEnabledCursorFollow = true;
      bridge.setCursorFollow(true);
    } else {
      _autoEnabledCursorFollow = false;
    }
  }

  void _handleHoverExit() {
    if (!mounted) return;
    if (_petMode) {
      return;
    }
    if (_autoEnabledCursorFollow) {
      _autoEnabledCursorFollow = false;
      _hub.live3dBridge.setCursorFollow(false);
    }
  }

  void _setStatus(String msg) {
    if (!mounted) return;
    debugPrint('[Live3D] $msg');
    setState(() {
      _status = msg;
    });
  }

  void _debug(String msg) {
    debugPrint('[Live3D] $msg');
  }

  void _maybePlayStartupGreeting() {
    if (_startupGreetingPlayed) {
      return;
    }
    _startupGreetingPlayed = true;
    // Give the model a brief moment to settle on its idle loop before
    // triggering the first gesture (prevents initial snapping).
    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _hub.live3dBridge.playMotion('gesture_greeting');
    });
  }

  @override
  void initState() {
    super.initState();
    if (_isFlutterTest) {
      _winInitFailed = true;
      _setStatus('Live3D 在测试环境中禁用');
      return;
    }
    _syncPetModeFlag(force: true);
    _syncRenderSettings(force: true);
    widget.settingsRepository?.addListener(_handleSettingsChanged);
    _prepareBundle().then((_) {
      if (!mounted) return;
      if (Platform.isWindows) {
        _initWindows();
      } else {
        _setStatus('暂未支持该平台的渲染');
      }
    });
    _modelSub = _hub.live3dBridge.modelPaths.listen(_loadModel);
    _loadModel(_hub.live3dBridge.currentModelPath);
  }

  @override
  void didUpdateWidget(covariant Live3DPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settingsRepository != widget.settingsRepository) {
      oldWidget.settingsRepository?.removeListener(_handleSettingsChanged);
      widget.settingsRepository?.addListener(_handleSettingsChanged);
      _syncPetModeFlag(force: true);
    }
  }

  void _handleSettingsChanged() {
    _syncPetModeFlag();
    _syncRenderSettings();
  }

  void _syncPetModeFlag({bool force = false}) {
    final next = widget.settingsRepository?.settings.petMode == true;
    if (!force && next == _petMode) {
      return;
    }
    _petMode = next;
    _hub.live3dBridge.setPetMode(_petMode);
  }

  int _fpsCapValue(Live3dFpsCap cap) {
    switch (cap) {
      case Live3dFpsCap.fps30:
        return 30;
      case Live3dFpsCap.fps60:
        return 60;
      case Live3dFpsCap.unlimited:
        return 0;
    }
  }

  void _syncRenderSettings({bool force = false}) {
    final settings = widget.settingsRepository?.settings;
    if (settings == null) return;
    final nextQuality = settings.live3dRenderQuality.name;
    final nextFps = _fpsCapValue(settings.live3dFpsCap);
    if (!force && nextQuality == _renderQuality && nextFps == _fpsCap) {
      return;
    }
    _renderQuality = nextQuality;
    _fpsCap = nextFps;
    _hub.live3dBridge.setRenderQuality(nextQuality);
    _hub.live3dBridge.setFpsCap(nextFps);
  }

  Future<void> _prepareBundle() async {
    final dir = await getTemporaryDirectory();
    final bundleDir = Directory(p.join(dir.path, 'cmyke_live3d'));
    if (!await bundleDir.exists()) {
      await bundleDir.create(recursive: true);
    }
    final assets = <String, String>{
      'assets/live3d/viewer.html': 'viewer.html',
      'assets/live3d/vendor/three.module.js': 'assets/vrm_core/three.module.js',
      'assets/live3d/vendor/OrbitControls.js':
          'assets/vrm_core/jsm/controls/OrbitControls.js',
      'assets/live3d/vendor/GLTFLoader.js':
          'assets/vrm_core/jsm/loaders/GLTFLoader.js',
      'assets/live3d/vendor/three-vrm-animation.module.js':
          'assets/vrm_core/three-vrm-animation.module.js',
      'assets/live3d/vendor/utils/BufferGeometryUtils.js':
          'assets/vrm_core/jsm/utils/BufferGeometryUtils.js',
      'assets/live3d/vendor/three-vrm.module.js':
          'assets/vrm_core/three-vrm.module.js',
      'assets/live3d/vendor/es-module-shims.js':
          'assets/vrm_core/es-module-shims.js',
    };

    // Copy all .vrma clips so we can rely on authored animations instead of
    // hand-written bone rotations for most motions.
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final decoded = jsonDecode(manifest);
      if (decoded is Map<String, dynamic>) {
        final vrmas =
            decoded.keys
                .where(
                  (k) =>
                      k.startsWith('assets/live3d/animations/') &&
                      k.endsWith('.vrma'),
                )
                .toList()
              ..sort();
        for (final asset in vrmas) {
          final rel = asset.substring('assets/live3d/'.length);
          assets[asset] = 'assets/vrm_core/$rel';
        }
      }
    } catch (_) {
      // Ignore and fall back to the hardcoded idle loop below.
    }
    assets.putIfAbsent(
      'assets/live3d/animations/idle_loop.vrma',
      () => 'assets/vrm_core/animations/idle_loop.vrma',
    );
    for (final entry in assets.entries) {
      final data = await _loadAssetBytes(entry.key);
      if (data == null) {
        _winInitFailed = true;
        _setStatus('资源缺失: ${entry.key}');
        return;
      }
      final outPath = p.join(bundleDir.path, entry.value);
      await Directory(p.dirname(outPath)).create(recursive: true);
      await File(outPath).writeAsBytes(data, flush: true);
    }
    _availableVrmaUrls = await _scanVrmaUrls(bundleDir.path);
    _vrmaCatalog = await _loadVrmaCatalog(_availableVrmaUrls);
    _hub.live3dBridge.debug.setVrmaCatalog(_vrmaCatalog);
    _bundlePath = bundleDir.path;
    _debug('Bundle prepared at $_bundlePath');
    await _ensureStaticServer(bundleDir.path);
  }

  List<String> _extractAutoMotionKeys() {
    final catalog = _vrmaCatalog;
    if (catalog == null) return const [];
    final motions = catalog['motions'];
    if (motions is! List) return const [];
    final result = <String>[];
    final seen = <String>{};
    for (final entry in motions) {
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      final auto = m['auto'];
      if (auto is! Map) continue;
      final hasAuto =
          auto['talk'] == true || auto['idle'] == true || auto['hover'] == true;
      if (!hasAuto) continue;
      final id = (m['id'] ?? '').toString().trim();
      final url = (m['url'] ?? '').toString().trim();
      final key = id.isNotEmpty ? id : url;
      if (key.isEmpty) continue;
      final normalized = key.toLowerCase();
      if (!seen.add(normalized)) continue;
      result.add(key);
    }
    return result;
  }

  Future<void> _syncAutoMotionPolicy() async {
    final controller = _winController;
    if (!mounted || !_viewerReady || controller == null) {
      return;
    }
    final whitelist = _extractAutoMotionKeys();
    final js =
        'window.setAutoMotionWhitelist && window.setAutoMotionWhitelist(${jsonEncode(whitelist)});';
    try {
      await controller.executeScript(js);
    } catch (_) {
      // Ignore; viewer might not be ready yet.
    }
  }

  Future<Map<String, dynamic>?> _loadVrmaCatalog(
    List<String> availableUrls,
  ) async {
    Map<String, dynamic>? decoded;
    try {
      final raw = await rootBundle.loadString(
        'assets/live3d/animations/catalog.json',
      );
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        decoded = data;
      }
    } catch (_) {
      decoded = null;
    }

    final available = availableUrls.toSet();
    final motions = <Map<String, dynamic>>[];
    final seen = <String>{};

    String canonicalizeUrl(String url) {
      // Ensure the URL matches the runtime-scanned list which uses encoded path
      // segments (e.g. spaces -> %20, unicode -> %E3...).
      final trimmed = url.trim();
      if (!trimmed.startsWith('/')) return trimmed;
      String safeDecode(String segment) {
        if (!segment.contains('%')) return segment;
        try {
          return Uri.decodeComponent(segment);
        } catch (_) {
          // Keep best-effort: invalid percent sequences should not crash the app.
          return segment;
        }
      }

      final parts = trimmed
          .split('/')
          .where((e) => e.isNotEmpty)
          .map(safeDecode)
          .map(Uri.encodeComponent)
          .join('/');
      return '/$parts';
    }

    void addMotion(Map<String, dynamic> motion) {
      final url = motion['url'];
      if (url is! String || url.isEmpty) return;
      var resolvedUrl = url.trim();
      if (resolvedUrl.isEmpty) return;
      if (!available.contains(resolvedUrl)) {
        final encoded = canonicalizeUrl(resolvedUrl);
        if (!available.contains(encoded)) return;
        resolvedUrl = encoded;
      }
      final id = motion['id'];
      motion['url'] = resolvedUrl;
      final key = (id is String && id.trim().isNotEmpty)
          ? id.trim()
          : resolvedUrl;
      if (seen.contains(key)) return;
      seen.add(key);
      motions.add(motion);
    }

    if (decoded != null) {
      final list = decoded['motions'];
      if (list is List) {
        for (final entry in list) {
          if (entry is Map) {
            addMotion(Map<String, dynamic>.from(entry));
          }
        }
      }
    }

    const idleUrl = '/assets/vrm_core/animations/idle_loop.vrma';
    if (available.contains(idleUrl) &&
        !motions.any((m) => m['url'] == idleUrl || m['id'] == 'idle_loop')) {
      motions.insert(0, {
        'id': 'idle_loop',
        'name': 'Idle（呼吸循环）',
        'type': 'idle',
        'url': idleUrl,
        'auto': {'idle': true},
      });
    }

    if (motions.isEmpty && availableUrls.isNotEmpty) {
      motions.addAll(
        availableUrls.map(
          (url) => {
            'id': url == idleUrl ? 'idle_loop' : url,
            'name': url.split('/').last,
            'type': url == idleUrl ? 'idle' : 'unknown',
            'url': url,
            'auto': {'idle': url == idleUrl},
          },
        ),
      );
    }

    if (motions.isEmpty) {
      return null;
    }

    return {'version': 1, 'motions': motions};
  }

  Future<List<String>> _scanVrmaUrls(String bundleRoot) async {
    final root = Directory(bundleRoot);
    final animRoot = Directory(
      p.join(bundleRoot, 'assets', 'vrm_core', 'animations'),
    );
    if (!await animRoot.exists()) {
      return const [];
    }
    final urls = <String>[];
    await for (final entity in animRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.vrma') continue;
      final rel = p.relative(entity.path, from: root.path);
      final parts = rel
          .split(Platform.pathSeparator)
          .where((e) => e.isNotEmpty);
      final encoded = parts.map(Uri.encodeComponent).join('/');
      urls.add('/$encoded');
    }
    urls.sort();
    return urls;
  }

  Future<void> _syncVrmaLibrary() async {
    final controller = _winController;
    if (!mounted || !_viewerReady || controller == null) {
      return;
    }
    if (_vrmaCatalog != null) {
      final js =
          'window.setVrmaCatalog && window.setVrmaCatalog(${jsonEncode(_vrmaCatalog)});';
      try {
        await controller.executeScript(js);
      } catch (_) {
        // Ignore; viewer might not be ready yet.
      }
      await _syncAutoMotionPolicy();
      return;
    }
    if (_availableVrmaUrls.isEmpty) {
      return;
    }
    final js =
        'window.setAvailableVrmaAnimations && window.setAvailableVrmaAnimations(${jsonEncode(_availableVrmaUrls)});';
    try {
      await controller.executeScript(js);
    } catch (_) {
      // Ignore; viewer might not be ready yet.
    }
  }

  Future<List<int>?> _loadAssetBytes(String asset) async {
    try {
      final bytes = await rootBundle.load(asset);
      return bytes.buffer.asUint8List();
    } catch (_) {
      // Fallback to reading from project dir when asset bundle is missing (e.g., stale build).
      final file = File(
        p.join(
          Directory.current.path,
          asset.replaceAll('/', Platform.pathSeparator),
        ),
      );
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    }
    return null;
  }

  Future<void> _ensureStaticServer(String folder) async {
    if (_staticServer != null && _staticBaseUrl != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _staticServer = server;
    final base = 'http://${server.address.address}:${server.port}/';
    _staticBaseUrl = base;
    _debug('Static server started at $base serving $folder');
    // basic static file handler
    Future(() async {
      await for (final req in server) {
        final relPath = req.uri.path == '/' ? '/viewer.html' : req.uri.path;
        final safePath = relPath.replaceAll('..', '');
        final filePath = p.join(folder, safePath.replaceFirst('/', ''));
        final file = File(filePath);
        if (!await file.exists()) {
          _debug('Static 404: $relPath -> $filePath');
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          continue;
        }
        final ext = p.extension(filePath).toLowerCase();
        req.response.headers.contentType = _contentTypeForExt(ext);
        req.response.headers.add('Access-Control-Allow-Origin', '*');
        req.response.headers.add('Cache-Control', 'no-store');
        await req.response.addStream(file.openRead());
        await req.response.close();
      }
    });
  }

  ContentType _contentTypeForExt(String ext) {
    switch (ext) {
      case '.html':
        return ContentType.html;
      case '.js':
        return ContentType('application', 'javascript', charset: 'utf-8');
      case '.vrm':
        return ContentType('model', 'gltf-binary');
      case '.vrma':
        return ContentType('model', 'gltf-binary');
      default:
        return ContentType.binary;
    }
  }

  Future<void> _initWindows() async {
    final bundle = _bundlePath;
    final baseUrl = _staticBaseUrl;
    if (bundle == null) {
      _winInitFailed = true;
      _setStatus('WebView 初始化失败: bundle 不存在');
      return;
    }
    if (baseUrl == null) {
      _winInitFailed = true;
      _setStatus('WebView 初始化失败: 本地服务未启动');
      return;
    }
    final controller = WebviewController();
    try {
      await controller.initialize();
      await controller.setBackgroundColor(Colors.transparent);
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      // Listen to structured messages from the viewer for easier debugging.
      controller.webMessage.listen((message) {
        if (!mounted) return;
        try {
          final decoded = jsonDecode(message);
          if (decoded is! Map) {
            throw const FormatException('unexpected viewer payload');
          }
          final type = decoded['type']?.toString() ?? 'msg';
          final msg = decoded['msg'];
          if (type == 'pet' &&
              msg == 'drag' &&
              Platform.isWindows &&
              widget.petMode) {
            unawaited(WinWindow.startDragging());
            return;
          }
          _hub.live3dBridge.debug.ingestViewerMessage(type, msg);
          final msgText = msg is String ? msg : jsonEncode(msg);
          if (type == 'info' && msg == 'viewer:ready') {
            _viewerReady = true;
            unawaited(_maybeLoadPending());
            unawaited(_syncVrmaLibrary());
          }
          if (type == 'info' && msg == 'VRM loaded') {
            _lastLoadedPath = _lastRequestedPath;
            _maybePlayStartupGreeting();
          }
          _setStatus('viewer[$type]: $msgText');
          return;
        } catch (_) {
          // Fallback: treat as plain text.
        }
        _setStatus('viewer: $message');
      });
      final params = <String, String>{};
      if (widget.transparentBackground) {
        params['transparent'] = '1';
      }
      if (widget.petMode) {
        params['pet'] = '1';
      }
      final settings = widget.settingsRepository?.settings;
      if (settings != null) {
        params['quality'] = settings.live3dRenderQuality.name;
        params['fps'] = _fpsCapValue(settings.live3dFpsCap).toString();
      }
      if (params.isNotEmpty) {
        final query = params.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');
        await controller.loadUrl('${baseUrl}viewer.html?$query');
      } else {
        await controller.loadUrl('${baseUrl}viewer.html');
      }
      _hub.live3dBridge.attachJsInvoker(
        (script) => controller.executeScript(script),
      );
      _syncRenderSettings(force: true);
      setState(() {
        _winController = controller;
        _winReady = true;
        _winInitFailed = false;
        _status = 'WebView 已初始化';
      });
      _debug('WebView initialized, baseUrl=$baseUrl');
    } catch (e) {
      _winInitFailed = true;
      _setStatus('WebView 初始化失败: $e');
    }
  }

  @override
  void dispose() {
    _modelSub?.cancel();
    widget.settingsRepository?.removeListener(_handleSettingsChanged);
    _hub.live3dBridge.detachJsInvoker();
    super.dispose();
  }

  Future<void> _loadModel(String? path) async {
    if (!mounted) return;
    final normalizedPath = path == null ? '' : _normalizePath(path);
    setState(() {
      _path = normalizedPath;
    });
    if (normalizedPath.isEmpty) {
      _setStatus('未加载模型');
      return;
    }
    try {
      if (Platform.isWindows) {
        if (_winController == null ||
            !_winReady ||
            _bundlePath == null ||
            _staticBaseUrl == null) {
          _pendingModelPath = normalizedPath;
          _setStatus('等待 WebView 初始化');
          return;
        }
        await _loadModelFromPath(normalizedPath);
      } else {
        _setStatus('当前平台尚未实现渲染');
        return;
      }
      _setStatus('已加载模型');
    } catch (e) {
      _setStatus('加载失败: $e');
    }
  }

  Future<void> _loadModelFromPath(String path) async {
    final bundle = _bundlePath;
    final baseUrl = _staticBaseUrl;
    final controller = _winController;
    if (bundle == null || baseUrl == null || controller == null) {
      _setStatus('加载失败: 本地服务未就绪');
      return;
    }
    _lastRequestedPath = path;
    final modelsDir = Directory(p.join(bundle, 'assets/vrm_model'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    final fileName = p.basename(path);
    final destPath = p.join(modelsDir.path, fileName);
    final destFile = File(destPath);
    if (!await destFile.exists()) {
      try {
        await File(path).copy(destPath);
        _debug('Copied VRM to $destPath');
      } catch (e) {
        _setStatus('复制模型失败: $e');
        return;
      }
    }
    final url = '${baseUrl}assets/vrm_model/${Uri.encodeComponent(fileName)}';
    final js = 'window.loadVrmFromUrl(${jsonEncode(url)});';
    _debug('Loading VRM via $url');
    try {
      await controller.executeScript(js);
    } catch (e) {
      _pendingModelPath = path;
      _setStatus('等待 WebView 加载: $e');
      return;
    }
  }

  String _normalizePath(String path) {
    // 去除首尾引号以及多余空白，防止用户输入包含 "C:\\path\\file.vrm"
    var cleaned = path.trim();
    cleaned = cleaned.replaceAll(RegExp(r'^[\"“”]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[\"“”]+$'), '');
    return cleaned;
  }

  Future<void> _maybeLoadPending() async {
    if (!mounted || !_viewerReady) {
      return;
    }
    final candidate = _pendingModelPath ?? _path;
    if (candidate == null || candidate.isEmpty) {
      return;
    }
    final normalized = _normalizePath(candidate);
    if (_lastLoadedPath == normalized) {
      return;
    }
    if (_winController == null ||
        !_winReady ||
        _bundlePath == null ||
        _staticBaseUrl == null) {
      _pendingModelPath = normalized;
      return;
    }
    _pendingModelPath = null;
    await _loadModelFromPath(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final radius = widget.transparentBackground ? 0.0 : 16.0;
    final bg = widget.transparentBackground
        ? Colors.transparent
        : (widget.compact ? chrome.surface : chrome.surfaceElevated);
    final border = widget.transparentBackground
        ? Colors.transparent
        : chrome.separatorStrong;
    final fileName = (_path == null || _path!.isEmpty)
        ? null
        : _path!.split(RegExp(r'[\\/]')).last;

    Widget viewer;
    if (Platform.isWindows) {
      if (_winInitFailed) {
        viewer = Center(
          child: Text(
            _status ?? 'WebView 未初始化',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      } else if (_winController == null) {
        viewer = const Center(child: CircularProgressIndicator(strokeWidth: 2));
      } else {
        viewer = Stack(
          children: [
            Positioned.fill(
              child: Webview(
                _winController!,
                permissionRequested: (url, kind, isUserInitiated) =>
                    WebviewPermissionDecision.deny,
              ),
            ),
            if (widget.debug)
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  tooltip: '打开 DevTools',
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  onPressed: () => _winController?.openDevTools(),
                ),
              ),
          ],
        );
      }
    } else {
      viewer = Center(
        child: Text(
          '当前平台暂未启用 Live3D 渲染',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final content = Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: widget.transparentBackground ? null : Border.all(color: border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: viewer,
            ),
          ),
          if (widget.speechText != null &&
              widget.speechText!.trim().isNotEmpty)
            Positioned(
              top: 14,
              left: 12,
              right: 12,
              child: IgnorePointer(
                child: Center(
                  child: _SpeechBubble(
                    text: widget.speechText!.trim(),
                  ),
                ),
              ),
            ),
          if (widget.debug) ...[
            Positioned(
              left: 12,
              bottom: 12,
              child: FrostedSurface(
                blurSigma: chrome.blurSigma * 0.6,
                shadows: const [],
                highlight: false,
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName ?? '未加载 VRM',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_status != null)
                      Text(
                        _status!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: chrome.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 10,
              child: FrostedSurface(
                borderRadius: BorderRadius.circular(999),
                blurSigma: chrome.blurSigma * 0.55,
                shadows: const [],
                highlight: false,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Text(
                  fileName == null ? '未加载模型' : '已加载',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: chrome.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (!Platform.isWindows) {
      return content;
    }

    return MouseRegion(
      onEnter: (_) => _handleHoverEnter(),
      onExit: (_) => _handleHoverExit(),
      child: content,
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FrostedSurface(
          blurSigma: chrome.blurSigma * 0.8,
          shadows: const [],
          highlight: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Transform.rotate(
          angle: 0.785398, // 45deg
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: chrome.frostedTint,
              border: Border.all(color: chrome.frostedBorder),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }
}
