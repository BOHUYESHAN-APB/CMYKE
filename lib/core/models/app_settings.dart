enum ModelRoute {
  standard,
  realtime,
  omni,
}

enum PersonaMode {
  persona,
  standard,
}

enum PersonaLevel {
  basic,
  advanced,
  full,
}

enum PersonaStyle {
  none,
  neuro,
  toxic,
  cute,
}

const Object _unset = Object();

class AppSettings {
  AppSettings({
    required this.route,
    this.llmProviderId,
    this.embeddingProviderId,
    this.visionProviderId,
    this.ttsProviderId,
    this.sttProviderId,
    this.realtimeProviderId,
    this.omniProviderId,
    this.live3dModelPath,
    this.personaMode = PersonaMode.persona,
    this.personaLevel = PersonaLevel.full,
    this.personaStyle = PersonaStyle.none,
    this.personaPrompt,
    this.enableSystemTts = true,
    this.enableSystemStt = true,
    this.petMode = false,
    this.petFollowCursor = true,
    this.motionAgentEnabled = false,
    this.motionAgentProviderId,
    this.motionBasicCount = 9,
    this.motionAgentCooldownSeconds = 12,
    this.memoryAgentEnabled = false,
    this.memoryAgentProviderId,
    this.memoryAgentCooldownSeconds = 20,
  });

  ModelRoute route;
  String? llmProviderId;
  String? embeddingProviderId;
  String? visionProviderId;
  String? ttsProviderId;
  String? sttProviderId;
  String? realtimeProviderId;
  String? omniProviderId;
  String? live3dModelPath;
  PersonaMode personaMode;
  PersonaLevel personaLevel;
  PersonaStyle personaStyle;
  String? personaPrompt;
  bool enableSystemTts;
  bool enableSystemStt;
  bool petMode;
  bool petFollowCursor;
  bool motionAgentEnabled;
  String? motionAgentProviderId;
  int motionBasicCount;
  int motionAgentCooldownSeconds;
  bool memoryAgentEnabled;
  String? memoryAgentProviderId;
  int memoryAgentCooldownSeconds;

