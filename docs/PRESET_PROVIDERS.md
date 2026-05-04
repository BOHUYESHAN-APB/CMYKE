# 预设服务商配置

本文档说明如何使用 CMYKE 的预设服务商配置。

## 概述

CMYKE 提供了 13 个主流 AI 模型的预设配置，基于 [OpenCode Zen](https://opencode.ai/docs/zh-cn/zen/) 的推荐列表。

**设计原则：**
- ✅ 仅使用 API Token 认证（不包含 Coding 接口）
- ✅ 兼容 @ai-sdk 包（openai, anthropic, google, openai-compatible）
- ✅ 模板化配置，避免用户账号被封

## 支持的服务商

### OpenAI 系列 (@ai-sdk/openai)

| 模型 ID | 名称 | 上下文窗口 | 最大输出 | 定价 (输入/输出) |
|---------|------|-----------|---------|-----------------|
| `openai-gpt-5.5` | OpenAI GPT-5.5 | 272K | 32K | $5/$30 per 1M tokens |
| `openai-gpt-5.4` | OpenAI GPT-5.4 | 272K | 32K | $2.5/$15 per 1M tokens |
| `openai-gpt-5.4-mini` | OpenAI GPT-5.4 Mini | 128K | 16K | $0.75/$4.5 per 1M tokens |

**能力：** Chat, Vision, Tool Calling

### Anthropic 系列 (@ai-sdk/anthropic)

| 模型 ID | 名称 | 上下文窗口 | 最大输出 | 定价 (输入/输出) |
|---------|------|-----------|---------|-----------------|
| `anthropic-opus-4.7` | Claude Opus 4.7 | 200K | 8K | $5/$25 per 1M tokens |
| `anthropic-sonnet-4.6` | Claude Sonnet 4.6 | 200K | 8K | $3/$15 per 1M tokens |
| `anthropic-haiku-4.5` | Claude Haiku 4.5 | 200K | 8K | $1/$5 per 1M tokens |

**能力：** Chat, Vision, Tool Calling

### Google 系列 (@ai-sdk/google)

| 模型 ID | 名称 | 上下文窗口 | 最大输出 | 定价 (输入/输出) |
|---------|------|-----------|---------|-----------------|
| `google-gemini-3.1-pro` | Gemini 3.1 Pro | 200K | 8K | $2/$12 per 1M tokens |
| `google-gemini-3-flash` | Gemini 3 Flash | 1M | 8K | $0.5/$3 per 1M tokens |

**能力：** Chat, Vision, Tool Calling

### 中国服务商 (@ai-sdk/openai-compatible)

| 模型 ID | 名称 | 上下文窗口 | 最大输出 | 定价 (输入/输出) |
|---------|------|-----------|---------|-----------------|
| `alibaba-qwen3.6-plus` | Qwen 3.6 Plus | 128K | 8K | $0.5/$3 per 1M tokens |
| `zhipu-glm-5.1` | GLM 5.1 | 128K | 8K | $1.4/$4.4 per 1M tokens |
| `moonshot-kimi-k2.6` | Kimi K2.6 | 128K | 8K | $0.95/$4 per 1M tokens |
| `minimax-m2.7` | MiniMax M2.7 | 128K | 8K | $0.3/$1.2 per 1M tokens |
| `free-big-pickle` | Big Pickle (Free) | 128K | 8K | **FREE** (Beta) |

**能力：** Chat, Tool Calling

⚠️ **注意：** Big Pickle 在测试期间免费，数据可能用于模型改进。

## 使用方法

### 1. 获取所有预设配置

```dart
import 'package:cmyke/core/config/preset_providers.dart';

// 获取所有预设
final allProviders = PresetProviders.getAll();

// 按协议筛选
final openaiProviders = PresetProviders.getByProtocol(ProviderProtocol.openaiCompatible);

// 按 npm 包筛选
final anthropicProviders = PresetProviders.getByNpmPackage('@ai-sdk/anthropic');

// 获取免费模型
final freeProviders = PresetProviders.getFreeProviders();
```

### 2. 配置 API Key

预设配置中的 `apiKey` 字段为空，需要用户手动填写：

```dart
final provider = PresetProviders.openAIProviders.first;
provider.apiKey = 'sk-...'; // 用户的 OpenAI API Key
```

### 3. 保存到设置

```dart
final settingsRepo = SettingsRepository();
final settings = await settingsRepo.getSettings();

// 添加预设配置
settings.providers.add(provider);

await settingsRepo.saveSettings(settings);
```

### 4. 在 UI 中使用

```dart
// 在设置页面显示预设列表
ListView.builder(
  itemCount: PresetProviders.getAll().length,
  itemBuilder: (context, index) {
    final preset = PresetProviders.getAll()[index];
    return ListTile(
      title: Text(preset.name),
      subtitle: Text(preset.notes ?? ''),
      trailing: IconButton(
        icon: Icon(Icons.add),
        onPressed: () {
          // 添加到用户配置
          _addProvider(preset);
        },
      ),
    );
  },
);
```

## 与 ai-gateway 集成

CMYKE 的预设配置与你的 [ai-gateway](https://github.com/yourusername/ai-gateway) 项目兼容：

```dart
// 从 ai-gateway 的 UniversalProviderConfig 转换
import 'package:ai_gateway/config/universal.dart';

final universalConfig = UniversalProviderConfig(
  id: 'openai-gpt-5.5',
  name: 'OpenAI GPT-5.5',
  baseUrl: 'https://api.openai.com/v1',
  apiKey: 'sk-...',
  protocol: ProtocolType.OpenAI,
  models: [...],
);

// 转换为 CMYKE ProviderConfig
final cmykeConfig = ProviderConfig(
  id: universalConfig.id,
  name: universalConfig.name,
  kind: ProviderKind.llm,
  baseUrl: universalConfig.baseUrl,
  apiKey: universalConfig.apiKey,
  model: universalConfig.models.first.id,
  protocol: _mapProtocol(universalConfig.protocol),
);
```

## 安全注意事项

1. **不要硬编码 API Key**：预设配置中的 `apiKey` 字段为空，必须由用户提供。
2. **避免使用 Coding 接口**：所有预设配置仅使用标准 API Token 认证，不包含可能导致封号的 Coding 接口。
3. **数据隐私**：免费模型（如 Big Pickle）可能会收集数据用于改进，请查看 `notes` 字段中的说明。

## 扩展预设

如果需要添加新的预设配置，编辑 `lib/core/config/preset_providers.dart`：

```dart
static final List<ProviderConfig> customProviders = [
  ProviderConfig(
    id: 'custom-model',
    name: 'Custom Model',
    kind: ProviderKind.llm,
    protocol: ProviderProtocol.openaiCompatible,
    baseUrl: 'https://api.custom.com/v1',
    apiKey: '',
    model: 'custom-model-v1',
    contextWindowTokens: 128000,
    maxTokens: 8192,
    capabilities: [ProviderCapability.tools],
    notes: 'npm: @ai-sdk/openai-compatible | Custom pricing',
  ),
];
```

## 参考资料

- [OpenCode Zen 文档](https://opencode.ai/docs/zh-cn/zen/)
- [Vercel AI SDK](https://sdk.vercel.ai/docs)
- [ai-gateway 项目](https://github.com/yourusername/ai-gateway)

## 常见问题

**Q: 为什么不包含 Coding 接口？**  
A: Coding 接口（如 Claude Code）可能导致用户账号被封，我们只提供标准 API Token 认证的模型。

**Q: 如何获取 API Key？**  
A: 访问对应服务商的官网（OpenAI、Anthropic、Google 等）注册账号并生成 API Key。

**Q: 预设配置会自动更新吗？**  
A: 不会。预设配置是静态的，如果需要最新的模型列表，请参考 OpenCode Zen 文档手动更新。

**Q: 可以同时使用多个服务商吗？**  
A: 可以。CMYKE 支持配置多个服务商，用户可以在设置中切换。
