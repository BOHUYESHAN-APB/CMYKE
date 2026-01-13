import 'dart:convert';
import 'dart:async';

import '../models/expression_event.dart';
import '../models/lipsync_frame.dart';
import '../models/stage_action.dart';
import '../models/vrm_mapping.dart';
import 'event_bus.dart';

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

  VrmConfig _config;
  String? currentModelPath;
  final _modelPathController = StreamController<String?>.broadcast();
  Future<void> Function(String script)? _jsInvoker;
  late final StreamSubscription<ExpressionEvent> _expressionSub;
  late final StreamSubscription<StageAction> _stageSub;
  late final StreamSubscription<LipSyncFrame> _lipSub;

  Stream<String?> get modelPaths => _modelPathController.stream;

  /// Swap VRM mapping at runtime (e.g., user loads a different model).
  void updateConfig(VrmConfig config) {
    _config = config;
  }

  void attachJsInvoker(Future<void> Function(String script) invoker) {
    _jsInvoker = invoker;
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

  Future<void> dispose() async {
    await Future.wait([
      _expressionSub.cancel(),
      _stageSub.cancel(),
      _lipSub.cancel(),
      _modelPathController.close(),
    ]);
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
