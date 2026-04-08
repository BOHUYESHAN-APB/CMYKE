class Note {
  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.summary = '',
    this.type = 'text',
    this.category = 'default',
    this.memoryTier,
    this.memoryRecordId,
    this.memorySyncedAt,
  });

  final String id;
  final String title;
  final String content;
  final String summary;
  final String type;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String category;
  final String? memoryTier;
  final String? memoryRecordId;
  final DateTime? memorySyncedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'summary': summary,
    'type': type,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'category': category,
    'memory_tier': memoryTier,
    'memory_record_id': memoryRecordId,
    'memory_synced_at': memorySyncedAt?.toIso8601String(),
  };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    type: json['type'] as String? ?? 'text',
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    category: json['category'] as String? ?? 'default',
    memoryTier: json['memory_tier'] as String?,
    memoryRecordId: json['memory_record_id'] as String?,
    memorySyncedAt: (json['memory_synced_at'] as String?) == null
        ? null
        : DateTime.parse(json['memory_synced_at'] as String),
  );

  Note copyWith({
    String? title,
    String? content,
    String? summary,
    String? type,
    DateTime? updatedAt,
    String? category,
    String? memoryTier,
    String? memoryRecordId,
    DateTime? memorySyncedAt,
    bool clearMemoryLink = false,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      summary: summary ?? this.summary,
      type: type ?? this.type,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      category: category ?? this.category,
      memoryTier: clearMemoryLink ? null : memoryTier ?? this.memoryTier,
      memoryRecordId: clearMemoryLink
          ? null
          : memoryRecordId ?? this.memoryRecordId,
      memorySyncedAt: clearMemoryLink
          ? null
          : memorySyncedAt ?? this.memorySyncedAt,
    );
  }
}
