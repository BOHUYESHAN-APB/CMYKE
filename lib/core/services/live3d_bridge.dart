import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/expression_event.dart';
import '../models/lipsync_frame.dart';
import '../models/stage_action.dart';
import '../models/vrm_mapping.dart';
import 'event_bus.dart';

class Live3DDebugState extends ChangeNotifier {
  Map<String, dynamic>? _vrmaCatalog;
  String? _currentMotionKey;
  String? _currentMotionKind;
  String? _currentMotionRaw;
  final List<String> _motionHistory = <String>[];

  Map<String, dynamic>? get vrmaCatalog => _vrmaCatalog;
  String? get currentMotionKey => _currentMotionKey;
  String? get currentMotionKind => _currentMotionKind;
  String? get currentMotionRaw => _currentMotionRaw;
  List<String> get motionHistory => List.unmodifiable(_motionHistory);

  void setVrmaCatalog(Map<String, dynamic>? catalog) {
    _vrmaCatalog = catalog;
    notifyListeners();
  }

  void ingestViewerMessage(String type, Object? msg) {
    if (type != 'info') return;
    if (msg is! String) return;
    final raw = msg.trim();
    if (raw.isEmpty) return;

    const vrmaPrefix = 'motion(vrma): ';
    const procPrefix = 'motion(procedural): ';

    if (raw == 'motion: Idle') {
      _setCurrentMotion(kind: 'idle', key: 'idle_loop', raw: raw);
      return;
    }
    if (raw.startsWith(vrmaPrefix)) {
      _setCurrentMotion(
        kind: 'vrma',
        key: raw.substring(vrmaPrefix.length).trim(),
        raw: raw,
      );
      return;
    }
    if (raw.startsWith(procPrefix)) {
      _setCurrentMotion(
        kind: 'procedural',
        key: raw.substring(procPrefix.length).trim(),
        raw: raw,
      );
      return;
    }
    if (raw.startsWith('motion: unavailable')) {
      final start = raw.indexOf('(');
      final end = raw.lastIndexOf(')');
      final key = (start >= 0 && end > start)
          ? raw.substring(start + 1, end).trim()
          : raw;
      _setCurrentMotion(kind: 'unavailable', key: key, raw: raw);
      return;
    }
  }

  void _setCurrentMotion({
    required String kind,
    required String key,
    required String raw,
  }) {
    if (key.isEmpty) return;
    final changed =
        _currentMotionKey != key || _currentMotionKind != kind || _currentMotionRaw != raw;
    if (!changed) return;
    _currentMotionKey = key;
    _currentMotionKind = kind;
    _currentMotionRaw = raw;
    _motionHistory.insert(0, raw);
    if (_motionHistory.length > 30) {
      _motionHistory.removeRange(30, _motionHistory.length);
    }
    notifyListeners();
  }
}

/// Bridge for Live3D rendering surface (VRM) to receive expression/stage actions
/// and lip-sync frames. The actual rendering is expected to live in a
/// platform view or WebView; this class is a placeholder for future binding.
class Live3DBridge {
  Live3DBridge(RuntimeEventBus bus, {VrmConfig config = const VrmConfig()})
      : _config = config {
    _expressionSub = bus.expressions.listen(onExpression);
    _stageSub = bus.stageActions.listen(onStageAction);
    _lipSub = bus.lipSyncFrames.listen(onLipSync);
  }

  final Live3DDebugState debug = Live3DDebugState();
  VrmConfig _config;
  String? currentModelPath;
  final _modelPathController = StreamController<String?>.broadcast();
  Future<void> Function(String script)? _jsInvoker;
  String _controlMode = 'basic';
  bool _talking = false;
  bool _cursorFollowEnabled = false;
  bool _petMode = false;
  late final StreamSubscription<ExpressionEvent> _expressionSub;
  late final StreamSubscription<StageAction> _stageSub;
  late final StreamSubscription<LipSyncFrame> _lipSub;

