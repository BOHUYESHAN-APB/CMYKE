class DanmakuEvent {
  const DanmakuEvent({
    required this.type,
    required this.roomId,
    required this.timestamp,
    this.userId,
    this.userName,
    this.message,
    this.price,
    this.emoticonUnique,
    this.emoticonUrl,
    this.extra,
    this.raw,
  });

  final DanmakuEventType type;
  final int roomId;
  final DateTime timestamp;
  final int? userId;
  final String? userName;
  final String? message;
  final double? price;
  final String? emoticonUnique;
  final String? emoticonUrl;
  final Map<String, dynamic>? extra;
  final Map<String, dynamic>? raw;
}

enum DanmakuEventType {
  danmaku,
  superChat,
  gift,
  guardBuy,
  unknown,
}
