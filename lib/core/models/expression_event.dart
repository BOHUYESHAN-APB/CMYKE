enum ExpressionEmotion {
  idle,
  happy,
  sad,
  angry,
  surprise,
  think,
  awkward,
  question,
  curious,
}

class ExpressionEvent {
  const ExpressionEvent({
    required this.emotion,
    this.intensity,
    this.durationMs,
  });

  final ExpressionEmotion emotion;
  final double? intensity; // 0.0 - 1.0 (optional)
  final int? durationMs;
}

ExpressionEmotion? emotionFromToken(String token) {
  switch (token.trim()) {
    case '<|EMOTE_NEUTRAL|>':
      return ExpressionEmotion.idle;
    case '<|EMOTE_HAPPY|>':
      return ExpressionEmotion.happy;
    case '<|EMOTE_SAD|>':
      return ExpressionEmotion.sad;
    case '<|EMOTE_ANGRY|>':
      return ExpressionEmotion.angry;
    case '<|EMOTE_SURPRISED|>':
      return ExpressionEmotion.surprise;
    case '<|EMOTE_THINK|>':
      return ExpressionEmotion.think;
    case '<|EMOTE_AWKWARD|>':
      return ExpressionEmotion.awkward;
    case '<|EMOTE_QUESTION|>':
      return ExpressionEmotion.question;
    case '<|EMOTE_CURIOUS|>':
      return ExpressionEmotion.curious;
    default:
      return null;
  }
}
