import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../core/models/app_settings.dart';
import '../../core/models/chat_attachment.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/deep_research_message.dart';
import '../../core/models/deep_research_session.dart';
import '../../core/models/provider_config.dart';
import '../../core/models/research_job.dart';
import '../../core/models/tool_intent.dart';
import '../../core/repositories/deep_research_repository.dart';
import '../../core/repositories/memory_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/attachment_ingest_service.dart';
import '../../core/services/chat_export_service.dart';
import '../../core/services/deep_research_export_service.dart';
import '../../core/services/llm_client.dart';
import '../../core/services/runtime_hub.dart';
import '../../core/services/universal_agent.dart';
import '../../core/services/web_search_orchestrator.dart';
import '../../core/services/workspace_service.dart';
import '../../ui/theme/cmyke_chrome.dart';
import '../../ui/widgets/frosted_surface.dart';

class DeepResearchScreen extends StatefulWidget {
  const DeepResearchScreen({
    super.key,
    required this.settingsRepository,
    required this.memoryRepository,
    required this.workspaceService,
  });

  final SettingsRepository settingsRepository;
  final MemoryRepository memoryRepository;
  final WorkspaceService workspaceService;

  @override
  State<DeepResearchScreen> createState() => _DeepResearchScreenState();
}

class _DeepResearchScreenState extends State<DeepResearchScreen> {
  final DeepResearchRepository _repository = DeepResearchRepository();
  final ChatExportService _exportService = ChatExportService();
  final TextEditingController _inputController = TextEditingController();
  final LlmClient _llmClient = LlmClient();
  late final UniversalAgent _universalAgent;
  late final AttachmentIngestService _attachmentIngest;
  static const Duration _questionnaireTimeout = Duration(seconds: 90);
  bool _ready = false;
  bool _previewVisible = true;
  double _previewWidth = 520;
  double _sidebarWidth = 260;
  bool _layoutEditing = false;
  bool _isBusy = false;
  ResearchDeliverable _deliverable = ResearchDeliverable.report;
  ResearchDepth _depth = ResearchDepth.deep;
  final Set<DeepResearchExportFormat> _exportFormats = {
    DeepResearchExportFormat.docx,
    DeepResearchExportFormat.pdf,
  };
  final Map<String, List<_ResearchStep>> _stepsBySession = {};
  final Map<String, List<_ArtifactItem>> _artifactsBySession = {};
  final Map<String, String> _previewBySession = {};
  final Map<String, _QuestionnaireState> _questionnairesBySession = {};
  final Map<String, Timer> _questionnaireTimers = {};
  final Map<String, Map<String, String>> _questionnaireAnswersBySession = {};
  final Map<String, String> _pendingQueryBySession = {};
  final Map<String, List<ChatAttachment>> _pendingAttachmentsBySession = {};
  final List<_ResearchSection> _sectionOrder = [
    _ResearchSection.progress,
    _ResearchSection.messages,
    _ResearchSection.artifacts,
  ];
  @override
  void initState() {
    super.initState();
    _universalAgent = UniversalAgent(
      settingsRepository: widget.settingsRepository,
      memoryRepository: widget.memoryRepository,
    );
    _attachmentIngest = AttachmentIngestService(
      workspaceService: widget.workspaceService,
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _repository.load();
    if (!mounted) return;
    setState(() => _ready = true);
    _repository.addListener(_handleRepoChanged);
  }

  void _handleRepoChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    for (final timer in _questionnaireTimers.values) {
      timer.cancel();
    }
    _questionnaireTimers.clear();
    _repository.removeListener(_handleRepoChanged);
    _repository.dispose();
    _inputController.dispose();
    super.dispose();
  }

  DeepResearchSession? get _activeSession => _repository.activeSession;

  List<_ResearchStep> _stepsForSession(String sessionId) {
    return _stepsBySession[sessionId] ?? const [];
  }

  List<_ArtifactItem> _artifactsForSession(String sessionId) {
    return _artifactsBySession[sessionId] ?? const [];
  }

  String? _previewForSession(String sessionId) => _previewBySession[sessionId];

  Future<void> _createNewSession() async {
    await _repository.createSession();
  }

  Future<void> _resetCurrentSession() async {
    final session = _activeSession;
    if (session == null) return;
    _stepsBySession.remove(session.id);
    _artifactsBySession.remove(session.id);
    _previewBySession.remove(session.id);
    _clearQuestionnaire(session.id);
    await _repository.renameSession(session.id, '未命名研究');
    session.messages.clear();
    await _repository.addMessage(
      DeepResearchMessage(
        id: _newId(),
        role: DeepResearchRole.system,
        content: '已重置研究上下文。',
        createdAt: DateTime.now(),
      ),
    );
  }

  void _resetLayout() {
    setState(() {
      _sectionOrder
        ..clear()
        ..addAll([
          _ResearchSection.progress,
          _ResearchSection.messages,
          _ResearchSection.artifacts,
        ]);
      _sidebarWidth = 260;
      _previewWidth = 520;
      _previewVisible = true;
    });
  }

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (_isBusy) return;
    _inputController.clear();
    _resetResearchOptionsForNewRun();
    setState(() => _isBusy = true);

    var session = _activeSession;
    session ??= await _repository.createSession(title: _deriveTitle(text));
    final pendingAttachments = List<ChatAttachment>.from(
      _pendingAttachmentsBySession[session.id] ?? [],
    );
    if (text.isEmpty) {
      if (pendingAttachments.isNotEmpty) {
        await _repository.addMessage(
          DeepResearchMessage(
            id: _newId(),
            role: DeepResearchRole.system,
            content: '已收到附件，请再输入本次研究目标（文本）。',
            createdAt: DateTime.now(),
          ),
        );
      }
      setState(() => _isBusy = false);
      return;
    }

    final resolvedAttachments = pendingAttachments.isEmpty
        ? const <ChatAttachment>[]
        : await _maybeAnalyzeUserAttachments(text, pendingAttachments);
    _pendingAttachmentsBySession.remove(session.id);
    await _repository.addMessage(
      DeepResearchMessage(
        id: _newId(),
        role: DeepResearchRole.user,
        content: text,
        createdAt: DateTime.now(),
        attachments: resolvedAttachments,
      ),
    );

    _clearQuestionnaire(session.id);
    _pendingQueryBySession[session.id] = text;

    if (_shouldAskQuestionnaire(text)) {
      _startQuestionnaire(session.id);
      await _repository.addMessage(
        DeepResearchMessage(
          id: _newId(),
          role: DeepResearchRole.assistant,
          content: '需求还不够明确，我先生成一份简短问卷，完成后再继续研究。',
          createdAt: DateTime.now(),
        ),
      );
      setState(() => _isBusy = false);
      return;
    }

