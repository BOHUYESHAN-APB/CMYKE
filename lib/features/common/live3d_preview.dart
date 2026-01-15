import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/services/runtime_hub.dart';

/// Minimal Live3D preview using WebView:
/// - Windows: webview_windows (Edge WebView2)
/// - Other: fallback placeholder (todo: platform view)
class Live3DPreview extends StatefulWidget {
  const Live3DPreview({
    super.key,
    this.height = 180,
    this.compact = false,
  });

  final double height;
  final bool compact;

  @override
  State<Live3DPreview> createState() => _Live3DPreviewState();
}

class _Live3DPreviewState extends State<Live3DPreview> {
  final _hub = RuntimeHub.instance;
  WebviewController? _winController;
  StreamSubscription<String?>? _modelSub;
  String? _status;
  String? _path;
  bool _winReady = false;
  bool _winInitFailed = false;
  bool _viewerReady = false;
  String? _bundlePath;
  String? _pendingModelPath;
  String? _lastRequestedPath;
  String? _lastLoadedPath;
  static HttpServer? _staticServer;
  static String? _staticBaseUrl;

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

  @override
  void initState() {
    super.initState();
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
      'assets/live3d/animations/idle_loop.vrma':
          'assets/vrm_core/animations/idle_loop.vrma',
    };
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
    _bundlePath = bundleDir.path;
    _debug('Bundle prepared at $_bundlePath');
    await _ensureStaticServer(bundleDir.path);
  }

  Future<List<int>?> _loadAssetBytes(String asset) async {
    try {
      final bytes = await rootBundle.load(asset);
      return bytes.buffer.asUint8List();
    } catch (_) {
      // Fallback to reading from project dir when asset bundle is missing (e.g., stale build).
      final file = File(p.join(Directory.current.path, asset.replaceAll('/', Platform.pathSeparator)));
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
          final data = jsonDecode(message) as Map<String, dynamic>;
          final type = data['type'] ?? 'msg';
          final msg = data['msg'] ?? '';
          if (type == 'info' && msg == 'viewer:ready') {
            _viewerReady = true;
            unawaited(_maybeLoadPending());
          }
          if (type == 'info' && msg == 'VRM loaded') {
            _lastLoadedPath = _lastRequestedPath;
          }
          _setStatus('viewer[$type]: $msg');
          return;
        } catch (_) {
          // Fallback: treat as plain text.
        }
        _setStatus('viewer: $message');
      });
      await controller.loadUrl('${baseUrl}viewer.html');
      _hub.live3dBridge.attachJsInvoker(
        (script) => controller.executeScript(script),
      );
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
    final bg = widget.compact ? const Color(0xFFF6F2EA) : const Color(0xFFF2EEE6);
    final border =
        widget.compact ? const Color(0xFFE8DFD3) : const Color(0xFFE4DDD2);
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

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: viewer,
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(12),
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
                            color: const Color(0xFF6B6F7A),
                          ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x1F1B9B7B),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                fileName == null ? '未加载模型' : '已加载',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF1B9B7B),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
