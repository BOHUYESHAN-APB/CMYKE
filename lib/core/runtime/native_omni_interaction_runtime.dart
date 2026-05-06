// ignore_for_file: unused_field

import 'dart:async';
import 'dart:typed_data';

import '../models/interaction_contract.dart';
import '../services/llm_client.dart';
import '../services/speech_client.dart';
import 'interaction_event.dart';
import 'interaction_runtime.dart';
import 'interaction_session.dart';

/// Omni multi-modal interaction runtime.
///
/// This is a minimal skeleton. Real implementation requires:
/// - Multimodal input forwarding (text + image + audio)
/// - Native audio-in/out via HTTP streaming or WS
/// - Vision input passthrough
/// - enableThinking toggle
/// - Tool-intent side channel parsing
///
/// Differs from [NativeRealtimeInteractionRuntime] primarily in:
/// - Accepting text and image as input alongside audio
/// - Often using HTTP streaming rather than persistent WS
/// - Carrying enableThinking / deeper reasoning hints
///
/// Currently all [InteractionSession] methods throw [UnsupportedError]
/// except [start] and [dispose].
class NativeOmniInteractionRuntime implements InteractionRuntime {
  NativeOmniInteractionRuntime({
    LlmClient? llmClient,
    SpeechClient? speechClient,
  }) : _llmClient = llmClient ?? LlmClient(),
       _speechClient = speechClient ?? SpeechClient();

  final LlmClient _llmClient;
  final SpeechClient _speechClient;

  @override
  InteractionSession createSession({
    required InteractionContract contract,
    String? systemPrompt,
  }) {
    return _NativeOmniInteractionSession(
      contract: contract,
      systemPrompt: systemPrompt,
    );
  }
}

class _NativeOmniInteractionSession implements InteractionSession {
  _NativeOmniInteractionSession({
    required InteractionContract contract,
    required String? systemPrompt,
  }) : _contract = contract,
       _systemPrompt = systemPrompt;

  final InteractionContract _contract;
  final String? _systemPrompt;

  final StreamController<InteractionEvent> _events =
      StreamController<InteractionEvent>.broadcast();

  bool _started = false;
  bool _disposed = false;

  @override
  Stream<InteractionEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _events.add(InteractionEvent.status('ready'));
    _events.add(InteractionEvent.status(
      'native_omni_not_implemented',
    ));
  }

  @override
  Future<void> sendUserText(
    String text, {
    String? systemPrompt,
    List<Map<String, String>>? contextMessages,
  }) async {
    _checkDisposed();
    _events.add(InteractionEvent.error(
      UnsupportedError(
        'NativeOmni text path not yet wired. '
        'Use lightweight mode for text-only interaction.',
      ),
    ));
  }

  @override
  Future<void> sendUserAudio(
    Uint8List audioBytes, {
    String? format,
    String? language,
    String? systemPrompt,
    List<Map<String, String>>? contextMessages,
  }) async {
    _checkDisposed();
    _events.add(InteractionEvent.error(
      UnsupportedError(
        'NativeOmni audio path not yet wired.',
      ),
    ));
  }

  @override
  Future<void> sendRuntimeCue(
    String cue, {
    String? systemPrompt,
    List<Map<String, String>>? contextMessages,
  }) async {
    _checkDisposed();
    _events.add(InteractionEvent.error(
      UnsupportedError(
        'NativeOmni runtime cue not yet wired.',
      ),
    ));
  }

  @override
  Future<void> interrupt() async {
    _checkDisposed();
    _events.add(InteractionEvent.status('interrupt_requested'));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _events.close();
  }

  void _checkDisposed() {
    if (_disposed) throw StateError('Session already disposed');
  }
}
