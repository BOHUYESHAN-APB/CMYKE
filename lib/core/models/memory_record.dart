import 'memory_tier.dart';

class MemoryRecord {
  MemoryRecord({
    required this.id,
    required this.tier,
    required this.content,
    required this.createdAt,
    this.sourceMessageId,
    this.title,
    this.tags = const [],
    this.sessionId,
    this.scope,
  });

  final String id;
  final MemoryTier tier;
  final String content;
  final DateTime createdAt;
  final String? sourceMessageId;
  final String? title;
  final List<String> tags;
  final String? sessionId;
  final String? scope;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tier': tier.key,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        'source_message_id': sourceMessageId,
        'title': title,
        'tags': tags,
        'session_id': sessionId,
        'scope': scope,
      };

  factory MemoryRecord.fromJson(Map<String, dynamic> json) => MemoryRecord(
        id: json['id'] as String,
        tier: MemoryTier.values.firstWhere(
          (tier) => tier.key == json['tier'],
          orElse: () => MemoryTier.context,
        ),
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        sourceMessageId: json['source_message_id'] as String?,
        title: json['title'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
        sessionId: json['session_id'] as String?,
        scope: json['scope'] as String?,
      );

  MemoryRecord copyWith({
    String? id,
    MemoryTier? tier,
    String? content,
    DateTime? createdAt,
    String? sourceMessageId,
    String? title,
    List<String>? tags,
    String? sessionId,
    String? scope,
  }) {
    return MemoryRecord(
      id: id ?? this.id,
      tier: tier ?? this.tier,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      sessionId: sessionId ?? this.sessionId,
      scope: scope ?? this.scope,
    );
  }
}
