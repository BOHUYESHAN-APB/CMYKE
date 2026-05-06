import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_settings.dart';
import '../models/brain_contract.dart';
import '../models/interaction_contract.dart';
import '../models/interaction_profile.dart';
import '../models/provider_config.dart';
import '../services/local_database.dart';
import '../services/interaction_profile_resolver.dart';
import '../services/local_storage.dart';

class SettingsRepository extends ChangeNotifier {
  SettingsRepository({
    required LocalDatabase database,
    LocalStorage? legacyStorage,
  }) : _database = database,
       _legacyStorage = legacyStorage ?? LocalStorage();

  final LocalDatabase _database;
  final LocalStorage _legacyStorage;
  final InteractionProfileResolver _interactionProfileResolver =
      const InteractionProfileResolver();
  final List<ProviderConfig> _providers = [];
  AppSettings _settings = AppSettings(route: ModelRoute.standard);

  static const String _providersFile = 'providers.json';
  static const String _settingsFile = 'settings.json';
  static const String _providersTable = 'providers';
  static const String _settingsTable = 'app_settings';
  static const String _interactionProfilesTable = 'interaction_profiles';

  final List<InteractionProfile> _interactionProfiles = [];

  List<ProviderConfig> get providers => List.unmodifiable(_providers);
  List<InteractionProfile> get interactionProfiles =>
      List.unmodifiable(_interactionProfiles);
  AppSettings get settings => _settings;
  InteractionProfile get activeInteractionProfile {
    final activeId = _settings.resolvedActiveProfileId;
    for (final profile in _interactionProfiles) {
      if (profile.id == activeId) {
        return profile;
      }
    }
    return _settings.toDefaultInteractionProfile();
  }

  InteractionContract get interactionContract => _interactionProfileResolver
      .resolve(profile: activeInteractionProfile, providers: _providers);

  BrainContract get brainContract => BrainContract.fromInteractionContract(
    interactionContract,
  );

  List<ProviderConfig> providersByKind(ProviderKind kind) => _providers
      .where((provider) => provider.kind == kind)
      .toList(growable: false);

  ProviderConfig? findProvider(String? id) {
    if (id == null) {
      return null;
    }
    for (final provider in _providers) {
      if (provider.id == id) {
        return provider;
      }
    }
    return null;
  }

  ProviderConfig? resolveBrainProvider(BrainRole role) {
    final contract = brainContract;
    final providerId = switch (role) {
      BrainRole.left => contract.leftBrain.providerId,
      BrainRole.right => contract.rightBrain?.providerId,
    };
    return findProvider(providerId);
  }

  Future<void> load() async {
    final db = await _database.database;
    var providerRows = await db.query(_providersTable);
    if (providerRows.isEmpty) {
      await _importLegacy(db);
      providerRows = await db.query(_providersTable);
    }
    if (providerRows.isEmpty) {
      _providers
        ..clear()
        ..addAll(_defaultProviders());
      await _persistProviders(db);
    } else {
      _providers
        ..clear()
        ..addAll(providerRows.map(_providerFromRow));
    }

    final settingsRows = await db.query(_settingsTable, limit: 1);
    if (settingsRows.isEmpty) {
      final legacySettings = await _legacyStorage.readJsonMap(_settingsFile);
      _settings = legacySettings == null
          ? AppSettings(route: ModelRoute.standard)
          : AppSettings.fromJson(legacySettings);
      await _persistSettings(db);
    } else {
      _settings = _settingsFromRow(settingsRows.first);
    }

    final profileRows = await db.query(_interactionProfilesTable);
    _interactionProfiles
      ..clear()
      ..addAll(profileRows.map(_interactionProfileFromRow));

    _ensureDefaults();
    _ensureInteractionProfiles();
    notifyListeners();
    await _persistSettings(db);
    await _persistInteractionProfiles(db);
  }

