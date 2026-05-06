// ignore_for_file: unused_field

import 'dart:async';
import 'dart:typed_data';

import '../models/interaction_contract.dart';
import 'interaction_event.dart';
import 'interaction_runtime.dart';
import 'interaction_session.dart';

/// Composite interaction runtime — coordinates left + right brain.
///
/// This is a minimal skeleton. Real implementation requires:
/// - Left runtime owns live interaction (presence, speech, low-latency output)
/// - Right runtime owns slow reasoning (deep thinking, tool calls, research)
/// - Left acknowledges user; right works in background
/// - Left reintegrates right results when ready
/// - Escalation policy based on InteractionContract options
///
/// Follows the left-brain-first architecture:
/// - docs/left_brain_first_architecture.md
/// - lib/core/models/brain_contract.dart
/// - lib/core/services/brain_router.dart
///
/// Currently all [InteractionSession] methods throw [UnsupportedError]
/// except [start] and [dispose].
class CompositeInteractionRuntime implements InteractionRuntime {
  CompositeInteractionRuntime();

  @override
  InteractionSession createSession({
    required InteractionContract contract,
    String? systemPrompt,
  }) {
    return _CompositeInteractionSession(
      contract: contract,
      systemPrompt: systemPrompt,
    );
  }
}

class _CompositeInteractionSession implements InteractionSession {
  _CompositeInteractionSession({
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
      'composite_not_implemented',
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
        'Composite text path not yet wired. '
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
        'Composite audio path not yet wired.',
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
        'Composite runtime cue not yet wired.',
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
