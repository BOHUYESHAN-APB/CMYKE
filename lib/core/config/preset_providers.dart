import '../models/provider_config.dart';

/// Preset provider configurations based on OpenCode Zen mainstream models.
/// 
/// Reference: https://opencode.ai/docs/zh-cn/zen/
/// 
/// Design principles:
/// - All providers use API token authentication (no coding interfaces)
/// - Compatible with @ai-sdk packages (openai, anthropic, google, openai-compatible)
/// - Template-based configuration to avoid user account bans
class PresetProviders {
  /// Get all preset providers.
  static List<ProviderConfig> getAll() {
    return [
      // OpenAI family
      ...openAIProviders,
      
      // Anthropic family
      ...anthropicProviders,
      
      // Google family
      ...googleProviders,
      
      // Chinese providers (OpenAI-compatible)
      ...chineseProviders,
    ];
  }

  /// OpenAI providers (@ai-sdk/openai)
  static final List<ProviderConfig> openAIProviders = [
    ProviderConfig(
      id: 'openai-gpt-5.5',
      name: 'OpenAI GPT-5.5',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://api.openai.com/v1',
      apiKey: '', // User must provide
      model: 'gpt-5.5',
      contextWindowTokens: 272000,
      maxTokens: 32000,
      capabilities: [ProviderCapability.vision, ProviderCapability.tools],
      notes: 'npm: @ai-sdk/openai | Pricing: \$5/\$30 per 1M tokens (input/output)',
    ),
    ProviderConfig(
      id: 'openai-gpt-5.4',
      name: 'OpenAI GPT-5.4',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://api.openai.com/v1',
      apiKey: '',
      model: 'gpt-5.4',
      contextWindowTokens: 272000,
      maxTokens: 32000,
      capabilities: [ProviderCapability.vision, ProviderCapability.tools],
      notes: 'npm: @ai-sdk/openai | Pricing: \$2.5/\$15 per 1M tokens',
    ),
    ProviderConfig(
      id: 'openai-gpt-5.4-mini',
      name: 'OpenAI GPT-5.4 Mini',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://api.openai.com/v1',
      apiKey: '',
      model: 'gpt-5.4-mini',
      contextWindowTokens: 128000,
      maxTokens: 16000,
      capabilities: [ProviderCapability.vision, ProviderCapability.tools],
      notes: 'npm: @ai-sdk/openai | Pricing: \$0.75/\$4.5 per 1M tokens',
    ),
  ];

  /// Anthropic providers (@ai-sdk/anthropic)
  static final List<ProviderConfig> anthropicProviders = [
    ProviderConfig(
      id: 'anthropic-opus-4.7',
      name: 'Claude Opus 4.7',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://api.anthropic.com/v1',
      apiKey: '',
      model: 'claude-opus-4-7',
      contextWindowTokens: 200000,
      maxTokens: 8192,
      capabilities: [ProviderCapability.vision, ProviderCapability.tools],
      notes: 'npm: @ai-sdk/anthropic | Pricing: \$5/\$25 per 1M tokens',
    ),
    ProviderConfig(
      id: 'anthropic-sonnet-4.6',
      name: 'Claude Sonnet 4.6',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://api.anthropic.com/v1',
      apiKey: '',
      model: 'claude-sonnet-4-6',
      contextWindowTokens: 200000,
      maxTokens: 8192,
      capabilities: [ProviderCapability.vision, ProviderCapability.tools],
      notes: 'npm: @ai-sdk/anthropic | Pricing: \$3/\$15 per 1M tokens',
    ),
    ProviderConfig(
      id: 'anthropic-haiku-4.5',
      name: 'Claude Haiku 4.5',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://api.anthropic.com/v1',
      apiKey: '',
      model: 'claude-haiku-4-5',
      contextWindowTokens: 200000,
      maxTokens: 8192,
      capabilities: [ProviderCapability.vision, ProviderCapability.tools],
      notes: 'npm: @ai-sdk/anthropic | Pricing: \$1/\$5 per 1M tokens',
    ),
  ];