  Stream<String?> get modelPaths => _modelPathController.stream;
  bool get isTalking => _talking;
  bool get cursorFollowEnabled => _cursorFollowEnabled;
  bool get petMode => _petMode;

  /// Swap VRM mapping at runtime (e.g., user loads a different model).
  void updateConfig(VrmConfig config) {
    _config = config;
  }

  void attachJsInvoker(Future<void> Function(String script) invoker) {
    _jsInvoker = invoker;
    // Force basic mode; external pose driving is disabled.
    setControlMode('basic');
    setTalking(_talking);
    setCursorFollow(_cursorFollowEnabled);
    setPetMode(_petMode);
  }

  void detachJsInvoker() {
    _jsInvoker = null;
  }

  /// Load a VRM model (path points to a local file). This is a placeholder and
  /// should call into the platform renderer (WebView/Unity/etc.) in the future.
  Future<void> loadModel(String path) async {
    currentModelPath = path;
    _modelPathController.add(path);
    // TODO: forward to platform channel / JS bridge to actually load VRM.
  }

  void onExpression(ExpressionEvent event) {
    final clip = _config.expressionClips[event.emotion];
    if (clip == null) return;
    _runJs('window.setExpression(${jsonEncode(clip)}, ${event.intensity ?? 1.0});');
  }

  void onStageAction(StageAction action) {
    final motion = _config.motionClips[action.motion];
    if (motion == null) return;
    _runJs('window.setMotion(${jsonEncode(motion)});');
  }

  void onLipSync(LipSyncFrame frame) {
    // Map AEIOU weights to VRM viseme blendshapes.
    final payload = <String, double>{};
    for (final entry in frame.toMap().entries) {
      final clip = _config.visemeClips[entry.key];
      if (clip != null) {
        payload[clip] = entry.value;
      }
    }
    if (payload.isEmpty) return;
    _runJs('window.setVisemeWeights(${jsonEncode(payload)});');
  }

  /// Switch control mode: 'basic' | 'advanced'. Advanced is driven via applyPose.
  void setControlMode(String mode) {
    _controlMode = 'basic';
    _runJs('window.setControlMode(${jsonEncode(_controlMode)});');
  }

  void setTalking(bool isTalking) {
    _talking = isTalking;
    _runJs('window.setTalking(${isTalking ? 'true' : 'false'});');
  }

  void setCursorFollow(bool enabled) {
    _cursorFollowEnabled = enabled;
    _runJs(
      'window.setCursorFollow && window.setCursorFollow(${enabled ? 'true' : 'false'});',
    );
  }

  void setPetMode(bool enabled) {
    _petMode = enabled;
    _runJs(
      'window.setPetMode && window.setPetMode(${enabled ? 'true' : 'false'});',
    );
  }

  /// Play a named motion (VRMA catalog id / file name / url / procedural id).
  /// This is primarily for debugging and manual triggering from the app.
  void playMotion(String motion) {
    final trimmed = motion.trim();
    if (trimmed.isEmpty) return;
    _runJs('window.setMotion && window.setMotion(${jsonEncode(trimmed)});');
  }

  void stopMotion() {
    _runJs("window.setMotion && window.setMotion('idle');");
  }

  /// Send a pose payload (bones/expression/viseme) to viewer in advanced mode.
  Future<void> sendPose(Map<String, dynamic> pose) async {
    // External pose driving is disabled in basic-only mode.
    return;
  }

  Future<void> dispose() async {
    await Future.wait([
      _expressionSub.cancel(),
      _stageSub.cancel(),
      _lipSub.cancel(),
      _modelPathController.close(),
    ]);
    debug.dispose();
  }

  Future<void> _runJs(String script) async {
    final invoker = _jsInvoker;
    if (invoker == null) return;
    try {
      await invoker(script);
    } catch (_) {
      // swallow for now; render surface might not be ready.
    }
  }
}
