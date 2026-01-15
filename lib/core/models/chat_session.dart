import 'chat_message.dart';

enum ChatSessionMode {
  standard,
  realtime,
  universal,
}

class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.mode = ChatSessionMode.standard,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  final ChatSessionMode mode;
  final List<ChatMessage> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'mode': mode.name,
        'messages': messages.map((message) => message.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        mode: ChatSessionMode.values.firstWhere(
          (mode) => mode.name == json['mode'],
          orElse: () => ChatSessionMode.standard,
        ),
        messages: (json['messages'] as List<dynamic>? ?? [])
            .map((entry) => ChatMessage.fromJson(entry as Map<String, dynamic>))
            .toList(),
      );
}
