import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_settings.dart';
import '../models/provider_config.dart';
import '../services/local_database.dart';
import '../services/local_storage.dart';

class SettingsRepository extends ChangeNotifier {
  SettingsRepository({
    required LocalDatabase database,
    LocalStorage? legacyStorage,
  })  : _database = database,
        _legacyStorage = legacyStorage ?? LocalStorage();

  final LocalDatabase _database;
  final LocalStorage _legacyStorage;
  final List<ProviderConfig> _providers = [];
  late AppSettings _settings;

  static const String _providersFile = 'providers.json';
  static const String _settingsFile = 'settings.json';
  static const String _providersTable = 'providers';
  static const String _settingsTable = 'app_settings';

  List<ProviderConfig> get providers => List.unmodifiable(_providers);
  AppSettings get settings => _settings;

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

    _ensureDefaults();
    notifyListeners();
    await _persistSettings(db);
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
    await db.delete(
      _providersTable,
      where: 'id = ?',
      whereArgs: [providerId],
    );
    _sanitizeSelections();
    await _persistSettings(db);
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings settings) async {
    final db = await _database.database;
    _settings = settings;
    _sanitizeSelections();
    await _persistSettings(db);
    notifyListeners();
  }

  void _ensureDefaults() {
    _sanitizeSelections();
    if (_settings.llmProviderId == null &&
        providersByKind(ProviderKind.llm).isNotEmpty) {
      _settings.llmProviderId = providersByKind(ProviderKind.llm).first.id;
    }
    if (_settings.visionProviderId == null &&
        providersByKind(ProviderKind.visionAgent).isNotEmpty) {
      _settings.visionProviderId =
          providersByKind(ProviderKind.visionAgent).first.id;
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
      _settings.realtimeProviderId =
          providersByKind(ProviderKind.realtime).first.id;
    }
    if (_settings.omniProviderId == null &&
        providersByKind(ProviderKind.omni).isNotEmpty) {
      _settings.omniProviderId = providersByKind(ProviderKind.omni).first.id;
    }
  }

  void _sanitizeSelections() {
    final ids = _providers.map((provider) => provider.id).toSet();
    if (_settings.llmProviderId != null &&
        !ids.contains(_settings.llmProviderId)) {
      _settings.llmProviderId = null;
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

  Future<void> _importLegacy(Database db) async {
    final providerData = await _legacyStorage.readJsonList(_providersFile);
    if (providerData != null && providerData.isNotEmpty) {
      final batch = db.batch();
      for (final entry in providerData) {
        final provider =
            ProviderConfig.fromJson(entry as Map<String, dynamic>);
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
            .map((entry) => ProviderCapability.values.firstWhere(
                  (cap) => cap.name == entry,
                  orElse: () => ProviderCapability.tools,
                ))
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
      llmProviderId: row['llm_provider_id'] as String?,
      visionProviderId: row['vision_provider_id'] as String?,
      ttsProviderId: row['tts_provider_id'] as String?,
      sttProviderId: row['stt_provider_id'] as String?,
      realtimeProviderId: row['realtime_provider_id'] as String?,
      omniProviderId: row['omni_provider_id'] as String?,
    );
  }

  Map<String, Object?> _settingsToRow(AppSettings settings) {
    return {
      'id': 1,
      'route': settings.route.name,
      'llm_provider_id': settings.llmProviderId,
      'vision_provider_id': settings.visionProviderId,
      'tts_provider_id': settings.ttsProviderId,
      'stt_provider_id': settings.sttProviderId,
      'realtime_provider_id': settings.realtimeProviderId,
      'omni_provider_id': settings.omniProviderId,
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
