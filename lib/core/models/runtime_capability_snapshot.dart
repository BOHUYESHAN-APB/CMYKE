enum RuntimeCapabilityState { unknown, ready, degraded, unavailable }

enum RuntimeCapabilityKind { toolGateway, provider }

class RuntimeCapabilitySnapshot {
  const RuntimeCapabilitySnapshot({
    required this.capabilityId,
    this.kind = RuntimeCapabilityKind.provider,
    required this.state,
    required this.enabled,
    required this.checkedAt,
    this.summary,
    this.error,
    this.providerId,
    this.providerLabel,
    this.providerModel,
    this.routes = const <String>{},
    this.features = const <String>{},
    this.activeRuns = 0,
  });

  final String capabilityId;
  final RuntimeCapabilityKind kind;
  final RuntimeCapabilityState state;
  final bool enabled;
  final DateTime checkedAt;
  final String? summary;
  final String? error;
  final String? providerId;
  final String? providerLabel;
  final String? providerModel;
  final Set<String> routes;
  final Set<String> features;
  final int activeRuns;

  bool get isReady => state == RuntimeCapabilityState.ready;
  bool get isUsable =>
      state == RuntimeCapabilityState.ready ||
      state == RuntimeCapabilityState.degraded;

  RuntimeCapabilitySnapshot copyWith({
    RuntimeCapabilityState? state,
    RuntimeCapabilityKind? kind,
    bool? enabled,
    DateTime? checkedAt,
    Object? summary = _sentinel,
    Object? error = _sentinel,
    Object? providerId = _sentinel,
    Object? providerLabel = _sentinel,
    Object? providerModel = _sentinel,
    Set<String>? routes,
    Set<String>? features,
    int? activeRuns,
  }) {
    return RuntimeCapabilitySnapshot(
      capabilityId: capabilityId,
      kind: kind ?? this.kind,
      state: state ?? this.state,
      enabled: enabled ?? this.enabled,
      checkedAt: checkedAt ?? this.checkedAt,
      summary: identical(summary, _sentinel)
          ? this.summary
          : summary as String?,
      error: identical(error, _sentinel) ? this.error : error as String?,
      providerId: identical(providerId, _sentinel)
          ? this.providerId
          : providerId as String?,
      providerLabel: identical(providerLabel, _sentinel)
          ? this.providerLabel
          : providerLabel as String?,
      providerModel: identical(providerModel, _sentinel)
          ? this.providerModel
          : providerModel as String?,
      routes: routes ?? this.routes,
      features: features ?? this.features,
      activeRuns: activeRuns ?? this.activeRuns,
    );
  }

  static RuntimeCapabilitySnapshot initial(String capabilityId) {
    return RuntimeCapabilitySnapshot(
      capabilityId: capabilityId,
      kind: RuntimeCapabilityKind.provider,
      state: RuntimeCapabilityState.unknown,
      enabled: false,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

extension RuntimeCapabilityStatePresentation on RuntimeCapabilityState {
  String get label => switch (this) {
    RuntimeCapabilityState.unknown => '待探测',
    RuntimeCapabilityState.ready => '已就绪',
    RuntimeCapabilityState.degraded => '降级',
    RuntimeCapabilityState.unavailable => '不可用',
  };
}

const Object _sentinel = Object();
