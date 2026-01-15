enum ProviderKind {
  llm,
  visionAgent,
  realtime,
  omni,
  tts,
  stt,
}

enum ProviderCapability {
  vision,
  audioIn,
  audioOut,
  bargeIn,
  tools,
}

enum ProviderProtocol {
  openaiCompatible,
  ollamaNative,
  deviceBuiltin,
}

class ProviderConfig {
  ProviderConfig({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    required this.model,
    this.embeddingModel,
    this.embeddingBaseUrl,
    this.embeddingApiKey,
    this.protocol = ProviderProtocol.openaiCompatible,
    this.apiKey,
    this.capabilities = const [],
    this.wsUrl,
    this.audioVoice,
    this.audioFormat,
    this.inputAudioFormat,
    this.inputSampleRate,
    this.outputSampleRate,
    this.audioChannels,
    this.temperature,
    this.topP,
    this.maxTokens,
    this.contextWindowTokens,
    this.frequencyPenalty,
    this.presencePenalty,
    this.seed,
    this.enableThinking,
    this.notes,
  });

  final String id;
  String name;
  final ProviderKind kind;
  String baseUrl;
  String model;
  String? embeddingModel;
  String? embeddingBaseUrl;
  String? embeddingApiKey;
  ProviderProtocol protocol;
  String? apiKey;
  List<ProviderCapability> capabilities;
  String? wsUrl;
  String? audioVoice;
  String? audioFormat;
  String? inputAudioFormat;
  int? inputSampleRate;
  int? outputSampleRate;
  int? audioChannels;
  double? temperature;
  double? topP;
  int? maxTokens;
  int? contextWindowTokens;
  double? frequencyPenalty;
  double? presencePenalty;
  int? seed;
  bool? enableThinking;
  String? notes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'base_url': baseUrl,
        'model': model,
        'embedding_model': embeddingModel,
        'embedding_base_url': embeddingBaseUrl,
        'embedding_api_key': embeddingApiKey,
        'protocol': protocol.name,
        'api_key': apiKey,
        'capabilities': capabilities.map((cap) => cap.name).toList(),
        'ws_url': wsUrl,
        'audio_voice': audioVoice,
        'audio_format': audioFormat,
        'audio_in_format': inputAudioFormat,
        'audio_in_sample_rate': inputSampleRate,
        'audio_out_sample_rate': outputSampleRate,
        'audio_channels': audioChannels,
        'temperature': temperature,
        'top_p': topP,
        'max_tokens': maxTokens,
        'context_window_tokens': contextWindowTokens,
        'frequency_penalty': frequencyPenalty,
        'presence_penalty': presencePenalty,
        'seed': seed,
        'enable_thinking': enableThinking,
        'notes': notes,
      };

  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: ProviderKind.values.firstWhere(
          (kind) => kind.name == json['kind'],
          orElse: () => ProviderKind.llm,
        ),
        baseUrl: json['base_url'] as String? ?? '',
        model: json['model'] as String? ?? '',
        embeddingModel: json['embedding_model'] as String?,
        embeddingBaseUrl: json['embedding_base_url'] as String?,
        embeddingApiKey: json['embedding_api_key'] as String?,
        protocol: ProviderProtocol.values.firstWhere(
          (protocol) => protocol.name == json['protocol'],
          orElse: () => ProviderProtocol.openaiCompatible,
        ),
        apiKey: json['api_key'] as String?,
        capabilities: (json['capabilities'] as List<dynamic>? ?? [])
            .map((entry) => ProviderCapability.values.firstWhere(
                  (cap) => cap.name == entry,
                  orElse: () => ProviderCapability.tools,
                ))
            .toList(),
        wsUrl: json['ws_url'] as String?,
        audioVoice: json['audio_voice'] as String?,
        audioFormat: json['audio_format'] as String?,
        inputAudioFormat: json['audio_in_format'] as String?,
        inputSampleRate: (json['audio_in_sample_rate'] as num?)?.toInt(),
        outputSampleRate: (json['audio_out_sample_rate'] as num?)?.toInt(),
        audioChannels: (json['audio_channels'] as num?)?.toInt(),
        temperature: (json['temperature'] as num?)?.toDouble(),
        topP: (json['top_p'] as num?)?.toDouble(),
        maxTokens: (json['max_tokens'] as num?)?.toInt(),
        contextWindowTokens:
            (json['context_window_tokens'] as num?)?.toInt(),
        frequencyPenalty: (json['frequency_penalty'] as num?)?.toDouble(),
        presencePenalty: (json['presence_penalty'] as num?)?.toDouble(),
        seed: (json['seed'] as num?)?.toInt(),
        enableThinking: json['enable_thinking'] as bool?,
        notes: json['notes'] as String?,
      );
}
