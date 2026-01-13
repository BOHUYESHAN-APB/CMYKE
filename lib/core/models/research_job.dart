enum ResearchDepth { quick, deep }

enum ResearchDeliverable {
  summary,
  report,
  table,
  slides,
}

class ResearchJob {
  const ResearchJob({
    required this.goal,
    this.constraints = const [],
    this.sources = const [],
    this.deliverable = ResearchDeliverable.summary,
    this.depth = ResearchDepth.quick,
    this.progressUpdates = false,
  });

  final String goal;
  final List<String> constraints;
  final List<String> sources;
  final ResearchDeliverable deliverable;
  final ResearchDepth depth;
  final bool progressUpdates;
}
