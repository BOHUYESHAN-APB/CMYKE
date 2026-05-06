import 'dart:async';
import 'dart:typed_data';

import '../models/interaction_contract.dart';
import '../models/provider_config.dart';
import '../providers/system_stt_provider.dart';
import '../providers/system_tts_provider.dart';
import '../services/llm_client.dart';
import '../services/speech_client.dart';
import 'interaction_event.dart';
import 'interaction_runtime.dart';
import 'interaction_session.dart';

class LightweightInteractionRuntime implements InteractionRuntime {
  LightweightInteractionRuntime({
    LlmClient? llmClient,
    SpeechClient? speechClient,
    SystemTtsProvider? systemTtsProvider,
    SystemSttProvider? systemSttProvider,
  }) : _llmClient = llmClient ?? LlmClient(),
       _speechClient = speechClient ?? SpeechClient(),
       _systemTtsProvider = systemTtsProvider,
       _systemSttProvider = systemSttProvider;

  final LlmClient _llmClient;
  final SpeechClient _speechClient;
  final SystemTtsProvider? _systemTtsProvider;
  final SystemSttProvider? _systemSttProvider;

  @override
  InteractionSession createSession({
    required InteractionContract contract,
    String? systemPrompt,
  }) {
    return _LightweightInteractionSession(
      contract: contract,
      llmClient: _llmClient,
      speechClient: _speechClient,
      systemTtsProvider: _systemTtsProvider,
      systemSttProvider: _systemSttProvider,
      systemPrompt: systemPrompt,
    );
  }
}

class _LightweightInteractionSession implements InteractionSession {
  _LightweightInteractionSession({
    required InteractionContract contract,
    required LlmClient llmClient,
    required SpeechClient speechClient,
    SystemTtsProvider? systemTtsProvider,
    SystemSttProvider? systemSttProvider,
    String? systemPrompt,
  }) : _contract = contract,
       _llmClient = llmClient,
       _speechClient = speechClient,
       _systemTtsProvider = systemTtsProvider,
       _systemSttProvider = systemSttProvider,
       _systemPrompt = systemPrompt;

  final InteractionContract _contract;
  final LlmClient _llmClient;
  final SpeechClient _speechClient;
  final SystemTtsProvider? _systemTtsProvider;
  final SystemSttProvider? _systemSttProvider;
  final String? _systemPrompt;
  final StreamController<InteractionEvent> _events =
      StreamController<InteractionEvent>.broadcast();
  final List<Map<String, String>> _history = [];

  bool _started = false;
  bool _disposed = false;
  bool _interrupted = false;