  Future<void> addProvider(ProviderConfig provider) async {
    final db = await _database.database;
    _providers.add(provider);
    await db.insert(
      _providersTable,
      _providerToRow(provider),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> updateProvider(ProviderConfig provider) async {
    final db = await _database.database;
    final index = _providers.indexWhere((item) => item.id == provider.id);
    if (index == -1) {
      return;
    }
    _providers[index] = provider;
    await db.update(
      _providersTable,
      _providerToRow(provider),
      where: 'id = ?',
      whereArgs: [provider.id],
    );
    notifyListeners();
  }

  Future<void> removeProvider(String providerId) async {
    final db = await _database.database;
    _providers.removeWhere((provider) => provider.id == providerId);
    await db.delete(_providersTable, where: 'id = ?', whereArgs: [providerId]);
    _sanitizeSelections();
    await _persistSettings(db);
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings settings) async {
    final db = await _database.database;
    _settings = settings;
    _sanitizeSelections();
    _ensureInteractionProfiles();
    await _persistSettings(db);
    await _persistInteractionProfiles(db);
    notifyListeners();
  }

  /// Sync the active profile mode when the user changes route.
  Future<void> updateActiveProfileMode(InteractionMode mode) async {
    final profile = activeInteractionProfile;
    if (profile.mode == mode) return;
    final updated = profile.copyWith(mode: mode);
    _interactionProfiles.removeWhere((p) => p.id == updated.id);
    _interactionProfiles.add(updated);
    final db = await _database.database;
    await _persistInteractionProfiles(db);
    // Re-sync BrainContract since mode changed
    notifyListeners();
  }

  void _ensureDefaults() {
    _sanitizeSelections();
    final llmProviders = providersByKind(ProviderKind.llm);
    if (_settings.llmProviderId == null && llmProviders.isNotEmpty) {
      _settings.llmProviderId = llmProviders.first.id;
    }
    if (_settings.embeddingProviderId == null && llmProviders.isNotEmpty) {
      final llm = findProvider(_settings.llmProviderId);
      if (llm != null && (llm.embeddingModel?.trim().isNotEmpty ?? false)) {
        _settings.embeddingProviderId = llm.id;
      } else {
        final candidate = llmProviders.firstWhere(
          (p) => p.embeddingModel?.trim().isNotEmpty == true,
          orElse: () => llmProviders.first,
        );
        if (candidate.embeddingModel?.trim().isNotEmpty == true) {
          _settings.embeddingProviderId = candidate.id;
        }
      }
    }
    if (_settings.motionAgentEnabled &&
        _settings.motionAgentProviderId == null &&
        providersByKind(ProviderKind.llm).isNotEmpty) {
      _settings.motionAgentProviderId = providersByKind(
        ProviderKind.llm,
      ).first.id;
    }
    if (_settings.memoryAgentEnabled &&
        _settings.memoryAgentProviderId == null &&
        providersByKind(ProviderKind.llm).isNotEmpty) {
      _settings.memoryAgentProviderId = providersByKind(
        ProviderKind.llm,
      ).first.id;
    }
    if (_settings.visionProviderId == null &&
        providersByKind(ProviderKind.visionAgent).isNotEmpty) {
      _settings.visionProviderId = providersByKind(
        ProviderKind.visionAgent,
      ).first.id;
    }
    if (_settings.ttsProviderId == null &&
        providersByKind(ProviderKind.tts).isNotEmpty) {
      _settings.ttsProviderId = providersByKind(ProviderKind.tts).first.id;
    }
    if (_settings.sttProviderId == null &&
        providersByKind(ProviderKind.stt).isNotEmpty) {
      _settings.sttProviderId = providersByKind(ProviderKind.stt).first.id;
    }
    if (_settings.realtimeProviderId == null &&
        providersByKind(ProviderKind.realtime).isNotEmpty) {
      _settings.realtimeProviderId = providersByKind(
        ProviderKind.realtime,
      ).first.id;
    }
    if (_settings.omniProviderId == null &&
        providersByKind(ProviderKind.omni).isNotEmpty) {
      _settings.omniProviderId = providersByKind(ProviderKind.omni).first.id;
    }
    if (_settings.toolGatewayBaseUrl.trim().isEmpty) {
      _settings.toolGatewayBaseUrl = 'http://127.0.0.1:4891';
    }
    if ((_settings.activeProfileId ?? '').trim().isEmpty) {
      _settings.activeProfileId = _settings.resolvedActiveProfileId;
    }
  }

  void _ensureInteractionProfiles() {
    final defaultProfile = _settings.toDefaultInteractionProfile();
    final index = _interactionProfiles.indexWhere(
      (profile) => profile.id == defaultProfile.id,
    );
    if (index == -1) {
      _interactionProfiles.add(defaultProfile);
      return;
    }
    final existing = _interactionProfiles[index];
    _interactionProfiles[index] = existing.copyWith(
      mode: defaultProfile.mode,
      bindings: defaultProfile.bindings,
      options: defaultProfile.options,
      updatedAt: defaultProfile.updatedAt,
    );
  }

  void _sanitizeSelections() {
    final ids = _providers.map((provider) => provider.id).toSet();
    if (_settings.llmProviderId != null &&
        !ids.contains(_settings.llmProviderId)) {
      _settings.llmProviderId = null;
    }
    if (_settings.embeddingProviderId != null &&
        !ids.contains(_settings.embeddingProviderId)) {
      _settings.embeddingProviderId = null;
    }
    if (_settings.motionAgentProviderId != null &&
        !ids.contains(_settings.motionAgentProviderId)) {
      _settings.motionAgentProviderId = null;
    }
    if (_settings.memoryAgentProviderId != null &&
        !ids.contains(_settings.memoryAgentProviderId)) {
      _settings.memoryAgentProviderId = null;
    }
    if (_settings.visionProviderId != null &&
        !ids.contains(_settings.visionProviderId)) {
      _settings.visionProviderId = null;
    }
    if (_settings.ttsProviderId != null &&
        !ids.contains(_settings.ttsProviderId)) {
      _settings.ttsProviderId = null;
    }
    if (_settings.sttProviderId != null &&
        !ids.contains(_settings.sttProviderId)) {
      _settings.sttProviderId = null;
    }
    if (_settings.realtimeProviderId != null &&
        !ids.contains(_settings.realtimeProviderId)) {
      _settings.realtimeProviderId = null;
    }
    if (_settings.omniProviderId != null &&
        !ids.contains(_settings.omniProviderId)) {
      _settings.omniProviderId = null;
    }
  }

  Future<void> _persistProviders(Database db) async {
    final batch = db.batch();
    for (final provider in _providers) {
      batch.insert(
        _providersTable,
        _providerToRow(provider),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _persistSettings(Database db) async {
    await db.insert(
      _settingsTable,
      _settingsToRow(_settings),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _persistInteractionProfiles(Database db) async {
    await db.delete(_interactionProfilesTable);
    final batch = db.batch();
    for (final profile in _interactionProfiles) {
      batch.insert(
        _interactionProfilesTable,
        _interactionProfileToRow(profile),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _importLegacy(Database db) async {
    final providerData = await _legacyStorage.readJsonList(_providersFile);
    if (providerData != null && providerData.isNotEmpty) {
      final batch = db.batch();
      for (final entry in providerData) {
        final provider = ProviderConfig.fromJson(entry as Map<String, dynamic>);
        batch.insert(
          _providersTable,
          _providerToRow(provider),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
  }

  ProviderConfig _providerFromRow(Map<String, Object?> row) {
    final capabilitiesRaw = row['capabilities'] as String?;
    final capabilities = (capabilitiesRaw == null || capabilitiesRaw.isEmpty)
        ? <ProviderCapability>[]
        : (jsonDecode(capabilitiesRaw) as List<dynamic>)
              .map(
                (entry) => ProviderCapability.values.firstWhere(
                  (cap) => cap.name == entry,
                  orElse: () => ProviderCapability.tools,
                ),
              )
              .toList();
    return ProviderConfig(
      id: row['id'] as String,
      name: row['name'] as String,
      kind: ProviderKind.values.firstWhere(
        (kind) => kind.name == row['kind'],
        orElse: () => ProviderKind.llm,
      ),
      baseUrl: row['base_url'] as String? ?? '',
      model: row['model'] as String? ?? '',
      embeddingModel: row['embedding_model'] as String?,
      embeddingBaseUrl: row['embedding_base_url'] as String?,
      embeddingApiKey: row['embedding_api_key'] as String?,
      protocol: ProviderProtocol.values.firstWhere(
        (protocol) => protocol.name == row['protocol'],
        orElse: () => ProviderProtocol.openaiCompatible,
      ),
      apiKey: row['api_key'] as String?,
      capabilities: capabilities,
      wsUrl: row['ws_url'] as String?,
      audioVoice: row['audio_voice'] as String?,
      audioFormat: row['audio_format'] as String?,
      inputAudioFormat: row['input_audio_format'] as String?,
      inputSampleRate: (row['input_sample_rate'] as num?)?.toInt(),
      outputSampleRate: (row['output_sample_rate'] as num?)?.toInt(),
      audioChannels: (row['audio_channels'] as num?)?.toInt(),
      temperature: (row['temperature'] as num?)?.toDouble(),
      topP: (row['top_p'] as num?)?.toDouble(),
      maxTokens: (row['max_tokens'] as num?)?.toInt(),
      contextWindowTokens: (row['context_window_tokens'] as num?)?.toInt(),
      frequencyPenalty: (row['frequency_penalty'] as num?)?.toDouble(),
      presencePenalty: (row['presence_penalty'] as num?)?.toDouble(),
      seed: (row['seed'] as num?)?.toInt(),
      enableThinking: _toBool(row['enable_thinking']),
      notes: row['notes'] as String?,
    );
  }

  Map<String, Object?> _providerToRow(ProviderConfig provider) {
    return {
      'id': provider.id,
      'name': provider.name,
      'kind': provider.kind.name,
      'base_url': provider.baseUrl,
      'model': provider.model,
      'embedding_model': provider.embeddingModel,
      'embedding_base_url': provider.embeddingBaseUrl,
      'embedding_api_key': provider.embeddingApiKey,
      'protocol': provider.protocol.name,
      'api_key': provider.apiKey,
      'capabilities': jsonEncode(
        provider.capabilities.map((cap) => cap.name).toList(),
      ),
      'ws_url': provider.wsUrl,
      'audio_voice': provider.audioVoice,
      'audio_format': provider.audioFormat,
      'input_audio_format': provider.inputAudioFormat,
      'input_sample_rate': provider.inputSampleRate,
      'output_sample_rate': provider.outputSampleRate,
      'audio_channels': provider.audioChannels,
      'temperature': provider.temperature,
      'top_p': provider.topP,
      'max_tokens': provider.maxTokens,
      'context_window_tokens': provider.contextWindowTokens,
      'frequency_penalty': provider.frequencyPenalty,
      'presence_penalty': provider.presencePenalty,
      'seed': provider.seed,
      'enable_thinking': provider.enableThinking == null
          ? null
          : (provider.enableThinking! ? 1 : 0),
      'notes': provider.notes,
    };
  }

  AppSettings _settingsFromRow(Map<String, Object?> row) {
    return AppSettings(
      route: ModelRoute.values.firstWhere(
        (route) => route.name == row['route'],
        orElse: () => ModelRoute.standard,
      ),
      activeProfileId: row['active_profile_id'] as String?,
      llmProviderId: row['llm_provider_id'] as String?,
      embeddingProviderId: row['embedding_provider_id'] as String?,
      visionProviderId: row['vision_provider_id'] as String?,
      ttsProviderId: row['tts_provider_id'] as String?,
      sttProviderId: row['stt_provider_id'] as String?,
      realtimeProviderId: row['realtime_provider_id'] as String?,
      omniProviderId: row['omni_provider_id'] as String?,
      live3dModelPath: row['live3d_model_path'] as String?,
      personaMode: PersonaMode.values.firstWhere(
        (mode) => mode.name == row['persona_mode'],
        orElse: () => PersonaMode.persona,
      ),
      personaLevel: PersonaLevel.values.firstWhere(
        (level) => level.name == row['persona_level'],
        orElse: () => PersonaLevel.full,
      ),
      personaStyle: PersonaStyle.values.firstWhere(
        (style) => style.name == row['persona_style'],
        orElse: () => PersonaStyle.none,
      ),
      personaPrompt: row['persona_prompt'] as String?,
      enableSystemTts: _toBool(row['enable_system_tts']) ?? true,
      enableSystemStt: _toBool(row['enable_system_stt']) ?? true,
      petMode: _toBool(row['pet_mode']) ?? false,
      petFollowCursor: _toBool(row['pet_follow_cursor']) ?? true,
      motionAgentEnabled: _toBool(row['motion_agent_enabled']) ?? false,
      motionAgentProviderId: row['motion_agent_provider_id'] as String?,
      motionBasicCount: row['motion_basic_count'] as int? ?? 9,
      motionAgentCooldownSeconds:
          row['motion_agent_cooldown_seconds'] as int? ?? 12,
      memoryAgentEnabled: _toBool(row['memory_agent_enabled']) ?? false,
      memoryAgentProviderId: row['memory_agent_provider_id'] as String?,
      memoryAgentCooldownSeconds:
          row['memory_agent_cooldown_seconds'] as int? ?? 20,
      live3dRenderQuality: Live3dRenderQuality.values.firstWhere(
        (quality) => quality.name == row['live3d_quality'],
        orElse: () => Live3dRenderQuality.balanced,
      ),
      live3dFpsCap: Live3dFpsCap.values.firstWhere(
        (cap) => cap.name == row['live3d_fps_cap'],
        orElse: () => Live3dFpsCap.fps60,
      ),
      autonomyEnabled: _toBool(row['autonomy_enabled']) ?? false,
      autonomyProactiveEnabled:
          _toBool(row['autonomy_proactive_enabled']) ?? false,
      autonomyProactiveIntervalMinutes:
          (row['autonomy_proactive_interval_minutes'] as num?)?.toInt() ?? 20,
      autonomyExploreEnabled: _toBool(row['autonomy_explore_enabled']) ?? false,
      autonomyExploreIntervalMinutes:
          (row['autonomy_explore_interval_minutes'] as num?)?.toInt() ?? 60,
      autonomyPlatforms: _parseAutonomyPlatforms(row['autonomy_platforms']),
      draftFormatStrategy: DraftFormatStrategy.values.firstWhere(
        (strategy) => strategy.name == row['draft_format_strategy'],
        orElse: () => DraftFormatStrategy.platformDefault,
      ),
      toolGatewayEnabled: _toBool(row['tool_gateway_enabled']) ?? false,
      toolGatewayBaseUrl:
          (row['tool_gateway_base_url'] as String?)?.trim().isNotEmpty == true
          ? (row['tool_gateway_base_url'] as String)
          : 'http://127.0.0.1:4891',
      toolGatewayPairingToken:
          row['tool_gateway_pairing_token'] as String? ?? '',
      standardWebSearchEnabled:
          _toBool(row['standard_web_search_enabled']) ?? true,
      deepResearchWebSearchEnabled:
          _toBool(row['deep_research_web_search_enabled']) ?? true,
      deepResearchWebImageVisionEnabled:
          _toBool(row['deep_research_web_image_vision_enabled']) ?? false,
      voiceChannelEnabled: _toBool(row['voice_channel_enabled']) ?? false,
      voiceChannelInjectEnabled:
          _toBool(row['voice_channel_inject_enabled']) ?? true,
      voiceChannelDeviceId: row['voice_channel_device_id'] as String?,
      voiceChannelDeviceLabel: row['voice_channel_device_label'] as String?,
      voiceChannelPlaybackDeviceId:
          row['voice_channel_playback_device_id'] as String?,
      voiceChannelPlaybackDeviceLabel:
          row['voice_channel_playback_device_label'] as String?,
      voiceChannelTtsInjectEnabled:
          _toBool(row['voice_channel_tts_inject_enabled']) ?? false,
      uiPalette: UiPalette.values.firstWhere(
        (palette) => palette.name == row['ui_palette'],
        orElse: () => UiPalette.jade,
      ),
      uiGlass: UiGlass.values.firstWhere(
        (glass) => glass.name == row['ui_glass'],
        orElse: () => UiGlass.standard,
      ),
      layoutPreset: LayoutPreset.values.firstWhere(
        (preset) => preset.name == row['layout_preset'],
        orElse: () => LayoutPreset.balanced,
      ),
      layoutSidebarWidth:
          (row['layout_sidebar_width'] as num?)?.toDouble() ?? 280.0,
      layoutRightPanelWidth:
          (row['layout_right_panel_width'] as num?)?.toDouble() ?? 380.0,
      layoutShowRightPanel: _toBool(row['layout_show_right_panel']) ?? true,
      danmakuEnabled: _toBool(row['danmaku_enabled']) ?? false,
      danmakuPlatform: DanmakuPlatform.values.firstWhere(
        (platform) => platform.name == row['danmaku_platform'],
        orElse: () => DanmakuPlatform.mock,
      ),
      danmakuRoomId: (row['danmaku_room_id'] as num?)?.toInt(),
      danmakuBatchIntervalSeconds:
          (row['danmaku_batch_interval_seconds'] as num?)?.toInt() ?? 20,
      danmakuBatchSize: (row['danmaku_batch_size'] as num?)?.toInt() ?? 50,
      danmakuInjectToChatEnabled:
          _toBool(row['danmaku_inject_to_chat_enabled']) ?? false,
      danmakuBilibiliSessData: row['danmaku_bilibili_sess_data'] as String?,
      danmakuBilibiliBiliJct: row['danmaku_bilibili_bili_jct'] as String?,
      danmakuBilibiliBuvid3: row['danmaku_bilibili_buvid3'] as String?,
    );
  }

  Map<String, Object?> _settingsToRow(AppSettings settings) {
    return {
      'id': 1,
      'route': settings.route.name,
      'active_profile_id': settings.activeProfileId,
      'llm_provider_id': settings.llmProviderId,
      'embedding_provider_id': settings.embeddingProviderId,
      'vision_provider_id': settings.visionProviderId,
      'tts_provider_id': settings.ttsProviderId,
      'stt_provider_id': settings.sttProviderId,
      'realtime_provider_id': settings.realtimeProviderId,
      'omni_provider_id': settings.omniProviderId,
      'live3d_model_path': settings.live3dModelPath,
      'persona_mode': settings.personaMode.name,
      'persona_level': settings.personaLevel.name,
      'persona_style': settings.personaStyle.name,
      'persona_prompt': settings.personaPrompt,
      'enable_system_tts': settings.enableSystemTts ? 1 : 0,
      'enable_system_stt': settings.enableSystemStt ? 1 : 0,
      'pet_mode': settings.petMode ? 1 : 0,
      'pet_follow_cursor': settings.petFollowCursor ? 1 : 0,
      'motion_agent_enabled': settings.motionAgentEnabled ? 1 : 0,
      'motion_agent_provider_id': settings.motionAgentProviderId,
      'motion_basic_count': settings.motionBasicCount,
      'motion_agent_cooldown_seconds': settings.motionAgentCooldownSeconds,
      'memory_agent_enabled': settings.memoryAgentEnabled ? 1 : 0,
      'memory_agent_provider_id': settings.memoryAgentProviderId,
      'memory_agent_cooldown_seconds': settings.memoryAgentCooldownSeconds,
      'live3d_quality': settings.live3dRenderQuality.name,
      'live3d_fps_cap': settings.live3dFpsCap.name,
      'autonomy_enabled': settings.autonomyEnabled ? 1 : 0,
      'autonomy_proactive_enabled': settings.autonomyProactiveEnabled ? 1 : 0,
      'autonomy_proactive_interval_minutes':
          settings.autonomyProactiveIntervalMinutes,
      'autonomy_explore_enabled': settings.autonomyExploreEnabled ? 1 : 0,
      'autonomy_explore_interval_minutes':
          settings.autonomyExploreIntervalMinutes,
      'autonomy_platforms': _autonomyPlatformsToRow(settings.autonomyPlatforms),
      'draft_format_strategy': settings.draftFormatStrategy.name,
      'tool_gateway_enabled': settings.toolGatewayEnabled ? 1 : 0,
      'tool_gateway_base_url': settings.toolGatewayBaseUrl,
      'tool_gateway_pairing_token': settings.toolGatewayPairingToken,
      'standard_web_search_enabled': settings.standardWebSearchEnabled ? 1 : 0,
      'deep_research_web_search_enabled': settings.deepResearchWebSearchEnabled
          ? 1
          : 0,
      'deep_research_web_image_vision_enabled':
          settings.deepResearchWebImageVisionEnabled ? 1 : 0,
      'voice_channel_enabled': settings.voiceChannelEnabled ? 1 : 0,
      'voice_channel_inject_enabled': settings.voiceChannelInjectEnabled
          ? 1
          : 0,
      'voice_channel_device_id': settings.voiceChannelDeviceId,
      'voice_channel_device_label': settings.voiceChannelDeviceLabel,
      'voice_channel_playback_device_id': settings.voiceChannelPlaybackDeviceId,
      'voice_channel_playback_device_label':
          settings.voiceChannelPlaybackDeviceLabel,
      'voice_channel_tts_inject_enabled': settings.voiceChannelTtsInjectEnabled
          ? 1
          : 0,
      'ui_palette': settings.uiPalette.name,
      'ui_glass': settings.uiGlass.name,
      'layout_preset': settings.layoutPreset.name,
      'layout_sidebar_width': settings.layoutSidebarWidth,
      'layout_right_panel_width': settings.layoutRightPanelWidth,
      'layout_show_right_panel': settings.layoutShowRightPanel ? 1 : 0,
      'danmaku_enabled': settings.danmakuEnabled ? 1 : 0,
      'danmaku_platform': settings.danmakuPlatform.name,
      'danmaku_room_id': settings.danmakuRoomId,
      'danmaku_batch_interval_seconds': settings.danmakuBatchIntervalSeconds,
      'danmaku_batch_size': settings.danmakuBatchSize,
      'danmaku_inject_to_chat_enabled':
          settings.danmakuInjectToChatEnabled ? 1 : 0,
      'danmaku_bilibili_sess_data': settings.danmakuBilibiliSessData,
      'danmaku_bilibili_bili_jct': settings.danmakuBilibiliBiliJct,
      'danmaku_bilibili_buvid3': settings.danmakuBilibiliBuvid3,
    };
  }

  InteractionProfile _interactionProfileFromRow(Map<String, Object?> row) {
    return InteractionProfile.fromJson({
      'id': row['id'],
      'name': row['name'],
      'mode': row['mode'],
      'bindings': jsonDecode(row['bindings_json'] as String),
      'options': jsonDecode(row['options_json'] as String),
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    });
  }

  Map<String, Object?> _interactionProfileToRow(InteractionProfile profile) {
    return {
      'id': profile.id,
      'name': profile.name,
      'mode': profile.mode.name,
      'bindings_json': jsonEncode(profile.bindings.toJson()),
      'options_json': jsonEncode(profile.options.toJson()),
      'created_at': profile.createdAt.toIso8601String(),
      'updated_at': profile.updatedAt.toIso8601String(),
    };
  }

  bool? _toBool(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value != 0;
    }
    if (value is bool) {
      return value;
    }
    return null;
  }

  List<AutonomyPlatform> _parseAutonomyPlatforms(Object? raw) {
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

  String _autonomyPlatformsToRow(List<AutonomyPlatform> platforms) {
    if (platforms.isEmpty) {
      return AutonomyPlatform.x.name;
    }
    return platforms.map((p) => p.name).join(',');
  }

  List<ProviderConfig> _defaultProviders() {
    return [
      ProviderConfig(
        id: _newId(),
        name: 'OpenAI LLM',
        kind: ProviderKind.llm,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
        embeddingModel: 'text-embedding-3-small',
        apiKey: '',
        capabilities: const [ProviderCapability.tools],
        notes: '标准文本模型 + 工具调用',
      ),
      ProviderConfig(
        id: _newId(),
        name: 'SiliconFlow LLM',
        kind: ProviderKind.llm,
        baseUrl: 'https://api.siliconflow.cn/v1',
        model: 'Qwen/Qwen2.5-72B-Instruct',
        apiKey: '',
        capabilities: const [ProviderCapability.tools],
        notes: '硅基流动 OpenAI 兼容接口',
      ),
      ProviderConfig(
        id: _newId(),
        name: 'LM Studio',
        kind: ProviderKind.llm,
        baseUrl: 'http://localhost:1234/v1',
        model: 'local-model',
        apiKey: '',
        capabilities: const [ProviderCapability.tools],
      ),
      ProviderConfig(
        id: _newId(),
        name: 'Ollama',
        kind: ProviderKind.llm,
        baseUrl: 'http://localhost:11434',
        model: 'llama3.1',
        protocol: ProviderProtocol.ollamaNative,
        apiKey: '',
        capabilities: const [ProviderCapability.tools],
      ),
      ProviderConfig(
        id: _newId(),
        name: 'Vision Agent',
        kind: ProviderKind.visionAgent,
        baseUrl: 'https://api.siliconflow.cn/v1',
        model: 'vision-agent',
        apiKey: '',
        capabilities: const [ProviderCapability.vision],
      ),
      ProviderConfig(
        id: _newId(),
        name: 'Realtime Voice (OpenAI compatible)',
        kind: ProviderKind.realtime,
        baseUrl: 'https://api.openai.com/v1',
        model: 'realtime-voice',
        apiKey: '',
        capabilities: const [
          ProviderCapability.audioIn,
          ProviderCapability.audioOut,
          ProviderCapability.bargeIn,
        ],
      ),
      ProviderConfig(
        id: _newId(),
        name: 'Realtime Voice (StepFun)',
        kind: ProviderKind.realtime,
        baseUrl: 'https://api.stepfun.com/v1',
        model: 'realtime-voice',
        apiKey: '',
        capabilities: const [
          ProviderCapability.audioIn,
          ProviderCapability.audioOut,
          ProviderCapability.bargeIn,
        ],
        notes: '按 StepFun realtime 文档调整模型与地址',
      ),
      ProviderConfig(
        id: _newId(),
        name: 'DashScope Qwen Omni',
        kind: ProviderKind.omni,
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        model: 'qwen3-omni-flash',
        apiKey: '',
        audioVoice: 'Cherry',
        audioFormat: 'wav',
        enableThinking: false,
        capabilities: const [
          ProviderCapability.vision,
          ProviderCapability.audioIn,
          ProviderCapability.audioOut,
          ProviderCapability.bargeIn,
        ],
      ),
      ProviderConfig(
        id: _newId(),
        name: 'Local TTS',
        kind: ProviderKind.tts,
        baseUrl: '',
        model: 'device',
        protocol: ProviderProtocol.deviceBuiltin,
        apiKey: '',
        outputSampleRate: 44100,
        audioChannels: 1,
        capabilities: const [ProviderCapability.audioOut],
      ),
      ProviderConfig(
        id: _newId(),
        name: 'SiliconFlow TTS',
        kind: ProviderKind.tts,
        baseUrl: 'https://api.siliconflow.cn/v1',
        model: 'FunAudioLLM/CosyVoice2-0.5B',
        apiKey: '',
        audioVoice: 'FunAudioLLM/CosyVoice2-0.5B:anna',
        audioFormat: 'wav',
        outputSampleRate: 32000,
        audioChannels: 1,
        capabilities: const [ProviderCapability.audioOut],
      ),
      ProviderConfig(
        id: _newId(),
        name: 'Local STT',
        kind: ProviderKind.stt,
        baseUrl: '',
        model: 'device',
        protocol: ProviderProtocol.deviceBuiltin,
        apiKey: '',
        inputAudioFormat: 'wav',
        inputSampleRate: 16000,
        audioChannels: 1,
        capabilities: const [ProviderCapability.audioIn],
      ),
      ProviderConfig(
        id: _newId(),
        name: 'SiliconFlow STT',
        kind: ProviderKind.stt,
        baseUrl: 'https://api.siliconflow.cn/v1',
        model: 'FunAudioLLM/SenseVoiceSmall',
        apiKey: '',
        inputAudioFormat: 'wav',
        inputSampleRate: 16000,
        audioChannels: 1,
        capabilities: const [ProviderCapability.audioIn],
      ),
    ];
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
