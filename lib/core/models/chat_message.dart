enum ChatRole {
  system,
  user,
  assistant,
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'created_at': createdAt.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        role: ChatRole.values.firstWhere(
          (role) => role.name == json['role'],
          orElse: () => ChatRole.assistant,
        ),
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