  @override
  Stream<InteractionEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _events.add(InteractionEvent.status('ready'));
  }

  @override
  Future<void> sendUserText(
    String text, {
    String? systemPrompt,
    List<Map<String, String>>? contextMessages,
  }) async {
    if (_disposed) {
      return;
    }
    await start();
    final provider = _contract.main.provider ?? _contract.leftBrain.provider;
    if (provider == null) {
      _events.add(InteractionEvent.error(StateError('No main provider configured')));
      return;
    }

    _interrupted = false;
    _events.add(InteractionEvent.status('processing'));

    final messages = <Map<String, String>>[
      ...?contextMessages,
      ..._history,
      {'role': 'user', 'content': text},
    ];
    _history.add({'role': 'user', 'content': text});

    final buffer = StringBuffer();
    var producedModelAudio = false;

    try {
      await for (final event in _llmClient.streamChat(
        provider,
        messages,
        systemPrompt: systemPrompt ?? _systemPrompt,
      )) {
        if (_disposed || _interrupted) {
          break;
        }
        if (event.hasText) {
          final delta = event.textDelta!;
          buffer.write(delta);
          _events.add(InteractionEvent.textDelta(delta));
        }
        if (event.hasAudio) {
          producedModelAudio = true;
          _events.add(
            InteractionEvent.audioChunk(
              event.audioChunk!,
              format: event.audioFormat,
            ),
          );
        }
      }

      if (_disposed || _interrupted) {
        _events.add(InteractionEvent.status('interrupted'));
        return;
      }

      final fullText = buffer.toString().trim();
      if (fullText.isNotEmpty) {
        _history.add({'role': 'assistant', 'content': fullText});
        _events.add(InteractionEvent.textComplete(fullText));
      }

      if (!producedModelAudio) {
        await _emitTts(fullText);
      }

      _events.add(InteractionEvent.done());
    } catch (error) {
      _events.add(InteractionEvent.error(error));
    }
  }

  Future<void> _emitTts(String text) async {
    final provider = _contract.tts.provider;
    if (provider == null || text.isEmpty) {
      return;
    }
    if (provider.protocol == ProviderProtocol.deviceBuiltin) {
      await _emitSystemTts(text);
      return;
    }
    await _emitRemoteTts(text);
  }

  Future<void> _emitSystemTts(String text) async {
    final systemTts = _systemTtsProvider;
    if (systemTts == null) {
      _events.add(InteractionEvent.status('tts_device_builtin_pending'));
      return;
    }
    _events.add(InteractionEvent.status('tts_system_speaking'));
    try {
      await systemTts.speak(text: text);
      _events.add(InteractionEvent.status('tts_system_completed'));
    } catch (error) {
      _events.add(InteractionEvent.error(error));
    }
  }

  Future<void> _emitRemoteTts(String text) async {
    final provider = _contract.tts.provider;
    if (provider == null || text.isEmpty) {
      return;
    }
    await for (final chunk in _speechClient.streamSpeech(
      provider: provider,
      text: text,
    )) {
      if (_disposed || _interrupted) {
        break;
      }
      _events.add(
        InteractionEvent.audioChunk(
          chunk,
          format: provider.audioFormat,
        ),
      );
    }
  }

  @override
  Future<void> sendUserAudio(
    Uint8List audioBytes, {
    String? format,
    String? language,
    String? systemPrompt,
    List<Map<String, String>>? contextMessages,
  }) async {
    if (_disposed) {
      return;
    }
    await start();
    final provider = _contract.stt.provider;
    if (provider == null) {
      _events.add(InteractionEvent.error(StateError('No STT provider configured')));
      return;
    }
    if (provider.protocol == ProviderProtocol.deviceBuiltin) {
      _events.add(
        InteractionEvent.error(
          UnsupportedError(
            'Device builtin STT uses microphone. Call startSystemListening() instead.',
          ),
        ),
      );
      return;
    }
    try {
      final transcript = await _speechClient.transcribeBytes(
        provider: provider,
        audioBytes: audioBytes,
        language: language,
        format: format,
      );
      final trimmed = transcript.trim();
      if (trimmed.isEmpty) {
        _events.add(InteractionEvent.done());
        return;
      }
      _events.add(InteractionEvent.transcriptFinal(trimmed));
      await sendUserText(
        trimmed,
        systemPrompt: systemPrompt,
        contextMessages: contextMessages,
      );
    } catch (error) {
      _events.add(InteractionEvent.error(error));
    }
  }

  @override
  Future<void> sendRuntimeCue(
    String cue, {
    String? systemPrompt,
    List<Map<String, String>>? contextMessages,
  }) async {
    if (_disposed) {
      return;
    }
    _events.add(InteractionEvent.status('runtime_cue'));
    final cueMessages = <Map<String, String>>[
      ...?contextMessages,
      {'role': 'system', 'content': cue},
    ];
    await sendUserText('', systemPrompt: systemPrompt, contextMessages: cueMessages);
  }

  /// Start listening via platform microphone and feed transcript
  /// into the session as if it were user text.
  Future<void> startSystemListening({
    String? localeId,
    Duration? listenFor,
    Duration? pauseFor,
  }) async {
    if (_disposed) {
      return;
    }
    final provider = _systemSttProvider;
    if (provider == null) {
      _events.add(
        InteractionEvent.error(StateError('System STT provider not available')),
      );
      return;
    }
    final initialized = await provider.initialize();
    if (!initialized) {
      _events.add(
        InteractionEvent.error(StateError('Failed to initialize system speech recognition')),
      );
      return;
    }
    _events.add(InteractionEvent.status('stt_system_listening'));
    try {
      await provider.listen(
        localeId: localeId,
        listenFor: listenFor,
        pauseFor: pauseFor,
        partialResults: true,
        onResult: (text) {
          if (_disposed) {
            return;
          }
          if (text.isEmpty || text.trim().isEmpty) {
            return;
          }
          _events.add(InteractionEvent.transcriptFinal(text.trim()));
        },
      );
    } catch (error) {
      if (!_disposed) {
        _events.add(InteractionEvent.error(error));
      }
    }
  }

  /// Stop active system microphone listening.
  Future<void> stopSystemListening() async {
    await _systemSttProvider?.stop();
  }

  @override
  Future<void> interrupt() async {
    if (_disposed) {
      return;
    }
    _interrupted = true;
    _events.add(InteractionEvent.status('interrupt_requested'));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_systemSttProvider?.cancel());
    await _events.close();
  }
}
