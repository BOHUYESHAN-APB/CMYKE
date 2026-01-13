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
  ExpressionEmotion.idle: 'Neutral',
  ExpressionEmotion.happy: 'Joy',
  ExpressionEmotion.sad: 'Sorrow',
  ExpressionEmotion.angry: 'Angry',
  ExpressionEmotion.surprise: 'Surprised',
  ExpressionEmotion.think: 'Thinking',
  ExpressionEmotion.awkward: 'Relieved',
  ExpressionEmotion.question: 'Question',
  ExpressionEmotion.curious: 'LookUp',
};

const Map<String, String> defaultVisemeClips = {
  'aa': 'A',
  'ee': 'E',
  'ih': 'I',
  'oh': 'O',
  'ou': 'U',
};

const Map<StageMotion, String> defaultMotionClips = {
  StageMotion.idle: 'Idle',
  StageMotion.wave: 'Wave',
  StageMotion.nod: 'Nod',
  StageMotion.lookLeft: 'LookLeft',
  StageMotion.lookRight: 'LookRight',
  StageMotion.lookAtUser: 'LookAtUser',
};
