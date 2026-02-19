import 'chat_attachment.dart';

enum DeepResearchRole { user, assistant, system }

class DeepResearchMessage {
  DeepResearchMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    List<ChatAttachment>? attachments,
  }) : attachments = attachments ?? const [];

  final String id;
  final DeepResearchRole role;
  final String content;
  final DateTime createdAt;
  final List<ChatAttachment> attachments;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'attachments': attachments.map((a) => a.toJson()).toList(),
  };

  factory DeepResearchMessage.fromJson(Map<String, dynamic> json) {
    return DeepResearchMessage(
      id: json['id'] as String,
      role: DeepResearchRole.values.firstWhere(
        (role) => role.name == json['role'],
        orElse: () => DeepResearchRole.assistant,
      ),
      content: json['content'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      attachments: (json['attachments'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChatAttachment.fromJson)
          .toList(),
    );
  }
}
