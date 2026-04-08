enum ToolAction {
  search,
  code,
  analyze,
  summarize,
  crawl,
  imageGen,
  imageAnalyze,
}

enum IntentUrgency { low, normal, high }

class ToolIntent {
  const ToolIntent({
    required this.action,
    this.query,
    this.context,
    this.urgency = IntentUrgency.normal,
    this.routing,
    this.sessionId,
    this.traceId,
    this.cancelGroup,
    this.interruptible = true,
  });

  final ToolAction action;
  final String? query;
  final String? context;
  final IntentUrgency urgency;
  final String? routing; // e.g. "standard" | "realtime"
  final String? sessionId;
  final String? traceId;
  final String? cancelGroup;
  final bool interruptible;
}
