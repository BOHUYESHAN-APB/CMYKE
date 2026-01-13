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
  });

  final ToolAction action;
  final String? query;
  final String? context;
  final IntentUrgency urgency;
  final String? routing; // e.g. "standard" | "realtime"
}
