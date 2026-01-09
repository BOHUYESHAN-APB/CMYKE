import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/provider_config.dart';
import '../services/local_storage.dart';

class SettingsRepository extends ChangeNotifier {
  SettingsRepository({required LocalStorage storage}) : _storage = storage;

  final LocalStorage _storage;
  final List<ProviderConfig> _providers = [];
  late AppSettings _settings;

  static const String _providersFile = 'providers.json';
  static const String _settingsFile = 'settings.json';

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
    final providerData = await _storage.readJsonList(_providersFile);
    if (providerData == null || providerData.isEmpty) {
      _providers
        ..clear()
        ..addAll(_defaultProviders());
    } else {
      _providers
        ..clear()
        ..addAll(
          providerData.map(
            (entry) => ProviderConfig.fromJson(entry as Map<String, dynamic>),
          ),
        );
    }

    final settingsData = await _storage.readJsonMap(_settingsFile);
    _settings = settingsData == null
        ? AppSettings(route: ModelRoute.standard)
        : AppSettings.fromJson(settingsData);

    _ensureDefaults();
    notifyListeners();
    await _persist();
  }

  Future<void> addProvider(ProviderConfig provider) async {
    _providers.add(provider);
    notifyListeners();
    await _persist();
  }

  Future<void> updateProvider(ProviderConfig provider) async {
    final index = _providers.indexWhere((item) => item.id == provider.id);
    if (index == -1) {
      return;
    }
    _providers[index] = provider;
    notifyListeners();
    await _persist();
  }

  Future<void> removeProvider(String providerId) async {
    _providers.removeWhere((provider) => provider.id == providerId);
    _sanitizeSelections();
    notifyListeners();
    await _persist();
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    _sanitizeSelections();
    notifyListeners();
    await _persist();
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

  Future<void> _persist() async {
    await _storage.writeJson(
      _providersFile,
      _providers.map((provider) => provider.toJson()).toList(),
    );
    await _storage.writeJson(_settingsFile, _settings.toJson());
  }

  List<ProviderConfig> _defaultProviders() {
    return [
      ProviderConfig(
        id: _newId(),
        name: 'OpenAI LLM',
        kind: ProviderKind.llm,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
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
