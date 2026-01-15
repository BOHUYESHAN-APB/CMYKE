import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/llm_stream_event.dart';
import '../models/lipsync_frame.dart';
import '../models/memory_tier.dart';
import '../models/memory_record.dart';
import '../models/provider_config.dart';
import '../models/research_job.dart';
import '../prompts/persona_lumi.dart';
import '../repositories/chat_repository.dart';
import '../repositories/memory_repository.dart';
import '../repositories/settings_repository.dart';
import 'audio_stream_player.dart';
import 'llm_client.dart';
import 'speech_client.dart';
import 'token_estimator.dart';
import 'universal_agent.dart';
import 'runtime_hub.dart';

class ChatEngine extends ChangeNotifier {
  ChatEngine({
    required ChatRepository chatRepository,
    required MemoryRepository memoryRepository,
    required SettingsRepository settingsRepository,
  })  : _chatRepository = chatRepository,
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
    _audioPlayingSubscription =
        _audioPlayer.playingStream.listen((playing) {
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
    _refreshTokenUsage();
  }

  final ChatRepository _chatRepository;
  final MemoryRepository _memoryRepository;
  final SettingsRepository _settingsRepository;
  final LlmClient _llmClient = LlmClient();
  late final UniversalAgent _universalAgent;
  final SpeechClient _speechClient = SpeechClient();
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioStreamPlayer _audioPlayer = AudioStreamPlayer();
  StreamSubscription<bool>? _audioPlayingSubscription;
  final Random _lipSyncRandom = Random();
  Timer? _lipSyncTimer;
  bool _lipSyncActive = false;
  bool _isTalking = false;

  StreamSubscription<LlmStreamEvent>? _streamSubscription;
  bool _isListening = false;
  bool _isTtsSpeaking = false;
  bool _isAudioPlaying = false;
  bool _isStreaming = false;
  bool _isCompressing = false;
  String _partialTranscript = '';
  int _estimatedTokens = 0;
  int? _tokenLimit;

  static const int _compressionKeepMessages = 8;
  static const double _compressionTriggerRatio = 0.92;

  bool get isListening => _isListening;
  bool get isSpeaking => _isTtsSpeaking || _isAudioPlaying;
  bool get isStreaming => _isStreaming;
  bool get isCompressing => _isCompressing;
  String get partialTranscript => _partialTranscript;
  int get estimatedTokens => _estimatedTokens;
  int? get tokenLimit => _tokenLimit;

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final agentCommand = _parseAgentCommand(trimmed);
    if (agentCommand != null) {
      await _runUniversalAgent(agentCommand);
      return;
    }
    await interrupt();
    await _chatRepository.sendUserMessage(trimmed);

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
    final systemPrompt = await _buildSystemPrompt(trimmed);
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
        _chatRepository.updateMessageContent(
          assistantMessage.id,
          buffer.toString(),
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
        final content = buffer.toString();
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
      },
      cancelOnError: true,
    );
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
    final standardProvider =
        _settingsRepository.findProvider(_settingsRepository.settings.llmProviderId);
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

  String _formatUniversalAgentResult(
    String goal,
    UniversalAgentResult result,
  ) {
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
    final snippet =
        trimmed.length <= maxLen ? trimmed : '${trimmed.substring(0, maxLen)}...';
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
    if (_isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  Future<void> startListening() async {
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
    final available = await _speech.initialize();
    if (!available) {
      return;
    }
    _partialTranscript = '';
    _isListening = true;
    notifyListeners();
    await _speech.listen(
      onResult: (result) {
        _partialTranscript = result.recognizedWords;
        notifyListeners();
        if (result.finalResult) {
          _isListening = false;
          notifyListeners();
          _speech.stop();
          sendText(_partialTranscript);
          _partialTranscript = '';
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        partialResults: true,
      ),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
    _partialTranscript = '';
    notifyListeners();
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
        debugPrint('[TTS] Streaming audio disabled on this platform. Using device TTS.');
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
    final currentTokens = _estimatePromptTokens(
      messages,
      session.id,
    );
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
      final trimmedCandidates = _trimMessagesToTokenBudget(
        candidates,
        (limit * 0.7).round(),
      );
      final summary = await _summarizeMessages(
        provider,
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
        scope: 'brain.user',
      );
      await _memoryRepository.replaceSessionSummary(
        session.id,
        summaryRecord,
      );
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
      systemPrompt = '$systemPrompt\n已有摘要如下，请在此基础上补充新增要点：\n'
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
    final crossRecords =
        _memoryRepository.recordsForTier(MemoryTier.crossSession).take(12);
    final autoRecords =
        _memoryRepository.recordsForTier(MemoryTier.autonomous).take(12);
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
  }

  List<String> _splitAssistantResponse(String content) {
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

  Future<String> _buildSystemPrompt(String userMessage) async {
    final settings = _settingsRepository.settings;
    final base = buildLumiPersona(
      mode: settings.personaMode,
      level: settings.personaLevel,
      style: settings.personaStyle,
      customPrompt: settings.personaPrompt,
    );
    final sessionId = _chatRepository.activeSessionId;
    final contextRecords = _memoryRepository.recordsForTier(
      MemoryTier.context,
      sessionId: sessionId,
    );
    final relevant =
        await _memoryRepository.searchRelevant(userMessage, limit: 12);
    if (relevant.isEmpty) {
      final cross =
          _memoryRepository.recordsForTier(MemoryTier.crossSession);
      final auto =
          _memoryRepository.recordsForTier(MemoryTier.autonomous);
      if (contextRecords.isEmpty && cross.isEmpty && auto.isEmpty) {
        return base;
      }
      final buffer = StringBuffer('$base\n');
      if (contextRecords.isNotEmpty) {
        buffer.writeln('\n[会话内记忆]');
        for (final record in contextRecords.take(12)) {
          buffer.writeln('- ${record.content}');
        }
      }
      if (cross.isNotEmpty) {
        buffer.writeln('\n[跨会话记忆]');
        for (final record in cross.take(12)) {
          buffer.writeln('- ${record.content}');
        }
      }
      if (auto.isNotEmpty) {
        buffer.writeln('\n[自主沉淀]');
        for (final record in auto.take(12)) {
          buffer.writeln('- ${record.content}');
        }
      }
      return buffer.toString();
    }
    final buffer = StringBuffer('$base\n');
    if (contextRecords.isNotEmpty) {
      buffer.writeln('\n[会话内记忆]');
      for (final record in contextRecords.take(12)) {
        buffer.writeln('- ${record.content}');
      }
    }
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

    appendTier(MemoryTier.crossSession, '跨会话记忆');
    appendTier(MemoryTier.autonomous, '自主沉淀');
    appendTier(MemoryTier.external, '外部知识库');
    return buffer.toString();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _audioPlayingSubscription?.cancel();
    _lipSyncTimer?.cancel();
    _chatRepository.removeListener(_refreshTokenUsage);
    _memoryRepository.removeListener(_refreshTokenUsage);
    _settingsRepository.removeListener(_refreshTokenUsage);
    _speech.stop();
    _tts.stop();
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }
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
