import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/llm_stream_event.dart';
import '../models/memory_tier.dart';
import '../models/provider_config.dart';
import '../repositories/chat_repository.dart';
import '../repositories/memory_repository.dart';
import '../repositories/settings_repository.dart';
import 'audio_stream_player.dart';
import 'llm_client.dart';
import 'speech_client.dart';

class ChatEngine extends ChangeNotifier {
  ChatEngine({
    required ChatRepository chatRepository,
    required MemoryRepository memoryRepository,
    required SettingsRepository settingsRepository,
  })  : _chatRepository = chatRepository,
        _memoryRepository = memoryRepository,
        _settingsRepository = settingsRepository {
    _tts.setStartHandler(() {
      _isTtsSpeaking = true;
      notifyListeners();
    });
    _tts.setCompletionHandler(() {
      _isTtsSpeaking = false;
      notifyListeners();
    });
    _tts.setCancelHandler(() {
      _isTtsSpeaking = false;
      notifyListeners();
    });
    _tts.setErrorHandler((_) {
      _isTtsSpeaking = false;
      notifyListeners();
    });
    _audioPlayingSubscription =
        _audioPlayer.playingStream.listen((playing) {
      _isAudioPlaying = playing;
      notifyListeners();
    });
  }

  final ChatRepository _chatRepository;
  final MemoryRepository _memoryRepository;
  final SettingsRepository _settingsRepository;
  final LlmClient _llmClient = LlmClient();
  final SpeechClient _speechClient = SpeechClient();
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioStreamPlayer _audioPlayer = AudioStreamPlayer();
  StreamSubscription<bool>? _audioPlayingSubscription;

  StreamSubscription<LlmStreamEvent>? _streamSubscription;
  bool _isListening = false;
  bool _isTtsSpeaking = false;
  bool _isAudioPlaying = false;
  bool _isStreaming = false;
  String _partialTranscript = '';

  bool get isListening => _isListening;
  bool get isSpeaking => _isTtsSpeaking || _isAudioPlaying;
  bool get isStreaming => _isStreaming;
  String get partialTranscript => _partialTranscript;

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
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

    final systemPrompt = _buildSystemPrompt();
    _isStreaming = true;
    notifyListeners();
    final buffer = StringBuffer();
    bool receivedAudio = false;
    Future<void>? audioStartFuture;

    final messageHistory = (_chatRepository.activeSession?.messages ?? [])
        .where((message) => message.content.trim().isNotEmpty)
        .toList();

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
        notifyListeners();
        await _chatRepository.updateMessageContent(
          assistantMessage.id,
          buffer.toString(),
          persist: true,
        );
        if (receivedAudio && audioStartFuture != null) {
          await audioStartFuture;
          await _audioPlayer.finish();
        }
        if (_shouldSpeakResponse(modelProvidedAudio: receivedAudio)) {
          await _playTts(buffer.toString());
        }
      },
      cancelOnError: true,
    );
  }

  Future<void> interrupt() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _isStreaming = false;
    _partialTranscript = '';
    await _audioPlayer.stop();
    await _tts.stop();
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
    final settings = _settingsRepository.settings;
    if (settings.route == ModelRoute.standard) {
      return _resolveTtsProvider() != null;
    }
    return true;
  }

  ProviderConfig? _resolveTtsProvider() {
    final settings = _settingsRepository.settings;
    return _settingsRepository.findProvider(settings.ttsProviderId);
  }

  Future<void> _playTts(String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    final provider = _resolveTtsProvider();
    if (provider == null ||
        provider.protocol == ProviderProtocol.deviceBuiltin) {
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
      await _speak(text);
    }
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

  String _buildSystemPrompt() {
    final cross = _memoryRepository
        .defaultCollection(MemoryTier.crossSession)
        .records;
    final auto = _memoryRepository
        .defaultCollection(MemoryTier.autonomous)
        .records;
    if (cross.isEmpty && auto.isEmpty) {
      return '你是 CMYKE，一个强调多模态与可扩展能力的智能体。';
    }
    final buffer = StringBuffer(
      '你是 CMYKE，一个强调多模态与可扩展能力的智能体。\n',
    );
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

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _audioPlayingSubscription?.cancel();
    _speech.stop();
    _tts.stop();
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }
}
