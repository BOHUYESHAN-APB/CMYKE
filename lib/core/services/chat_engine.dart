import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image/image.dart' as img;
import 'package:speech_to_text/speech_to_text.dart';

import '../models/app_settings.dart';
import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/llm_stream_event.dart';
import '../models/lipsync_frame.dart';
import '../models/memory_tier.dart';
import '../models/memory_record.dart';
import '../models/provider_config.dart';
import '../models/research_job.dart';
import '../models/tool_intent.dart';
import '../prompts/persona_lumi.dart';
import '../repositories/chat_repository.dart';
import '../repositories/memory_repository.dart';
import '../repositories/settings_repository.dart';
import '../models/voice_transcript_event.dart';
import 'audio_stream_player.dart';
import 'llm_client.dart';
import 'speech_client.dart';
import 'token_estimator.dart';
import 'universal_agent.dart';
import 'runtime_hub.dart';
import 'motion_agent.dart';
import 'memory_agent.dart';
import 'time_range_parser.dart';
import 'web_search_orchestrator.dart';

class ChatEngine extends ChangeNotifier {
  ChatEngine({
    required ChatRepository chatRepository,
    required MemoryRepository memoryRepository,
    required SettingsRepository settingsRepository,
  }) : _chatRepository = chatRepository,
       _memoryRepository = memoryRepository,
       _settingsRepository = settingsRepository {
    _chatRepository.addListener(_refreshTokenUsage);
    _memoryRepository.addListener(_refreshTokenUsage);
    _settingsRepository.addListener(_refreshTokenUsage);
    _tts.setStartHandler(() {
      _isTtsSpeaking = true;
      _syncLipSyncState();
      _updateTalkingState();
      notifyListeners();
    });
    _tts.setCompletionHandler(() {
      _isTtsSpeaking = false;
      _syncLipSyncState();
      _updateTalkingState();
      notifyListeners();
    });
    _tts.setCancelHandler(() {
      _isTtsSpeaking = false;
      _syncLipSyncState();
      _updateTalkingState();
      notifyListeners();
    });
    _tts.setErrorHandler((_) {
      _isTtsSpeaking = false;
      _syncLipSyncState();
      _updateTalkingState();
      notifyListeners();
    });
    _audioPlayingSubscription = _audioPlayer.playingStream.listen((playing) {
      _isAudioPlaying = playing;
      _syncLipSyncState();
      _updateTalkingState();
      notifyListeners();
    });
    _universalAgent = UniversalAgent(
      settingsRepository: _settingsRepository,
      memoryRepository: _memoryRepository,
      llmClient: _llmClient,
    );
    _motionAgent = MotionAgent(llmClient: _llmClient);
    _memoryAgent = MemoryAgent(llmClient: _llmClient);
    _refreshTokenUsage();
  }

  final ChatRepository _chatRepository;
  final MemoryRepository _memoryRepository;
  final SettingsRepository _settingsRepository;
  final LlmClient _llmClient = LlmClient();
  late final UniversalAgent _universalAgent;
  late final MotionAgent _motionAgent;
  late final MemoryAgent _memoryAgent;
  final SpeechClient _speechClient = SpeechClient();
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioStreamPlayer _audioPlayer = AudioStreamPlayer();
  StreamSubscription<bool>? _audioPlayingSubscription;
  final Random _lipSyncRandom = Random();
  Timer? _lipSyncTimer;
  bool _lipSyncActive = false;
  bool _isTalking = false;
  DateTime? _lastMotionAgentAt;
  DateTime? _lastMemoryAgentAt;
  String? _pendingMotionAgentId;
  bool _memoryAgentRunning = false;

  StreamSubscription<LlmStreamEvent>? _streamSubscription;
  bool _isListening = false;
  bool _isTtsSpeaking = false;
  bool _isAudioPlaying = false;
  bool _isStreaming = false;
  bool _isCompressing = false;
  String _partialTranscript = '';
  bool _isVoiceChannelMonitoring = false;
  String _voiceChannelPartialTranscript = '';
  final List<VoiceTranscriptEvent> _voiceChannelHistory = [];
  final Queue<VoiceTranscriptEvent> _voiceChannelPending = Queue();
  bool _voiceChannelInjecting = false;
  Timer? _voiceChannelRestartTimer;
  bool _speechReady = false;
  String _sttStatus = '';
  String _sttLastError = '';
  int _estimatedTokens = 0;
  int? _tokenLimit;

  static const int _compressionKeepMessages = 8;
  static const double _compressionTriggerRatio = 0.92;

  bool get isListening => _isListening;
  bool get isVoiceChannelMonitoring => _isVoiceChannelMonitoring;
  bool get isSpeaking => _isTtsSpeaking || _isAudioPlaying;
  bool get isStreaming => _isStreaming;
  bool get isCompressing => _isCompressing;
  String get partialTranscript => _partialTranscript;
  String get voiceChannelPartialTranscript => _voiceChannelPartialTranscript;
  List<VoiceTranscriptEvent> get voiceChannelHistory =>
      List.unmodifiable(_voiceChannelHistory);
  String get sttStatus => _sttStatus;
  String get sttLastError => _sttLastError;
  int get estimatedTokens => _estimatedTokens;
  int? get tokenLimit => _tokenLimit;

