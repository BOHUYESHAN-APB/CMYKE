import 'dart:typed_data';

enum InteractionEventType {
  status,
  textDelta,
  textComplete,
  audioChunk,
  transcriptFinal,
  error,
  done,
}

class InteractionEvent {
  const InteractionEvent._({
    required this.type,
    this.status,
    this.text,
    this.audioChunk,
    this.audioFormat,
    this.error,
  });

  final InteractionEventType type;
  final String? status;
  final String? text;
  final Uint8List? audioChunk;
  final String? audioFormat;
  final Object? error;

  factory InteractionEvent.status(String status) =>
      InteractionEvent._(type: InteractionEventType.status, status: status);

  factory InteractionEvent.textDelta(String text) =>
      InteractionEvent._(type: InteractionEventType.textDelta, text: text);

  factory InteractionEvent.textComplete(String text) =>
      InteractionEvent._(type: InteractionEventType.textComplete, text: text);

  factory InteractionEvent.audioChunk(
    Uint8List chunk, {
    String? format,
  }) => InteractionEvent._(
    type: InteractionEventType.audioChunk,
    audioChunk: chunk,
    audioFormat: format,
  );

  factory InteractionEvent.transcriptFinal(String text) =>
      InteractionEvent._(type: InteractionEventType.transcriptFinal, text: text);

  factory InteractionEvent.error(Object error) =>
      InteractionEvent._(type: InteractionEventType.error, error: error);

  factory InteractionEvent.done() =>
      const InteractionEvent._(type: InteractionEventType.done);
}
