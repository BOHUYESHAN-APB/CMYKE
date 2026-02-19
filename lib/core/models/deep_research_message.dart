enum DeepResearchRole { user, assistant, system }

class DeepResearchMessage {
  DeepResearchMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final DeepResearchRole role;
  final String content;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    'created_at': createdAt.toIso8601String(),
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
    );
  }
}