  Future<void> sendText(
    String text, {
    ChatSourceKind sourceKind = ChatSourceKind.user,
    String? sourceId,
    ChatPriority priority = ChatPriority.user,
    List<ChatAttachment> attachments = const [],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      return;
    }
    final helpTopic = _parseHelpTopic(trimmed);
    if (helpTopic != null) {
      await _sendCommandHelp(
        trimmed,
        topic: helpTopic,
        sourceKind: sourceKind,
        sourceId: sourceId,
        priority: priority,
      );
      return;
    }
    if (trimmed == '/motions') {
      await interrupt();
      await _chatRepository.sendUserMessage(
        trimmed,
        sourceKind: sourceKind,
        sourceId: sourceId,
        priority: priority,
      );
      final info = await _describeLive3dMotions();
      await _chatRepository.addMessage(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.system,
          content: info,
          createdAt: DateTime.now(),
          sourceKind: ChatSourceKind.system,
          priority: ChatPriority.low,
        ),
        persist: true,
      );
      return;
    }
    if (trimmed == '/stop') {
      await interrupt();
      RuntimeHub.instance.live3dBridge.stopMotion();
      await _chatRepository.sendUserMessage(
        trimmed,
        sourceKind: sourceKind,
        sourceId: sourceId,
        priority: priority,
      );
      await _chatRepository.addMessage(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.system,
          content: '已停止动作，回到 idle。',
          createdAt: DateTime.now(),
          sourceKind: ChatSourceKind.system,
          priority: ChatPriority.low,
        ),
        persist: true,
      );
      return;
    }
    if (trimmed.startsWith('/play ')) {
      final motion = trimmed.substring(6).trim();
      if (motion.isEmpty) {
        return;
      }
      await interrupt();
      RuntimeHub.instance.live3dBridge.playMotion(motion);
      await _chatRepository.sendUserMessage(
        trimmed,
        sourceKind: sourceKind,
        sourceId: sourceId,
        priority: priority,
      );
      await _chatRepository.addMessage(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.system,
          content: '已触发动作：$motion',
          createdAt: DateTime.now(),
          sourceKind: ChatSourceKind.system,
          priority: ChatPriority.low,
        ),
        persist: true,
      );
      return;
    }
    if (trimmed == '/persona') {
      await interrupt();
      await _chatRepository.sendUserMessage(
        trimmed,
        sourceKind: sourceKind,
        sourceId: sourceId,
        priority: priority,
      );
      final settings = _settingsRepository.settings;
      final persona = buildLumiPersona(
        mode: settings.personaMode,
        level: settings.personaLevel,
        style: settings.personaStyle,
        customPrompt: settings.personaPrompt,
      );
      await _chatRepository.addMessage(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.system,
          content: persona,
          createdAt: DateTime.now(),
          sourceKind: ChatSourceKind.system,
          priority: ChatPriority.low,
        ),
        persist: true,
      );
      return;
    }
    final toolCommand = _parseToolCommand(trimmed);
    if (toolCommand != null) {
      if (toolCommand.showHelp || toolCommand.query.trim().isEmpty) {
        await _sendCommandHelp(
          trimmed,
          topic: 'tool',
          sourceKind: sourceKind,
          sourceId: sourceId,
          priority: priority,
        );
        return;
      }
      await _runToolCommand(
        trimmed,
        toolCommand,
        sourceKind: sourceKind,
        sourceId: sourceId,
        priority: priority,
      );
      return;
    }
    final agentCommand = _parseAgentCommand(trimmed);
    if (agentCommand != null) {
      await _runUniversalAgent(agentCommand);
      return;
    }
    final tagCommand = _parseTagCommand(trimmed);
    if (tagCommand != null) {
      if (tagCommand.type == _TagCommandType.help) {
        await _sendCommandHelp(
          trimmed,
          topic: tagCommand.topic ?? '',
          sourceKind: sourceKind,
          sourceId: sourceId,
          priority: priority,
        );
        return;
      }
      if (tagCommand.type == _TagCommandType.tool) {
        if (tagCommand.payload.trim().isEmpty) {
          await _sendCommandHelp(
            trimmed,
            topic: 'tool',
            sourceKind: sourceKind,
            sourceId: sourceId,
            priority: priority,
          );
          return;
        }
        await _runToolCommand(
          trimmed,
          _ToolCommand(
            action: tagCommand.action ?? ToolAction.code,
            query: tagCommand.payload,
          ),
          sourceKind: sourceKind,
          sourceId: sourceId,
          priority: priority,
        );
        return;
      }
      if (tagCommand.type == _TagCommandType.agent) {
        if (tagCommand.payload.trim().isEmpty) {
          await _sendCommandHelp(
            trimmed,
            topic: 'agent',
            sourceKind: sourceKind,
            sourceId: sourceId,
            priority: priority,
          );
          return;
        }
        await _runUniversalAgent(
          _AgentCommand(
            goal: tagCommand.payload,
            deliverable: tagCommand.deliverable ?? ResearchDeliverable.report,
            depth: tagCommand.depth ?? ResearchDepth.deep,
          ),
        );
        return;
      }
      if (tagCommand.type == _TagCommandType.info) {
        await _sendCommandHelp(
          trimmed,
          topic: tagCommand.topic ?? '',
          sourceKind: sourceKind,
          sourceId: sourceId,
          priority: priority,
        );
        return;
      }
    }
    await interrupt();

    final normalizedText =
        trimmed.isEmpty && attachments.isNotEmpty
            ? '（发送了 ${attachments.length} 个附件）'
            : trimmed;

    final resolvedAttachments = attachments.isEmpty
        ? const <ChatAttachment>[]
        : await _maybeAnalyzeUserAttachments(
          normalizedText,
          attachments: attachments,
        );
    final attachmentContext = _formatAttachmentContext(resolvedAttachments);

    await _chatRepository.sendUserMessage(
      normalizedText,
      sourceKind: sourceKind,
      sourceId: sourceId,
      priority: priority,
      attachments: resolvedAttachments,
    );

    final assistantMessage = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: ChatRole.assistant,
      content: '',
      createdAt: DateTime.now(),
    );
    await _chatRepository.addMessage(assistantMessage, persist: false);

    final provider = _activeProvider();
    if (provider == null) {
      await _chatRepository.updateMessageContent(
        assistantMessage.id,
        '未配置模型，请在“模型与能力配置”中选择 Provider。',
        persist: true,
      );
      return;
    }

    await _maybeCompressSession(provider);
    final autoSearch = await _tryAutoWebSearchForStandardMode(normalizedText);
    if (autoSearch.statusMessage != null) {
      await _chatRepository.addMessage(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.system,
          content: autoSearch.statusMessage!,
          createdAt: DateTime.now(),
          sourceKind: ChatSourceKind.tool,
          priority: ChatPriority.low,
        ),
        persist: true,
      );
    }
    final systemPrompt = await _buildSystemPrompt(
      normalizedText,
      webSearchContext: autoSearch.contextSnippet,
      attachmentContext: attachmentContext,
    );
    _isStreaming = true;
    _updateTalkingState();
    notifyListeners();
    final buffer = StringBuffer();
    bool receivedAudio = false;
    Future<void>? audioStartFuture;

    final session = _chatRepository.activeSession;
    final messageHistory = session == null
        ? <ChatMessage>[]
        : _messageHistoryForPrompt(session);

    Future<void> handleEvent(LlmStreamEvent event) async {
      if (event.hasText) {
        buffer.write(event.textDelta);
        final snapshot = buffer.toString();
        final display = _shouldSoftCleanStreaming(snapshot)
            ? _stripForbiddenAsides(snapshot)
            : snapshot;
        _chatRepository.updateMessageContent(
          assistantMessage.id,
          display,
          persist: false,
        );
      }
      if (event.hasAudio) {
        if (!_supportsStreamingAudio()) {
          return;
        }
        receivedAudio = true;
        final format = event.audioFormat ?? provider.audioFormat ?? 'wav';
        audioStartFuture ??= _audioPlayer.start(
          contentType: _contentTypeForFormat(format),
        );
        await audioStartFuture;
        await _audioPlayer.addChunk(event.audioChunk!);
      }
    }

    _streamSubscription = _llmClient
        .streamChat(
          provider: provider,
          messages: messageHistory,
          systemPrompt: systemPrompt,
        )
        .listen(
          (event) => unawaited(handleEvent(event)),
          onError: (error) async {
            _isStreaming = false;
            _updateTalkingState();
            notifyListeners();
            await _audioPlayer.stop();
            await _chatRepository.updateMessageContent(
              assistantMessage.id,
              '请求失败: $error',
              persist: true,
            );
          },
          onDone: () async {
            _isStreaming = false;
            _updateTalkingState();
            notifyListeners();
            final raw = buffer.toString();
            final provisional =
                _settingsRepository.settings.route == ModelRoute.realtime
                ? raw
                : _stripForbiddenAsides(raw);
            if (provisional != raw) {
              await _chatRepository.updateMessageContent(
                assistantMessage.id,
                provisional,
                persist: false,
              );
            }
            final content = await _postProcessAssistantText(
              provider: provider,
              content: provisional,
              modelProvidedAudio: receivedAudio,
            );
            final parts = _splitAssistantResponse(content);
            await _applyAssistantResponse(assistantMessage, parts);
            if (receivedAudio && audioStartFuture != null) {
              await audioStartFuture;
              await _audioPlayer.finish();
            }
            if (_shouldSpeakResponse(modelProvidedAudio: receivedAudio)) {
              await _playTts(parts.join('\n'));
            }
            _refreshTokenUsage();
            unawaited(
              _maybeTriggerMemoryAgent(
                userText: trimmed,
                assistantText: parts.join('\n'),
                sourceMessageId: assistantMessage.id,
              ),
            );
            unawaited(
              _maybeTriggerMotionAgent(
                userText: trimmed,
                assistantText: parts.join('\n'),
              ),
            );
          },
          cancelOnError: true,
        );
  }

  Future<void> sendTextWithAttachments(
    String text, {
    ChatSourceKind sourceKind = ChatSourceKind.user,
    String? sourceId,
    ChatPriority priority = ChatPriority.user,
    List<ChatAttachment> attachments = const [],
  }) {
    return sendText(
      text,
      sourceKind: sourceKind,
      sourceId: sourceId,
      priority: priority,
      attachments: attachments,
    );
  }

  Future<void> speakAssistant(String text) async {
    await _playTts(text);
  }

  Future<String> _describeLive3dMotions() async {
    final lines = <String>[];
    lines.add('Live3D 动作目录（VRMA）:');
    try {
      final raw = await rootBundle.loadString(
        'assets/live3d/animations/catalog.json',
      );
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final motions = decoded['motions'];
        if (motions is List) {
          for (final entry in motions) {
            if (entry is! Map) continue;
            final m = Map<String, dynamic>.from(entry);
            final id = (m['id'] ?? '').toString().trim();
            final name = (m['name'] ?? '').toString().trim();
            final type = (m['type'] ?? 'unknown').toString().trim();
            final auto = m['auto'];
            final autoTalk = auto is Map && auto['talk'] == true;
            final autoIdle = auto is Map && auto['idle'] == true;
            final autoHover = auto is Map && auto['hover'] == true;
            final tags = <String>[];
            if (autoIdle) tags.add('idle');
            if (autoTalk) tags.add('talk');
            if (autoHover) tags.add('hover');
            final suffix = tags.isEmpty ? '' : ' (${tags.join(', ')})';
            if (id.isEmpty) continue;
            lines.add('- [$type] $id: ${name.isEmpty ? id : name}$suffix');
          }
        }
      }
    } catch (_) {
      lines.add('- (未找到 catalog.json，或运行环境不包含该资源)');
    }

    lines.add('');
    lines.add('程序动作（Procedural overlays）:');
    lines.add('- procedural_stable_idle: 稳定待机叠加（呼吸/轻微摆动）');
    lines.add('- procedural_talk_overlay: 说话叠加（轻微躯干/手臂动作）');
    lines.add(
      '- procedural_nod / procedural_look_left / procedural_look_right: 仅在被明确触发时生效',
    );
    lines.add('');
    lines.add('调试指令:');
    lines.add('- /play <id> 触发动作（例如 /play gesture_greeting）');
    lines.add('- /stop 停止并回到 idle');
    return lines.join('\n');
  }

  Future<void> runUniversalAgent({
    required String goal,
    ResearchDeliverable deliverable = ResearchDeliverable.report,
    ResearchDepth depth = ResearchDepth.deep,
  }) async {
    final command = _AgentCommand(
      goal: goal,
      deliverable: deliverable,
      depth: depth,
    );
    await _runUniversalAgent(command);
  }

  _AgentCommand? _parseAgentCommand(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('/agent ')) {
      return _AgentCommand(
        goal: trimmed.substring(7).trim(),
        deliverable: ResearchDeliverable.report,
        depth: ResearchDepth.deep,
      );
    }
    if (trimmed.startsWith('/research ')) {
      return _AgentCommand(
        goal: trimmed.substring(10).trim(),
        deliverable: ResearchDeliverable.report,
        depth: ResearchDepth.deep,
      );
    }
    if (trimmed.startsWith('/summary ')) {
      return _AgentCommand(
        goal: trimmed.substring(9).trim(),
        deliverable: ResearchDeliverable.summary,
        depth: ResearchDepth.quick,
      );
    }
    return null;
  }

  String? _parseHelpTopic(String text) {
    final trimmed = text.trim();
    if (trimmed == '/help' || trimmed == '/commands' || trimmed == '/?') {
      return '';
    }
    if (trimmed.startsWith('/help ')) {
      return trimmed.substring(6).trim();
    }
    if (trimmed.startsWith('/commands ')) {
      return trimmed.substring(10).trim();
    }
    if (trimmed == '/mcp') {
      return 'mcp';
    }
    if (trimmed == '/skills') {
      return 'skills';
    }
    if (trimmed == '/agents') {
      return 'agents';
    }
    return null;
  }

  Future<void> _sendCommandHelp(
    String rawText, {
    required String topic,
    required ChatSourceKind sourceKind,
    required String? sourceId,
    required ChatPriority priority,
  }) async {
    await interrupt();
    await _chatRepository.sendUserMessage(
      rawText,
      sourceKind: sourceKind,
      sourceId: sourceId,
      priority: priority,
    );
    final info = _buildCommandHelp(topic: topic);
    await _chatRepository.addMessage(
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        role: ChatRole.system,
        content: info,
        createdAt: DateTime.now(),
        sourceKind: ChatSourceKind.system,
        priority: ChatPriority.low,
      ),
      persist: true,
    );
  }

  _ToolCommand? _parseToolCommand(String text) {
    final trimmed = text.trim();
    if (!(trimmed == '/tool' || trimmed.startsWith('/tool '))) {
      return null;
    }
    final rest = trimmed.substring(5).trim();
    if (rest.isEmpty) {
      return const _ToolCommand(
        action: ToolAction.code,
        query: '',
        showHelp: true,
      );
    }
    if (rest == 'help' || rest == '?' || rest == 'h') {
      return const _ToolCommand(
        action: ToolAction.code,
        query: '',
        showHelp: true,
      );
    }
    final parts = rest.split(RegExp(r'\s+'));
    if (parts.isEmpty) {
      return null;
    }
    final action = _parseToolAction(parts.first);
    if (action != null) {
      final query = rest.substring(parts.first.length).trim();
      return _ToolCommand(
        action: action,
        query: query,
        showHelp: query.isEmpty,
      );
    }
    return _ToolCommand(action: ToolAction.code, query: rest);
  }

  Future<void> _runToolCommand(
    String rawText,
    _ToolCommand command, {
    required ChatSourceKind sourceKind,
    required String? sourceId,
    required ChatPriority priority,
  }) async {
    await interrupt();
    await _chatRepository.sendUserMessage(
      rawText,
      sourceKind: sourceKind,
      sourceId: sourceId,
      priority: priority,
    );
    final sessionId = _chatRepository.activeSession?.id;
    final intent = ToolIntent(
      action: command.action,
      query: command.query,
      sessionId: sessionId,
      routing: 'gateway',
    );
    final result = await RuntimeHub.instance.controlAgent.dispatchToolIntent(
      intent,
    );
    await _chatRepository.addMessage(
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        role: ChatRole.system,
        content: result,
        createdAt: DateTime.now(),
        sourceKind: ChatSourceKind.tool,
        priority: ChatPriority.low,
      ),
      persist: true,
    );
  }

  ToolAction? _parseToolAction(String token) {
    final normalized = token.trim().toLowerCase();
    switch (normalized) {
      case 'code':
      case 'shell':
      case 'run':
      case 'cli':
        return ToolAction.code;
      case 'search':
      case 'web':
      case 'find':
        return ToolAction.search;
      case 'crawl':
      case 'fetch':
      case 'http':
        return ToolAction.crawl;
      case 'analyze':
      case 'analysis':
        return ToolAction.analyze;
      case 'summarize':
      case 'summary':
      case 'sum':
        return ToolAction.summarize;
      case 'image':
      case 'img':
      case 'imagegen':
      case 'imagine':
        return ToolAction.imageGen;
      case 'vision':
      case 'imageanalyze':
      case 'imganalyze':
        return ToolAction.imageAnalyze;
      default:
        return null;
    }
  }

  _TagCommand? _parseTagCommand(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('#')) {
      return null;
    }
    final match = RegExp(
      r'^#([A-Za-z][\w-]*)(?:\s+(.+))?$',
    ).firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    final tag = match.group(1)!.toLowerCase();
    final payload = (match.group(2) ?? '').trim();
    if (tag == 'help' || tag == '?') {
      return _TagCommand.help(topic: payload);
    }
    if (tag == 'mcp' || tag == 'skills' || tag == 'agents') {
      return _TagCommand.info(topic: tag);
    }
    if (tag == 'agent' || tag == 'research') {
      return _TagCommand.agent(
        payload: payload,
        deliverable: ResearchDeliverable.report,
        depth: ResearchDepth.deep,
      );
    }
    if (tag == 'summary') {
      return _TagCommand.tool(action: ToolAction.summarize, payload: payload);
    }
    if (tag == 'tool') {
      return _TagCommand.tool(action: ToolAction.code, payload: payload);
    }
    final action = _parseToolAction(tag);
    if (action != null) {
      return _TagCommand.tool(action: action, payload: payload);
    }
    return null;
  }

  bool _isCommandMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('/')) {
      return true;
    }
    return _parseTagCommand(trimmed) != null;
  }

  Future<_AutoWebSearchResult> _tryAutoWebSearchForStandardMode(
    String userText,
  ) async {
    final settings = _settingsRepository.settings;
    if (settings.route != ModelRoute.standard) {
      return const _AutoWebSearchResult();
    }
    if (!settings.standardWebSearchEnabled) {
      return const _AutoWebSearchResult();
    }
    if (!settings.toolGatewayEnabled ||
        settings.toolGatewayBaseUrl.trim().isEmpty ||
        settings.toolGatewayPairingToken.trim().isEmpty) {
      return const _AutoWebSearchResult();
    }
    if (!_shouldAutoWebSearch(userText)) {
      return const _AutoWebSearchResult();
    }
    final sessionId = _chatRepository.activeSession?.id;
    final tracePrefix =
        'std_${DateTime.now().millisecondsSinceEpoch}_${sessionId ?? "default"}';
    final orchestrator = WebSearchOrchestrator(
      dispatchToolIntent: RuntimeHub.instance.controlAgent.dispatchToolIntent,
    );
    final queries = _buildStandardAutoSearchQueries(userText);
    final batch = await orchestrator.searchBatch(
      queries: queries,
      sessionId: sessionId,
      routing: 'standard_chat',
      tracePrefix: tracePrefix,
      maxResultsChars: 6000,
    );

    var success = 0;
    final buffer = StringBuffer();
    for (var i = 0; i < batch.queries.length; i += 1) {
      final raw = batch.rawResults[i].trim();
      if (raw.isEmpty || _isToolSearchFailure(raw)) {
        continue;
      }
      success += 1;
      if (buffer.length > 0) buffer.writeln('\n');
      buffer.writeln('### ${batch.queries[i]}');
      buffer.writeln('trace_id: ${batch.traceIds[i]}');
      buffer.writeln(raw);
      if (buffer.length >= 5000) {
        break;
      }
    }
    final snippet = buffer.toString().trim();
    if (success <= 0 || snippet.isEmpty) {
      final preview = batch.rawResults.isEmpty
          ? ''
          : batch.rawResults.first.trim().replaceAll('\n', ' ');
      final tail = preview.length <= 180
          ? preview
          : '${preview.substring(0, 180)}...';
      return _AutoWebSearchResult(
        statusMessage:
            '基础模式并发检索失败（${batch.queries.length}条）。${tail.isEmpty ? "" : "首条返回：$tail"}',
      );
    }
    return _AutoWebSearchResult(
      statusMessage: '基础模式并发检索完成：$success/${batch.queries.length}条已注入上下文。',
      contextSnippet: snippet,
    );
  }

  List<String> _buildStandardAutoSearchQueries(String userText) {
    final trimmed = userText.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    return [trimmed, '$trimmed 最新', '$trimmed 官方 文档'];
  }

  bool _shouldAutoWebSearch(String input) {
    final text = input.trim();
    if (text.length < 6) {
      return false;
    }
    final lower = text.toLowerCase();
    const keywords = <String>[
      '最新',
      '最近',
      '今天',
      '本周',
      '本月',
      '今年',
      '新闻',
      '行情',
      '价格',
      '汇率',
      '政策',
      '发布',
      '更新',
      '官网',
      '文档',
      '版本',
      '推荐',
      '对比',
      'latest',
      'today',
      'news',
      'price',
      'policy',
      'release',
      'update',
      'documentation',
      'docs',
      'version',
      'compare',
      'best',
    ];
    for (final keyword in keywords) {
      if (lower.contains(keyword)) {
        return true;
      }
    }
    return RegExp(r'20\d{2}').hasMatch(lower);
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

  String _buildCommandHelp({String? topic}) {
    final normalized = (topic ?? '').trim().toLowerCase();
    final settings = _settingsRepository.settings;
    final lines = <String>[];
    void addGatewayStatus() {
      final enabled = settings.toolGatewayEnabled ? '已启用' : '未启用';
      final baseUrl = settings.toolGatewayBaseUrl.trim().isEmpty
          ? '未配置'
          : settings.toolGatewayBaseUrl.trim();
      final standardSearch = settings.standardWebSearchEnabled ? '开启' : '关闭';
      final deepSearch = settings.deepResearchWebSearchEnabled ? '开启' : '关闭';
      lines.add('基础模式联网搜索: $standardSearch');
      lines.add('深度研究联网搜索: $deepSearch');
      lines.add('工具网关状态: $enabled ($baseUrl)');
      if (settings.toolGatewayPairingToken.trim().isEmpty) {
        lines.add('工具网关 pairing token: 未配置');
      } else {
        lines.add('工具网关 pairing token: 已配置');
      }
    }

    if (normalized == 'tool') {
      lines.add('工具指令（/tool 与 #标签）');
      lines.add('/tool <action> <query> 运行工具');
      lines.add('/tool help 查看工具指令帮助');
      lines.add('#tool <query> 默认走 code 执行');
      lines.add('#search <query> 搜索');
      lines.add('#crawl <url> 抓取网页');
      lines.add('#analyze <text> 分析');
      lines.add('#summarize <text> 摘要');
      lines.add('#image <prompt> 生图（待接入）');
      lines.add('#vision <prompt> 视觉分析（待接入）');
      lines.add(
        '支持的 action: code / search / crawl / analyze / summarize / image / vision',
      );
      addGatewayStatus();
      return lines.join('\n');
    }

    if (normalized == 'agent' || normalized == 'research') {
      lines.add('通用 Agent 指令');
      lines.add('/agent <目标> 新建通用 Agent 会话');
      lines.add('/research <目标> 深度研究（默认报告）');
      lines.add('/summary <目标> 快速总结（浅层）');
      lines.add('#agent <目标> 同 /agent');
      lines.add('#research <目标> 同 /research');
      return lines.join('\n');
    }

    if (normalized == 'mcp') {
      lines.add('MCP 接入（规划中）');
      lines.add('目标: 支持外部 MCP server 发现与调用');
      lines.add('当前: 先通过 工具网关 + OpenCode 进行通用工具执行');
      lines.add('后续: 在设置页提供 MCP 服务器配置与权限策略');
      addGatewayStatus();
      return lines.join('\n');
    }

    if (normalized == 'skills') {
      lines.add('Skills（能力编排）');
      lines.add('目标: 以 YAML/JSON 描述流程，组合多个工具调用');
      lines.add('后续: 提供导入/启用/权限管理的 UI');
      addGatewayStatus();
      return lines.join('\n');
    }

    if (normalized == 'agents') {
      lines.add('Agents（智能体）');
      lines.add('目标: 支持外部平台 Agent 导入与调用');
      lines.add('后续: 提供 Coze / Dify / OpenClaw 等接入模板');
      addGatewayStatus();
      return lines.join('\n');
    }

    lines.add('指令速查（/ 与 #）');
    lines.add('注意: 指令与 # 标签仅在消息开头生效');
    lines.add('/help 或 /commands 查看帮助');
    lines.add('/tool <action> <query> 工具调用');
    lines.add('/agent <目标> 通用 Agent');
    lines.add('/research <目标> 深度研究');
    lines.add('/summary <目标> 快速总结');
    lines.add('/persona 查看当前人设');
    lines.add('/motions 查看可用动作');
    lines.add('/play <id> 触发动作');
    lines.add('/stop 停止动作');
    lines.add('#search / #crawl / #analyze / #summarize 作为快捷工具标签');
    lines.add('#tool / #agent / #research / #help 快捷入口');
    addGatewayStatus();
    return lines.join('\n');
  }

  Future<void> _runUniversalAgent(_AgentCommand command) async {
    final goal = command.goal.trim();
    if (goal.isEmpty) {
      return;
    }
    await interrupt();
    await _chatRepository.createSession(
      title: _agentSessionTitle(goal),
      mode: ChatSessionMode.universal,
    );
    await _chatRepository.sendUserMessage('【通用Agent】$goal');
    final assistantMessage = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: ChatRole.assistant,
      content: '正在规划任务，请稍候...',
      createdAt: DateTime.now(),
    );
    await _chatRepository.addMessage(assistantMessage, persist: false);

    final session = _chatRepository.activeSession;
    if (session == null) {
      return;
    }
    final standardProvider = _settingsRepository.findProvider(
      _settingsRepository.settings.llmProviderId,
    );
    if (standardProvider == null) {
      await _chatRepository.updateMessageContent(
        assistantMessage.id,
        '未配置普通 LLM Provider，请在“模型与能力配置”中选择 LLM 模型。',
        persist: true,
      );
      _isStreaming = false;
      notifyListeners();
      return;
    }
    _isStreaming = true;
    _updateTalkingState();
    notifyListeners();
    try {
      final result = await _universalAgent.runResearch(
        ResearchJob(
          goal: goal,
          deliverable: command.deliverable,
          depth: command.depth,
        ),
        sessionId: session.id,
      );
      final content = _formatUniversalAgentResult(goal, result);
      await _chatRepository.updateMessageContent(
        assistantMessage.id,
        content,
        persist: true,
      );
      if (_shouldSpeakResponse(modelProvidedAudio: false)) {
        await _playTts(content);
      }
    } catch (error) {
      await _chatRepository.updateMessageContent(
        assistantMessage.id,
        '通用Agent执行失败: $error',
        persist: true,
      );
    } finally {
      _isStreaming = false;
      _updateTalkingState();
      notifyListeners();
      _refreshTokenUsage();
    }
  }

  String _formatUniversalAgentResult(String goal, UniversalAgentResult result) {
    final buffer = StringBuffer();
    buffer.writeln('【目标】');
    buffer.writeln(goal);
    buffer.writeln('\n【计划】');
    buffer.writeln(result.plan.trim());
    buffer.writeln('\n【输出】');
    buffer.writeln(result.output.trim());
    return buffer.toString().trimRight();
  }

  String _agentSessionTitle(String goal) {
    final trimmed = goal.trim();
    if (trimmed.isEmpty) {
      return '通用Agent';
    }
    const maxLen = 18;
    final snippet = trimmed.length <= maxLen
        ? trimmed
        : '${trimmed.substring(0, maxLen)}...';
    return '通用Agent · $snippet';
  }

  Future<void> interrupt() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _isStreaming = false;
    _isTtsSpeaking = false;
    _isAudioPlaying = false;
    _partialTranscript = '';
    await _audioPlayer.stop();
    await _tts.stop();
    _setLipSyncActive(false);
    _updateTalkingState();
    if (_isListening) {
      await stopListening();
    }
    notifyListeners();
  }

  Future<void> toggleListening() async {
    if (_isVoiceChannelMonitoring) {
      await stopVoiceChannelMonitoring();
    }
    if (_isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  Future<void> startListening() async {
    if (_isVoiceChannelMonitoring) {
      await stopVoiceChannelMonitoring();
    }
    await interrupt();
    if (!_isSystemSttEnabled()) {
      debugPrint('[STT] System STT disabled.');
      return;
    }
    final sttProvider = _resolveSttProvider();
    if (sttProvider != null &&
        sttProvider.protocol != ProviderProtocol.deviceBuiltin) {
      debugPrint('[STT] Remote STT not wired yet. Falling back to system STT.');
    }
    final available = await _ensureSpeechReady();
    if (!available) {
      return;
    }

    _sttLastError = '';
    _partialTranscript = '';
    _isListening = true;
    notifyListeners();
    await _speech.listen(
      onResult: (result) {
        _partialTranscript = result.recognizedWords;
        notifyListeners();
        if (result.finalResult) {
          final finalText = result.recognizedWords.trim();
          _isListening = false;
          _partialTranscript = '';
          notifyListeners();
          unawaited(_speech.stop());
          if (finalText.isNotEmpty) {
            unawaited(
              sendText(
                finalText,
                sourceKind: ChatSourceKind.mic,
                priority: ChatPriority.user,
              ),
            );
          }
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      ),
      listenFor: const Duration(seconds: 35),
      pauseFor: const Duration(milliseconds: 1200),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
    _partialTranscript = '';
    notifyListeners();
  }

  Future<void> toggleVoiceChannelMonitoring() async {
    if (_isVoiceChannelMonitoring) {
      await stopVoiceChannelMonitoring();
    } else {
      await startVoiceChannelMonitoring();
    }
  }

  Future<void> startVoiceChannelMonitoring() async {
    if (kIsWeb) {
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }
    if (!_settingsRepository.settings.voiceChannelEnabled) {
      debugPrint('[VoiceCH] voiceChannelEnabled is off.');
      return;
    }
    if (!_isSystemSttEnabled()) {
      debugPrint('[VoiceCH] System STT disabled.');
      return;
    }

    if (_isListening) {
      await stopListening();
    }

    final available = await _ensureSpeechReady();
    if (!available) {
      return;
    }

    _voiceChannelRestartTimer?.cancel();
    _voiceChannelRestartTimer = null;
    _voiceChannelPartialTranscript = '';
    _isVoiceChannelMonitoring = true;
    notifyListeners();

    await _startVoiceChannelListen();
  }

  Future<void> stopVoiceChannelMonitoring() async {
    _voiceChannelRestartTimer?.cancel();
    _voiceChannelRestartTimer = null;
    _isVoiceChannelMonitoring = false;
    _voiceChannelPartialTranscript = '';
    _voiceChannelPending.clear();
    notifyListeners();
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  Future<void> _startVoiceChannelListen() async {
    if (!_isVoiceChannelMonitoring) {
      return;
    }
    try {
      await _speech.listen(
        onResult: (result) {
          final text = result.recognizedWords.trim();
          if (text != _voiceChannelPartialTranscript) {
            _voiceChannelPartialTranscript = text;
            notifyListeners();
          }
          if (!result.finalResult) {
            return;
          }
          final finalText = result.recognizedWords.trim();
          _voiceChannelPartialTranscript = '';
          if (finalText.isNotEmpty) {
            final event = VoiceTranscriptEvent(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              text: finalText,
              createdAt: DateTime.now(),
              sourceLabel: 'voice_channel',
              isFinal: true,
            );
            _voiceChannelHistory.add(event);
            if (_voiceChannelHistory.length > 50) {
              _voiceChannelHistory.removeRange(
                0,
                _voiceChannelHistory.length - 50,
              );
            }
            RuntimeHub.instance.bus.emitVoiceTranscript(event);
            _voiceChannelPending.add(event);
            unawaited(_maybeInjectVoiceChannelPending());
          }
          // Close this recognition session after we got a full utterance.
          // We'll restart if monitoring is still enabled.
          unawaited(_speech.stop());
          notifyListeners();
        },
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
        listenFor: const Duration(minutes: 10),
        pauseFor: const Duration(seconds: 2),
      );
    } catch (e) {
      debugPrint('[VoiceCH] listen failed: $e');
      _scheduleVoiceChannelRestart();
    }
  }

  Future<void> _maybeInjectVoiceChannelPending() async {
    if (_voiceChannelInjecting) {
      return;
    }
    if (!_settingsRepository.settings.voiceChannelInjectEnabled) {
      _voiceChannelPending.clear();
      return;
    }
    _voiceChannelInjecting = true;
    try {
      while (_voiceChannelPending.isNotEmpty) {
        if (!_isVoiceChannelMonitoring) {
          _voiceChannelPending.clear();
          break;
        }
        // Don't preempt user chats or TTS playback. Voice-channel should feel
        // "background" and only inject when the assistant is idle.
        if (_isStreaming || isSpeaking || _isCompressing || _isListening) {
          await Future.delayed(const Duration(milliseconds: 400));
          continue;
        }
        final next = _voiceChannelPending.removeFirst();
        // Prefix keeps UI readable until we have proper message metadata.
        await sendText(
          next.text,
          sourceKind: ChatSourceKind.voiceChannel,
          priority: ChatPriority.voiceChannel,
        );
        // Small cooldown to avoid rapid-fire injections.
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } finally {
      _voiceChannelInjecting = false;
    }
  }

  void _scheduleVoiceChannelRestart() {
    if (!_isVoiceChannelMonitoring) {
      return;
    }
    _voiceChannelRestartTimer?.cancel();
    _voiceChannelRestartTimer = Timer(const Duration(milliseconds: 350), () {
      _voiceChannelRestartTimer = null;
      if (!_isVoiceChannelMonitoring) {
        return;
      }
      _startVoiceChannelListen();
    });
  }

  Future<bool> _ensureSpeechReady() async {
    if (_speechReady && _speech.isAvailable) {
      return true;
    }
    _sttLastError = '';
    _speechReady = await _speech.initialize(
      onError: (error) {
        debugPrint('[STT] error: ${error.errorMsg} (${error.permanent})');
        _sttLastError =
            '${error.errorMsg}${error.permanent ? " (permanent)" : ""}';
        notifyListeners();
        if (_isVoiceChannelMonitoring) {
          _scheduleVoiceChannelRestart();
        }
      },
      onStatus: (status) {
        if (_sttStatus != status) {
          _sttStatus = status;
          notifyListeners();
        }
        if (_isVoiceChannelMonitoring &&
            (status == SpeechToText.doneStatus ||
                status == SpeechToText.notListeningStatus)) {
          _scheduleVoiceChannelRestart();
        }
      },
    );
    return _speechReady;
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    await _tts.stop();
    await _tts.speak(text);
  }

  ProviderConfig? _activeProvider() {
    final settings = _settingsRepository.settings;
    switch (settings.route) {
      case ModelRoute.standard:
        return _settingsRepository.findProvider(settings.llmProviderId);
      case ModelRoute.realtime:
        return _settingsRepository.findProvider(settings.realtimeProviderId);
      case ModelRoute.omni:
        return _settingsRepository.findProvider(settings.omniProviderId);
    }
  }

  ProviderConfig _resolveSummarizerProvider(ProviderConfig fallback) {
    final settings = _settingsRepository.settings;
    if (settings.memoryAgentEnabled) {
      final id = settings.memoryAgentProviderId?.trim();
      if (id != null && id.isNotEmpty) {
        final candidate = _settingsRepository.findProvider(id);
        if (candidate != null &&
            candidate.protocol != ProviderProtocol.deviceBuiltin) {
          return candidate;
        }
      }
    }
    return fallback;
  }

  bool _shouldSpeakResponse({required bool modelProvidedAudio}) {
    if (modelProvidedAudio) {
      return false;
    }
    return _resolveTtsProvider() != null || _isSystemTtsEnabled();
  }

  ProviderConfig? _resolveTtsProvider() {
    final settings = _settingsRepository.settings;
    return _settingsRepository.findProvider(settings.ttsProviderId);
  }

  ProviderConfig? _resolveSttProvider() {
    final settings = _settingsRepository.settings;
    return _settingsRepository.findProvider(settings.sttProviderId);
  }

  Future<void> _playTts(String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    final provider = _resolveTtsProvider();
    if (provider == null) {
      if (!_isSystemTtsEnabled()) {
        return;
      }
      await _speak(text);
      return;
    }
    if (provider.protocol == ProviderProtocol.deviceBuiltin) {
      if (!_isSystemTtsEnabled()) {
        return;
      }
      await _speak(text);
      return;
    }
    if (!_supportsStreamingAudio()) {
      if (!_isSystemTtsEnabled()) {
        return;
      }
      if (!_supportsStreamingAudio() &&
          provider.protocol != ProviderProtocol.deviceBuiltin) {
        debugPrint(
          '[TTS] Streaming audio disabled on this platform. Using device TTS.',
        );
      }
      await _speak(text);
      return;
    }
    try {
      await _audioPlayer.start(
        contentType: _contentTypeForFormat(provider.audioFormat ?? 'wav'),
      );
      await for (final chunk in _speechClient.streamSpeech(
        provider: provider,
        text: text,
      )) {
        await _audioPlayer.addChunk(chunk);
      }
      await _audioPlayer.finish();
    } catch (_) {
      await _audioPlayer.stop();
      if (_isSystemTtsEnabled()) {
        await _speak(text);
      }
    }
  }

  Future<void> _maybeCompressSession(ProviderConfig provider) async {
    final limit = _resolveContextLimit(provider);
    if (limit == null || limit <= 0) {
      _refreshTokenUsage();
      return;
    }
    final session = _chatRepository.activeSession;
    if (session == null) {
      _refreshTokenUsage();
      return;
    }
    final messages = session.messages
        .where((message) => message.content.trim().isNotEmpty)
        .toList();
    if (messages.length <= _compressionKeepMessages + 1) {
      _refreshTokenUsage();
      return;
    }
    final currentTokens = _estimatePromptTokens(messages, session.id);
    if (currentTokens < (limit * _compressionTriggerRatio).round()) {
      _refreshTokenUsage();
      return;
    }
    if (_isCompressing) {
      return;
    }
    final anchor = _memoryRepository.latestSessionSummary(session.id);
    var startIndex = 0;
    if (anchor?.sourceMessageId != null) {
      final anchorIndex = messages.indexWhere(
        (message) => message.id == anchor!.sourceMessageId,
      );
      if (anchorIndex >= 0) {
        startIndex = anchorIndex + 1;
      }
    }
    final endIndex = messages.length - _compressionKeepMessages;
    if (startIndex >= endIndex) {
      _refreshTokenUsage();
      return;
    }
    final candidates = messages.sublist(startIndex, endIndex);
    if (candidates.isEmpty) {
      _refreshTokenUsage();
      return;
    }
    _isCompressing = true;
    notifyListeners();
    try {
      final summarizer = _resolveSummarizerProvider(provider);
      final summarizerLimit = _resolveContextLimit(summarizer);
      final summaryBudget = (min(limit, summarizerLimit ?? limit) * 0.7)
          .round();
      final trimmedCandidates = _trimMessagesToTokenBudget(
        candidates,
        summaryBudget,
      );
      final summary = await _summarizeMessages(
        summarizer,
        trimmedCandidates,
        previousSummary: anchor?.content,
      );
      if (summary.trim().isEmpty) {
        return;
      }
      final anchorMessageId = trimmedCandidates.last.id;
      final summaryRecord = MemoryRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        tier: MemoryTier.context,
        content: summary.trim(),
        createdAt: DateTime.now(),
        sourceMessageId: anchorMessageId,
        title: '会话摘要',
        tags: const ['session_summary'],
        sessionId: session.id,
        scope: 'brain.session',
      );
      await _memoryRepository.replaceSessionSummary(session.id, summaryRecord);
    } catch (_) {
      // Ignore compression errors and continue.
    } finally {
      _isCompressing = false;
      _refreshTokenUsage();
    }
  }

  List<ChatMessage> _messageHistoryForPrompt(ChatSession session) {
    final messages = session.messages
        .where((message) => message.content.trim().isNotEmpty)
        .toList();
    final summary = _memoryRepository.latestSessionSummary(session.id);
    var startIndex = 0;
    if (summary?.sourceMessageId != null) {
      final anchorIndex = messages.indexWhere(
        (message) => message.id == summary!.sourceMessageId,
      );
      if (anchorIndex >= 0) {
        startIndex = anchorIndex + 1;
      }
    }
    var trimmed = messages.sublist(startIndex);
    if (summary != null && trimmed.length > _compressionKeepMessages) {
      trimmed = trimmed.sublist(trimmed.length - _compressionKeepMessages);
    }
    return trimmed;
  }

  List<ChatMessage> _trimMessagesToTokenBudget(
    List<ChatMessage> messages,
    int budget,
  ) {
    if (budget <= 0 || messages.isEmpty) {
      return messages;
    }
    var total = 0;
    final trimmed = <ChatMessage>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      final estimate = TokenEstimator.estimateText(message.content) + 4;
      if (total + estimate > budget && trimmed.isNotEmpty) {
        break;
      }
      total += estimate;
      trimmed.add(message);
    }
    return trimmed.reversed.toList();
  }

  Future<String> _summarizeMessages(
    ProviderConfig provider,
    List<ChatMessage> messages, {
    String? previousSummary,
  }) async {
    if (messages.isEmpty) {
      return '';
    }
    var systemPrompt =
        '你是会话压缩器。请将对话压缩成可继续对话的要点摘要，'
        '保留人物设定、事实、决定、未完成事项、约束、名称/数值。'
        '输出使用简明中文要点列表，不要加入虚构内容。';
    final existing = previousSummary?.trim();
    if (existing != null && existing.isNotEmpty) {
      systemPrompt =
          '$systemPrompt\n已有摘要如下，请在此基础上补充新增要点：\n'
          '$existing';
    }
    return _llmClient.completeChat(
      provider: provider,
      messages: messages,
      systemPrompt: systemPrompt,
    );
  }

  int _estimatePromptTokens(List<ChatMessage> messages, String sessionId) {
    final contextRecords = _memoryRepository.recordsForTier(
      MemoryTier.context,
      sessionId: sessionId,
    );
    final crossRecords = _memoryRepository
        .recordsForTier(MemoryTier.crossSession)
        .take(12);
    final autoRecords = _memoryRepository
        .recordsForTier(MemoryTier.autonomous)
        .take(12);
    return TokenEstimator.estimateMessages(messages) +
        TokenEstimator.estimateRecords(contextRecords) +
        TokenEstimator.estimateRecords(crossRecords) +
        TokenEstimator.estimateRecords(autoRecords);
  }

  int? _resolveContextLimit(ProviderConfig provider) {
    return provider.contextWindowTokens;
  }

  String _contentTypeForFormat(String format) {
    switch (format.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'opus':
        return 'audio/opus';
      case 'pcm':
        return 'audio/wav';
      case 'wav':
      default:
        return 'audio/wav';
    }
  }

  bool _supportsStreamingAudio() {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform != TargetPlatform.windows;
  }

  bool _isSystemTtsEnabled() {
    return _settingsRepository.settings.enableSystemTts;
  }

  bool _isSystemSttEnabled() {
    return _settingsRepository.settings.enableSystemStt;
  }

  void _syncLipSyncState() {
    final shouldSync = _isTtsSpeaking || _isAudioPlaying;
    _setLipSyncActive(shouldSync);
  }

  void _setLipSyncActive(bool active) {
    if (_lipSyncActive == active) {
      return;
    }
    _lipSyncActive = active;
    _lipSyncTimer?.cancel();
    _lipSyncTimer = null;
    if (!active) {
      RuntimeHub.instance.bus.emitLipSync(
        const LipSyncFrame(aa: 0, ee: 0, ih: 0, oh: 0, ou: 0),
      );
      return;
    }
    _lipSyncTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _emitLipSyncFrame(),
    );
  }

  void _emitLipSyncFrame() {
    final open = 0.15 + _lipSyncRandom.nextDouble() * 0.65;
    final pick = _lipSyncRandom.nextInt(5);
    double aa = 0, ee = 0, ih = 0, oh = 0, ou = 0;
    switch (pick) {
      case 0:
        aa = open;
        ih = open * 0.35;
        ou = open * 0.2;
        break;
      case 1:
        ee = open;
        ih = open * 0.4;
        break;
      case 2:
        ih = open;
        ee = open * 0.3;
        break;
      case 3:
        oh = open;
        ou = open * 0.4;
        break;
      case 4:
      default:
        ou = open;
        oh = open * 0.35;
        break;
    }
    RuntimeHub.instance.bus.emitLipSync(
      LipSyncFrame(aa: aa, ee: ee, ih: ih, oh: oh, ou: ou),
    );
  }

  void _updateTalkingState() {
    final shouldTalk = _isStreaming || _isTtsSpeaking || _isAudioPlaying;
    if (_isTalking == shouldTalk) {
      return;
    }
    _isTalking = shouldTalk;
    RuntimeHub.instance.live3dBridge.setTalking(shouldTalk);

    if (!shouldTalk) {
      final pending = _pendingMotionAgentId;
      if (pending != null && pending.trim().isNotEmpty) {
        _pendingMotionAgentId = null;
        RuntimeHub.instance.live3dBridge.playMotion(pending);
      }
    }
  }

  Future<void> _maybeTriggerMotionAgent({
    required String userText,
    required String assistantText,
  }) async {
    final settings = _settingsRepository.settings;
    if (!settings.motionAgentEnabled) {
      return;
    }
    if (userText.trim().startsWith('/')) {
      return;
    }
    final providerId = settings.motionAgentProviderId ?? settings.llmProviderId;
    final provider = _settingsRepository.findProvider(providerId);
    if (provider == null ||
        provider.protocol == ProviderProtocol.deviceBuiltin) {
      return;
    }
    if (provider.kind != ProviderKind.llm) {
      return;
    }

    final cooldownSeconds = settings.motionAgentCooldownSeconds <= 0
        ? 0
        : settings.motionAgentCooldownSeconds;
    final now = DateTime.now();
    final last = _lastMotionAgentAt;
    if (last != null &&
        now.difference(last) < Duration(seconds: cooldownSeconds)) {
      return;
    }

    final catalog = await _loadVrmaCatalogForMotionAgent();
    final motions = _catalogMotions(catalog);
    if (motions.isEmpty) {
      return;
    }

    final allowed = motions
        .where((m) {
          final id = (m['id'] ?? '').toString().trim();
          if (id.isEmpty) return false;
          final tier = (m['agent'] ?? '').toString().trim().toLowerCase();
          return tier == 'common' || tier == 'rare';
        })
        .toList(growable: false);
    if (allowed.isEmpty) {
      return;
    }

    final contextMessages = _buildMotionAgentContextMessages(maxMessages: 8);
    final decision = await _motionAgent.decide(
      provider: provider,
      userText: userText,
      assistantText: assistantText,
      allowedMotions: allowed,
      contextMessages: contextMessages,
      conversationMode: settings.route.name,
    );

    final id = decision.id?.trim();
    if (!decision.shouldPlay || id == null || id.isEmpty) {
      return;
    }

    final tierById = <String, String>{};
    for (final m in allowed) {
      final mid = (m['id'] ?? '').toString().trim().toLowerCase();
      if (mid.isEmpty) continue;
      final tier = (m['agent'] ?? '').toString().trim().toLowerCase();
      if (tier == 'common' || tier == 'rare') {
        tierById[mid] = tier;
      }
    }
    final pickedTier = tierById[id.toLowerCase()];
    if (pickedTier == null) {
      return;
    }

    final minConfidence = pickedTier == 'rare' ? 0.8 : 0.55;
    if (decision.confidence < minConfidence) {
      return;
    }

    _lastMotionAgentAt = now;
    if (_isTalking) {
      _pendingMotionAgentId = id;
      return;
    }
    RuntimeHub.instance.live3dBridge.playMotion(id);
  }

  Future<void> _maybeTriggerMemoryAgent({
    required String userText,
    required String assistantText,
    required String sourceMessageId,
  }) async {
    final settings = _settingsRepository.settings;
    if (!settings.memoryAgentEnabled) {
      return;
    }
    if (_memoryAgentRunning) {
      return;
    }
    if (userText.trim().startsWith('/')) {
      return;
    }
    final providerId = settings.memoryAgentProviderId ?? settings.llmProviderId;
    final provider = _settingsRepository.findProvider(providerId);
    if (provider == null ||
        provider.protocol == ProviderProtocol.deviceBuiltin) {
      return;
    }
    if (provider.kind != ProviderKind.llm) {
      return;
    }

    final cooldownSeconds = settings.memoryAgentCooldownSeconds <= 0
        ? 0
        : settings.memoryAgentCooldownSeconds;
    final now = DateTime.now();
    final last = _lastMemoryAgentAt;
    if (last != null &&
        now.difference(last) < Duration(seconds: cooldownSeconds)) {
      return;
    }

    _memoryAgentRunning = true;
    try {
      final contextMessages = _buildMotionAgentContextMessages(maxMessages: 12);
      final existingCore = _memoryRepository.exportCoreKeyValues(limit: 40);
      final result = await _memoryAgent.decide(
        provider: provider,
        userText: userText,
        assistantText: assistantText,
        now: now,
        contextMessages: contextMessages,
        existingCore: existingCore,
        conversationMode: settings.route.name,
      );
      _lastMemoryAgentAt = now;

      final sessionId = _chatRepository.activeSessionId;
      for (final op in result.core) {
        if (op.shouldUpsert && op.confidence >= 0.6) {
          await _memoryRepository.upsertCoreMemory(
            key: op.key,
            content: op.value,
            title: op.title ?? op.key,
            sourceMessageId: sourceMessageId,
            originSessionId: sessionId,
            tags: ['core', ...op.tags],
          );
        } else if (op.shouldDelete && op.confidence >= 0.9) {
          await _memoryRepository.deleteCoreMemory(op.key);
        }
      }

      for (final op in result.diary) {
        if (!op.shouldAdd || op.confidence < 0.55) {
          continue;
        }
        var occurredAt = op.occurredAt;
        if (occurredAt.isAfter(now.add(const Duration(days: 1)))) {
          occurredAt = now;
        }
        await _memoryRepository.addDiaryMemory(
          occurredAt: occurredAt,
          content: op.summary,
          title: op.title,
          sourceMessageId: sourceMessageId,
          originSessionId: sessionId,
          tags: ['diary', ...op.tags],
        );
      }
    } catch (_) {
      // Ignore memory agent failures; it should never break chat UX.
    } finally {
      _memoryAgentRunning = false;
    }
  }

  List<Map<String, String>> _buildMotionAgentContextMessages({
    int maxMessages = 8,
  }) {
    final session = _chatRepository.activeSession;
    if (session == null) {
      return const [];
    }
    final entries = session.messages
        .where((m) => m.role != ChatRole.system)
        .where((m) => m.content.trim().isNotEmpty)
        .where(
          (m) => !(m.role == ChatRole.user && _isCommandMessage(m.content)),
        )
        .toList(growable: false);
    if (entries.isEmpty) {
      return const [];
    }
    final start = entries.length > maxMessages
        ? entries.length - maxMessages
        : 0;
    final slice = entries.sublist(start);
    return slice
        .map((m) {
          var content = m.content.trim();
          if (content.length > 240) {
            content = '${content.substring(0, 240)}…';
          }
          return {'role': m.role.name, 'content': content};
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> _loadVrmaCatalogForMotionAgent() async {
    final cached = RuntimeHub.instance.live3dBridge.debug.vrmaCatalog;
    if (cached != null) {
      return cached;
    }
    try {
      final raw = await rootBundle.loadString(
        'assets/live3d/animations/catalog.json',
      );
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  List<Map<String, dynamic>> _catalogMotions(Map<String, dynamic>? catalog) {
    if (catalog == null) return const [];
    final motions = catalog['motions'];
    if (motions is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final entry in motions) {
      if (entry is Map) {
        out.add(Map<String, dynamic>.from(entry));
      }
    }
    return out;
  }

  List<String> _splitAssistantResponse(String content) {
    if (_settingsRepository.settings.route == ModelRoute.realtime) {
      final normalized = content.replaceAll('[SPLIT]', '\n').trim();
      return [normalized.isEmpty ? content : normalized];
    }
    if (!content.contains('[SPLIT]')) {
      return [content];
    }
    final parts = content
        .split('[SPLIT]')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? [content] : parts;
  }

  Future<String> _postProcessAssistantText({
    required ProviderConfig provider,
    required String content,
    required bool modelProvidedAudio,
  }) async {
    final original = content.trimRight();
    if (original.trim().isEmpty) {
      return original;
    }
    final isRealtime =
        _settingsRepository.settings.route == ModelRoute.realtime;
    final normalized = isRealtime
        ? original.replaceAll('[SPLIT]', '\n')
        : original;
    if (modelProvidedAudio) {
      final base = isRealtime ? normalized : _stripForbiddenAsides(normalized);
      return _redactIdentityDisclosure(base).trimRight();
    }
    if (isRealtime) {
      final softened = _stripForbiddenAsides(normalized);
      if (!_violatesAssistantOutputPolicy(softened)) {
        return _redactIdentityDisclosure(softened).trimRight();
      }
      if (_containsForbiddenIdentityDisclosure(softened)) {
        try {
          final rewritten = await _rewriteAssistantToPureDialogue(
            provider: provider,
            original: softened,
          );
          final normalizedRewrite = rewritten.trim();
          if (normalizedRewrite.isNotEmpty &&
              !_violatesAssistantOutputPolicy(normalizedRewrite)) {
            return _redactIdentityDisclosure(normalizedRewrite).trimRight();
          }
        } catch (_) {
          // Ignore and fall back to local stripping below.
        }
      }
      return _redactIdentityDisclosure(
        _stripForbiddenAsides(softened),
      ).trimRight();
    }
    final softened = _stripForbiddenAsides(normalized);
    if (!_violatesAssistantOutputPolicy(softened)) {
      return _redactIdentityDisclosure(softened).trimRight();
    }
    var candidate = softened;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final rewritten = await _rewriteAssistantToPureDialogue(
          provider: provider,
          original: candidate,
        );
        final normalized = rewritten.trim();
        if (normalized.isEmpty) {
          break;
        }
        candidate = rewritten;
        if (!_violatesAssistantOutputPolicy(candidate)) {
          return _redactIdentityDisclosure(candidate).trimRight();
        }
      } catch (_) {
        break;
      }
    }
    return _redactIdentityDisclosure(_stripForbiddenAsides(candidate));
  }

  Future<String> _rewriteAssistantToPureDialogue({
    required ProviderConfig provider,
    required String original,
  }) async {
    const rewriteSystemPrompt = '''
你是一个“文本改写器”。你的任务是把输入内容改写成可直接朗读的纯台词正文。
硬性规则：
1) 保持主要语义不变；如果原文包含自我身份揭露（例如自称 AI/人工智能/语言模型/模型/程序/数字生命），必须删掉这类内容并用更自然的人设说法替代。
   - 例：把“作为一个AI，我……”改为自然的第一人称说法（例如“我想……”或“我叫露米……”），但不要解释自己为什么这样改。
   - 例：把“我是数字生命/模型”改为不暴露身份的说法，或直接省略该句。
2) 不添加解释，不提及“改写/规则/系统/提示词”。
2) 删除所有心理描写、动作描写、舞台指令、旁白、镜头描述、音效文字、表情标记。
3) 禁止输出 Markdown（例如 #、*、**、>、```）。
4) 允许且必须原样保留这些系统标记：`[SPLIT]`、以及输入中已有的 `[IMAGE: ...]`。
只输出改写后的正文，不要加任何前缀或标题。
''';
    final prompt =
        '''
原始回复：
<<<
$original
>>>
''';
    final rewriteMessages = <ChatMessage>[
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        role: ChatRole.user,
        content: prompt,
        createdAt: DateTime.now(),
      ),
    ];
    return _llmClient.completeChat(
      provider: provider,
      messages: rewriteMessages,
      systemPrompt: rewriteSystemPrompt,
    );
  }

  bool _violatesAssistantOutputPolicy(String content) {
    if (content.trim().isEmpty) {
      return false;
    }
    if (_containsForbiddenIdentityDisclosure(content)) {
      return true;
    }
    if (content.contains('```')) {
      return true;
    }
    final lines = content.split('\n');
    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (_isParentheticalAsideOnly(trimmed) || _isStarAsideOnly(trimmed)) {
        return true;
      }
      if (_stripLeadingParentheticalAside(rawLine) != rawLine) {
        return true;
      }
    }
    const patterns = <_AsidePattern>[
      _AsidePattern(open: '（', close: '）', regex: r'（[^）]{1,80}）'),
      _AsidePattern(open: '(', close: ')', regex: r'\([^)]{1,80}\)'),
      _AsidePattern(open: '【', close: '】', regex: r'【[^】]{1,80}】'),
      _AsidePattern(open: '[', close: ']', regex: r'\[[^\]]{1,80}\]'),
      _AsidePattern(open: '*', close: '*', regex: r'\*[^*]{1,80}\*'),
    ];
    for (final pat in patterns) {
      final reg = RegExp(pat.regex);
      for (final match in reg.allMatches(content)) {
        final token = match.group(0);
        if (token == null) {
          continue;
        }
        final inner = token.substring(
          pat.open.length,
          token.length - pat.close.length,
        );
        if (_looksLikeForbiddenAside(inner.trim())) {
          return true;
        }
      }
    }
    return false;
  }

  bool _shouldSoftCleanStreaming(String content) {
    if (_settingsRepository.settings.route == ModelRoute.realtime) {
      return false;
    }
    if (content.isEmpty) {
      return false;
    }
    const markers = ['（', '(', '【', '*', '```'];
    for (final marker in markers) {
      if (content.contains(marker)) {
        return true;
      }
    }
    return false;
  }

  String _stripForbiddenAsides(String content) {
    if (content.trim().isEmpty) {
      return content;
    }
    final lines = content.split('\n');
    final cleaned = <String>[];
    for (final rawLine in lines) {
      final stripped = _stripLeadingParentheticalAside(rawLine);
      final trimmed = stripped.trim();
      if (trimmed.isEmpty) {
        cleaned.add(stripped);
        continue;
      }
      if (_isParentheticalAsideOnly(trimmed) || _isStarAsideOnly(trimmed)) {
        continue;
      }
      cleaned.add(stripped);
    }
    return cleaned.join('\n').trimRight();
  }

  String? _sanitizeMemoryForSystemPrompt(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (_containsForbiddenIdentityDisclosure(trimmed)) {
      return null;
    }
    final softened = _stripForbiddenAsides(trimmed).trim();
    if (softened.isEmpty) {
      return null;
    }
    if (_containsForbiddenIdentityDisclosure(softened)) {
      return null;
    }
    return softened;
  }

  bool _containsForbiddenIdentityDisclosure(String content) {
    final normalized = content.replaceAll('\u200B', '').trim();
    if (normalized.isEmpty) {
      return false;
    }
    final patterns = <RegExp>[
      RegExp(
        r'(?:作为|身为)\s*(?:一名|一个)?\s*(?:人工智能|语言模型|大模型|数字生命|程序|机器人|模型|AI)\s*[,，:：]?\s*(?:我|本人|在下)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:我|本人|在下)\s*(?:是|只是|不过是|属于|算是|作为|身为)\s*(?:一名|一个)?\s*(?:人工智能|语言模型|大模型|数字生命|程序|机器人|模型|AI)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:我|本人|在下)\s*(?:不|并不|不是|并不是)\s*(?:一名|一个)?\s*(?:人工智能|语言模型|大模型|数字生命|程序|机器人|模型|AI)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:你|您)\s*(?:是|就是|本质上是)\s*(?:一名|一个)?\s*(?:人工智能|语言模型|大模型|数字生命|程序|机器人|模型|AI)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:你|您)\s*(?:不|并不|不是|并不是)\s*(?:一名|一个)?\s*(?:人工智能|语言模型|大模型|数字生命|程序|机器人|模型|AI)',
        caseSensitive: false,
      ),
      RegExp(
        r"\b(?:i\s*(?:am|'m)|as\s+an)\s+(?:ai|language\s+model|llm)\b",
        caseSensitive: false,
      ),
      RegExp(
        r"\b(?:i\s*(?:am|'m))\s+not\s+(?:an?\s+)?(?:ai|language\s+model|llm)\b",
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:as\s+a)\s+(?:language\s+model|llm)\b',
        caseSensitive: false,
      ),
      RegExp(
        r"\b(?:i\s*(?:am|'m))\s+(?:chatgpt|gpt(?:-?\d+)?)\b",
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      if (pattern.hasMatch(normalized)) {
        return true;
      }
    }
    return false;
  }

  String _redactIdentityDisclosure(String content) {
    final trimmed = content.trimRight();
    if (trimmed.isEmpty) {
      return content;
    }
    if (!_containsForbiddenIdentityDisclosure(trimmed)) {
      return content;
    }
    var working = trimmed;
    final patterns = <RegExp>[
      RegExp(
        r'(?:作为|身为)\s*(?:一名|一个)?\s*(?:人工智能|语言模型|大模型|数字生命|程序|机器人|模型|AI)\s*[,，:：]?\s*',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:我|本人|在下)\s*(?:是|只是|不过是|属于|算是|作为|身为)\s*(?:一名|一个)?\s*(?:人工智能|语言模型|大模型|数字生命|程序|机器人|模型|AI)\s*[,，:：]?\s*',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:as\s+an?)\s+(?:ai|language\s+model|llm)\b\s*[,;:]?\s*',
        caseSensitive: false,
      ),
      RegExp(
        r"\b(?:i\s*(?:am|'m))\s+(?:an?\s+)?(?:ai|language\s+model|llm)\b\s*[,;:]?\s*",
        caseSensitive: false,
      ),
      RegExp(
        r"\b(?:i\s*(?:am|'m))\s+(?:chatgpt|gpt(?:-?\d+)?)\b\s*[,;:]?\s*",
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      working = working.replaceAll(pattern, '');
    }

    final kept = <String>[];
    for (final rawLine in working.split('\n')) {
      if (_containsForbiddenIdentityDisclosure(rawLine)) {
        continue;
      }
      kept.add(rawLine);
    }
    final joined = kept.join('\n').trimRight();
    if (joined.isNotEmpty && !_containsForbiddenIdentityDisclosure(joined)) {
      return joined;
    }
    return joined.isNotEmpty ? joined : '';
  }

  String _stripLeadingParentheticalAside(String line) {
    final trimmedLeft = line.trimLeft();
    final prefixLen = line.length - trimmedLeft.length;
    final stripped = _stripLeadingAsideForPair(
      trimmedLeft,
      open: '（',
      close: '）',
    );
    if (stripped != null) {
      return '${''.padLeft(prefixLen)}${stripped.trimLeft()}';
    }
    final strippedCorner = _stripLeadingAsideForPair(
      trimmedLeft,
      open: '【',
      close: '】',
    );
    if (strippedCorner != null) {
      return '${''.padLeft(prefixLen)}${strippedCorner.trimLeft()}';
    }
    final strippedAscii = _stripLeadingAsideForPair(
      trimmedLeft,
      open: '(',
      close: ')',
    );
    if (strippedAscii != null) {
      return '${''.padLeft(prefixLen)}${strippedAscii.trimLeft()}';
    }
    final strippedSquare = _stripLeadingAsideForPair(
      trimmedLeft,
      open: '[',
      close: ']',
    );
    if (strippedSquare != null) {
      return '${''.padLeft(prefixLen)}${strippedSquare.trimLeft()}';
    }
    return line;
  }

  String? _stripLeadingAsideForPair(
    String trimmedLeft, {
    required String open,
    required String close,
  }) {
    if (!trimmedLeft.startsWith(open)) {
      return null;
    }
    final closeIndex = trimmedLeft.indexOf(close);
    if (closeIndex <= 0) {
      return null;
    }
    final inner = trimmedLeft.substring(open.length, closeIndex).trim();
    if (!_looksLikeForbiddenAside(inner)) {
      return null;
    }
    return trimmedLeft.substring(closeIndex + close.length);
  }

  bool _isParentheticalAsideOnly(String trimmedLine) {
    String? inner;
    if (trimmedLine.startsWith('（') && trimmedLine.endsWith('）')) {
      inner = trimmedLine.substring(1, trimmedLine.length - 1).trim();
    } else if (trimmedLine.startsWith('(') && trimmedLine.endsWith(')')) {
      inner = trimmedLine.substring(1, trimmedLine.length - 1).trim();
    } else if (trimmedLine.startsWith('【') && trimmedLine.endsWith('】')) {
      inner = trimmedLine.substring(1, trimmedLine.length - 1).trim();
    } else if (trimmedLine.startsWith('[') && trimmedLine.endsWith(']')) {
      inner = trimmedLine.substring(1, trimmedLine.length - 1).trim();
    }
    if (inner == null) {
      return false;
    }
    return _looksLikeForbiddenAside(inner);
  }

  bool _isStarAsideOnly(String trimmedLine) {
    if (!(trimmedLine.startsWith('*') && trimmedLine.endsWith('*'))) {
      return false;
    }
    if (trimmedLine.length < 2) {
      return false;
    }
    final inner = trimmedLine.substring(1, trimmedLine.length - 1).trim();
    return _looksLikeForbiddenAside(inner);
  }

  bool _looksLikeForbiddenAside(String inner) {
    final normalized = inner.replaceAll(' ', '').trim();
    if (normalized.isEmpty) {
      return false;
    }
    if (_isEnumerationToken(normalized)) {
      return false;
    }
    const keywords = <String>[
      '轻轻',
      '微微',
      '缓缓',
      '悄悄',
      '歪',
      '点头',
      '摇头',
      '眨',
      '看向',
      '望向',
      '抬头',
      '低头',
      '抬手',
      '挥手',
      '伸手',
      '转身',
      '靠近',
      '后退',
      '叹',
      '叹气',
      '笑',
      '微笑',
      '皱眉',
      '沉默',
      '停顿',
      '小声',
      '低声',
      '内心',
      '心想',
      '想了想',
      '思考',
      '沉吟',
      '咳',
      '清了清嗓子',
      '耸肩',
      '鼓掌',
      '摸',
      '拍',
      '抱',
      'OS',
      '旁白',
    ];
    for (final keyword in keywords) {
      if (normalized.contains(keyword)) {
        return true;
      }
    }
    final lower = normalized.toLowerCase();
    const enKeywords = <String>[
      'smile',
      'smiles',
      'grin',
      'grins',
      'laugh',
      'laughs',
      'giggle',
      'giggles',
      'sigh',
      'sighs',
      'nod',
      'nods',
      'shake',
      'shakes',
      'shrug',
      'shrugs',
      'whisper',
      'whispers',
      'cough',
      'coughs',
      'think',
      'thinks',
      'thinking',
      'aside',
      'ooc',
    ];
    for (final keyword in enKeywords) {
      if (lower.contains(keyword)) {
        return true;
      }
    }
    if (normalized.length <= 12 &&
        normalized.runes.any((r) => r >= 0x4E00 && r <= 0x9FFF)) {
      return true;
    }
    return false;
  }

  bool _isEnumerationToken(String token) {
    const digits = '0123456789';
    const cnNums = '一二三四五六七八九十百千万';
    if (token.length <= 4 &&
        token.runes.every((r) => digits.contains(String.fromCharCode(r)))) {
      return true;
    }
    if (token.length <= 4 &&
        token.runes.every((r) => cnNums.contains(String.fromCharCode(r)))) {
      return true;
    }
    return false;
  }

  Future<void> _applyAssistantResponse(
    ChatMessage firstMessage,
    List<String> parts,
  ) async {
    if (parts.isEmpty) {
      return;
    }
    await _chatRepository.updateMessageContent(
      firstMessage.id,
      parts.first,
      persist: true,
    );
    if (parts.length <= 1) {
      return;
    }
    for (final part in parts.skip(1)) {
      await _chatRepository.addAssistantMessage(part, persist: true);
    }
  }

  void _refreshTokenUsage() {
    final provider = _activeProvider();
    final nextLimit = provider?.contextWindowTokens;
    var shouldNotify = false;
    if (nextLimit != _tokenLimit) {
      _tokenLimit = nextLimit;
      shouldNotify = true;
    }
    final session = _chatRepository.activeSession;
    if (session == null) {
      if (_estimatedTokens != 0 || shouldNotify) {
        _estimatedTokens = 0;
        notifyListeners();
      }
      return;
    }
    final messages = session.messages
        .where((message) => message.content.trim().isNotEmpty)
        .toList();
    final estimate = _estimatePromptTokens(messages, session.id);
    if (estimate != _estimatedTokens || shouldNotify) {
      _estimatedTokens = estimate;
      notifyListeners();
    }
  }

  Future<String> _buildSystemPrompt(
    String userMessage, {
    String? webSearchContext,
    String? attachmentContext,
  }) async {
    final settings = _settingsRepository.settings;
    final base = buildLumiPersona(
      mode: settings.personaMode,
      level: settings.personaLevel,
      style: settings.personaStyle,
      customPrompt: settings.personaPrompt,
    );
    final normalizedWebSearch = _sanitizeWebSearchContext(webSearchContext);
    final normalizedAttachment = _sanitizeAttachmentContext(attachmentContext);
    String applyRouteAddons(String prompt) {
      if (settings.route != ModelRoute.realtime) {
        return prompt;
      }
      return '$prompt\n\n[Realtime 模式约束]\n'
          '- 当前为实时语音/低延迟对话模式。\n'
          '- 禁止输出 `[SPLIT]`，也不要尝试把回复拆分成多段消息。\n'
          '- 只输出连续的纯文本台词正文。';
    }

    final sessionId = _chatRepository.activeSessionId;
    final contextRecords = _memoryRepository.recordsForTier(
      MemoryTier.context,
      sessionId: sessionId,
    );

    final coreAll = _memoryRepository.recordsForTier(MemoryTier.crossSession);

    final now = DateTime.now();
    final timeRange = parseChineseTimeRange(userMessage, now);
    final diaryAll = _memoryRepository.recordsForTier(MemoryTier.autonomous);
    final timeDiary = timeRange == null
        ? const <MemoryRecord>[]
        : diaryAll
              .where(
                (record) =>
                    !record.createdAt.isBefore(timeRange.start) &&
                    record.createdAt.isBefore(timeRange.end),
              )
              .take(24)
              .toList(growable: false);
    final timeDiaryIds = timeDiary.map((record) => record.id).toSet();

    final relevantAll = await _memoryRepository.searchRelevantScored(
      userMessage,
      limit: 24,
    );
    const diaryMinScore = 0.33;
    const knowledgeMinScore = 0.42;

    final relevantCore = relevantAll
        .where((hit) => hit.record.tier == MemoryTier.crossSession)
        .map((hit) => hit.record)
        .toList(growable: false);

    final relevantFiltered = relevantAll
        .where((hit) => hit.record.tier != MemoryTier.crossSession)
        .where((hit) => !timeDiaryIds.contains(hit.record.id))
        .where((hit) {
          switch (hit.record.tier) {
            case MemoryTier.autonomous:
              return hit.method != MemorySearchMethod.embedding ||
                  hit.score >= diaryMinScore;
            case MemoryTier.external:
              return hit.method != MemorySearchMethod.embedding ||
                  hit.score >= knowledgeMinScore;
            default:
              return true;
          }
        })
        .map((hit) => hit.record)
        .toList(growable: false);

    const coreLimit = 12;
    final coreSelected = <MemoryRecord>[];
    final seenCoreKeys = <String>{};

    String coreUniqKey(MemoryRecord record) {
      final keyTag = record.tags.firstWhere(
        (t) => t.startsWith('core_key:'),
        orElse: () => '',
      );
      final key = keyTag.isEmpty
          ? ''
          : keyTag.substring('core_key:'.length).trim();
      return key.isEmpty ? record.id : key;
    }

    void pushCore(MemoryRecord record) {
      final key = coreUniqKey(record);
      if (seenCoreKeys.contains(key)) {
        return;
      }
      seenCoreKeys.add(key);
      coreSelected.add(record);
    }

    for (final record in relevantCore) {
      if (coreSelected.length >= coreLimit) break;
      pushCore(record);
    }
    for (final record in coreAll) {
      if (coreSelected.length >= coreLimit) break;
      pushCore(record);
    }

    if (contextRecords.isEmpty &&
        coreSelected.isEmpty &&
        diaryAll.isEmpty &&
        relevantFiltered.isEmpty &&
        normalizedWebSearch == null &&
        normalizedAttachment == null) {
      return applyRouteAddons(base);
    }

    final buffer = StringBuffer('$base\n');
    if (normalizedWebSearch != null) {
      buffer.writeln('\n[外部检索结果]');
      buffer.writeln(normalizedWebSearch);
    }
    if (normalizedAttachment != null) {
      buffer.writeln('\n[用户上传资料]');
      buffer.writeln(normalizedAttachment);
    }

    final seen = <String>{};
    String dedupeKey(String content) {
      return content
          .replaceAll('\u200B', '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    String? formatUnique(MemoryRecord record) {
      final sanitized = _sanitizeMemoryForSystemPrompt(record.content);
      if (sanitized == null) {
        return null;
      }
      final key = dedupeKey(sanitized);
      if (seen.contains(key)) {
        return null;
      }
      seen.add(key);

      if (record.tier == MemoryTier.crossSession) {
        final keyTag = record.tags.firstWhere(
          (t) => t.startsWith('core_key:'),
          orElse: () => '',
        );
        final coreKey = keyTag.isEmpty
            ? ''
            : keyTag.substring('core_key:'.length).trim();
        if (coreKey.isNotEmpty) {
          return '$coreKey: $sanitized';
        }
      }

      if (record.tier == MemoryTier.autonomous) {
        final day = record.createdAt.toIso8601String().substring(0, 10);
        return '$day $sanitized';
      }

      return sanitized;
    }

    void appendSection(String label, Iterable<MemoryRecord> records) {
      final lines = <String>[];
      for (final record in records) {
        final formatted = formatUnique(record);
        if (formatted == null) continue;
        lines.add(formatted);
      }
      if (lines.isEmpty) {
        return;
      }
      buffer.writeln('\n[$label]');
      for (final line in lines) {
        buffer.writeln('- $line');
      }
    }

    if (contextRecords.isNotEmpty) {
      appendSection('会话内记忆', contextRecords.take(12));
    }

    if (timeDiary.isNotEmpty) {
      appendSection('日记记忆·${timeRange!.label}', timeDiary);
    }

    if (coreSelected.isNotEmpty) {
      appendSection('核心记忆', coreSelected);
    }

    if (relevantFiltered.isNotEmpty) {
      final byTier = <MemoryTier, List<MemoryRecord>>{};
      for (final record in relevantFiltered) {
        byTier.putIfAbsent(record.tier, () => []).add(record);
      }
      final diaryRelated = byTier[MemoryTier.autonomous];
      if (diaryRelated != null && diaryRelated.isNotEmpty) {
        appendSection('日记记忆·相关', diaryRelated);
      }
      final kbRelated = byTier[MemoryTier.external];
      if (kbRelated != null && kbRelated.isNotEmpty) {
        appendSection('知识库·相关', kbRelated);
      }
    } else if (timeDiary.isEmpty && diaryAll.isNotEmpty) {
      appendSection('日记记忆·近期', diaryAll.take(12));
    }

    return applyRouteAddons(buffer.toString());
  }

  String? _sanitizeWebSearchContext(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    if (text.length <= 5000) {
      return text;
    }
    return '${text.substring(0, 5000)}...';
  }

  String? _sanitizeAttachmentContext(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    if (text.length <= 4000) {
      return text;
    }
    return '${text.substring(0, 4000)}...';
  }

  String _formatAttachmentContext(List<ChatAttachment> attachments) {
    if (attachments.isEmpty) {
      return '';
    }
    final images = attachments
        .where((a) => a.kind == ChatAttachmentKind.image)
        .toList(growable: false);
    final files = attachments
        .where((a) => a.kind == ChatAttachmentKind.file)
        .toList(growable: false);

    final buffer = StringBuffer();
    if (images.isNotEmpty) {
      buffer.writeln('图片：');
      for (var i = 0; i < images.length; i += 1) {
        final a = images[i];
        final dim = (a.width != null && a.height != null)
            ? '${a.width}x${a.height}'
            : 'unknown';
        final kb = a.bytes == null ? '?' : ((a.bytes! / 1024).round()).toString();
        final caption = a.caption?.trim();
        final token = Uri.file(a.localPath).toString();
        buffer.writeln(
          '- IMG${i + 1}: ${caption == null || caption.isEmpty ? a.fileName : caption} ($dim, ~${kb}KB) [IMAGE: $token]',
        );
        if (buffer.length > 3500) {
          buffer.writeln('...');
          break;
        }
      }
    }
    if (files.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln('');
      buffer.writeln('文件：');
      for (var i = 0; i < files.length; i += 1) {
        final a = files[i];
        final kb = a.bytes == null ? '?' : ((a.bytes! / 1024).round()).toString();
        buffer.writeln('- FILE${i + 1}: ${a.fileName} (~${kb}KB) path=${a.localPath}');
        if (buffer.length > 3900) {
          buffer.writeln('...');
          break;
        }
      }
    }
    return buffer.toString().trimRight();
  }

  ProviderConfig? _resolveVisionProvider() {
    final settings = _settingsRepository.settings;
    final explicit = settings.visionProviderId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return _settingsRepository.findProvider(explicit);
    }
    final main = _activeProvider();
    if (main != null && main.capabilities.contains(ProviderCapability.vision)) {
      return main;
    }
    return null;
  }

  Future<List<ChatAttachment>> _maybeAnalyzeUserAttachments(
    String userText, {
    required List<ChatAttachment> attachments,
  }) async {
    final images = attachments
        .where((a) => a.kind == ChatAttachmentKind.image)
        .toList(growable: false);
    if (images.isEmpty) {
      return attachments;
    }
    final provider = _resolveVisionProvider();
    if (provider == null) {
      return attachments;
    }

    final limited = images.take(6).toList(growable: false);
    final prepared = <LlmImageInput>[];
    final idByIndex = <int, String>{};
    for (var i = 0; i < limited.length; i += 1) {
      final attachment = limited[i];
      final bytes = await _readFileBytesSafe(attachment.localPath);
      if (bytes == null || bytes.isEmpty) continue;
      final resized = _resizeForVision(bytes);
      if (resized == null || resized.isEmpty) continue;
      prepared.add(LlmImageInput(bytes: resized, mimeType: 'image/jpeg'));
      idByIndex[prepared.length] = attachment.id;
    }
    if (prepared.isEmpty) {
      return attachments;
    }

    const systemPrompt = '''
你是“图片归类与说明”助手。你的输出将被注入对话上下文，用于后续对话与深度研究。
硬性要求：
1) 只输出 JSON 数组，不要输出 Markdown，不要输出解释文字；
2) 每个元素包含：index(从1开始)、type、caption、tags(数组)、has_text(布尔)；
3) type 只能取：sticker,meme,screenshot,photo,chart,document,other；
4) caption 要能被引用（偏客观描述）；不确定写“待核验”。
''';
    final prompt = '''
用户消息：$userText
请逐张图输出结构化结果。tags 可以包含：表情包/流程图/截图/网页/代码/表格/人物/风景/Logo 等。
'''.trim();

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
    if (parsed.isEmpty) {
      return attachments;
    }

    final updatedById = <String, ChatAttachment>{};
    for (final entry in parsed) {
      final idx = entry.index;
      if (idx <= 0) continue;
      final id = idByIndex[idx];
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

      if (entry.type == 'sticker' || entry.type == 'meme') {
        try {
          await _memoryRepository.addRecord(
            tier: MemoryTier.crossSession,
            record: MemoryRecord(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              tier: MemoryTier.crossSession,
              content:
                  '用户表情包/图片素材：${entry.caption}\n可引用图片：[IMAGE: ${Uri.file(original.localPath)}]',
              createdAt: DateTime.now(),
              tags: ['media', entry.type, ...entry.tags],
            ),
            embed: false,
          );
        } catch (_) {
          // Best-effort; don't block chat on memory writes.
        }
      }
    }

    if (updatedById.isEmpty) {
      return attachments;
    }
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
      if (jpg.length > 1200 * 1024 && maxSide > 960) {
        final scale = 960 / maxSide;
        final smaller = img.copyResize(
          working,
          width: (working.width * scale).round(),
          height: (working.height * scale).round(),
          interpolation: img.Interpolation.average,
        );
        jpg = img.encodeJpg(smaller, quality: 80);
      }
      if (jpg.length > 1600 * 1024) {
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
      out.add(_VisionJsonEntry(index: idx, type: type, caption: caption, tags: tags));
    }
    return out;
  }

  @override
  void dispose() {
    _voiceChannelRestartTimer?.cancel();
    _voiceChannelRestartTimer = null;
    _streamSubscription?.cancel();
    _audioPlayingSubscription?.cancel();
    _lipSyncTimer?.cancel();
    _chatRepository.removeListener(_refreshTokenUsage);
    _memoryRepository.removeListener(_refreshTokenUsage);
    _settingsRepository.removeListener(_refreshTokenUsage);
    // Best-effort teardown; don't block widget dispose.
    unawaited(_speech.stop());
    unawaited(_tts.stop());
    unawaited(_audioPlayer.stop());
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }
}

class _AutoWebSearchResult {
  const _AutoWebSearchResult({this.statusMessage, this.contextSnippet = ''});

  final String? statusMessage;
  final String contextSnippet;
}

class _VisionJsonEntry {
  const _VisionJsonEntry({
    required this.index,
    required this.type,
    required this.caption,
    required this.tags,
  });

  final int index; // 1-based index in the analyzed image list
  final String type;
  final String caption;
  final List<String> tags;
}

class _AgentCommand {
  const _AgentCommand({
    required this.goal,
    required this.deliverable,
    required this.depth,
  });

  final String goal;
  final ResearchDeliverable deliverable;
  final ResearchDepth depth;
}

class _ToolCommand {
  const _ToolCommand({
    required this.action,
    required this.query,
    this.showHelp = false,
  });

  final ToolAction action;
  final String query;
  final bool showHelp;
}

enum _TagCommandType { tool, agent, help, info }

class _TagCommand {
  const _TagCommand({
    required this.type,
    this.action,
    this.payload = '',
    this.deliverable,
    this.depth,
    this.topic,
  });

  const _TagCommand.tool({required ToolAction action, required String payload})
    : this(type: _TagCommandType.tool, action: action, payload: payload);

  const _TagCommand.agent({
    required String payload,
    required ResearchDeliverable deliverable,
    required ResearchDepth depth,
  }) : this(
         type: _TagCommandType.agent,
         payload: payload,
         deliverable: deliverable,
         depth: depth,
       );

  const _TagCommand.help({String topic = ''})
    : this(type: _TagCommandType.help, topic: topic);

  const _TagCommand.info({required String topic})
    : this(type: _TagCommandType.info, topic: topic);

  final _TagCommandType type;
  final ToolAction? action;
  final String payload;
  final ResearchDeliverable? deliverable;
  final ResearchDepth? depth;
  final String? topic;
}

class _AsidePattern {
  const _AsidePattern({
    required this.open,
    required this.close,
    required this.regex,
  });

  final String open;
  final String close;
  final String regex;
}
