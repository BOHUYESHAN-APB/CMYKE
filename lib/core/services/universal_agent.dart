import '../models/chat_message.dart';
import '../models/memory_record.dart';
import '../models/memory_tier.dart';
import '../models/provider_config.dart';
import '../models/research_job.dart';
import '../repositories/memory_repository.dart';
import '../repositories/settings_repository.dart';
import 'llm_client.dart';

const String _deepResearchSystemPrompt = '''
你是 CMYKE 的“深度研究代理”，职责是交付可复核的研究产物，而不是闲聊。

[身份与输出边界]
- 当前模式是深度研究，不使用聊天伙伴人设语气。
- 禁止输出 `[SPLIT]`。
- 禁止输出“我是 AI/模型”等身份描述。
- 输出必须结构化、可直接用于文档生成。

[事实与来源]
- 若问题涉及外部事实，优先使用输入中给出的“外部检索结果”。
- 对无法核验的事实必须标注“待核验”，不要伪造来源。
- 在结论后附“来源与核验状态”小节。

[交付意识]
- 根据 Deliverable 类型组织内容：
  - structured report: 标题/摘要/正文/结论/来源
  - slide deck: 按“第N页”给出标题+3~5要点+可视化建议
  - comparison table: 给出可落地字段的对比表
  - summary: 先结论后要点
''';

class UniversalAgentResult {
  const UniversalAgentResult({required this.plan, required this.output});

  final String plan;
  final String output;
}

class UniversalAgent {
  UniversalAgent({
    required SettingsRepository settingsRepository,
    required MemoryRepository memoryRepository,
    LlmClient? llmClient,
  }) : _settingsRepository = settingsRepository,
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
    const base = _deepResearchSystemPrompt;
    final contextRecords = _memoryRepository.recordsForTier(
      MemoryTier.context,
      sessionId: sessionId,
    );
    final relevant = await _memoryRepository.searchRelevant(
      userMessage,
      limit: 12,
    );
    if (relevant.isEmpty) {
      final cross = _memoryRepository.recordsForTier(MemoryTier.crossSession);
      final auto = _memoryRepository.recordsForTier(MemoryTier.autonomous);
      if (contextRecords.isEmpty && cross.isEmpty && auto.isEmpty) {
        return base;
      }
      final buffer = StringBuffer('$base\n');
      _appendMemoryBlock(buffer, '会话记忆', contextRecords);
      _appendMemoryBlock(buffer, '跨会话记忆', cross);
      _appendMemoryBlock(buffer, '自主记忆', auto);
      return buffer.toString();
    }
    final buffer = StringBuffer('$base\n');
    _appendMemoryBlock(buffer, '会话记忆', contextRecords);
    final byTier = <MemoryTier, List<MemoryRecord>>{};
    for (final record in relevant) {
      byTier.putIfAbsent(record.tier, () => []).add(record);
    }
    void appendTier(MemoryTier tier, String label) {
      final records = byTier[tier];
      if (records == null || records.isEmpty) {
        return;
      }
      _appendMemoryBlock(buffer, label, records);
    }

    appendTier(MemoryTier.crossSession, '跨会话记忆');
    appendTier(MemoryTier.autonomous, '自主记忆');
    appendTier(MemoryTier.external, '外部知识');
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
    final seen = <String>{};
    for (final record in records) {
      final formatted = _formatMemoryLine(record);
      if (formatted == null || !seen.add(formatted)) {
        continue;
      }
      buffer.writeln('- $formatted');
    }
  }

  String? _formatMemoryLine(MemoryRecord record) {
    final content = record.content.trim();
    if (content.isEmpty) {
      return null;
    }
    switch (record.tier) {
      case MemoryTier.crossSession:
        final keyTag = record.tags.firstWhere(
          (tag) => tag.startsWith('core_key:'),
          orElse: () => '',
        );
        final coreKey = keyTag.isEmpty
            ? ''
            : keyTag.substring('core_key:'.length).trim();
        return coreKey.isEmpty ? content : '$coreKey: $content';
      case MemoryTier.autonomous:
        final day = record.createdAt.toIso8601String().substring(0, 10);
        return '$day $content';
      case MemoryTier.context:
      case MemoryTier.external:
        return content;
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
    final depthHint = depth == ResearchDepth.deep ? '深度' : '快速';
    return '''
请输出“$depthHint研究计划”，要求：
1) 仅输出计划，不输出最终结论；
2) 计划 4-8 步，每步包含：目标、输入、方法、预期产出；
3) 必须包含“检索与核验”步骤；
4) 明确本次交付类型：${_deliverableLabel(deliverable)}；
5) 全文中文，不使用 Markdown 代码块，不要输出 `[SPLIT]`。
''';
  }

  String _writerInstruction(
    ResearchDepth depth,
    ResearchDeliverable deliverable,
  ) {
    final depthHint = depth == ResearchDepth.deep ? '深度' : '快速';
    return '''
请基于 Goal 与 Plan 产出“$depthHint研究结果”。
交付类型：${_deliverableLabel(deliverable)}。

硬性要求：
1) 不要输出 `[SPLIT]`；
2) 不要使用闲聊语气或人设台词；
3) 若缺失可验证外部来源，明确写“待核验”；
4) 结尾必须包含“来源与核验状态”；
5) 输出内容要可直接用于导出文档/PPT。
''';
  }

  String _deliverableLabel(ResearchDeliverable deliverable) {
    switch (deliverable) {
      case ResearchDeliverable.summary:
        return '摘要';
      case ResearchDeliverable.report:
        return '结构化研报';
      case ResearchDeliverable.table:
        return '对比表';
      case ResearchDeliverable.slides:
        return '演示文稿';
    }
  }
}
