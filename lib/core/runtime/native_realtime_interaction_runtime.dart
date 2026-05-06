// ignore_for_file: unused_field

import 'dart:async';
import 'dart:typed_data';

import '../models/interaction_contract.dart';
import '../services/llm_client.dart';
import '../services/speech_client.dart';
import 'interaction_event.dart';
import 'interaction_runtime.dart';
import 'interaction_session.dart';

/// Realtime native audio-interaction runtime.
///
/// This is a minimal skeleton. Real implementation requires:
/// - WebSocket-based realtime session lifecycle
/// - Native audio-in chunk forwarding
/// - Server event parsing (text/audio/transcript/tool-intent)
/// - Barge-in / interrupt signaling
/// - Partial transcript → final transcript coalescing
///
/// Currently all [InteractionSession] methods throw [UnsupportedError]
/// except [start] and [dispose].
class NativeRealtimeInteractionRuntime implements InteractionRuntime {
  NativeRealtimeInteractionRuntime({
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
    return _NativeRealtimeInteractionSession(
      contract: contract,
      systemPrompt: systemPrompt,
    );
  }
}

class _NativeRealtimeInteractionSession implements InteractionSession {
  _NativeRealtimeInteractionSession({
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
      'native_realtime_not_implemented',
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
        'NativeRealtime text path not yet wired. '
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
        'NativeRealtime audio path not yet wired. '
        'Full realtime session integration pending.',
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
        'NativeRealtime runtime cue not yet wired.',
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
