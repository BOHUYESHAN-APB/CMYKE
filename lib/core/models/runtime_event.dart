enum RuntimeEventKind {
  expression,
  stageAction,
  lipSync,
  toolIntent,
  researchJob,
  runtimeMetric,
  voiceTranscript,
  danmaku,
  interrupt,
  interruptAck,
}

enum RuntimeEventPriority { critical, high, normal, low }

extension RuntimeEventPriorityScore on RuntimeEventPriority {
  int get score {
    switch (this) {
      case RuntimeEventPriority.critical:
        return 300;
      case RuntimeEventPriority.high:
        return 200;
      case RuntimeEventPriority.normal:
        return 100;
      case RuntimeEventPriority.low:
        return 0;
    }
  }
}

enum RuntimeEventSource {
  system,
  controlAgent,
  toolRouter,
  chatEngine,
  voiceChannel,
  danmaku,
  user,
  autonomy,
  gateway,
}

class RuntimeEventMeta {
  const RuntimeEventMeta({
    required this.id,
    required this.kind,
    required this.source,
    required this.priority,
    required this.createdAt,
    this.sessionId,
    this.traceId,
    this.cancelGroup,
    this.attributes = const {},
  });

  final String id;
  final RuntimeEventKind kind;
  final RuntimeEventSource source;
  final RuntimeEventPriority priority;
  final DateTime createdAt;
  final String? sessionId;
  final String? traceId;
  final String? cancelGroup;
  final Map<String, Object?> attributes;
}

class RuntimeEventEnvelope<T> {
  const RuntimeEventEnvelope({required this.meta, required this.payload});

  final RuntimeEventMeta meta;
  final T payload;
}

enum RuntimeInterruptPhase { start, end }

class RuntimeInterruptSignal {
  const RuntimeInterruptSignal({
    required this.phase,
    required this.cancelGroup,
    this.reason,
  });

  final RuntimeInterruptPhase phase;
  final String cancelGroup;
  final String? reason;
}
