import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/provider_config.dart';
import '../../core/repositories/settings_repository.dart';

class ProviderConfigScreen extends StatelessWidget {
  const ProviderConfigScreen({
    super.key,
    required this.settingsRepository,
  });

  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsRepository,
      builder: (context, _) {
        final settings = settingsRepository.settings;
        return Scaffold(
          appBar: AppBar(
            title: const Text('模型与能力配置'),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth =
                  constraints.maxWidth >= 1040 ? 980.0 : constraints.maxWidth;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _SectionHeader(
                        title: '运行模式',
                        subtitle: '选择普通 LLM、实时语音模型或 Omni 模型',
                      ),
                      const SizedBox(height: 12),
                      _RouteSelector(
                        route: settings.route,
                        onChanged: (route) {
                          settingsRepository.updateSettings(
                            settings.copyWith(route: route),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _HintCard(
                        title: '快速说明',
                        items: const [
                          '普通 LLM 模式：可直接工具调用，适合深度搜索/研究。',
                          'Realtime 模式：由控制代理调用工具，保证低延迟对话。',
                          '需要向量检索时请填写 Embedding Model。',
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (settings.route == ModelRoute.standard) ...[
                        _SectionHeader(
                          title: '普通 LLM 组合',
                          subtitle: 'LLM + 视觉 Agent + TTS + STT',
                        ),
                        const SizedBox(height: 12),
                        _ProviderPicker(
                          label: 'LLM 模型',
                          providers:
                              settingsRepository.providersByKind(ProviderKind.llm),
                          selectedId: settings.llmProviderId,
                          onChanged: (id) {
                            settingsRepository.updateSettings(
                              settings.copyWith(llmProviderId: id),
                            );
                          },
                        ),
                        _ProviderPicker(
                          label: '视觉 Agent',
                          providers: settingsRepository
                              .providersByKind(ProviderKind.visionAgent),
                          selectedId: settings.visionProviderId,
                          onChanged: (id) {
                            settingsRepository.updateSettings(
                              settings.copyWith(visionProviderId: id),
                            );
                          },
                        ),
                        _ProviderPicker(
                          label: 'TTS',
                          providers:
                              settingsRepository.providersByKind(ProviderKind.tts),
                          selectedId: settings.ttsProviderId,
                          onChanged: (id) {
                            settingsRepository.updateSettings(
                              settings.copyWith(ttsProviderId: id),
                            );
                          },
                        ),
                        _ProviderPicker(
                          label: 'STT',
                          providers:
                              settingsRepository.providersByKind(ProviderKind.stt),
                          selectedId: settings.sttProviderId,
                          onChanged: (id) {
                            settingsRepository.updateSettings(
                              settings.copyWith(sttProviderId: id),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (settings.route == ModelRoute.realtime) ...[
                        _SectionHeader(
                          title: '实时语音模型',
                          subtitle: '带实时语音输出与打断能力',
                        ),
                        const SizedBox(height: 12),
                        _ProviderPicker(
                          label: 'Realtime 模型',
                          providers:
                              settingsRepository.providersByKind(ProviderKind.realtime),
                          selectedId: settings.realtimeProviderId,
                          onChanged: (id) {
                            settingsRepository.updateSettings(
                              settings.copyWith(realtimeProviderId: id),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (settings.route == ModelRoute.omni) ...[
                        _SectionHeader(
                          title: 'Omni 模型',
                          subtitle: '文本 + 语音 + 视觉一体化',
                        ),
                        const SizedBox(height: 12),
                        _ProviderPicker(
                          label: 'Omni 模型',
                          providers:
                              settingsRepository.providersByKind(ProviderKind.omni),
                          selectedId: settings.omniProviderId,
                          onChanged: (id) {
                            settingsRepository.updateSettings(
                              settings.copyWith(omniProviderId: id),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                      ],
                      _CollapsibleSection(
                        title: '模型与能力清单',
                        subtitle: '管理所有 Provider 与高级参数',
                        child: _ProviderCatalog(
                          settingsRepository: settingsRepository,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _SectionHeader(
                        title: '软件与反馈',
                        subtitle: '版本信息、代码仓库与反馈渠道',
                      ),
                      const SizedBox(height: 12),
                      const _AppInfoSection(),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RouteSelector extends StatelessWidget {
  const _RouteSelector({
    required this.route,
    required this.onChanged,
  });

  final ModelRoute route;
  final ValueChanged<ModelRoute> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ModelRoute>(
      segments: const [
        ButtonSegment(
          value: ModelRoute.standard,
          label: Text('普通 LLM'),
          icon: Icon(Icons.chat_bubble_outline),
        ),
        ButtonSegment(
          value: ModelRoute.realtime,
          label: Text('Realtime'),
          icon: Icon(Icons.hearing),
        ),
        ButtonSegment(
          value: ModelRoute.omni,
          label: Text('Omni'),
          icon: Icon(Icons.auto_awesome),
        ),
      ],
      selected: {route},
      onSelectionChanged: (value) {
        onChanged(value.first);
      },
    );
  }
}

class _ProviderPicker extends StatelessWidget {
  const _ProviderPicker({
    required this.label,
    required this.providers,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final List<ProviderConfig> providers;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: selectedId,
        decoration: InputDecoration(labelText: label),
        items: providers
            .map(
              (provider) => DropdownMenuItem(
                value: provider.id,
                child: Text(provider.name),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _ProviderCatalog extends StatelessWidget {
  const _ProviderCatalog({
    required this.settingsRepository,
  });

  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProviderSection(
          title: '普通 LLM',
          kind: ProviderKind.llm,
          settingsRepository: settingsRepository,
        ),
        _ProviderSection(
          title: '视觉 Agent',
          kind: ProviderKind.visionAgent,
          settingsRepository: settingsRepository,
        ),
        _ProviderSection(
          title: 'Realtime 模型',
          kind: ProviderKind.realtime,
          settingsRepository: settingsRepository,
        ),
        _ProviderSection(
          title: 'Omni 模型',
          kind: ProviderKind.omni,
          settingsRepository: settingsRepository,
        ),
        _ProviderSection(
          title: 'TTS',
          kind: ProviderKind.tts,
          settingsRepository: settingsRepository,
        ),
        _ProviderSection(
          title: 'STT',
          kind: ProviderKind.stt,
          settingsRepository: settingsRepository,
        ),
      ],
    );
  }
}

class _ProviderSection extends StatelessWidget {
  const _ProviderSection({
    required this.title,
    required this.kind,
    required this.settingsRepository,
  });

  final String title;
  final ProviderKind kind;
  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    final providers = settingsRepository.providersByKind(kind);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    _openProviderDialog(
                      context,
                      settingsRepository,
                      kind: kind,
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('新增'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (providers.isEmpty)
              Text(
                '暂无配置',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B6F7A),
                    ),
              ),
            ...providers.map(
              (provider) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(provider.name),
                subtitle: Text('${provider.baseUrl} · ${provider.model}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: '编辑',
                      onPressed: () {
                        _openProviderDialog(
                          context,
                          settingsRepository,
                          kind: kind,
                          provider: provider,
                        );
                      },
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                    IconButton(
                      tooltip: '删除',
                      onPressed: () {
                        settingsRepository.removeProvider(provider.id);
                      },
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.notoSerifSc(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1F2228),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B6F7A),
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('- '),
                    Expanded(
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF5E636F),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B6F7A),
              ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _AppInfoSection extends StatelessWidget {
  const _AppInfoSection();

  static const String _repoUrl = 'https://github.com/BOHUYESHAN-APB/CMYKE';
  static const String _feedback = 'https://github.com/BOHUYESHAN-APB/CMYKE/issues';
  static const String _license = 'Apache-2.0 (planned)';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            final info = snapshot.data;
            final version = info == null
                ? '读取中...'
                : '${info.version}+${info.buildNumber}';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  label: '版本号',
                  value: version,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: '代码仓库',
                  value: _repoUrl,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: '反馈渠道',
                  value: _feedback,
                ),
                const SizedBox(height: 12),
                const _InfoRow(
                  label: '许可协议',
                  value: _license,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF6B6F7A),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

Future<void> _openProviderDialog(
  BuildContext context,
  SettingsRepository repository, {
  required ProviderKind kind,
  ProviderConfig? provider,
}) async {
  final nameController =
      TextEditingController(text: provider?.name ?? '');
  final baseUrlController =
      TextEditingController(text: provider?.baseUrl ?? '');
  final modelController =
      TextEditingController(text: provider?.model ?? '');
  final embeddingModelController =
      TextEditingController(text: provider?.embeddingModel ?? '');
  final notesController =
      TextEditingController(text: provider?.notes ?? '');
  final selectedCapabilities = <ProviderCapability>{
    ...(provider?.capabilities ?? _defaultCapabilities(kind)),
  };
  final apiKeyController =
      TextEditingController(text: provider?.apiKey ?? '');
  final audioVoiceController =
      TextEditingController(text: provider?.audioVoice ?? '');
  final audioFormatController =
      TextEditingController(text: provider?.audioFormat ?? '');
  final inputAudioFormatController =
      TextEditingController(text: provider?.inputAudioFormat ?? '');
  final inputSampleRateController = TextEditingController(
    text: provider?.inputSampleRate?.toString() ?? '',
  );
  final outputSampleRateController = TextEditingController(
    text: provider?.outputSampleRate?.toString() ?? '',
  );
  final audioChannelsController = TextEditingController(
    text: provider?.audioChannels?.toString() ?? '',
  );
  final temperatureController = TextEditingController(
    text: provider?.temperature?.toString() ?? '',
  );
  final topPController = TextEditingController(
    text: provider?.topP?.toString() ?? '',
  );
  final maxTokensController = TextEditingController(
    text: provider?.maxTokens?.toString() ?? '',
  );
  final presencePenaltyController = TextEditingController(
    text: provider?.presencePenalty?.toString() ?? '',
  );
  final frequencyPenaltyController = TextEditingController(
    text: provider?.frequencyPenalty?.toString() ?? '',
  );
  final seedController = TextEditingController(
    text: provider?.seed?.toString() ?? '',
  );
  final wsUrlController =
      TextEditingController(text: provider?.wsUrl ?? '');
  final showAudioSettings = kind == ProviderKind.omni ||
      kind == ProviderKind.tts ||
      kind == ProviderKind.realtime ||
      kind == ProviderKind.stt;
  final showRealtimeSettings =
      kind == ProviderKind.realtime || kind == ProviderKind.omni;
  final showModelTuning = kind == ProviderKind.llm ||
      kind == ProviderKind.realtime ||
      kind == ProviderKind.omni ||
      kind == ProviderKind.visionAgent;
  ProviderProtocol protocol =
      provider?.protocol ?? ProviderProtocol.openaiCompatible;
  bool enableThinking = provider?.enableThinking ?? false;

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final supportsAudioIn =
              selectedCapabilities.contains(ProviderCapability.audioIn) ||
                  kind == ProviderKind.stt;
          final supportsAudioOut =
              selectedCapabilities.contains(ProviderCapability.audioOut) ||
                  kind == ProviderKind.tts;
          return AlertDialog(
            title: Text(provider == null ? '新增配置' : '编辑配置'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '名称'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: baseUrlController,
                    decoration: const InputDecoration(labelText: 'Base URL'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelController,
                    decoration: const InputDecoration(labelText: '模型/端点'),
                  ),
                  if (kind == ProviderKind.llm) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: embeddingModelController,
                      decoration: const InputDecoration(
                        labelText: 'Embedding Model (向量检索)',
                        hintText: '例如 text-embedding-3-small',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ProviderProtocol>(
                    value: protocol,
                    decoration: const InputDecoration(labelText: '调用协议'),
                    items: const [
                      DropdownMenuItem(
                        value: ProviderProtocol.openaiCompatible,
                        child: Text('OpenAI Compatible (/v1/chat/completions)'),
                      ),
                      DropdownMenuItem(
                        value: ProviderProtocol.ollamaNative,
                        child: Text('Ollama Native (/api/chat)'),
                      ),
                      DropdownMenuItem(
                        value: ProviderProtocol.deviceBuiltin,
                        child: Text('Device Built-in (本地能力)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => protocol = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (showRealtimeSettings) ...[
                    TextField(
                      controller: wsUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Realtime WS URL',
                        hintText: 'wss://... (可选)',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '快速预设',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PresetChip(
                        label: 'OpenAI',
                        onTap: () {
                          setState(() {
                            protocol = ProviderProtocol.openaiCompatible;
                            baseUrlController.text = 'https://api.openai.com/v1';
                          });
                        },
                      ),
                      _PresetChip(
                        label: 'SiliconFlow',
                        onTap: () {
                          setState(() {
                            protocol = ProviderProtocol.openaiCompatible;
                            baseUrlController.text =
                                'https://api.siliconflow.cn/v1';
                            if (kind == ProviderKind.tts) {
                              audioVoiceController.text =
                                  audioVoiceController.text.isEmpty
                                      ? 'FunAudioLLM/CosyVoice2-0.5B:anna'
                                      : audioVoiceController.text;
                              audioFormatController.text =
                                  audioFormatController.text.isEmpty
                                      ? 'wav'
                                      : audioFormatController.text;
                              outputSampleRateController.text =
                                  outputSampleRateController.text.isEmpty
                                      ? '32000'
                                      : outputSampleRateController.text;
                              audioChannelsController.text =
                                  audioChannelsController.text.isEmpty
                                      ? '1'
                                      : audioChannelsController.text;
                            }
                            if (kind == ProviderKind.stt) {
                              inputAudioFormatController.text =
                                  inputAudioFormatController.text.isEmpty
                                      ? 'wav'
                                      : inputAudioFormatController.text;
                              inputSampleRateController.text =
                                  inputSampleRateController.text.isEmpty
                                      ? '16000'
                                      : inputSampleRateController.text;
                              audioChannelsController.text =
                                  audioChannelsController.text.isEmpty
                                      ? '1'
                                      : audioChannelsController.text;
                            }
                          });
                        },
                      ),
                      _PresetChip(
                        label: 'DashScope',
                        onTap: () {
                          setState(() {
                            protocol = ProviderProtocol.openaiCompatible;
                            baseUrlController.text =
                                'https://dashscope.aliyuncs.com/compatible-mode/v1';
                            if (kind == ProviderKind.omni) {
                              audioVoiceController.text =
                                  audioVoiceController.text.isEmpty
                                      ? 'Cherry'
                                      : audioVoiceController.text;
                              audioFormatController.text =
                                  audioFormatController.text.isEmpty
                                      ? 'wav'
                                      : audioFormatController.text;
                            }
                          });
                        },
                      ),
                      _PresetChip(
                        label: 'StepFun',
                        onTap: () {
                          setState(() {
                            protocol = ProviderProtocol.openaiCompatible;
                            baseUrlController.text = 'https://api.stepfun.com/v1';
                          });
                        },
                      ),
                      _PresetChip(
                        label: 'LM Studio',
                        onTap: () {
                          setState(() {
                            protocol = ProviderProtocol.openaiCompatible;
                            baseUrlController.text =
                                'http://localhost:1234/v1';
                          });
                        },
                      ),
                      _PresetChip(
                        label: 'Ollama',
                        onTap: () {
                          setState(() {
                            protocol = ProviderProtocol.ollamaNative;
                            baseUrlController.text = 'http://localhost:11434';
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'API Key (本地加密存储)',
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  if (showModelTuning) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '模型参数',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: temperatureController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Temperature',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: topPController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Top P',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: maxTokensController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Max Tokens',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: seedController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Seed',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: presencePenaltyController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Presence Penalty',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: frequencyPenaltyController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Frequency Penalty',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showAudioSettings && supportsAudioIn) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '音频输入',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: inputAudioFormatController,
                      decoration: const InputDecoration(
                        labelText: '输入格式',
                        hintText: 'pcm / wav / opus / mp3',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: inputSampleRateController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '输入采样率',
                              hintText: '例如 16000',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: audioChannelsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '声道',
                              hintText: '1 / 2',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showAudioSettings && supportsAudioOut) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '音频输出',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: audioVoiceController,
                      decoration: const InputDecoration(
                        labelText: '音色',
                        hintText: '例如 Cherry / CosyVoice voice id',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: audioFormatController,
                      decoration: const InputDecoration(
                        labelText: '输出格式',
                        hintText: 'wav / mp3 / pcm / opus',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: outputSampleRateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '输出采样率',
                        hintText: '例如 44100',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (kind == ProviderKind.omni) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用思考模式'),
                      value: enableThinking,
                      onChanged: (value) {
                        setState(() => enableThinking = value);
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '能力标记',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ProviderCapability.values.map((capability) {
                      final selected =
                          selectedCapabilities.contains(capability);
                      return FilterChip(
                        label: Text(_capabilityLabel(capability)),
                        selected: selected,
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              selectedCapabilities.add(capability);
                            } else {
                              selectedCapabilities.remove(capability);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '备注',
                      hintText: '例如：支持 barge-in、带视觉回退等',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    return;
                  }
                  final config = ProviderConfig(
                    id: provider?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name,
                    kind: kind,
                    baseUrl: baseUrlController.text.trim(),
                    model: modelController.text.trim(),
                    embeddingModel:
                        embeddingModelController.text.trim().isEmpty
                            ? null
                            : embeddingModelController.text.trim(),
                    protocol: protocol,
                    apiKey: apiKeyController.text.trim(),
                    capabilities: selectedCapabilities.toList(),
                    wsUrl: wsUrlController.text.trim().isEmpty
                        ? null
                        : wsUrlController.text.trim(),
                    audioVoice: audioVoiceController.text.trim().isEmpty
                        ? null
                        : audioVoiceController.text.trim(),
                    audioFormat: audioFormatController.text.trim().isEmpty
                        ? null
                        : audioFormatController.text.trim(),
                    inputAudioFormat:
                        inputAudioFormatController.text.trim().isEmpty
                            ? null
                            : inputAudioFormatController.text.trim(),
                    inputSampleRate:
                        _parseInt(inputSampleRateController.text),
                    outputSampleRate:
                        _parseInt(outputSampleRateController.text),
                    audioChannels: _parseInt(audioChannelsController.text),
                    temperature: _parseDouble(temperatureController.text),
                    topP: _parseDouble(topPController.text),
                    maxTokens: _parseInt(maxTokensController.text),
                    presencePenalty:
                        _parseDouble(presencePenaltyController.text),
                    frequencyPenalty:
                        _parseDouble(frequencyPenaltyController.text),
                    seed: _parseInt(seedController.text),
                    enableThinking:
                        kind == ProviderKind.omni ? enableThinking : null,
                    notes: notesController.text.trim().isEmpty
                        ? null
                        : notesController.text.trim(),
                  );
                  if (provider == null) {
                    repository.addProvider(config);
                  } else {
                    repository.updateProvider(config);
                  }
                  Navigator.of(context).pop();
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );
  nameController.dispose();
  baseUrlController.dispose();
  modelController.dispose();
  embeddingModelController.dispose();
  apiKeyController.dispose();
  audioVoiceController.dispose();
  audioFormatController.dispose();
  inputAudioFormatController.dispose();
  inputSampleRateController.dispose();
  outputSampleRateController.dispose();
  audioChannelsController.dispose();
  temperatureController.dispose();
  topPController.dispose();
  maxTokensController.dispose();
  presencePenaltyController.dispose();
  frequencyPenaltyController.dispose();
  seedController.dispose();
  wsUrlController.dispose();
  notesController.dispose();
}

double? _parseDouble(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return double.tryParse(trimmed);
}

int? _parseInt(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return int.tryParse(trimmed);
}

String _capabilityLabel(ProviderCapability capability) {
  switch (capability) {
    case ProviderCapability.vision:
      return '视觉';
    case ProviderCapability.audioIn:
      return '语音输入';
    case ProviderCapability.audioOut:
      return '语音输出';
    case ProviderCapability.bargeIn:
      return '可打断';
    case ProviderCapability.tools:
      return '工具';
  }
}

Set<ProviderCapability> _defaultCapabilities(ProviderKind kind) {
  switch (kind) {
    case ProviderKind.llm:
      return {ProviderCapability.tools};
    case ProviderKind.visionAgent:
      return {ProviderCapability.vision};
    case ProviderKind.realtime:
      return {
        ProviderCapability.audioIn,
        ProviderCapability.audioOut,
        ProviderCapability.bargeIn,
      };
    case ProviderKind.omni:
      return {
        ProviderCapability.vision,
        ProviderCapability.audioIn,
        ProviderCapability.audioOut,
        ProviderCapability.bargeIn,
      };
    case ProviderKind.tts:
      return {ProviderCapability.audioOut};
    case ProviderKind.stt:
      return {ProviderCapability.audioIn};
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
    );
  }
}
