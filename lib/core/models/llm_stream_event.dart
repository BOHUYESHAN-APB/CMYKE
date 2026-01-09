import 'dart:typed_data';

class LlmStreamEvent {
  const LlmStreamEvent({
    this.textDelta,
    this.audioChunk,
    this.audioFormat,
  });

  final String? textDelta;
  final Uint8List? audioChunk;
  final String? audioFormat;

  bool get hasText => textDelta != null && textDelta!.isNotEmpty;
  bool get hasAudio => audioChunk != null && audioChunk!.isNotEmpty;
}
