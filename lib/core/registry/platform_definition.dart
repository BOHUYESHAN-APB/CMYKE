/// Platform capability flags
class PlatformCapabilities {
  const PlatformCapabilities({
    this.supportsText = true,
    this.supportsVoice = false,
    this.supportsImage = false,
    this.supportsVideo = false,
    this.supportsFile = false,
    this.supportsStreaming = false,
    this.supportsThreads = false,
    this.supportsReactions = false,
  });

  final bool supportsText;
  final bool supportsVoice;
  final bool supportsImage;
  final bool supportsVideo;
  final bool supportsFile;
  final bool supportsStreaming;
  final bool supportsThreads;
  final bool supportsReactions;

  Map<String, dynamic> toJson() => {
        'text': supportsText,
        'voice': supportsVoice,
        'image': supportsImage,
        'video': supportsVideo,
        'file': supportsFile,
        'streaming': supportsStreaming,
        'threads': supportsThreads,
        'reactions': supportsReactions,
      };
}

/// Platform definition metadata
class PlatformDefinition {
  const PlatformDefinition({
    required this.name,
    required this.description,
    required this.capabilities,
    this.category,
    this.tags = const <String>[],
  });

  final String name;
  final String description;
  final PlatformCapabilities capabilities;
  final String? category;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'capabilities': capabilities.toJson(),
        if (category != null) 'category': category,
        'tags': tags,
      };
}

/// Platform message envelope
class PlatformMessage {
  const PlatformMessage({
    required this.content,
    this.sessionId,
    this.userId,
    this.threadId,
    this.replyTo,
    this.attachments = const <String>[],
    this.metadata = const <String, dynamic>{},
  });

  final String content;
  final String? sessionId;
  final String? userId;
  final String? threadId;
  final String? replyTo;
  final List<String> attachments;
  final Map<String, dynamic> metadata;
}

/// Platform connection status
enum PlatformStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

/// Abstract platform adapter interface
abstract class PlatformAdapter {
  PlatformDefinition get definition;

  PlatformStatus get status;

  Stream<PlatformMessage> get messages;

  Future<void> connect();

  Future<void> disconnect();

  Future<void> sendMessage(PlatformMessage message);

  Future<void> dispose() async {
    await disconnect();
  }
}
