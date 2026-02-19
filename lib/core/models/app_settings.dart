enum ModelRoute { standard, realtime, omni }

enum PersonaMode { persona, standard }

enum PersonaLevel { basic, advanced, full }

enum PersonaStyle { none, neuro, toxic, cute }

enum UiPalette { jade, ocean, ember, rose, slate }

enum UiGlass { soft, standard, strong }

enum LayoutPreset { balanced, focusChat, focusPresentation }

enum Live3dRenderQuality { low, balanced, high }

enum Live3dFpsCap { unlimited, fps60, fps30 }

enum DraftFormatStrategy { platformDefault, markdown, text }

enum AutonomyPlatform { x, xiaohongshu, bilibili, wechat }

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
    this.live3dRenderQuality = Live3dRenderQuality.balanced,
    this.live3dFpsCap = Live3dFpsCap.fps60,
    this.autonomyEnabled = false,
    this.autonomyProactiveEnabled = false,
    this.autonomyProactiveIntervalMinutes = 20,
    this.autonomyExploreEnabled = false,
    this.autonomyExploreIntervalMinutes = 60,
    this.autonomyPlatforms = const [
      AutonomyPlatform.x,
      AutonomyPlatform.xiaohongshu,
      AutonomyPlatform.bilibili,
      AutonomyPlatform.wechat,
    ],
    this.draftFormatStrategy = DraftFormatStrategy.platformDefault,
    this.toolGatewayEnabled = false,
    this.toolGatewayBaseUrl = 'http://127.0.0.1:4891',
    this.toolGatewayPairingToken = '',
    this.voiceChannelEnabled = false,
    this.voiceChannelInjectEnabled = true,
    this.voiceChannelDeviceId,
    this.voiceChannelDeviceLabel,
    this.uiPalette = UiPalette.jade,
    this.uiGlass = UiGlass.standard,
    this.layoutPreset = LayoutPreset.balanced,
    this.layoutSidebarWidth = 280.0,
    this.layoutRightPanelWidth = 380.0,
    this.layoutShowRightPanel = true,
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
  Live3dRenderQuality live3dRenderQuality;
  Live3dFpsCap live3dFpsCap;
  bool autonomyEnabled;
  bool autonomyProactiveEnabled;
  int autonomyProactiveIntervalMinutes;
  bool autonomyExploreEnabled;
  int autonomyExploreIntervalMinutes;
  List<AutonomyPlatform> autonomyPlatforms;
  DraftFormatStrategy draftFormatStrategy;
  bool toolGatewayEnabled;
  String toolGatewayBaseUrl;
  String toolGatewayPairingToken;

  /// Windows-only. Enables voice-channel monitoring UI + runtime hook.
  /// Actual audio routing is done by selecting a virtual sound card as the
  /// default recording device (e.g. VB-CABLE) and letting system STT listen.
  bool voiceChannelEnabled;
  bool voiceChannelInjectEnabled;
  String? voiceChannelDeviceId;
  String? voiceChannelDeviceLabel;
  UiPalette uiPalette;
  UiGlass uiGlass;
  LayoutPreset layoutPreset;
  double layoutSidebarWidth;
  double layoutRightPanelWidth;
  bool layoutShowRightPanel;

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
    Live3dRenderQuality? live3dRenderQuality,
    Live3dFpsCap? live3dFpsCap,
    bool? autonomyEnabled,
    bool? autonomyProactiveEnabled,
    int? autonomyProactiveIntervalMinutes,
    bool? autonomyExploreEnabled,
    int? autonomyExploreIntervalMinutes,
    List<AutonomyPlatform>? autonomyPlatforms,
    DraftFormatStrategy? draftFormatStrategy,
    bool? toolGatewayEnabled,
    String? toolGatewayBaseUrl,
    String? toolGatewayPairingToken,
    bool? voiceChannelEnabled,
    bool? voiceChannelInjectEnabled,
    String? voiceChannelDeviceId,
    String? voiceChannelDeviceLabel,
    UiPalette? uiPalette,
    UiGlass? uiGlass,
    LayoutPreset? layoutPreset,
    double? layoutSidebarWidth,
    double? layoutRightPanelWidth,
    bool? layoutShowRightPanel,
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
      motionAgentProviderId:
          motionAgentProviderId ?? this.motionAgentProviderId,
      motionBasicCount: motionBasicCount ?? this.motionBasicCount,
      motionAgentCooldownSeconds:
          motionAgentCooldownSeconds ?? this.motionAgentCooldownSeconds,
      memoryAgentEnabled: memoryAgentEnabled ?? this.memoryAgentEnabled,
      memoryAgentProviderId:
          memoryAgentProviderId ?? this.memoryAgentProviderId,
      memoryAgentCooldownSeconds:
          memoryAgentCooldownSeconds ?? this.memoryAgentCooldownSeconds,
      live3dRenderQuality: live3dRenderQuality ?? this.live3dRenderQuality,
      live3dFpsCap: live3dFpsCap ?? this.live3dFpsCap,
      autonomyEnabled: autonomyEnabled ?? this.autonomyEnabled,
      autonomyProactiveEnabled:
          autonomyProactiveEnabled ?? this.autonomyProactiveEnabled,
      autonomyProactiveIntervalMinutes:
          autonomyProactiveIntervalMinutes ??
          this.autonomyProactiveIntervalMinutes,
      autonomyExploreEnabled:
          autonomyExploreEnabled ?? this.autonomyExploreEnabled,
      autonomyExploreIntervalMinutes:
          autonomyExploreIntervalMinutes ?? this.autonomyExploreIntervalMinutes,
      autonomyPlatforms: autonomyPlatforms ?? this.autonomyPlatforms,
      draftFormatStrategy: draftFormatStrategy ?? this.draftFormatStrategy,
      toolGatewayEnabled: toolGatewayEnabled ?? this.toolGatewayEnabled,
      toolGatewayBaseUrl: toolGatewayBaseUrl ?? this.toolGatewayBaseUrl,
      toolGatewayPairingToken:
          toolGatewayPairingToken ?? this.toolGatewayPairingToken,
      voiceChannelEnabled: voiceChannelEnabled ?? this.voiceChannelEnabled,
      voiceChannelInjectEnabled:
          voiceChannelInjectEnabled ?? this.voiceChannelInjectEnabled,
      voiceChannelDeviceId: voiceChannelDeviceId ?? this.voiceChannelDeviceId,
      voiceChannelDeviceLabel:
          voiceChannelDeviceLabel ?? this.voiceChannelDeviceLabel,
      uiPalette: uiPalette ?? this.uiPalette,
      uiGlass: uiGlass ?? this.uiGlass,
      layoutPreset: layoutPreset ?? this.layoutPreset,
      layoutSidebarWidth: layoutSidebarWidth ?? this.layoutSidebarWidth,
      layoutRightPanelWidth:
          layoutRightPanelWidth ?? this.layoutRightPanelWidth,
      layoutShowRightPanel:
          layoutShowRightPanel ?? this.layoutShowRightPanel,
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
    'live3d_quality': live3dRenderQuality.name,
    'live3d_fps_cap': live3dFpsCap.name,
    'autonomy_enabled': autonomyEnabled,
    'autonomy_proactive_enabled': autonomyProactiveEnabled,
    'autonomy_proactive_interval_minutes': autonomyProactiveIntervalMinutes,
    'autonomy_explore_enabled': autonomyExploreEnabled,
    'autonomy_explore_interval_minutes': autonomyExploreIntervalMinutes,
    'autonomy_platforms': autonomyPlatforms.map((p) => p.name).toList(),
    'draft_format_strategy': draftFormatStrategy.name,
    'tool_gateway_enabled': toolGatewayEnabled,
    'tool_gateway_base_url': toolGatewayBaseUrl,
    'tool_gateway_pairing_token': toolGatewayPairingToken,
    'voice_channel_enabled': voiceChannelEnabled,
    'voice_channel_inject_enabled': voiceChannelInjectEnabled,
    'voice_channel_device_id': voiceChannelDeviceId,
    'voice_channel_device_label': voiceChannelDeviceLabel,
    'ui_palette': uiPalette.name,
    'ui_glass': uiGlass.name,
    'layout_preset': layoutPreset.name,
    'layout_sidebar_width': layoutSidebarWidth,
    'layout_right_panel_width': layoutRightPanelWidth,
    'layout_show_right_panel': layoutShowRightPanel,
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
    live3dRenderQuality: Live3dRenderQuality.values.firstWhere(
      (quality) => quality.name == json['live3d_quality'],
      orElse: () => Live3dRenderQuality.balanced,
    ),
    live3dFpsCap: Live3dFpsCap.values.firstWhere(
      (cap) => cap.name == json['live3d_fps_cap'],
      orElse: () => Live3dFpsCap.fps60,
    ),
    autonomyEnabled: json['autonomy_enabled'] as bool? ?? false,
    autonomyProactiveEnabled:
        json['autonomy_proactive_enabled'] as bool? ?? false,
    autonomyProactiveIntervalMinutes:
        (json['autonomy_proactive_interval_minutes'] as num?)?.toInt() ?? 20,
    autonomyExploreEnabled:
        json['autonomy_explore_enabled'] as bool? ?? false,
    autonomyExploreIntervalMinutes:
        (json['autonomy_explore_interval_minutes'] as num?)?.toInt() ?? 60,
    autonomyPlatforms: _parseAutonomyPlatforms(json['autonomy_platforms']),
    draftFormatStrategy: DraftFormatStrategy.values.firstWhere(
      (strategy) => strategy.name == json['draft_format_strategy'],
      orElse: () => DraftFormatStrategy.platformDefault,
    ),
    toolGatewayEnabled: json['tool_gateway_enabled'] as bool? ?? false,
    toolGatewayBaseUrl:
        (json['tool_gateway_base_url'] as String?)?.trim().isNotEmpty == true
            ? (json['tool_gateway_base_url'] as String)
            : 'http://127.0.0.1:4891',
    toolGatewayPairingToken:
        json['tool_gateway_pairing_token'] as String? ?? '',
    voiceChannelEnabled: json['voice_channel_enabled'] as bool? ?? false,
    voiceChannelInjectEnabled:
        json['voice_channel_inject_enabled'] as bool? ?? true,
    voiceChannelDeviceId: json['voice_channel_device_id'] as String?,
    voiceChannelDeviceLabel: json['voice_channel_device_label'] as String?,
    uiPalette: UiPalette.values.firstWhere(
      (palette) => palette.name == json['ui_palette'],
      orElse: () => UiPalette.jade,
    ),
    uiGlass: UiGlass.values.firstWhere(
      (glass) => glass.name == json['ui_glass'],
      orElse: () => UiGlass.standard,
    ),
    layoutPreset: LayoutPreset.values.firstWhere(
      (preset) => preset.name == json['layout_preset'],
      orElse: () => LayoutPreset.balanced,
    ),
    layoutSidebarWidth:
        (json['layout_sidebar_width'] as num?)?.toDouble() ?? 280.0,
    layoutRightPanelWidth:
        (json['layout_right_panel_width'] as num?)?.toDouble() ?? 380.0,
    layoutShowRightPanel: json['layout_show_right_panel'] as bool? ?? true,
  );
}

List<AutonomyPlatform> _parseAutonomyPlatforms(Object? raw) {
  if (raw is List) {
    return raw
        .map((entry) => entry.toString())
        .map(
          (name) => AutonomyPlatform.values.firstWhere(
            (platform) => platform.name == name,
            orElse: () => AutonomyPlatform.x,
          ),
        )
        .toSet()
        .toList();
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const [AutonomyPlatform.x];
    }
    return trimmed
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map(
          (name) => AutonomyPlatform.values.firstWhere(
            (platform) => platform.name == name,
            orElse: () => AutonomyPlatform.x,
          ),
        )
        .toSet()
        .toList();
  }
  return const [AutonomyPlatform.x];
}
