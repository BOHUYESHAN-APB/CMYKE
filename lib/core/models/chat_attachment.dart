enum ChatAttachmentKind { image, file }

class ChatAttachment {
  ChatAttachment({
    required this.id,
    required this.kind,
    required this.localPath,
    required this.fileName,
    required this.createdAt,
    this.mimeType,
    this.bytes,
    this.width,
    this.height,
    this.sha256,
    this.caption,
    this.tags = const [],
  });

  final String id;
  final ChatAttachmentKind kind;
  final String localPath;
  final String fileName;
  final DateTime createdAt;

  final String? mimeType;
  final int? bytes;
  final int? width;
  final int? height;
  final String? sha256;
  final String? caption;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'local_path': localPath,
    'file_name': fileName,
    'created_at': createdAt.toIso8601String(),
    'mime_type': mimeType,
    'bytes': bytes,
    'width': width,
    'height': height,
    'sha256': sha256,
    'caption': caption,
    'tags': tags,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    final kindRaw = json['kind'] as String? ?? ChatAttachmentKind.file.name;
    final kind = ChatAttachmentKind.values.firstWhere(
      (k) => k.name == kindRaw,
      orElse: () => ChatAttachmentKind.file,
    );
    return ChatAttachment(
      id: json['id'] as String,
      kind: kind,
      localPath: json['local_path'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      mimeType: json['mime_type'] as String?,
      bytes: (json['bytes'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      sha256: json['sha256'] as String?,
      caption: json['caption'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
    );
  }
}

