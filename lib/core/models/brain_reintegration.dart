enum BrainReintegrationPhase { idle, escalating, waiting, reintegrating }

class BrainReintegrationState {
  const BrainReintegrationState({
    required this.phase,
    required this.reason,
    required this.providerId,
  });

  const BrainReintegrationState.idle()
    : phase = BrainReintegrationPhase.idle,
      reason = '',
      providerId = '';

  final BrainReintegrationPhase phase;
  final String reason;
  final String providerId;

  bool get isActive => phase != BrainReintegrationPhase.idle;

  BrainReintegrationState copyWith({
    BrainReintegrationPhase? phase,
    String? reason,
    String? providerId,
  }) {
    return BrainReintegrationState(
      phase: phase ?? this.phase,
      reason: reason ?? this.reason,
      providerId: providerId ?? this.providerId,
    );
  }
}
