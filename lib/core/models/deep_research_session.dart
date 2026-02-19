import 'deep_research_message.dart';

class DeepResearchSession {
  DeepResearchSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    List<DeepResearchMessage>? messages,
  }) : messages = messages ?? [];

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<DeepResearchMessage> messages;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'messages': messages.map((message) => message.toJson()).toList(),
  };

  factory DeepResearchSession.fromJson(Map<String, dynamic> json) {
    return DeepResearchSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Research',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      messages: (json['messages'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(DeepResearchMessage.fromJson)
          .toList(),
    );
  }
}