  AppSettings copyWith({
    ModelRoute? route,
    String? llmProviderId,
    String? embeddingProviderId,
    String? visionProviderId,
    String? ttsProviderId,
    String? sttProviderId,
    String? realtimeProviderId,
    String? omniProviderId,
    String? live3dModelPath,
    PersonaMode? personaMode,
    PersonaLevel? personaLevel,
    PersonaStyle? personaStyle,
    Object? personaPrompt = _unset,
    bool? enableSystemTts,
    bool? enableSystemStt,
    bool? petMode,
    bool? petFollowCursor,
    bool? motionAgentEnabled,
    String? motionAgentProviderId,
    int? motionBasicCount,
    int? motionAgentCooldownSeconds,
    bool? memoryAgentEnabled,
    String? memoryAgentProviderId,
    int? memoryAgentCooldownSeconds,
  }) {
    return AppSettings(
      route: route ?? this.route,
      llmProviderId: llmProviderId ?? this.llmProviderId,
      embeddingProviderId: embeddingProviderId ?? this.embeddingProviderId,
      visionProviderId: visionProviderId ?? this.visionProviderId,
      ttsProviderId: ttsProviderId ?? this.ttsProviderId,
      sttProviderId: sttProviderId ?? this.sttProviderId,
      realtimeProviderId: realtimeProviderId ?? this.realtimeProviderId,
      omniProviderId: omniProviderId ?? this.omniProviderId,
      live3dModelPath: live3dModelPath ?? this.live3dModelPath,
      personaMode: personaMode ?? this.personaMode,
      personaLevel: personaLevel ?? this.personaLevel,
      personaStyle: personaStyle ?? this.personaStyle,
      personaPrompt: personaPrompt == _unset
          ? this.personaPrompt
          : personaPrompt as String?,
      enableSystemTts: enableSystemTts ?? this.enableSystemTts,
      enableSystemStt: enableSystemStt ?? this.enableSystemStt,
      petMode: petMode ?? this.petMode,
      petFollowCursor: petFollowCursor ?? this.petFollowCursor,
      motionAgentEnabled: motionAgentEnabled ?? this.motionAgentEnabled,
      motionAgentProviderId: motionAgentProviderId ?? this.motionAgentProviderId,
      motionBasicCount: motionBasicCount ?? this.motionBasicCount,
      motionAgentCooldownSeconds:
          motionAgentCooldownSeconds ?? this.motionAgentCooldownSeconds,
      memoryAgentEnabled: memoryAgentEnabled ?? this.memoryAgentEnabled,
      memoryAgentProviderId: memoryAgentProviderId ?? this.memoryAgentProviderId,
      memoryAgentCooldownSeconds:
          memoryAgentCooldownSeconds ?? this.memoryAgentCooldownSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'route': route.name,
        'llm_provider_id': llmProviderId,
        'embedding_provider_id': embeddingProviderId,
        'vision_provider_id': visionProviderId,
        'tts_provider_id': ttsProviderId,
        'stt_provider_id': sttProviderId,
        'realtime_provider_id': realtimeProviderId,
        'omni_provider_id': omniProviderId,
        'live3d_model_path': live3dModelPath,
        'persona_mode': personaMode.name,
        'persona_level': personaLevel.name,
        'persona_style': personaStyle.name,
        'persona_prompt': personaPrompt,
        'enable_system_tts': enableSystemTts,
        'enable_system_stt': enableSystemStt,
        'pet_mode': petMode,
        'pet_follow_cursor': petFollowCursor,
        'motion_agent_enabled': motionAgentEnabled,
        'motion_agent_provider_id': motionAgentProviderId,
        'motion_basic_count': motionBasicCount,
        'motion_agent_cooldown_seconds': motionAgentCooldownSeconds,
        'memory_agent_enabled': memoryAgentEnabled,
        'memory_agent_provider_id': memoryAgentProviderId,
        'memory_agent_cooldown_seconds': memoryAgentCooldownSeconds,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        route: ModelRoute.values.firstWhere(
          (route) => route.name == json['route'],
          orElse: () => ModelRoute.standard,
        ),
        llmProviderId: json['llm_provider_id'] as String?,
        embeddingProviderId: json['embedding_provider_id'] as String?,
        visionProviderId: json['vision_provider_id'] as String?,
        ttsProviderId: json['tts_provider_id'] as String?,
        sttProviderId: json['stt_provider_id'] as String?,
        realtimeProviderId: json['realtime_provider_id'] as String?,
        omniProviderId: json['omni_provider_id'] as String?,
        live3dModelPath: json['live3d_model_path'] as String?,
        personaMode: PersonaMode.values.firstWhere(
          (mode) => mode.name == json['persona_mode'],
          orElse: () => PersonaMode.persona,
        ),
        personaLevel: PersonaLevel.values.firstWhere(
          (level) => level.name == json['persona_level'],
          orElse: () => PersonaLevel.full,
        ),
        personaStyle: PersonaStyle.values.firstWhere(
          (style) => style.name == json['persona_style'],
          orElse: () => PersonaStyle.none,
        ),
        personaPrompt: json['persona_prompt'] as String?,
        enableSystemTts: json['enable_system_tts'] as bool? ?? true,
        enableSystemStt: json['enable_system_stt'] as bool? ?? true,
        petMode: json['pet_mode'] as bool? ?? false,
        petFollowCursor: json['pet_follow_cursor'] as bool? ?? true,
        motionAgentEnabled: json['motion_agent_enabled'] as bool? ?? false,
        motionAgentProviderId: json['motion_agent_provider_id'] as String?,
        motionBasicCount: json['motion_basic_count'] as int? ?? 9,
        motionAgentCooldownSeconds:
            json['motion_agent_cooldown_seconds'] as int? ?? 12,
        memoryAgentEnabled: json['memory_agent_enabled'] as bool? ?? false,
        memoryAgentProviderId: json['memory_agent_provider_id'] as String?,
        memoryAgentCooldownSeconds:
            json['memory_agent_cooldown_seconds'] as int? ?? 20,
      );
}
