enum StageMotion {
  idle,
  wave,
  nod,
  lookLeft,
  lookRight,
  lookAtUser,
}

enum StageTarget {
  cameraLeft,
  cameraRight,
  user,
  none,
}

class StageAction {
  const StageAction({
    required this.motion,
    this.target = StageTarget.none,
    this.durationMs,
    this.intensity,
  });

  final StageMotion motion;
  final StageTarget target;
  final int? durationMs;
  final double? intensity;
}
