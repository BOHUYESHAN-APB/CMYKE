import '../models/chat_message.dart';
import '../models/memory_record.dart';
import '../models/memory_tier.dart';
import '../models/provider_config.dart';
import '../models/research_job.dart';
import '../prompts/persona_lumi.dart';
import '../repositories/memory_repository.dart';
import '../repositories/settings_repository.dart';
import 'llm_client.dart';

class UniversalAgentResult {
  const UniversalAgentResult({
    required this.plan,
    required this.output,
  });

  final String plan;
  final String output;
}

class UniversalAgent {
  UniversalAgent({
    required SettingsRepository settingsRepository,
    required MemoryRepository memoryRepository,
    LlmClient? llmClient,
  })  : _settingsRepository = settingsRepository,
        _memoryRepository = memoryRepository,
        _llmClient = llmClient ?? LlmClient();

  final SettingsRepository _settingsRepository;
  final MemoryRepository _memoryRepository;
  final LlmClient _llmClient;

  Future<UniversalAgentResult> runResearch(
    ResearchJob job, {
    String? sessionId,
  }) async {
    final provider = _resolveStandardProvider();
    if (provider == null) {
      throw StateError('Standard LLM provider not configured.');
    }
    final basePrompt = await _buildSystemPrompt(job.goal, sessionId);
    final plan = await _generatePlan(
      provider: provider,
      goal: job.goal,
      basePrompt: basePrompt,
      depth: job.depth,
      deliverable: job.deliverable,
    );
    final output = await _generateReport(
      provider: provider,
      goal: job.goal,
      plan: plan,
      basePrompt: basePrompt,
      depth: job.depth,
      deliverable: job.deliverable,
    );
    return UniversalAgentResult(plan: plan, output: output);
  }

  ProviderConfig? _resolveStandardProvider() {
    final settings = _settingsRepository.settings;
    return _settingsRepository.findProvider(settings.llmProviderId);
  }

  Future<String> _buildSystemPrompt(
    String userMessage,
    String? sessionId,
  ) async {
    final settings = _settingsRepository.settings;
    final base = buildLumiPersona(
      mode: settings.personaMode,
      level: settings.personaLevel,
      style: settings.personaStyle,
      customPrompt: settings.personaPrompt,
    );
    final contextRecords = _memoryRepository.recordsForTier(
      MemoryTier.context,
      sessionId: sessionId,
    );
    final relevant =
        await _memoryRepository.searchRelevant(userMessage, limit: 12);
    if (relevant.isEmpty) {
      final cross = _memoryRepository.recordsForTier(
        MemoryTier.crossSession,
      );
      final auto = _memoryRepository.recordsForTier(
        MemoryTier.autonomous,
      );
      if (contextRecords.isEmpty && cross.isEmpty && auto.isEmpty) {
        return base;
      }
      final buffer = StringBuffer('$base\n');
      _appendMemoryBlock(buffer, 'Session Memory', contextRecords);
      _appendMemoryBlock(buffer, 'Cross-Session Memory', cross);
      _appendMemoryBlock(buffer, 'Autonomous Memory', auto);
      return buffer.toString();
    }
    final buffer = StringBuffer('$base\n');
    _appendMemoryBlock(buffer, 'Session Memory', contextRecords);
    final byTier = <MemoryTier, List<String>>{};
    for (final record in relevant) {
      byTier.putIfAbsent(record.tier, () => []).add(record.content);
    }
    void appendTier(MemoryTier tier, String label) {
      final items = byTier[tier];
      if (items == null || items.isEmpty) {
        return;
      }
      buffer.writeln('\n[$label]');
      for (final item in items) {
        buffer.writeln('- $item');
      }
    }

    appendTier(MemoryTier.crossSession, 'Cross-Session Memory');
    appendTier(MemoryTier.autonomous, 'Autonomous Memory');
    appendTier(MemoryTier.external, 'External Knowledge');
    return buffer.toString();
  }

  void _appendMemoryBlock(
    StringBuffer buffer,
    String label,
    List<MemoryRecord> records,
  ) {
    if (records.isEmpty) {
      return;
    }
    buffer.writeln('\n[$label]');
    for (final record in records) {
      buffer.writeln('- ${record.content}');
    }
  }

  Future<String> _generatePlan({
    required ProviderConfig provider,
    required String goal,
    required String basePrompt,
    required ResearchDepth depth,
    required ResearchDeliverable deliverable,
  }) async {
    final instruction = _plannerInstruction(depth, deliverable);
    return _llmClient.completeChat(
      provider: provider,
      messages: [
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.user,
          content: goal,
          createdAt: DateTime.now(),
        ),
      ],
      systemPrompt: '$basePrompt\n\n$instruction',
    );
  }

  Future<String> _generateReport({
    required ProviderConfig provider,
    required String goal,
    required String plan,
    required String basePrompt,
    required ResearchDepth depth,
    required ResearchDeliverable deliverable,
  }) async {
    final instruction = _writerInstruction(depth, deliverable);
    final content = 'Goal: $goal\n\nPlan:\n$plan';
    return _llmClient.completeChat(
      provider: provider,
      messages: [
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.user,
          content: content,
          createdAt: DateTime.now(),
        ),
      ],
      systemPrompt: '$basePrompt\n\n$instruction',
    );
  }

  String _plannerInstruction(
    ResearchDepth depth,
    ResearchDeliverable deliverable,
  ) {
    final depthHint =
        depth == ResearchDepth.deep ? 'deep' : 'quick';
    return 'You are a universal task planner. Produce a $depthHint execution '
        'plan with 4-8 steps. Each step should include purpose and required '
        'information. Output the plan in Chinese. Do not output the final '
        'answer, only the plan. Deliverable: ${_deliverableLabel(deliverable)}.';
  }

  String _writerInstruction(
    ResearchDepth depth,
    ResearchDeliverable deliverable,
  ) {
    final depthHint =
        depth == ResearchDepth.deep ? 'deep' : 'quick';
    return 'You are a universal research agent. Produce a $depthHint result '
        'based on the goal and plan. Output in Chinese. Deliverable: '
        '${_deliverableLabel(deliverable)}. If external sources are missing, '
        'state the limitation and propose next steps.';
  }

  String _deliverableLabel(ResearchDeliverable deliverable) {
    switch (deliverable) {
      case ResearchDeliverable.summary:
        return 'summary';
      case ResearchDeliverable.report:
        return 'structured report';
      case ResearchDeliverable.table:
        return 'comparison table';
      case ResearchDeliverable.slides:
        return 'slide outline';
    }
  }
}
