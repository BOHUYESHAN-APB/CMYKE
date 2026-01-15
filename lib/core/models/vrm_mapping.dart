import 'expression_event.dart';
import 'stage_action.dart';

/// VRM/VRoid mapping for expressions, visemes, and motions.
/// Keep this config-driven so users can swap their own blendshape names.
class VrmConfig {
  const VrmConfig({
    this.expressionClips = defaultExpressionClips,
    this.visemeClips = defaultVisemeClips,
    this.motionClips = defaultMotionClips,
  });

  /// ExpressionEmotion -> VRM BlendShapeClip name.
  final Map<ExpressionEmotion, String> expressionClips;

  /// Viseme key -> VRM BlendShapeClip name (mouth shapes).
  /// Keys follow LipSyncFrame fields: aa/ee/ih/oh/ou.
  final Map<String, String> visemeClips;

  /// StageMotion -> motion clip or animator trigger name.
  final Map<StageMotion, String> motionClips;

  VrmConfig copyWith({
    Map<ExpressionEmotion, String>? expressionClips,
    Map<String, String>? visemeClips,
    Map<StageMotion, String>? motionClips,
  }) {
    return VrmConfig(
      expressionClips: expressionClips ?? this.expressionClips,
      visemeClips: visemeClips ?? this.visemeClips,
      motionClips: motionClips ?? this.motionClips,
    );
  }
}

/// Default mappings aligned with common VRoid Studio exports (VRM 1.0).
const Map<ExpressionEmotion, String> defaultExpressionClips = {
  // VRM 1.0 preset names are lower-case.
  ExpressionEmotion.idle: 'neutral',
  ExpressionEmotion.happy: 'happy',
  ExpressionEmotion.sad: 'sad',
  ExpressionEmotion.angry: 'angry',
  ExpressionEmotion.surprise: 'surprised',
  // Map think/awkward/question/curious to relaxed/lookUp as a best-effort.
  ExpressionEmotion.think: 'relaxed',
  ExpressionEmotion.awkward: 'relaxed',
  ExpressionEmotion.question: 'lookUp',
  ExpressionEmotion.curious: 'lookUp',
};

// VRM 1.0 viseme preset names (aa/ih/uu/ee/oh).
const Map<String, String> defaultVisemeClips = {
  'aa': 'aa',
  'ee': 'ee',
  'ih': 'ih',
  'oh': 'oh',
  'ou': 'uu', // approximate mapping
};

const Map<StageMotion, String> defaultMotionClips = {
  StageMotion.idle: 'Idle',
  StageMotion.wave: 'Wave',
  StageMotion.nod: 'Nod',
  StageMotion.lookLeft: 'LookLeft',
  StageMotion.lookRight: 'LookRight',
  StageMotion.lookAtUser: 'LookAtUser',
};