    await _startResearch(session.id, text, announced: true);
    setState(() => _isBusy = false);
  }

  Future<void> _pickAttachments() async {
    if (_isBusy) return;
    var session = _activeSession;
    session ??= await _repository.createSession(title: '未命名研究');
    final sessionId = session.id;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (result == null) {
        return;
      }
      final inputs = result.files
          .where((f) => f.name.trim().isNotEmpty)
          .map(
            (f) =>
                IngestFileInput(fileName: f.name, path: f.path, bytes: f.bytes),
          )
          .toList(growable: false);
      final ingested = await _attachmentIngest.ingestToLibraryAndWorkspace(
        sessionId: sessionId,
        inputs: inputs,
      );
      if (ingested.isEmpty) {
        await _repository.addMessage(
          DeepResearchMessage(
            id: _newId(),
            role: DeepResearchRole.system,
            content: '未读取到可用附件。',
            createdAt: DateTime.now(),
          ),
        );
        return;
      }
      setState(() {
        _pendingAttachmentsBySession
            .putIfAbsent(sessionId, () => [])
            .addAll(ingested);
      });
    } catch (e) {
      await _repository.addMessage(
        DeepResearchMessage(
          id: _newId(),
          role: DeepResearchRole.system,
          content: '选择附件失败：$e',
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  void _removePendingAttachment(String attachmentId) {
    final session = _activeSession;
    if (session == null) return;
    setState(() {
      _pendingAttachmentsBySession[session.id]?.removeWhere(
        (a) => a.id == attachmentId,
      );
    });
  }

  ProviderConfig? _resolveVisionProvider() {
    final settings = widget.settingsRepository.settings;
    final explicit = settings.visionProviderId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return widget.settingsRepository.findProvider(explicit);
    }
    final mainId = settings.llmProviderId?.trim();
    if (mainId != null && mainId.isNotEmpty) {
      final provider = widget.settingsRepository.findProvider(mainId);
      if (provider != null &&
          provider.capabilities.contains(ProviderCapability.vision)) {
        return provider;
      }
    }
    return null;
  }

  Future<List<ChatAttachment>> _maybeAnalyzeUserAttachments(
    String userText,
    List<ChatAttachment> attachments,
  ) async {
    final images = attachments
        .where((a) => a.kind == ChatAttachmentKind.image)
        .toList(growable: false);
    if (images.isEmpty) return attachments;
    final provider = _resolveVisionProvider();
    if (provider == null) return attachments;

    final prepared = <LlmImageInput>[];
    final idByIndex = <int, String>{};
    final limited = images.take(6).toList(growable: false);
    for (final attachment in limited) {
      final bytes = await _readFileBytesSafe(attachment.localPath);
      if (bytes == null || bytes.isEmpty) continue;
      final resized = _resizeForVision(bytes);
      if (resized == null || resized.isEmpty) continue;
      prepared.add(LlmImageInput(bytes: resized, mimeType: 'image/jpeg'));
      idByIndex[prepared.length] = attachment.id;
    }
    if (prepared.isEmpty) return attachments;

    const systemPrompt = '''
你是“图片归类与说明”助手。只输出 JSON 数组。
每个元素包含：index(从1开始)、type、caption、tags(数组)、has_text(布尔)。
type 只能取：sticker,meme,screenshot,photo,chart,document,other。
''';
    final prompt = '用户目标：$userText\n请逐张图输出结构化结果。';

    String raw;
    try {
      raw = await _llmClient
          .analyzeImageBytes(
            provider: provider,
            prompt: prompt,
            images: prepared,
            systemPrompt: systemPrompt,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      return attachments;
    }
    final parsed = _parseVisionJson(raw);
    if (parsed.isEmpty) return attachments;

    final updatedById = <String, ChatAttachment>{};
    for (final entry in parsed) {
      final id = idByIndex[entry.index];
      if (id == null) continue;
      final original = attachments.firstWhere((a) => a.id == id);
      updatedById[id] = ChatAttachment(
        id: original.id,
        kind: original.kind,
        localPath: original.localPath,
        fileName: original.fileName,
        createdAt: original.createdAt,
        mimeType: original.mimeType,
        bytes: original.bytes,
        width: original.width,
        height: original.height,
        sha256: original.sha256,
        caption: entry.caption,
        tags: entry.tags,
      );
    }
    if (updatedById.isEmpty) return attachments;
    return attachments
        .map((a) => updatedById[a.id] ?? a)
        .toList(growable: false);
  }

  Future<Uint8List?> _readFileBytesSafe(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Uint8List? _resizeForVision(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final maxSide = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      var working = decoded;
      if (maxSide > 1280) {
        final scale = 1280 / maxSide;
        working = img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
          interpolation: img.Interpolation.average,
        );
      }
      var jpg = img.encodeJpg(working, quality: 85);
      if (jpg.length > 1400 * 1024) {
        jpg = img.encodeJpg(working, quality: 70);
      }
      return Uint8List.fromList(jpg);
    } catch (_) {
      return null;
    }
  }

  List<_VisionJsonEntry> _parseVisionJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      final start = trimmed.indexOf('[');
      final end = trimmed.lastIndexOf(']');
      if (start >= 0 && end > start) {
        try {
          decoded = jsonDecode(trimmed.substring(start, end + 1));
        } catch (_) {
          return const [];
        }
      } else {
        return const [];
      }
    }
    if (decoded is! List) return const [];
    final out = <_VisionJsonEntry>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final idx = (item['index'] as num?)?.toInt() ?? 0;
      final type = (item['type'] ?? '').toString().trim();
      final caption = (item['caption'] ?? '').toString().trim();
      final tags = (item['tags'] is List)
          ? (item['tags'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList(growable: false)
          : const <String>[];
      if (idx <= 0 || caption.isEmpty) continue;
      out.add(
        _VisionJsonEntry(index: idx, type: type, caption: caption, tags: tags),
      );
    }
    return out;
  }

  void _seedSessionState(String sessionId, String query) {
    _stepsBySession[sessionId] = [
      _ResearchStep(
        title: '澄清需求',
        desc: '确认目标、交付形式与约束',
        status: _StepStatus.completed,
      ),
      _ResearchStep(
        title: '信息检索',
        desc: '多轮检索并筛选可信来源',
        status: _StepStatus.running,
      ),
      _ResearchStep(
        title: '分析整理',
        desc: '归纳对比并结构化要点',
        status: _StepStatus.queued,
      ),
      _ResearchStep(
        title: '生成产物',
        desc: _deliverableLabel(_deliverable),
        status: _StepStatus.queued,
      ),
    ];
    _artifactsBySession[sessionId] = _exportFormats
        .map(
          (format) => _ArtifactItem(
            title: '深度研究结果.${format.name}',
            kind: format.name.toUpperCase(),
            size: '待生成',
          ),
        )
        .toList();
    final summary = _buildQuestionnaireSummary(sessionId);
    _previewBySession[sessionId] = summary.isEmpty
        ? '本次研究：$query\n输出：${_deliverableLabel(_deliverable)}'
        : '本次研究：$query\n输出：${_deliverableLabel(_deliverable)}\n问卷：\n$summary';
  }

  void _setStepStatus(String sessionId, int index, _StepStatus status) {
    final steps = _stepsBySession[sessionId];
    if (steps == null || index < 0 || index >= steps.length) {
      return;
    }
    steps[index] = steps[index].copyWith(status: status);
  }

  void _markRunningStepFailed(String sessionId) {
    final steps = _stepsBySession[sessionId];
    if (steps == null || steps.isEmpty) {
      return;
    }
    for (var i = 0; i < steps.length; i += 1) {
      if (steps[i].status == _StepStatus.running) {
        steps[i] = steps[i].copyWith(status: _StepStatus.failed);
        return;
      }
    }
    steps[steps.length - 1] = steps.last.copyWith(status: _StepStatus.failed);
  }

  String _buildResearchPreview({
    required String query,
    required UniversalAgentResult result,
    required String sessionId,
  }) {
    final summary = _buildQuestionnaireSummary(sessionId);
    final buffer = StringBuffer();
    buffer.writeln('本次研究：$query');
    buffer.writeln('输出：${_deliverableLabel(_deliverable)}');
    if (summary.isNotEmpty) {
      buffer.writeln('\n问卷：');
      buffer.writeln(summary);
    }
    buffer.writeln('\n执行计划：');
    buffer.writeln(_normalizeResearchText(result.plan));
    buffer.writeln('\n研究输出：');
    buffer.writeln(_normalizeResearchText(result.output));
    return buffer.toString().trim();
  }

  String _renderResearchHtml({
    required String query,
    required UniversalAgentResult result,
    required String sessionId,
  }) {
    final escape = const HtmlEscape();
    String asHtml(String text) =>
        escape.convert(text).replaceAll('\n', '<br/>');
    final summary = _buildQuestionnaireSummary(sessionId);
    final generatedAt = DateTime.now().toIso8601String();
    final summaryBlock = summary.isEmpty
        ? ''
        : '<h2>问卷约束</h2><div class="block">${asHtml(summary)}</div>';
    return '''
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escape.convert(query)}</title>
  <style>
    body { font-family: "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif; margin: 36px auto; max-width: 920px; color: #1f2937; line-height: 1.65; }
    h1 { font-size: 28px; margin: 0 0 8px 0; }
    h2 { font-size: 22px; margin-top: 28px; border-bottom: 1px solid #e5e7eb; padding-bottom: 6px; }
    .meta { color: #6b7280; font-size: 13px; margin-bottom: 18px; }
    .block { background: #f8fafc; border: 1px solid #e5e7eb; border-radius: 10px; padding: 12px 14px; }
  </style>
</head>
<body>
  <h1>${escape.convert(query)}</h1>
  <div class="meta">session: ${escape.convert(sessionId)} | generated_at: $generatedAt | deliverable: ${_deliverableLabel(_deliverable)}</div>
  $summaryBlock
  <h2>执行计划</h2>
  <div class="block">${asHtml(_normalizeResearchText(result.plan))}</div>
  <h2>研究输出</h2>
  <div>${asHtml(_normalizeResearchText(result.output))}</div>
</body>
</html>
''';
  }

  String _normalizeResearchText(String input) {
    final normalized = input.replaceAll('[SPLIT]', '\n').trim();
    if (normalized.isEmpty) {
      return input.trim();
    }
    return normalized;
  }

  DeepResearchSession? _sessionById(String sessionId) {
    for (final session in _repository.sessions) {
      if (session.id == sessionId) {
        return session;
      }
    }
    return null;
  }

  String _buildLatestUserAttachmentsContext(String sessionId) {
    final session = _sessionById(sessionId);
    if (session == null) return '';

    DeepResearchMessage? lastUser;
    for (var i = session.messages.length - 1; i >= 0; i -= 1) {
      final msg = session.messages[i];
      if (msg.role == DeepResearchRole.user && msg.attachments.isNotEmpty) {
        lastUser = msg;
        break;
      }
    }
    if (lastUser == null) return '';
    final attachments = lastUser.attachments;
    if (attachments.isEmpty) return '';

    final buffer = StringBuffer();
    for (var i = 0; i < attachments.length; i += 1) {
      final a = attachments[i];
      final idx = i + 1;
      final name = a.fileName.trim().isEmpty ? 'attachment_$idx' : a.fileName;
      if (a.kind == ChatAttachmentKind.image) {
        final tags = a.tags.isEmpty ? '' : ' tags=${a.tags.join(",")}';
        final caption = (a.caption ?? '').trim();
        final captionPart = caption.isEmpty ? '' : ' caption=$caption';
        final token = Uri.file(a.localPath).toString();
        buffer.writeln('- [Image $idx] $name$captionPart$tags [IMAGE: $token]');
      } else {
        final mime = (a.mimeType ?? '').trim();
        final mimePart = mime.isEmpty ? '' : ' mime=$mime';
        final sha = (a.sha256 ?? '').trim();
        final shaPart = sha.isEmpty ? '' : ' sha256=$sha';
        buffer.writeln(
          '- [File $idx] $name path=${a.localPath}$mimePart$shaPart',
        );
      }
    }
    return buffer.toString().trim();
  }

  Future<_GatewaySearchResult> _tryGatewaySearch({
    required String sessionId,
    required String query,
  }) async {
    final settings = widget.settingsRepository.settings;
    if (!settings.deepResearchWebSearchEnabled) {
      return const _GatewaySearchResult(
        statusMessage: '深度研究联网搜索已关闭，本轮仅使用模型与本地上下文。',
      );
    }

    final gatewayError = _gatewayReadyError(settings);
    if (gatewayError != null) {
      return _GatewaySearchResult(statusMessage: gatewayError);
    }
    final snapshot = await RuntimeHub.instance.capabilities
        .refreshToolGateway();
    if (!snapshot.isUsable) {
      return _GatewaySearchResult(
        statusMessage:
            snapshot.error ?? snapshot.summary ?? '工具网关能力探测失败，本轮仅使用模型与本地上下文。',
      );
    }
    if (!snapshot.routes.contains('/api/v1/opencode/run')) {
      return const _GatewaySearchResult(
        statusMessage: '工具网关未暴露运行接口，本轮仅使用模型与本地上下文。',
      );
    }

    final tracePrefix =
        'dr_${DateTime.now().millisecondsSinceEpoch}_$sessionId';
    final orchestrator = WebSearchOrchestrator(
      dispatchToolIntent: RuntimeHub.instance.controlAgent.dispatchToolIntent,
    );

    const maxRounds = 6; // Design target can be 100+; UI path uses a safe cap.
    const fanout = 4;

    final loop = await orchestrator.runSearchLoop(
      config: WebSearchLoopConfig(
        sessionId: sessionId,
        routing: 'deep_research',
        tracePrefix: tracePrefix,
        cancelGroup: _sessionToolCancelGroup(sessionId),
        maxRounds: maxRounds,
        fanoutPerRound: fanout,
        maxPerRoundChars: 9000,
        maxTotalInjectedChars: 9000,
        roundCooldown: const Duration(milliseconds: 250),
        planQueries: ({required round, required priorRounds}) async {
          if (round == 1) {
            return _planSearchQueriesRound1(goal: query, maxQueries: fanout);
          }
          final last = priorRounds.isEmpty
              ? ''
              : priorRounds.last.injectedSnippet;
          return _planSearchQueriesRound2(
            goal: query,
            round1Snippet: last,
            maxQueries: fanout,
          );
        },
        shouldStop:
            ({
              required round,
              required priorRounds,
              required lastRoundInjectedSnippet,
              required totalInjectedChars,
            }) async {
              if (lastRoundInjectedSnippet.trim().isEmpty) {
                return const WebSearchStopDecision(
                  stop: true,
                  reason: 'no_new_evidence',
                );
              }
              if (priorRounds.length >= 2) {
                final a = priorRounds[priorRounds.length - 1].injectedSnippet
                    .trim();
                final b = priorRounds[priorRounds.length - 2].injectedSnippet
                    .trim();
                if (a.isEmpty && b.isEmpty) {
                  return const WebSearchStopDecision(
                    stop: true,
                    reason: 'stalled',
                  );
                }
              }
              return const WebSearchStopDecision(stop: false);
            },
        isFailure: _isToolSearchFailure,
      ),
    );

    final totalQueries = loop.rounds.fold<int>(
      0,
      (prev, r) => prev + r.executedQueries.length,
    );
    final totalSuccess = loop.rounds.fold<int>(
      0,
      (prev, r) => prev + r.successful,
    );
    var combinedSnippet = loop.combinedInjectedSnippet.trim();
    if (combinedSnippet.isEmpty) {
      final stopReason = loop.rounds.isEmpty
          ? 'no_rounds'
          : (loop.rounds.last.stopReason ?? 'unknown');
      return _GatewaySearchResult(
        statusMessage:
            '工具网关检索循环完成：0/$totalQueries 条成功（stop=$stopReason）。本轮将仅使用模型与本地上下文。',
      );
    }

    final visionNote = await _maybeAnalyzeWebImages(
      settings: settings,
      sessionId: sessionId,
      tracePrefix: tracePrefix,
      combinedSnippet: combinedSnippet,
    );
    if (visionNote != null && visionNote.trim().isNotEmpty) {
      combinedSnippet = '$combinedSnippet\n\n[网页关键图片理解]\n$visionNote';
    }
    final visionStatus = settings.deepResearchWebImageVisionEnabled
        ? (visionNote == null ? '图片理解: 未注入' : '图片理解: 已注入')
        : null;
    return _GatewaySearchResult(
      statusMessage:
          '工具网关检索循环完成：$totalSuccess/$totalQueries 条成功（rounds=${loop.rounds.length}）'
          '${visionStatus == null ? "" : " · $visionStatus"}，已注入研究上下文。',
      contextSnippet: combinedSnippet,
    );
  }

  String? _gatewayReadyError(AppSettings settings) {
    if (!settings.toolGatewayEnabled) {
      return '已开启深度研究联网搜索，但工具网关未启用，本轮仅使用模型与本地上下文。';
    }
    if (settings.toolGatewayBaseUrl.trim().isEmpty) {
      return '已开启深度研究联网搜索，但工具网关地址未配置。';
    }
    if (settings.toolGatewayPairingToken.trim().isEmpty) {
      return '已开启深度研究联网搜索，但工具网关 Pairing Token 未配置。';
    }
    return null;
  }

  String _sessionToolCancelGroup(String? sessionId) {
    final normalized = sessionId?.trim();
    return 'session:${normalized == null || normalized.isEmpty ? 'default' : normalized}';
  }

  bool _isToolSearchFailure(String message) {
    final lower = message.toLowerCase();
    return lower.contains('未启用') ||
        lower.contains('未配置') ||
        lower.contains('请求失败') ||
        lower.contains('执行失败') ||
        lower.contains('网关错误') ||
        lower.contains('http ');
  }

  ProviderConfig? _resolveVisionProviderForWeb(AppSettings settings) {
    final explicit = settings.visionProviderId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      final provider = widget.settingsRepository.findProvider(explicit);
      if (provider != null) {
        return provider;
      }
    }
    final main = settings.llmProviderId?.trim();
    if (main != null && main.isNotEmpty) {
      final provider = widget.settingsRepository.findProvider(main);
      if (provider != null &&
          provider.capabilities.contains(ProviderCapability.vision)) {
        return provider;
      }
    }
    return null;
  }

  Future<String?> _maybeAnalyzeWebImages({
    required AppSettings settings,
    required String sessionId,
    required String tracePrefix,
    required String combinedSnippet,
  }) async {
    if (!settings.deepResearchWebImageVisionEnabled) {
      return null;
    }
    final provider = _resolveVisionProviderForWeb(settings);
    if (provider == null) {
      return null;
    }
    final urls = _extractHttpUrls(combinedSnippet, max: 2);
    if (urls.isEmpty) {
      return null;
    }

    final dispatch = RuntimeHub.instance.controlAgent.dispatchToolIntent;
    final crawlFutures = <Future<String>>[];
    for (var i = 0; i < urls.length; i += 1) {
      final traceId = '${tracePrefix}_crawl_$i';
      crawlFutures.add(
        dispatch(
          ToolIntent(
            action: ToolAction.crawl,
            query: urls[i],
            sessionId: sessionId,
            routing: 'deep_research',
            traceId: traceId,
            cancelGroup: _sessionToolCancelGroup(sessionId),
          ),
        ).timeout(const Duration(seconds: 25), onTimeout: () => 'timeout'),
      );
    }

    final crawled = await Future.wait(crawlFutures);
    final images = <String>{};
    for (final raw in crawled) {
      images.addAll(_extractImageUrls(raw, max: 24));
    }
    final candidates = images
        .where((u) => !_looksLikeUiAssetUrl(u))
        .take(12)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }

    final metas = <_WebImageMeta>[];
    for (final url in candidates) {
      final meta = await _probeImageMeta(url);
      if (meta == null) continue;
      if (!_isLikelyContentImage(meta)) continue;
      metas.add(meta);
      if (metas.length >= 3) {
        break;
      }
    }
    if (metas.isEmpty) {
      return null;
    }
    metas.sort((a, b) => b.score.compareTo(a.score));
    final selected = metas.take(2).toList(growable: false);
    final selectedUrls = selected.map((m) => m.url).toList(growable: false);

    final metaLines = selected
        .map(
          (m) =>
              '- ${m.url} (${m.width}x${m.height}, ~${(m.bytes / 1024).round()}KB)',
        )
        .join('\n');

    const systemPrompt = '''
你是“网页图片解读器”。你的输出将直接注入深度研究上下文。
硬性要求：
1) 全文中文；
2) 不要输出 [SPLIT]；
3) 不要使用 Markdown 代码块（不要输出 ```）；
4) 对不确定的内容明确写“待核验”，不要臆测。
''';

    final prompt =
        '''
请对以下网页图片进行研究向的解读（每张图一段）：
- 这张图主要表达什么信息？
- 如果是图表/表格/流程图：抽取关键结论与可能的指标名称（不要求精确数值，无法读清则标注“待核验”）。
- 如果是截图/示意图：总结可引用的要点。

已筛选图片（尽量排除图标/组件图）：
$metaLines
'''
            .trim();

    try {
      var analysis = await _llmClient.analyzeImageUrls(
        provider: provider,
        prompt: prompt,
        imageUrls: selectedUrls,
        systemPrompt: systemPrompt,
      );
      analysis = analysis.trim();
      if (analysis.length > 2400) {
        analysis = '${analysis.substring(0, 2400)}...';
      }
      return analysis;
    } catch (_) {
      return null;
    }
  }

  List<String> _extractHttpUrls(String text, {required int max}) {
    final matches = RegExp(r'https?://[^\s\]\">)]+')
        .allMatches(text)
        .map((m) => m.group(0) ?? '')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final out = <String>[];
    final seen = <String>{};
    for (final raw in matches) {
      final cleaned = raw.replaceAll(RegExp(r'[\\]$'), '');
      if (cleaned.length < 12) continue;
      final key = cleaned.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(cleaned);
      if (out.length >= max) break;
    }
    return out;
  }

  List<String> _extractImageUrls(String text, {required int max}) {
    final out = <String>[];
    final seen = <String>{};
    final patterns = <RegExp>[
      RegExp(r'\[IMAGE:\s*(https?://[^\]]+)\]', caseSensitive: false),
      RegExp(
        r'https?://[^\s\]\">)]+\.(?:png|jpe?g|webp|gif)(?:\?[^\s\]\">)]*)?',
        caseSensitive: false,
      ),
    ];
    for (final reg in patterns) {
      for (final match in reg.allMatches(text)) {
        final url =
            (match.groupCount >= 1 ? match.group(1) : match.group(0)) ?? '';
        final cleaned = url.trim();
        if (cleaned.isEmpty) continue;
        final key = cleaned.toLowerCase();
        if (seen.contains(key)) continue;
        seen.add(key);
        out.add(cleaned);
        if (out.length >= max) return out;
      }
    }
    return out;
  }

  bool _looksLikeUiAssetUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.svg')) return true;
    const tokens = <String>[
      'favicon',
      'sprite',
      'icon',
      'logo',
      'avatar',
      'badge',
      'button',
      'spinner',
      'loading',
      'tracking',
      'analytics',
      'pixel',
      'ads',
      'doubleclick',
    ];
    for (final t in tokens) {
      if (lower.contains(t)) return true;
    }
    return false;
  }

  bool _isLikelyContentImage(_WebImageMeta meta) {
    if (meta.bytes < 24 * 1024) return false;
    if (meta.width < 260 || meta.height < 180) return false;
    final ratio = meta.width / meta.height;
    if (ratio > 6.0 || ratio < 0.25) return false;
    return true;
  }

  Future<_WebImageMeta?> _probeImageMeta(String url) async {
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      int? lengthHint;
      String? mimeHint;
      try {
        final head = await client
            .headUrl(uri)
            .timeout(
              const Duration(seconds: 6),
              onTimeout: () => throw const SocketException('head timeout'),
            );
        head.headers.set(HttpHeaders.userAgentHeader, 'CMYKE/0.1');
        final res = await head.close();
        mimeHint = res.headers.contentType?.mimeType;
        if (res.headers.contentLength >= 0) {
          lengthHint = res.headers.contentLength;
        }
        await res.drain<void>();
      } catch (_) {}

      if (mimeHint != null && !mimeHint.startsWith('image/')) {
        return null;
      }
      if (lengthHint != null && lengthHint > 2 * 1024 * 1024) {
        return null;
      }

      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'CMYKE/0.1');
      req.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8');
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1048575');
      final res = await req.close();
      final data = await _readAtMost(res, 1024 * 1024).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw const SocketException('image read timeout'),
      );
      if (data.isEmpty) {
        return null;
      }
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final height = image.height;
      image.dispose();
      codec.dispose();
      return _WebImageMeta(
        url: url,
        bytes: data.length,
        width: width,
        height: height,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _readAtMost(HttpClientResponse res, int maxBytes) async {
    final builder = BytesBuilder(copy: false);
    final completer = Completer<Uint8List>();
    late final StreamSubscription<List<int>> sub;
    sub = res.listen(
      (chunk) async {
        if (completer.isCompleted) {
          return;
        }
        final remaining = maxBytes - builder.length;
        if (remaining <= 0) {
          await sub.cancel();
          completer.complete(builder.takeBytes());
          return;
        }
        if (chunk.length <= remaining) {
          builder.add(chunk);
          return;
        }
        builder.add(chunk.sublist(0, remaining));
        await sub.cancel();
        completer.complete(builder.takeBytes());
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(builder.takeBytes());
        }
      },
      onError: (e, _) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      },
      cancelOnError: true,
    );
    return completer.future;
  }

  Future<List<String>> _planSearchQueriesRound1({
    required String goal,
    required int maxQueries,
  }) async {
    final planned = await _planQueriesWithModel(
      goal: goal,
      contextHint: '',
      maxQueries: maxQueries,
    );
    if (planned.isNotEmpty) {
      return planned;
    }
    return _heuristicQueries(goal).take(maxQueries).toList(growable: false);
  }

  Future<List<String>> _planSearchQueriesRound2({
    required String goal,
    required String round1Snippet,
    required int maxQueries,
  }) async {
    if (round1Snippet.trim().isEmpty) {
      return const [];
    }
    final context = round1Snippet.length <= 1400
        ? round1Snippet
        : '${round1Snippet.substring(0, 1400)}...';
    final planned = await _planQueriesWithModel(
      goal: goal,
      contextHint: context,
      maxQueries: maxQueries,
    );
    if (planned.isNotEmpty) {
      return planned;
    }
    return const [];
  }

  List<String> _heuristicQueries(String goal) {
    final trimmed = goal.trim();
    if (trimmed.isEmpty) return const [];
    return [
      trimmed,
      '$trimmed 官方 文档',
      '$trimmed 论文 whitepaper',
      '$trimmed 竞品 对比',
      '$trimmed github',
    ];
  }

  Future<List<String>> _planQueriesWithModel({
    required String goal,
    required String contextHint,
    required int maxQueries,
  }) async {
    try {
      final provider = _resolveStandardProvider();
      if (provider == null) {
        return const [];
      }
      final systemPrompt =
          '''
你是一个“搜索关键词规划器”。你的任务是把用户目标拆解成可用于联网检索的查询词。

硬性要求：
1) 只输出 JSON 数组，例如 ["query1","query2"]，不要输出任何额外文字；
2) 每条 query 20-80 字，中文为主，可夹带英文关键字；
3) queries 之间要尽量互补（官方文档/评测对比/论文/社区实践等）；
4) 不要输出超过 $maxQueries 条；
5) 不要输出 [SPLIT]。
''';
      final user = contextHint.trim().isEmpty
          ? '目标：$goal'
          : '目标：$goal\n\n已检索到的部分线索（供你提出下一轮更好的 queries）：\n$contextHint';
      final raw = await _llmClient.completeChat(
        provider: provider,
        messages: [
          ChatMessage(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            role: ChatRole.user,
            content: user,
            createdAt: DateTime.now(),
          ),
        ],
        systemPrompt: systemPrompt,
      );
      final parsed = _parseJsonStringList(raw);
      final combined = <String>[
        goal.trim(),
        ...parsed,
      ].where((e) => e.trim().isNotEmpty).toList(growable: false);
      final deduped = <String>[];
      final seen = <String>{};
      for (final q in combined) {
        final normalized = q.trim();
        if (normalized.isEmpty) continue;
        final key = normalized.toLowerCase();
        if (seen.contains(key)) continue;
        seen.add(key);
        deduped.add(normalized);
        if (deduped.length >= maxQueries) {
          break;
        }
      }
      return deduped;
    } catch (_) {
      return const [];
    }
  }

  List<String> _parseJsonStringList(String raw) {
    try {
      final trimmed = raw.trim();
      final start = trimmed.indexOf('[');
      final end = trimmed.lastIndexOf(']');
      if (start == -1 || end == -1 || end <= start) {
        return const [];
      }
      final slice = trimmed.substring(start, end + 1);
      final decoded = jsonDecode(slice);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .map((e) => e?.toString() ?? '')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  ProviderConfig? _resolveStandardProvider() {
    final settings = widget.settingsRepository.settings;
    final provider = widget.settingsRepository.findProvider(
      settings.llmProviderId,
    );
    if (provider == null) {
      return null;
    }
    if (provider.protocol == ProviderProtocol.deviceBuiltin) {
      return null;
    }
    return provider;
  }

  Future<String> _formatFileSize(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return '未知大小';
      }
      final bytes = await file.length();
      if (bytes < 1024) {
        return '${bytes}B';
      }
      if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(1)}KB';
      }
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } catch (_) {
      return '未知大小';
    }
  }

  Future<List<_ArtifactItem>> _exportArtifacts({
    required String sessionId,
    required String query,
    required UniversalAgentResult result,
  }) async {
    final html = _renderResearchHtml(
      query: query,
      result: result,
      sessionId: sessionId,
    );
    final outputsRoot = await widget.workspaceService.outputsDirectory(
      sessionId,
    );
    final runId = DateTime.now().millisecondsSinceEpoch.toString();
    final runDir = Directory(
      p.join(outputsRoot.path, 'deep_research', 'runs', runId),
    );
    if (!await runDir.exists()) {
      await runDir.create(recursive: true);
    }
    final orderedFormats = DeepResearchExportFormat.values
        .where((format) => _exportFormats.contains(format))
        .toList();
    final artifacts = <_ArtifactItem>[];
    for (final format in orderedFormats) {
      final exportResult = await _exportService.exportDeepResearchHtml(
        html: html,
        metadata: {
          'session_id': sessionId,
          'title': query,
          'deliverable': _deliverable.name,
          'depth': _depth.name,
          'questionnaire': _questionnaireAnswersBySession[sessionId] ?? {},
          'workspace_run_id': runId,
        },
        format: format,
        filenamePrefix: 'deep_research_${sessionId}_${format.name}',
        outputDir: runDir,
      );
      final path =
          (exportResult.outputPath != null &&
              exportResult.outputPath!.isNotEmpty)
          ? exportResult.outputPath!
          : exportResult.htmlPath;
      final note = exportResult.warnings.isEmpty
          ? null
          : exportResult.warnings.join('；');
      final size = await _formatFileSize(path);
      final statusText = exportResult.converted ? '已生成' : 'HTML 回退';
      artifacts.add(
        _ArtifactItem(
          title: p.basename(path),
          kind: format.name.toUpperCase(),
          size: '$statusText · $size',
          path: path,
          note: note,
        ),
      );
    }

    try {
      final manifest = <String, dynamic>{
        'run_id': runId,
        'session_id': sessionId,
        'query': query,
        'deliverable': _deliverable.name,
        'depth': _depth.name,
        'generated_at': DateTime.now().toIso8601String(),
        'questionnaire': _questionnaireAnswersBySession[sessionId] ?? {},
        'artifacts': artifacts
            .where((a) => a.path != null && a.path!.trim().isNotEmpty)
            .map(
              (a) => {
                'title': a.title,
                'kind': a.kind,
                'size': a.size,
                'path': a.path,
                if (a.note != null) 'note': a.note,
              },
            )
            .toList(),
      };
      final file = File(p.join(runDir.path, 'manifest.json'));
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(manifest));
    } catch (_) {
      // Best-effort; export should still succeed without manifest.
    }
    return artifacts;
  }

  Future<void> _openArtifact(_ArtifactItem item) async {
    final path = item.path;
    if (path == null || path.trim().isEmpty) {
      _showSnack('该产物暂无可打开路径。');
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _showSnack('文件不存在：$path');
      return;
    }
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', path], runInShell: true);
        return;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [path]);
        return;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [path]);
        return;
      }
      _showSnack('当前平台暂不支持自动打开文件。');
    } catch (error) {
      _showSnack('打开失败：$error');
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _deriveTitle(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '未命名研究';
    return trimmed.length <= 18 ? trimmed : '${trimmed.substring(0, 18)}...';
  }

  void _resetResearchOptionsForNewRun() {
    _deliverable = ResearchDeliverable.report;
    _depth = ResearchDepth.deep;
    _exportFormats
      ..clear()
      ..add(DeepResearchExportFormat.docx)
      ..add(DeepResearchExportFormat.pdf);
  }

  bool _matchesAny(String haystack, List<String> needles) {
    for (final needle in needles) {
      if (needle.isEmpty) continue;
      if (haystack.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  void _resetExportFormatsByDeliverable(ResearchDeliverable deliverable) {
    _exportFormats.clear();
    _exportFormats.add(DeepResearchExportFormat.docx);
    _exportFormats.add(DeepResearchExportFormat.pdf);
    switch (deliverable) {
      case ResearchDeliverable.slides:
        _exportFormats.add(DeepResearchExportFormat.pptx);
        break;
      case ResearchDeliverable.table:
        _exportFormats.add(DeepResearchExportFormat.xlsx);
        break;
      case ResearchDeliverable.summary:
      case ResearchDeliverable.report:
        break;
    }
  }

  bool _shouldAskQuestionnaire(String input) {
    final text = input.toLowerCase();
    if (_matchesAny(text, const ['直接开始', '无需澄清', '跳过问卷', '不用问'])) {
      return false;
    }
    return true;
  }

  void _startQuestionnaire(String sessionId) {
    if (_questionnairesBySession.containsKey(sessionId)) {
      return;
    }
    final questions = _buildQuestionnaireRound(1);
    if (questions.isEmpty) {
      return;
    }
    _questionnairesBySession[sessionId] = _QuestionnaireState(
      round: 1,
      questions: questions,
      deadline: DateTime.now().add(_questionnaireTimeout),
      timeout: _questionnaireTimeout,
    );
    _scheduleQuestionnaireTimeout(sessionId);
    setState(() {});
  }

  void _clearQuestionnaire(String sessionId) {
    _questionnaireTimers[sessionId]?.cancel();
    _questionnaireTimers.remove(sessionId);
    _questionnairesBySession.remove(sessionId)?.dispose();
    _questionnaireAnswersBySession.remove(sessionId);
    _pendingQueryBySession.remove(sessionId);
    _isBusy = false;
  }

  void _scheduleQuestionnaireTimeout(String sessionId) {
    _questionnaireTimers[sessionId]?.cancel();
    _questionnaireTimers[sessionId] = Timer(
      _questionnaireTimeout,
      () => _autoFillQuestionnaire(sessionId),
    );
  }

  Future<void> _autoFillQuestionnaire(String sessionId) async {
    if (!mounted) return;
    final state = _questionnairesBySession[sessionId];
    if (state == null) return;
    final answers = _questionnaireAnswersBySession.putIfAbsent(
      sessionId,
      () => {},
    );
    for (final question in state.questions) {
      if (question.isAnswered) continue;
      question.autoFillDefault();
      question.autoFilled = true;
      final encoded = question.encodedAnswer;
      if (encoded != null) {
        answers[question.id] = encoded;
      }
    }
    await _repository.addMessage(
      DeepResearchMessage(
        id: _newId(),
        role: DeepResearchRole.system,
        content: '问卷超时，已自动选择默认项并继续。',
        createdAt: DateTime.now(),
      ),
    );
    await _advanceQuestionnaireRound(sessionId);
  }

  void _selectQuestionAnswer(
    String sessionId,
    String questionId,
    String value,
  ) {
    final state = _questionnairesBySession[sessionId];
    if (state == null) return;
    final answers = _questionnaireAnswersBySession.putIfAbsent(
      sessionId,
      () => {},
    );
    for (final question in state.questions) {
      if (question.id != questionId) continue;
      question.applyOptionSelection(value);
      question.autoFilled = false;
      final encoded = question.encodedAnswer;
      if (encoded != null) {
        answers[questionId] = encoded;
      } else {
        answers.remove(questionId);
      }
      break;
    }
    setState(() {});
  }

  void _updateQuestionText(String sessionId, String questionId, String text) {
    final state = _questionnairesBySession[sessionId];
    if (state == null) return;
    final answers = _questionnaireAnswersBySession.putIfAbsent(
      sessionId,
      () => {},
    );
    for (final question in state.questions) {
      if (question.id != questionId) continue;
      question.textAnswer = text;
      question.autoFilled = false;
      final encoded = question.encodedAnswer;
      if (encoded != null) {
        answers[questionId] = encoded;
      } else {
        answers.remove(questionId);
      }
      break;
    }
    setState(() {});
  }

  Future<void> _advanceQuestionnaireRound(String sessionId) async {
    if (!mounted) return;
    final state = _questionnairesBySession[sessionId];
    if (state == null) return;
    if (!state.isComplete) return;
    final nextRound = state.round + 1;
    if (nextRound > 3) {
      await _finishQuestionnaire(sessionId);
      return;
    }
    final nextQuestions = _buildQuestionnaireRound(nextRound);
    if (nextQuestions.isEmpty) {
      await _finishQuestionnaire(sessionId);
      return;
    }
    _questionnairesBySession[sessionId] = _QuestionnaireState(
      round: nextRound,
      questions: nextQuestions,
      deadline: DateTime.now().add(_questionnaireTimeout),
      timeout: _questionnaireTimeout,
    );
    _scheduleQuestionnaireTimeout(sessionId);
    setState(() {});
  }

  Future<void> _finishQuestionnaire(String sessionId) async {
    if (!mounted) return;
    setState(() => _isBusy = true);
    _questionnaireTimers[sessionId]?.cancel();
    _questionnaireTimers.remove(sessionId);
    _questionnairesBySession.remove(sessionId)?.dispose();
    _applyQuestionnaireAnswers(sessionId);
    final query = _pendingQueryBySession.remove(sessionId) ?? '未命名研究';
    await _repository.addMessage(
      DeepResearchMessage(
        id: _newId(),
        role: DeepResearchRole.assistant,
        content: '已确认需求，开始执行深度研究。',
        createdAt: DateTime.now(),
      ),
    );
    try {
      await _startResearch(sessionId, query, announced: false);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _startResearch(
    String sessionId,
    String query, {
    required bool announced,
  }) async {
    if (announced) {
      await _repository.addMessage(
        DeepResearchMessage(
          id: _newId(),
          role: DeepResearchRole.assistant,
          content: '已收到任务，深度研究管线将在此页面执行。',
          createdAt: DateTime.now(),
        ),
      );
    }
    _seedSessionState(sessionId, query);
    if (mounted) {
      setState(() {});
    }
    try {
      final goalSummary = _buildQuestionnaireSummary(sessionId);
      final gatewaySearch = await _tryGatewaySearch(
        sessionId: sessionId,
        query: query,
      );
      if (gatewaySearch.statusMessage.isNotEmpty) {
        await _repository.addMessage(
          DeepResearchMessage(
            id: _newId(),
            role: DeepResearchRole.system,
            content: gatewaySearch.statusMessage,
            createdAt: DateTime.now(),
          ),
        );
      }
      final normalizedGoal = goalSummary.isEmpty
          ? query
          : '$query\n\n问卷约束：\n$goalSummary';
      final attachmentContext = _buildLatestUserAttachmentsContext(sessionId);
      final goalWithAttachments = attachmentContext.isEmpty
          ? normalizedGoal
          : '$normalizedGoal\n\n用户上传资料（可在交付物中引用）:\n$attachmentContext';
      final goalWithSearchContext = gatewaySearch.contextSnippet.isEmpty
          ? goalWithAttachments
          : '$goalWithAttachments\n\n外部检索结果（工具网关原文）:\n${gatewaySearch.contextSnippet}';
      final result = await _universalAgent.runResearch(
        ResearchJob(
          goal: goalWithSearchContext,
          deliverable: _deliverable,
          depth: _depth,
          progressUpdates: true,
        ),
        sessionId: sessionId,
      );

      _setStepStatus(sessionId, 1, _StepStatus.completed);
      _setStepStatus(sessionId, 2, _StepStatus.running);
      _previewBySession[sessionId] = _buildResearchPreview(
        query: query,
        result: result,
        sessionId: sessionId,
      );
      if (mounted) {
        setState(() {});
      }

      await _repository.addMessage(
        DeepResearchMessage(
          id: _newId(),
          role: DeepResearchRole.assistant,
          content: '研究计划：\n${_normalizeResearchText(result.plan)}',
          createdAt: DateTime.now(),
        ),
      );

      _setStepStatus(sessionId, 2, _StepStatus.completed);
      _setStepStatus(sessionId, 3, _StepStatus.running);
      if (mounted) {
        setState(() {});
      }

      final artifacts = await _exportArtifacts(
        sessionId: sessionId,
        query: query,
        result: result,
      );
      _artifactsBySession[sessionId] = artifacts;
      _setStepStatus(sessionId, 3, _StepStatus.completed);

      final outputSummary = _normalizeResearchText(result.output);
      final shortOutput = outputSummary.length <= 1200
          ? outputSummary
          : '${outputSummary.substring(0, 1200)}...';
      await _repository.addMessage(
        DeepResearchMessage(
          id: _newId(),
          role: DeepResearchRole.assistant,
          content: '研究结论：\n$shortOutput',
          createdAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _markRunningStepFailed(sessionId);
      await _repository.addMessage(
        DeepResearchMessage(
          id: _newId(),
          role: DeepResearchRole.system,
          content: '研究执行失败：$error',
          createdAt: DateTime.now(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _applyQuestionnaireAnswers(String sessionId) {
    final answers = _questionnaireAnswersBySession[sessionId];
    if (answers == null || answers.isEmpty) return;
    final deliverable = answers['deliverable'];
    switch (deliverable) {
      case 'slides':
        _deliverable = ResearchDeliverable.slides;
        break;
      case 'table':
        _deliverable = ResearchDeliverable.table;
        break;
      case 'summary':
        _deliverable = ResearchDeliverable.summary;
        break;
      default:
        _deliverable = ResearchDeliverable.report;
        break;
    }
    final depth = answers['depth'];
    if (depth == 'quick') {
      _depth = ResearchDepth.quick;
    } else if (depth == 'deep') {
      _depth = ResearchDepth.deep;
    }
    final applied = _applyExportFormatsFromEncoded(answers['formats']);
    if (!applied) {
      _resetExportFormatsByDeliverable(_deliverable);
    }
  }

  bool _applyExportFormatsFromEncoded(String? encoded) {
    final raw = encoded?.trim();
    if (raw == null || raw.isEmpty) {
      return false;
    }
    final parts = raw
        .split(',')
        .map((p) => p.trim().toLowerCase())
        .where((p) => p.isNotEmpty)
        .toSet();
    if (parts.isEmpty) {
      return false;
    }
    _exportFormats.clear();
    for (final part in parts) {
      switch (part) {
        case 'docx':
          _exportFormats.add(DeepResearchExportFormat.docx);
          break;
        case 'pdf':
          _exportFormats.add(DeepResearchExportFormat.pdf);
          break;
        case 'pptx':
          _exportFormats.add(DeepResearchExportFormat.pptx);
          break;
        case 'xlsx':
          _exportFormats.add(DeepResearchExportFormat.xlsx);
          break;
      }
    }
    return _exportFormats.isNotEmpty;
  }

  String _buildQuestionnaireSummary(String sessionId) {
    final answers = _questionnaireAnswersBySession[sessionId];
    if (answers == null || answers.isEmpty) return '';
    final buffer = StringBuffer();
    void addLine(String label, String? value, String id) {
      if (value == null || value.isEmpty) return;
      buffer.writeln('$label：${_labelForAnswer(id, value)}');
    }

    addLine('受众', answers['audience'], 'audience');
    addLine('交付物', answers['deliverable'], 'deliverable');
    addLine('文件格式', answers['formats'], 'formats');
    addLine('深度', answers['depth'], 'depth');
    addLine('长度', answers['length'], 'length');
    addLine('引用', answers['citation'], 'citation');
    addLine('图表偏好', answers['charts'], 'charts');
    addLine('补充要求', answers['notes'], 'notes');
    return buffer.toString().trim();
  }

  String _labelForAnswer(String id, String value) {
    switch (id) {
      case 'audience':
        switch (value) {
          case 'exec':
            return '管理层/高层';
          case 'tech':
            return '技术团队';
          case 'mixed':
            return '混合受众';
        }
        break;
      case 'deliverable':
        switch (value) {
          case 'report':
            return '研报（结构化）';
          case 'slides':
            return '演示（讲稿/路演）';
          case 'table':
            return '表格（可计算）';
          case 'summary':
            return '摘要（结论先行）';
        }
        break;
      case 'formats':
        final parts = value
            .split(',')
            .map((p) => p.trim().toLowerCase())
            .where((p) => p.isNotEmpty)
            .toList();
        if (parts.isEmpty) return value;
        String label(String token) {
          switch (token) {
            case 'docx':
              return 'DOCX';
            case 'pdf':
              return 'PDF';
            case 'pptx':
              return 'PPTX';
            case 'xlsx':
              return 'XLSX';
            default:
              return token;
          }
        }

        return parts.map(label).join(' + ');
      case 'depth':
        switch (value) {
          case 'quick':
            return '快速';
          case 'deep':
            return '深入';
        }
        break;
      case 'length':
        switch (value) {
          case 'short':
            return '短（1-2页）';
          case 'normal':
            return '中（3-6页）';
          case 'long':
            return '长（10+页）';
        }
        break;
      case 'citation':
        switch (value) {
          case 'numeric':
            return '脚注编号';
          case 'apa':
            return 'APA';
          case 'gbt':
            return 'GB/T';
        }
        break;
      case 'charts':
        switch (value) {
          case 'table':
            return '以表格为主';
          case 'chart':
            return '以图表为主';
          case 'mixed':
            return '混合';
        }
        break;
      case 'notes':
        return value.trim();
    }
    return value;
  }

  List<_QuestionItem> _buildQuestionnaireRound(int round) {
    switch (round) {
      case 1:
        return [
          _QuestionItem(
            id: 'audience',
            title: '报告的主要受众是谁？',
            kind: _QuestionKind.singleChoice,
            defaultValue: 'mixed',
            options: const [
              _QuestionOption(value: 'exec', label: '管理层/高层'),
              _QuestionOption(value: 'tech', label: '技术团队'),
              _QuestionOption(value: 'mixed', label: '混合受众'),
            ],
          ),
          _QuestionItem(
            id: 'deliverable',
            title: '本次的主要内容交付物？',
            kind: _QuestionKind.singleChoice,
            defaultValue: 'report',
            options: const [
              _QuestionOption(value: 'report', label: '研报（结构化）'),
              _QuestionOption(value: 'slides', label: '演示（讲稿/路演）'),
              _QuestionOption(value: 'table', label: '表格（可计算）'),
              _QuestionOption(value: 'summary', label: '摘要（结论先行）'),
            ],
          ),
          _QuestionItem(
            id: 'formats',
            title: '需要导出哪些文件格式？（可多选）',
            kind: _QuestionKind.multiChoice,
            defaultValue: 'docx,pdf',
            options: const [
              _QuestionOption(value: 'docx', label: 'DOCX'),
              _QuestionOption(value: 'pdf', label: 'PDF'),
              _QuestionOption(value: 'pptx', label: 'PPTX'),
              _QuestionOption(value: 'xlsx', label: 'XLSX'),
            ],
          ),
        ];
      case 2:
        return [
          _QuestionItem(
            id: 'depth',
            title: '研究深度',
            kind: _QuestionKind.singleChoice,
            defaultValue: 'deep',
            options: const [
              _QuestionOption(value: 'quick', label: '快速'),
              _QuestionOption(value: 'deep', label: '深入'),
            ],
          ),
          _QuestionItem(
            id: 'length',
            title: '目标篇幅',
            kind: _QuestionKind.singleChoice,
            defaultValue: 'normal',
            options: const [
              _QuestionOption(value: 'short', label: '短（1-2页）'),
              _QuestionOption(value: 'normal', label: '中（3-6页）'),
              _QuestionOption(value: 'long', label: '长（10+页）'),
            ],
          ),
        ];
      case 3:
        return [
          _QuestionItem(
            id: 'citation',
            title: '引用样式',
            kind: _QuestionKind.singleChoice,
            defaultValue: 'numeric',
            options: const [
              _QuestionOption(value: 'numeric', label: '脚注编号'),
              _QuestionOption(value: 'apa', label: 'APA'),
              _QuestionOption(value: 'gbt', label: 'GB/T'),
            ],
          ),
          _QuestionItem(
            id: 'charts',
            title: '图表偏好',
            kind: _QuestionKind.singleChoice,
            defaultValue: 'mixed',
            options: const [
              _QuestionOption(value: 'table', label: '以表格为主'),
              _QuestionOption(value: 'chart', label: '以图表为主'),
              _QuestionOption(value: 'mixed', label: '混合'),
            ],
          ),
          _QuestionItem(
            id: 'notes',
            title: '补充约束（可选）',
            kind: _QuestionKind.text,
            required: false,
            defaultValue: '',
            hintText: '例如：必须包含的要点、禁用的来源、目标公司/地区、希望包含的章节等。',
          ),
        ];
      default:
        return const [];
    }
  }

  String _deliverableLabel(ResearchDeliverable deliverable) {
    switch (deliverable) {
      case ResearchDeliverable.summary:
        return '摘要';
      case ResearchDeliverable.report:
        return '研报';
      case ResearchDeliverable.table:
        return '表格';
      case ResearchDeliverable.slides:
        return '演示';
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = _activeSession;
    final showPreview = _previewVisible;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [chrome.background0, chrome.background1],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            top: -140,
            right: -120,
            child: _GlowOrb(
              size: 280,
              color: chrome.accent.withValues(alpha: 0.18),
            ),
          ),
          Positioned(
            bottom: -160,
            left: -100,
            child: _GlowOrb(
              size: 260,
              color: chrome.accent.withValues(alpha: 0.12),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const minSidebar = 220.0;
                final maxSidebar = (constraints.maxWidth * 0.32).clamp(
                  240.0,
                  360.0,
                );
                final sidebarWidth = _sidebarWidth.clamp(
                  minSidebar,
                  maxSidebar,
                );

                return Row(
                  children: [
                    SizedBox(
                      width: sidebarWidth,
                      child: _DeepResearchSidebar(
                        repository: _repository,
                        onNew: _createNewSession,
                      ),
                    ),
                    _ResizeHandle(
                      onDrag: (delta) {
                        setState(() {
                          _sidebarWidth = (_sidebarWidth + delta).clamp(
                            minSidebar,
                            maxSidebar,
                          );
                        });
                      },
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _DeepResearchHeader(
                            title: session?.title ?? '深度研究',
                            onBack: () => Navigator.of(context).pop(),
                            onNew: _createNewSession,
                            onReset: session == null
                                ? null
                                : _resetCurrentSession,
                            onToggleLayout: () {
                              setState(() => _layoutEditing = !_layoutEditing);
                            },
                            onResetLayout: _resetLayout,
                            layoutEditing: _layoutEditing,
                            isBusy: _isBusy,
                          ),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              child: session == null
                                  ? KeyedSubtree(
                                      key: const ValueKey('empty'),
                                      child: _buildEmptyState(),
                                    )
                                  : KeyedSubtree(
                                      key: ValueKey(session.id),
                                      child: _buildSplitView(
                                        session: session,
                                        showPreview: showPreview,
                                      ),
                                    ),
                            ),
                          ),
                          _DeepResearchInputBar(
                            controller: _inputController,
                            busy: _isBusy,
                            onSend: _handleSend,
                            onPickAttachments: _pickAttachments,
                            onRemoveAttachment: _removePendingAttachment,
                            pendingAttachments: session == null
                                ? const []
                                : (_pendingAttachmentsBySession[session.id] ??
                                      const []),
                            promptHint: session == null
                                ? '提交目标后将先进入问卷澄清，再开始研究。'
                                : _questionnairesBySession[session.id] == null
                                ? '本轮参数已由问卷确认：${_deliverableLabel(_deliverable)} / ${_depth == ResearchDepth.deep ? '深度' : '快速'}。'
                                : '问卷进行中：请先完成上方问卷，再开始研究执行。',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: FrostedSurface(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '深度研究',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '这是独立的研究工作区，适合长文档、多轮检索与结构化交付。',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: context.chrome.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: const [
                  _QuickHintChip(text: '多轮检索 + 引用'),
                  _QuickHintChip(text: '自动问卷澄清'),
                  _QuickHintChip(text: 'DOCX / PDF 输出'),
                  _QuickHintChip(text: '可接入 OpenCode'),
                ],
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _createNewSession,
                icon: const Icon(Icons.add),
                label: const Text('新建研究项目'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSplitView({
    required DeepResearchSession session,
    required bool showPreview,
  }) {
    if (!showPreview) {
      return Stack(
        children: [
          Positioned.fill(child: _buildActiveView(session)),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: _PreviewRestoreStrip(
              onTap: () => setState(() => _previewVisible = true),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 6.0;
        const minLeft = 340.0;
        const minRight = 320.0;
        final total = constraints.maxWidth;
        final available = total - dividerWidth;
        if (available <= 0) {
          return const SizedBox.shrink();
        }
        final minRightEffective = minRight > available ? available : minRight;
        final minLeftEffective = minLeft > available ? available : minLeft;
        final maxRight = (available - minLeftEffective).clamp(0.0, available);
        final rightUpper = maxRight < minRightEffective
            ? minRightEffective
            : maxRight;
        final right = _previewWidth.clamp(minRightEffective, rightUpper);
        final left = (available - right).clamp(0.0, available);

        return Row(
          children: [
            SizedBox(width: left, child: _buildActiveView(session)),
            _ResizeHandle(
              width: dividerWidth,
              onDrag: (delta) {
                setState(() {
                  _previewWidth = (_previewWidth - delta).clamp(
                    minRightEffective,
                    rightUpper,
                  );
                });
              },
            ),
            SizedBox(width: right, child: _buildPreviewPane(session)),
          ],
        );
      },
    );
  }

  Widget _buildActiveView(DeepResearchSession session) {
    final steps = _stepsForSession(session.id);
    final artifacts = _artifactsForSession(session.id);
    final padding = const EdgeInsets.fromLTRB(16, 8, 12, 12);
    final completed = steps
        .where((s) => s.status == _StepStatus.completed)
        .length;

    if (_layoutEditing) {
      return ReorderableListView.builder(
        padding: padding,
        buildDefaultDragHandles: false,
        itemCount: _sectionOrder.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) {
              newIndex -= 1;
            }
            final item = _sectionOrder.removeAt(oldIndex);
            _sectionOrder.insert(newIndex, item);
          });
        },
        proxyDecorator: (child, index, animation) {
          return Material(
            color: Colors.transparent,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1.02).animate(animation),
              child: child,
            ),
          );
        },
        itemBuilder: (context, index) {
          final section = _sectionOrder[index];
          return Container(
            key: ValueKey(section),
            margin: const EdgeInsets.only(bottom: 12),
            child: _buildSection(
              sessionId: session.id,
              section: section,
              steps: steps,
              completed: completed,
              artifacts: artifacts,
              messages: session.messages,
              dragHandle: ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle,
                  size: 18,
                  color: context.chrome.textSecondary,
                ),
              ),
            ),
          );
        },
      );
    }

    return ListView(
      padding: padding,
      children: [
        for (var i = 0; i < _sectionOrder.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _buildSection(
            sessionId: session.id,
            section: _sectionOrder[i],
            steps: steps,
            completed: completed,
            artifacts: artifacts,
            messages: session.messages,
          ),
        ],
      ],
    );
  }

  Widget _buildSection({
    required String sessionId,
    required _ResearchSection section,
    required List<_ResearchStep> steps,
    required int completed,
    required List<_ArtifactItem> artifacts,
    required List<DeepResearchMessage> messages,
    Widget? dragHandle,
  }) {
    final questionnaire = _questionnairesBySession[sessionId];
    switch (section) {
      case _ResearchSection.progress:
        return _SectionCard(
          title: '研究进度',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$completed/${steps.length}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: context.chrome.textSecondary,
                ),
              ),
              if (dragHandle != null) ...[const SizedBox(width: 8), dragHandle],
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (questionnaire != null) ...[
                _QuestionnaireCard(
                  sessionId: sessionId,
                  state: questionnaire,
                  onSelect: _selectQuestionAnswer,
                  onTextChanged: _updateQuestionText,
                  onAdvance: _advanceQuestionnaireRound,
                ),
                const SizedBox(height: 12),
              ],
              if (steps.isEmpty)
                Text(
                  '尚未开始任务。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.chrome.textSecondary,
                  ),
                )
              else
                Column(
                  children: steps.map((step) => _StepTile(step: step)).toList(),
                ),
            ],
          ),
        );
      case _ResearchSection.messages:
        return _SectionCard(
          title: '对话记录',
          trailing: dragHandle,
          child: messages.isEmpty
              ? Text(
                  '暂无对话。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.chrome.textSecondary,
                  ),
                )
              : Column(
                  children: messages
                      .map((msg) => _MessageBubble(message: msg))
                      .toList(),
                ),
        );
      case _ResearchSection.artifacts:
        return _SectionCard(
          title: '产物列表',
          trailing: dragHandle,
          child: artifacts.isEmpty
              ? Text(
                  '暂无产物。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.chrome.textSecondary,
                  ),
                )
              : Column(
                  children: artifacts
                      .map(
                        (item) => _ArtifactTile(
                          item: item,
                          onOpen: () => _openArtifact(item),
                        ),
                      )
                      .toList(),
                ),
        );
    }
  }

  Widget _buildPreviewPane(DeepResearchSession session) {
    final chrome = context.chrome;
    final preview = _previewForSession(session.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
      child: Column(
        children: [
          FrostedSurface(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '产物预览',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '收起预览',
                  onPressed: () => setState(() => _previewVisible = false),
                  icon: const Icon(Icons.close_fullscreen),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FrostedSurface(
              padding: const EdgeInsets.all(16),
              child: preview == null
                  ? Center(
                      child: Text(
                        '暂无预览，生成产物后将在此展示。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: chrome.textSecondary,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Text(
                        preview,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(height: 1.4),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeepResearchHeader extends StatelessWidget {
  const _DeepResearchHeader({
    required this.title,
    required this.onBack,
    required this.onNew,
    required this.onReset,
    required this.onToggleLayout,
    required this.onResetLayout,
    required this.layoutEditing,
    required this.isBusy,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onNew;
  final VoidCallback? onReset;
  final VoidCallback onToggleLayout;
  final VoidCallback onResetLayout;
  final bool layoutEditing;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: FrostedSurface(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconButton(
              tooltip: '返回聊天',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 6),
            Icon(Icons.science_outlined, color: chrome.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isBusy)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '执行中',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: chrome.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            IconButton(
              tooltip: layoutEditing ? '完成布局' : '布局编辑',
              onPressed: onToggleLayout,
              icon: Icon(layoutEditing ? Icons.check : Icons.view_quilt),
            ),
            if (layoutEditing)
              TextButton.icon(
                onPressed: onResetLayout,
                icon: const Icon(Icons.restore),
                label: const Text('重置布局'),
              ),
            TextButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add),
              label: const Text('新建项目'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('重置'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeepResearchSidebar extends StatelessWidget {
  const _DeepResearchSidebar({required this.repository, required this.onNew});

  final DeepResearchRepository repository;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return FrostedSurface(
      borderRadius: BorderRadius.zero,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      border: Border(right: BorderSide(color: chrome.separatorStrong)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science, color: chrome.accent),
              const SizedBox(width: 10),
              Text(
                '深度研究',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add),
              label: const Text('新建项目'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '最近项目',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: chrome.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: repository.sessions.length,
              itemBuilder: (context, index) {
                final session = repository.sessions[index];
                final isActive = session.id == repository.activeSessionId;
                return _SidebarSessionTile(
                  session: session,
                  isActive: isActive,
                  onTap: () => repository.setActive(session.id),
                  onRename: () => _showRenameDialog(context, session),
                  onDelete: () => _showDeleteDialog(context, session),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    DeepResearchSession session,
  ) async {
    final controller = TextEditingController(text: session.title);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重命名'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '输入新名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) {
                  repository.renameSession(session.id, value);
                }
                Navigator.of(context).pop();
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    DeepResearchSession session,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除项目'),
          content: Text('确定要删除「${session.title}」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                repository.removeSession(session.id);
                Navigator.of(context).pop();
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }
}

class _SidebarSessionTile extends StatelessWidget {
  const _SidebarSessionTile({
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final DeepResearchSession session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final bg = isActive
        ? chrome.accent.withValues(alpha: 0.14)
        : Colors.transparent;
    final border = isActive
        ? Border.all(color: chrome.accent.withValues(alpha: 0.4))
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: Icon(
          Icons.history,
          size: 18,
          color: isActive ? chrome.accent : chrome.textSecondary,
        ),
        title: Text(
          session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onTap: onTap,
        trailing: PopupMenuButton<String>(
          tooltip: '更多',
          icon: Icon(Icons.more_horiz, size: 18, color: chrome.textSecondary),
          onSelected: (value) {
            if (value == 'rename') {
              onRename();
            } else if (value == 'delete') {
              onDelete();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('重命名')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }
}

class _DeepResearchInputBar extends StatelessWidget {
  const _DeepResearchInputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onPickAttachments,
    required this.onRemoveAttachment,
    required this.pendingAttachments,
    required this.promptHint,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final Future<void> Function() onPickAttachments;
  final void Function(String attachmentId) onRemoveAttachment;
  final List<ChatAttachment> pendingAttachments;
  final String promptHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: FrostedSurface(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              promptHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.chrome.textSecondary,
              ),
            ),
            if (pendingAttachments.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: pendingAttachments
                    .take(12)
                    .map(
                      (a) => _AttachmentChip(
                        attachment: a,
                        onRemove: () => onRemoveAttachment(a.id),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: '输入研究目标，例如：整理 2025 年 AI Agent 生态并输出研报',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: '添加图片/文件',
                  onPressed: busy ? null : onPickAttachments,
                  icon: const Icon(Icons.attach_file),
                ),
                FilledButton.icon(
                  onPressed: busy ? null : onSend,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final icon = attachment.kind == ChatAttachmentKind.image
        ? Icons.image_outlined
        : Icons.insert_drive_file_outlined;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: chrome.surfaceElevated.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: chrome.separatorStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: chrome.textSecondary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              attachment.fileName,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: chrome.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            child: Icon(Icons.close, size: 16, color: chrome.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return FrostedSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _QuestionnaireCard extends StatelessWidget {
  const _QuestionnaireCard({
    required this.sessionId,
    required this.state,
    required this.onSelect,
    required this.onTextChanged,
    required this.onAdvance,
  });

  final String sessionId;
  final _QuestionnaireState state;
  final void Function(String sessionId, String questionId, String value)
  onSelect;
  final void Function(String sessionId, String questionId, String text)
  onTextChanged;
  final Future<void> Function(String sessionId) onAdvance;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final timeoutSeconds = state.timeout.inSeconds <= 0
        ? 90
        : state.timeout.inSeconds;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: chrome.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chrome.separatorStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<int>(
            stream: Stream<int>.periodic(
              const Duration(seconds: 1),
              (tick) => tick,
            ),
            builder: (context, _) {
              final left = state.deadline.difference(DateTime.now());
              final secondsLeft = left.inSeconds.clamp(0, timeoutSeconds);
              String two(int v) => v.toString().padLeft(2, '0');
              final mm = secondsLeft ~/ 60;
              final ss = secondsLeft % 60;
              final label = '${two(mm)}:${two(ss)}';
              final progress = secondsLeft / timeoutSeconds;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '需求问卷 · 第 ${state.round} 轮',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '剩余 $label（超时自动填充）',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: chrome.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: chrome.separatorStrong.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          ...state.questions.map((question) {
            final selected = question.selected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          question.title,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (question.autoFilled)
                        Text(
                          '已自动选择',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: chrome.textSecondary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (question.kind == _QuestionKind.text)
                    TextField(
                      controller: question.textController,
                      maxLines: null,
                      minLines: 2,
                      decoration: InputDecoration(
                        hintText: question.hintText ?? '可选，留空表示无。',
                        isDense: true,
                        filled: true,
                        fillColor: chrome.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: chrome.separatorStrong),
                        ),
                      ),
                      onChanged: (text) =>
                          onTextChanged(sessionId, question.id, text),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: question.options.map((option) {
                        final isSelected =
                            question.kind == _QuestionKind.multiChoice
                            ? question.selectedValues.contains(option.value)
                            : selected == option.value;
                        if (question.kind == _QuestionKind.multiChoice) {
                          return FilterChip(
                            label: Text(option.label),
                            selected: isSelected,
                            onSelected: (_) =>
                                onSelect(sessionId, question.id, option.value),
                          );
                        }
                        return ChoiceChip(
                          label: Text(option.label),
                          selected: isSelected,
                          onSelected: (_) =>
                              onSelect(sessionId, question.id, option.value),
                        );
                      }).toList(),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: state.isComplete ? () => onAdvance(sessionId) : null,
              child: Text(state.round >= 3 ? '开始研究' : '下一步'),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionnaireState {
  _QuestionnaireState({
    required this.round,
    required this.questions,
    required this.deadline,
    required this.timeout,
  });

  final int round;
  final List<_QuestionItem> questions;
  final DateTime deadline;
  final Duration timeout;

  bool get isComplete => questions.every((question) => question.isAnswered);

  void dispose() {
    for (final question in questions) {
      question.dispose();
    }
  }
}

enum _QuestionKind { singleChoice, multiChoice, text }

class _QuestionItem {
  _QuestionItem({
    required this.id,
    required this.title,
    required this.kind,
    this.required = true,
    this.options = const [],
    this.defaultValue = '',
    this.hintText,
  }) {
    if (kind == _QuestionKind.text) {
      textAnswer = defaultValue;
      textController = TextEditingController(text: textAnswer);
    }
    if (kind == _QuestionKind.multiChoice && defaultValue.trim().isNotEmpty) {
      selectedValues
        ..clear()
        ..addAll(
          defaultValue
              .split(',')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty),
        );
    }
  }

  final String id;
  final String title;
  final _QuestionKind kind;
  final bool required;
  final List<_QuestionOption> options;
  final String defaultValue;
  final String? hintText;
  String? selected;
  final Set<String> selectedValues = {};
  String textAnswer = '';
  TextEditingController? textController;
  bool autoFilled = false;

  bool get isAnswered {
    switch (kind) {
      case _QuestionKind.singleChoice:
        return selected != null;
      case _QuestionKind.multiChoice:
        return selectedValues.isNotEmpty || !required;
      case _QuestionKind.text:
        if (!required) return true;
        return textAnswer.trim().isNotEmpty;
    }
  }

  String? get encodedAnswer {
    switch (kind) {
      case _QuestionKind.singleChoice:
        return selected;
      case _QuestionKind.multiChoice:
        if (selectedValues.isEmpty) return null;
        final list = selectedValues.toList()..sort();
        return list.join(',');
      case _QuestionKind.text:
        final trimmed = textAnswer.trim();
        return trimmed.isEmpty ? null : trimmed;
    }
  }

  void applyOptionSelection(String value) {
    switch (kind) {
      case _QuestionKind.singleChoice:
        selected = value;
        break;
      case _QuestionKind.multiChoice:
        if (selectedValues.contains(value)) {
          selectedValues.remove(value);
        } else {
          selectedValues.add(value);
        }
        break;
      case _QuestionKind.text:
        break;
    }
  }

  void autoFillDefault() {
    switch (kind) {
      case _QuestionKind.singleChoice:
        selected = defaultValue.trim().isEmpty ? null : defaultValue.trim();
        break;
      case _QuestionKind.multiChoice:
        selectedValues
          ..clear()
          ..addAll(
            defaultValue
                .split(',')
                .map((p) => p.trim())
                .where((p) => p.isNotEmpty),
          );
        break;
      case _QuestionKind.text:
        textAnswer = defaultValue;
        textController ??= TextEditingController(text: textAnswer);
        textController!.text = textAnswer;
        break;
    }
  }

  void dispose() {
    textController?.dispose();
  }
}

class _QuestionOption {
  const _QuestionOption({required this.value, required this.label});

  final String value;
  final String label;
}

class _GatewaySearchResult {
  const _GatewaySearchResult({
    required this.statusMessage,
    this.contextSnippet = '',
  });

  final String statusMessage;
  final String contextSnippet;
}

class _WebImageMeta {
  const _WebImageMeta({
    required this.url,
    required this.bytes,
    required this.width,
    required this.height,
  });

  final String url;
  final int bytes;
  final int width;
  final int height;

  double get score => (width * height).toDouble() + bytes.toDouble();
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final DeepResearchMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == DeepResearchRole.user;
    final chrome = context.chrome;
    final bubbleColor = isUser
        ? chrome.accent.withValues(alpha: 0.18)
        : chrome.surfaceElevated;
    final images = message.attachments
        .where((a) => a.kind == ChatAttachmentKind.image)
        .toList(growable: false);
    final files = message.attachments
        .where((a) => a.kind == ChatAttachmentKind.file)
        .toList(growable: false);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chrome.separatorStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isUser ? '用户' : '助手',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: chrome.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (_displayContent(message.content).trim().isNotEmpty)
            Text(_displayContent(message.content)),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: images
                  .take(6)
                  .map(
                    (a) => ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(a.localPath),
                        width: 140,
                        height: 140,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 140,
                          height: 140,
                          alignment: Alignment.center,
                          color: chrome.surface,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: chrome.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (files.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: files
                  .take(8)
                  .map(
                    (a) => Chip(
                      label: Text(a.fileName),
                      avatar: const Icon(Icons.insert_drive_file_outlined),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  String _displayContent(String text) => text.replaceAll('[SPLIT]', '\n');
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final _ResearchStep step;

  @override
  Widget build(BuildContext context) {
    final color = step.status.color(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  step.desc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.chrome.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            step.status.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtifactTile extends StatelessWidget {
  const _ArtifactTile({required this.item, required this.onOpen});

  final _ArtifactItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: context.chrome.surfaceElevated,
        child: Text(
          item.kind,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(item.title),
      subtitle: Text(
        item.note == null ? item.size : '${item.size}\n${item.note!}',
        maxLines: item.note == null ? 1 : 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: '打开',
        onPressed: onOpen,
        icon: const Icon(Icons.open_in_new),
      ),
    );
  }
}

class _PreviewRestoreStrip extends StatelessWidget {
  const _PreviewRestoreStrip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 34,
          decoration: BoxDecoration(
            color: chrome.surfaceElevated,
            border: Border(left: BorderSide(color: chrome.separatorStrong)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Icon(Icons.open_in_full, size: 18, color: chrome.accent),
              const Spacer(),
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  '预览',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: chrome.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickHintChip extends StatelessWidget {
  const _QuickHintChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      backgroundColor: context.chrome.surfaceElevated,
      labelStyle: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag, this.width = 6});

  final ValueChanged<double> onDrag;
  final double width;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: width,
          child: Center(
            child: Container(
              width: 2,
              height: 36,
              decoration: BoxDecoration(
                color: chrome.separatorStrong.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ResearchSection { progress, messages, artifacts }

class _ResearchStep {
  const _ResearchStep({
    required this.title,
    required this.desc,
    required this.status,
  });

  final String title;
  final String desc;
  final _StepStatus status;

  _ResearchStep copyWith({_StepStatus? status}) =>
      _ResearchStep(title: title, desc: desc, status: status ?? this.status);
}

enum _StepStatus { queued, running, completed, failed }

extension on _StepStatus {
  String get label {
    switch (this) {
      case _StepStatus.queued:
        return '等待';
      case _StepStatus.running:
        return '进行中';
      case _StepStatus.completed:
        return '完成';
      case _StepStatus.failed:
        return '失败';
    }
  }

  Color color(BuildContext context) {
    final chrome = context.chrome;
    switch (this) {
      case _StepStatus.queued:
        return chrome.textSecondary;
      case _StepStatus.running:
        return chrome.accent;
      case _StepStatus.completed:
        return const Color(0xFF35B368);
      case _StepStatus.failed:
        return const Color(0xFFD1443D);
    }
  }
}

class _ArtifactItem {
  const _ArtifactItem({
    required this.title,
    required this.kind,
    required this.size,
    this.path,
    this.note,
  });

  final String title;
  final String kind;
  final String size;
  final String? path;
  final String? note;
}

class _VisionJsonEntry {
  const _VisionJsonEntry({
    required this.index,
    required this.type,
    required this.caption,
    required this.tags,
  });

  final int index;
  final String type;
  final String caption;
  final List<String> tags;
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