  /// Google providers (@ai-sdk/google)
  static final List<ProviderConfig> googleProviders = [
    ProviderConfig(
      id: 'google-gemini-3.1-pro',
      name: 'Gemini 3.1 Pro',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://generativelanguage.googleapis.com/v1',
      apiKey: '',
      model: 'gemini-3.1-pro',
      contextWindowTokens: 200000,
      maxTokens: 8192,
      capabilities: [ProviderCapability.vision, ProviderCapability.tools],
      notes: 'npm: @ai-sdk/google | Pricing: \$2/\$12 per 1M tokens',
    ),
    ProviderConfig(
      id: 'google-gemini-3-flash',
      name: 'Gemini 3 Flash',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://generativelanguage.googleapis.com/v1',
      apiKey: '',
      model: 'gemini-3-flash',
      contextWindowTokens: 1000000,
      maxTokens: 8192,
      capabilities: [ProviderCapability.vision, ProviderCapability.tools],
      notes: 'npm: @ai-sdk/google | Pricing: \$0.5/\$3 per 1M tokens',
    ),
  ];

  /// Chinese providers (@ai-sdk/openai-compatible)
  static final List<ProviderConfig> chineseProviders = [
    // Alibaba Qwen
    ProviderConfig(
      id: 'alibaba-qwen3.6-plus',
      name: 'Qwen 3.6 Plus',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      apiKey: '',
      model: 'qwen3.6-plus',
      contextWindowTokens: 128000,
      maxTokens: 8192,
      capabilities: [ProviderCapability.tools],
      notes: 'npm: @ai-sdk/openai-compatible | Pricing: \$0.5/\$3 per 1M tokens',
    ),
    
    // Zhipu GLM
    ProviderConfig(
      id: 'zhipu-glm-5.1',
      name: 'GLM 5.1',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      apiKey: '',
      model: 'glm-5.1',
      contextWindowTokens: 128000,
      maxTokens: 8192,
      capabilities: [ProviderCapability.tools],
      notes: 'npm: @ai-sdk/openai-compatible | Pricing: \$1.4/\$4.4 per 1M tokens',
    ),
    
    // Moonshot Kimi
    ProviderConfig(
      id: 'moonshot-kimi-k2.6',
      name: 'Kimi K2.6',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://api.moonshot.cn/v1',
      apiKey: '',
      model: 'kimi-k2.6',
      contextWindowTokens: 128000,
      maxTokens: 8192,
      capabilities: [ProviderCapability.tools],
      notes: 'npm: @ai-sdk/openai-compatible | Pricing: \$0.95/\$4 per 1M tokens',
    ),
    
    // MiniMax
    ProviderConfig(
      id: 'minimax-m2.7',
      name: 'MiniMax M2.7',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://api.minimax.chat/v1',
      apiKey: '',
      model: 'minimax-m2.7',
      contextWindowTokens: 128000,
      maxTokens: 8192,
      capabilities: [ProviderCapability.tools],
      notes: 'npm: @ai-sdk/openai-compatible | Pricing: \$0.3/\$1.2 per 1M tokens',
    ),
    
    // Free models
    ProviderConfig(
      id: 'free-big-pickle',
      name: 'Big Pickle (Free)',
      kind: ProviderKind.llm,
      protocol: ProviderProtocol.openaiCompatible,
      baseUrl: 'https://api.example.com/v1', // Placeholder
      apiKey: '',
      model: 'big-pickle',
      contextWindowTokens: 128000,
      maxTokens: 8192,
      capabilities: [],
      notes: 'npm: @ai-sdk/openai-compatible | FREE during beta. Data may be used for model improvement.',
    ),
  ];

  /// Get providers by protocol type.
  static List<ProviderConfig> getByProtocol(ProviderProtocol protocol) {
    return getAll().where((p) => p.protocol == protocol).toList();
  }

  /// Get providers by npm package (extracted from notes).
  static List<ProviderConfig> getByNpmPackage(String package) {
    return getAll()
        .where((p) => p.notes?.contains(package) ?? false)
        .toList();
  }

  /// Get free providers (extracted from notes).
  static List<ProviderConfig> getFreeProviders() {
    return getAll()
        .where((p) => p.notes?.toUpperCase().contains('FREE') ?? false)
        .toList();
  }
}
