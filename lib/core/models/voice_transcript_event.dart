class VoiceTranscriptEvent {
  const VoiceTranscriptEvent({
    required this.id,
    required this.text,
    required this.createdAt,
    this.sourceLabel = 'voice_channel',
    this.isFinal = true,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final String sourceLabel;
  final bool isFinal;
}

