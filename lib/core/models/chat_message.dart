import 'chat_attachment.dart';

enum ChatRole { system, user, assistant }

enum ChatSourceKind {
  user,
  mic,
  voiceChannel,
  barrage,
  plugin,
  system,
  tool,
  autonomy,
}

enum ChatPriority { user, voiceChannel, barrage, proactive, low, normal, high }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.sourceKind,
    this.sourceId,
    this.priority = ChatPriority.normal,
    List<ChatAttachment>? attachments,
  }) : attachments = attachments ?? const [];

  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final ChatSourceKind? sourceKind;
  final String? sourceId;
  final ChatPriority priority;
  final List<ChatAttachment> attachments;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'source_kind': sourceKind?.name,
    'source_id': sourceId,
    'priority': priority.name,
    'attachments': attachments.map((a) => a.toJson()).toList(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    role: ChatRole.values.firstWhere(
      (role) => role.name == json['role'],
      orElse: () => ChatRole.assistant,
    ),
    content: json['content'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    sourceKind: _parseSourceKind(json['source_kind']),
    sourceId: json['source_id'] as String?,
    priority: _parsePriority(json['priority']),
    attachments: (json['attachments'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ChatAttachment.fromJson)
        .toList(),
  );

  static ChatSourceKind? _parseSourceKind(Object? raw) {
    if (raw is String) {
      for (final kind in ChatSourceKind.values) {
        if (kind.name == raw) return kind;
      }
    }
    return null;
  }

  static ChatPriority _parsePriority(Object? raw) {
    if (raw is String) {
      return ChatPriority.values.firstWhere(
        (priority) => priority.name == raw,
        orElse: () => ChatPriority.normal,
      );
    }
    return ChatPriority.normal;
  }
}
