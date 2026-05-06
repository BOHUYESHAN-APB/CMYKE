import 'dart:typed_data';

import 'interaction_event.dart';

abstract class InteractionSession {
  Stream<InteractionEvent> get events;

  Future<void> start();

  Future<void> sendUserText(
    String text, {
    String? systemPrompt,
    List<Map<String, String>>? contextMessages,
  });

  Future<void> sendUserAudio(
    Uint8List audioBytes, {
    String? format,
    String? language,
    String? systemPrompt,
    List<Map<String, String>>? contextMessages,
  });

  Future<void> sendRuntimeCue(
    String cue, {
    String? systemPrompt,
    List<Map<String, String>>? contextMessages,
  });

  Future<void> interrupt();

  Future<void> dispose();
}
