import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/expression_event.dart';
import '../../core/models/provider_config.dart';
import '../../core/models/stage_action.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/runtime_hub.dart';
import '../../ui/theme/cmyke_chrome.dart';
import '../../ui/windows/audio_device_bridge.dart';
import '../chat/widgets/avatar_stage.dart';

class ProviderConfigScreen extends StatelessWidget {
  const ProviderConfigScreen({super.key, required this.settingsRepository});

  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsRepository,
      builder: (context, _) {
        final settings = settingsRepository.settings;
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('模型与能力配置'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: '模式与组合'),
                  Tab(text: '能力清单'),
                  Tab(text: '软件信息'),
                ],
              ),
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth >= 1040
                    ? 980.0
                    : constraints.maxWidth;
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: TabBarView(
                      children: [
                        _ModeTab(
                          settingsRepository: settingsRepository,
                          settings: settings,
                        ),
                        _CatalogTab(settingsRepository: settingsRepository),
                        const _AppInfoTab(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.settingsRepository, required this.settings});

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(title: '运行模式', subtitle: '选择普通 LLM、实时语音模型或 Omni 模型'),
        const SizedBox(height: 12),
        _RouteSelector(
          route: settings.route,
          onChanged: (route) {
            settingsRepository.updateSettings(settings.copyWith(route: route));
          },
        ),
        const SizedBox(height: 12),
        _HintCard(
          title: '快速说明',
          items: const [
            '普通 LLM 模式：可直接工具调用，适合深度搜索/研究。',
            'Realtime 模式：由控制代理调用工具，保证低延迟对话。',
            '需要向量检索时：在 Provider 中填写 Embedding Model，并选择 Embedding Provider。',
          ],
        ),
        const SizedBox(height: 12),
        _PersonaCard(
          settingsRepository: settingsRepository,
          settings: settings,
        ),
        const SizedBox(height: 12),
        const _VrmCard(),
        const SizedBox(height: 12),
        _Live3DPerformanceCard(
          settingsRepository: settingsRepository,
          settings: settings,
        ),
        const SizedBox(height: 12),
        _PetModeCard(
          settingsRepository: settingsRepository,
          settings: settings,
        ),
        const SizedBox(height: 12),
        _Live3DTestCard(
          settingsRepository: settingsRepository,
          settings: settings,
        ),
        const SizedBox(height: 12),
        _MemoryAgentCard(
          settingsRepository: settingsRepository,
          settings: settings,
        ),
        const SizedBox(height: 12),
        _MotionAgentCard(
          settingsRepository: settingsRepository,
          settings: settings,
        ),
        const SizedBox(height: 24),
        _AppearanceCard(
          settingsRepository: settingsRepository,
          settings: settings,
        ),
        const SizedBox(height: 12),
        _LayoutPresetCard(
          settingsRepository: settingsRepository,
          settings: settings,
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
            providers: settingsRepository.providersByKind(ProviderKind.llm),
            selectedId: settings.llmProviderId,
            onChanged: (id) {
              settingsRepository.updateSettings(
                settings.copyWith(llmProviderId: id),
              );
            },
          ),
          _ProviderPicker(
            label: 'Embedding Provider（向量检索）',
            providers: settingsRepository.providersByKind(ProviderKind.llm),
            selectedId: settings.embeddingProviderId,
            onChanged: (id) {
              settingsRepository.updateSettings(
                settings.copyWith(embeddingProviderId: id),
              );
            },
          ),
          _ProviderPicker(
            label: '视觉 Agent',
            providers: settingsRepository.providersByKind(
              ProviderKind.visionAgent,
            ),
            selectedId: settings.visionProviderId,
            onChanged: (id) {
              settingsRepository.updateSettings(
                settings.copyWith(visionProviderId: id),
              );
            },
          ),
          _ProviderPicker(
            label: 'TTS',
            providers: settingsRepository.providersByKind(ProviderKind.tts),
            selectedId: settings.ttsProviderId,
            onChanged: (id) {
              settingsRepository.updateSettings(
                settings.copyWith(ttsProviderId: id),
              );
            },
          ),
          _ProviderPicker(
            label: 'STT',
            providers: settingsRepository.providersByKind(ProviderKind.stt),
            selectedId: settings.sttProviderId,
            onChanged: (id) {
              settingsRepository.updateSettings(
                settings.copyWith(sttProviderId: id),
              );
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用系统语音输出（保底）'),
            subtitle: const Text('当第三方语音不可用时使用系统 TTS'),
            value: settings.enableSystemTts,
            onChanged: (value) {
              settingsRepository.updateSettings(
                settings.copyWith(enableSystemTts: value),
              );
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用系统语音输入（保底）'),
            subtitle: const Text('当第三方语音不可用时使用系统 STT'),
            value: settings.enableSystemStt,
            onChanged: (value) {
              settingsRepository.updateSettings(
                settings.copyWith(enableSystemStt: value),
              );
            },
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 4),
            _VoiceChannelCard(
              settingsRepository: settingsRepository,
              settings: settings,
            ),
            const SizedBox(height: 12),
          ],
          _ToolGatewayCard(
            settingsRepository: settingsRepository,
            settings: settings,
          ),
          const SizedBox(height: 24),
        ],
        if (settings.route == ModelRoute.realtime) ...[
          _SectionHeader(title: '实时语音模型', subtitle: '带实时语音输出与打断能力'),
          const SizedBox(height: 12),
          _ProviderPicker(
            label: 'Realtime 模型',
            providers: settingsRepository.providersByKind(
              ProviderKind.realtime,
            ),
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
          _SectionHeader(title: 'Omni 模型', subtitle: '文本 + 语音 + 视觉一体化'),
          const SizedBox(height: 12),
          _ProviderPicker(
            label: 'Omni 模型',
            providers: settingsRepository.providersByKind(ProviderKind.omni),
            selectedId: settings.omniProviderId,
            onChanged: (id) {
              settingsRepository.updateSettings(
                settings.copyWith(omniProviderId: id),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _CatalogTab extends StatelessWidget {
  const _CatalogTab({required this.settingsRepository});

  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(title: '模型与能力清单', subtitle: '管理所有 Provider 与高级参数'),
        const SizedBox(height: 12),
        _ProviderCatalog(settingsRepository: settingsRepository),
      ],
    );
  }
}

class _AppInfoTab extends StatelessWidget {
  const _AppInfoTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        _SectionHeader(title: '软件与反馈', subtitle: '版本信息、代码仓库与反馈渠道'),
        SizedBox(height: 12),
        _AppInfoSection(),
      ],
    );
  }
}

class _RouteSelector extends StatelessWidget {
  const _RouteSelector({required this.route, required this.onChanged});

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
  const _ProviderCatalog({required this.settingsRepository});

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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B6F7A)),
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
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final titleStyle = Platform.environment.containsKey('FLUTTER_TEST')
        ? const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2228),
          )
        : Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: chrome.textPrimary,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: titleStyle),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: chrome.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.title, required this.items});

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
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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

class _PersonaCard extends StatefulWidget {
  const _PersonaCard({
    required this.settingsRepository,
    required this.settings,
  });

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  @override
  State<_PersonaCard> createState() => _PersonaCardState();
}

class _PersonaCardState extends State<_PersonaCard> {
  final TextEditingController _promptController = TextEditingController();
  String? _lastSavedPrompt;

  @override
  void initState() {
    super.initState();
    _syncSavedPrompt(force: true);
  }

  @override
  void didUpdateWidget(covariant _PersonaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSavedPrompt();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _syncSavedPrompt({bool force = false}) {
    final saved = widget.settings.personaPrompt;
    final normalized = (saved == null || saved.trim().isEmpty) ? null : saved;
    if (!force && normalized == _lastSavedPrompt) {
      return;
    }
    final current = _promptController.text;
    if (force || current.isEmpty || current == (_lastSavedPrompt ?? '')) {
      _promptController.text = normalized ?? '';
    }
    _lastSavedPrompt = normalized;
  }

  void _updatePrompt(String value) {
    final next = value.trim().isEmpty ? null : value;
    widget.settingsRepository.updateSettings(
      widget.settings.copyWith(personaPrompt: next),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '人设设置',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '人设内容会注入系统提示词，影响普通 LLM 与实时对话模式。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5E636F),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PersonaMode>(
              value: widget.settings.personaMode,
              decoration: const InputDecoration(labelText: '人设模式'),
              items: PersonaMode.values
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(_personaModeLabel(mode)),
                    ),
                  )
                  .toList(),
              onChanged: (mode) {
                if (mode == null) {
                  return;
                }
                widget.settingsRepository.updateSettings(
                  widget.settings.copyWith(personaMode: mode),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<PersonaLevel>(
                    value: widget.settings.personaLevel,
                    decoration: const InputDecoration(labelText: '人设强度'),
                    items: PersonaLevel.values
                        .map(
                          (level) => DropdownMenuItem(
                            value: level,
                            child: Text(_personaLevelLabel(level)),
                          ),
                        )
                        .toList(),
                    onChanged: (level) {
                      if (level == null) {
                        return;
                      }
                      widget.settingsRepository.updateSettings(
                        widget.settings.copyWith(personaLevel: level),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<PersonaStyle>(
                    value: widget.settings.personaStyle,
                    decoration: const InputDecoration(labelText: '风格附加'),
                    items: PersonaStyle.values
                        .map(
                          (style) => DropdownMenuItem(
                            value: style,
                            child: Text(_personaStyleLabel(style)),
                          ),
                        )
                        .toList(),
                    onChanged: (style) {
                      if (style == null) {
                        return;
                      }
                      widget.settingsRepository.updateSettings(
                        widget.settings.copyWith(personaStyle: style),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _promptController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '自定义人设补充（可选）',
                hintText: '补充称呼、禁忌、对话习惯等内容',
              ),
              onChanged: _updatePrompt,
            ),
          ],
        ),
      ),
    );
  }
}

class _VrmCard extends StatelessWidget {
  const _VrmCard();

  static const String _vrmDoc =
      'https://vroid.pixiv.help/hc/en-us/articles/38726063278233-How-do-I-export-a-model-as-VRM';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live3D / VRM 模型',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '推荐使用 VRoid Studio 导出的 VRM 1.0 模型（含标准表情/嘴型/动作）。'
              '渲染 SDK 计划对接 three-vrm (Web) / UniVRM (Unity)。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5E636F),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '授权与来源：请仅加载自己制作或已获授权的 VRM 文件，保留原有许可提示。'
              '当前版本暂未内置模型，后续将支持文件选择与映射配置。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5E636F),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              'VRM 导出指引: $_vrmDoc',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF2E5AAC),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Live3DPerformanceCard extends StatelessWidget {
  const _Live3DPerformanceCard({
    required this.settingsRepository,
    required this.settings,
  });

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  String _qualityLabel(Live3dRenderQuality quality) {
    switch (quality) {
      case Live3dRenderQuality.low:
        return '低（更省内存）';
      case Live3dRenderQuality.balanced:
        return '均衡';
      case Live3dRenderQuality.high:
        return '高（更清晰）';
    }
  }

  String _fpsLabel(Live3dFpsCap cap) {
    switch (cap) {
      case Live3dFpsCap.fps30:
        return '30 FPS';
      case Live3dFpsCap.fps60:
        return '60 FPS';
      case Live3dFpsCap.unlimited:
        return '不限制';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live3D 渲染性能',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '在高分辨率屏幕上可以适当降低质量或帧率，减少内存和功耗。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5E636F),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Live3dRenderQuality>(
              value: settings.live3dRenderQuality,
              decoration: const InputDecoration(
                labelText: '渲染质量',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: Live3dRenderQuality.values
                  .map(
                    (quality) => DropdownMenuItem(
                      value: quality,
                      child: Text(_qualityLabel(quality)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                settingsRepository.updateSettings(
                  settings.copyWith(live3dRenderQuality: value),
                );
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Live3dFpsCap>(
              value: settings.live3dFpsCap,
              decoration: const InputDecoration(
                labelText: '帧率上限',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: Live3dFpsCap.values
                  .map(
                    (cap) => DropdownMenuItem(
                      value: cap,
                      child: Text(_fpsLabel(cap)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                settingsRepository.updateSettings(
                  settings.copyWith(live3dFpsCap: value),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PetModeCard extends StatelessWidget {
  const _PetModeCard({
    required this.settingsRepository,
    required this.settings,
  });

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '桌宠模式（桌面）',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '启用后将进入“只显示模型”的模式，适合挂机陪伴。'
              '目前为单窗口切换（非透明悬浮），后续可继续做置顶/透明/穿透。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5E636F),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用桌宠模式'),
              subtitle: const Text('进入仅模型界面，可随时从按钮返回聊天'),
              value: settings.petMode,
              onChanged: (value) {
                settingsRepository.updateSettings(
                  settings.copyWith(petMode: value),
                );
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('视线跟随鼠标（窗口内）'),
              subtitle: const Text('在模型区域移动鼠标，眼神会跟随位置'),
              value: settings.petFollowCursor,
              onChanged: settings.petMode
                  ? (value) {
                      settingsRepository.updateSettings(
                        settings.copyWith(petFollowCursor: value),
                      );
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Live3DTestCard extends StatefulWidget {
  const _Live3DTestCard({
    required this.settingsRepository,
    required this.settings,
  });

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  @override
  State<_Live3DTestCard> createState() => _Live3DTestCardState();
}

class _Live3DTestCardState extends State<_Live3DTestCard> {
  final _pathController = TextEditingController();
  String? _status;
  String _controlMode = 'basic';
  String? _lastSavedPath;

  @override
  void initState() {
    super.initState();
    _syncSavedPath(force: true);
  }

  @override
  void didUpdateWidget(covariant _Live3DTestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSavedPath();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _syncSavedPath({bool force = false}) {
    final saved = widget.settings.live3dModelPath?.trim();
    final normalized = (saved == null || saved.isEmpty) ? null : saved;
    if (!force && normalized == _lastSavedPath) {
      return;
    }
    final current = _pathController.text.trim();
    if (force || current.isEmpty || current == (_lastSavedPath ?? '')) {
      _pathController.text = normalized ?? '';
    }
    _lastSavedPath = normalized;
  }

  Future<void> _loadModel() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _status = '请先填写 VRM 文件路径');
      return;
    }
    await widget.settingsRepository.updateSettings(
      widget.settings.copyWith(live3dModelPath: path),
    );
    await RuntimeHub.instance.live3dBridge.loadModel(path);
    setState(() => _status = '已请求加载：$path');
  }

  Future<void> _emitExpression(ExpressionEmotion emotion) async {
    await RuntimeHub.instance.controlAgent.emitExpression(
      ExpressionEvent(emotion: emotion, intensity: 0.8),
    );
    setState(() => _status = '已发送表情：${emotion.name}');
  }

  Future<void> _emitMotion(StageMotion motion) async {
    await RuntimeHub.instance.controlAgent.emitStageAction(
      StageAction(motion: motion, intensity: 0.8),
    );
    setState(() => _status = '已发送动作：${motion.name}');
  }

  void _setControlMode(String mode) {
    _controlMode = 'basic';
    RuntimeHub.instance.live3dBridge.setControlMode('basic');
    setState(() {
      _status = '已切换模式：基础';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Live3D 快速测试',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text(
                  '（占位，需绑定 three-vrm/UniVRM 渲染端）',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B6F7A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('基础模式'),
                  selected: _controlMode == 'basic',
                  onSelected: (_) => _setControlMode('basic'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 520,
              child: AvatarStage(
                fill: true,
                settingsRepository: widget.settingsRepository,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'VRM 文件路径',
                hintText: '例如 C:\\\\models\\\\avatar.vrm',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _loadModel,
                  icon: const Icon(Icons.file_download_done),
                  label: const Text('加载模型'),
                ),
                OutlinedButton(
                  onPressed: () => _emitExpression(ExpressionEmotion.happy),
                  child: const Text('表情：开心'),
                ),
                OutlinedButton(
                  onPressed: () => _emitExpression(ExpressionEmotion.surprise),
                  child: const Text('表情：惊讶'),
                ),
                OutlinedButton(
                  onPressed: () => _emitMotion(StageMotion.wave),
                  child: const Text('动作：挥手'),
                ),
                OutlinedButton(
                  onPressed: () => _emitMotion(StageMotion.nod),
                  child: const Text('动作：点头'),
                ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 10),
              Text(
                _status!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF2E5AAC),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MotionAgentCard extends StatelessWidget {
  const _MotionAgentCard({
    required this.settingsRepository,
    required this.settings,
  });

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final providers = settingsRepository.providersByKind(ProviderKind.llm);
    final cooldown = settings.motionAgentCooldownSeconds.clamp(0, 60);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '动作 Agent（高级动作）',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '系统自动动作由动作 catalog 的 auto 标记控制；“动作 Agent”只会从标记了 agent 的动作里挑选，'
              '并在合适时机触发（最多一次/轮）。标准/Omni：根据主助手回复决策；Realtime：根据实时对话文本决策。'
              '动作分类在 assets/live3d/animations/catalog.json 里配置。建议给动作 Agent 单独配置一个小模型，减少主模型负担。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5E636F),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用动作 Agent'),
              subtitle: const Text('由小模型决定是否触发高级动作（最多一次/轮）'),
              value: settings.motionAgentEnabled,
              onChanged: (value) {
                settingsRepository.updateSettings(
                  settings.copyWith(motionAgentEnabled: value),
                );
              },
            ),
            _ProviderPicker(
              label: '动作 Agent 模型（建议小模型）',
              providers: providers,
              selectedId: settings.motionAgentProviderId,
              onChanged: (id) {
                settingsRepository.updateSettings(
                  settings.copyWith(motionAgentProviderId: id),
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              '动作 Agent 冷却：${settings.motionAgentCooldownSeconds}s',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Slider(
              value: cooldown.toDouble(),
              min: 0,
              max: 60,
              divisions: 60,
              label: '${cooldown}s',
              onChanged: (value) {
                settingsRepository.updateSettings(
                  settings.copyWith(motionAgentCooldownSeconds: value.round()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.settingsRepository,
    required this.settings,
  });

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '界面外观',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '切换配色与毛玻璃强度（支持深色/浅色自动适配）。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5E636F),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<UiPalette>(
                    value: settings.uiPalette,
                    decoration: const InputDecoration(labelText: '配色方案'),
                    items: UiPalette.values
                        .map(
                          (palette) => DropdownMenuItem(
                            value: palette,
                            child: Text(_paletteLabel(palette)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      settingsRepository.updateSettings(
                        settings.copyWith(uiPalette: value),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<UiGlass>(
                    value: settings.uiGlass,
                    decoration: const InputDecoration(labelText: '毛玻璃强度'),
                    items: UiGlass.values
                        .map(
                          (glass) => DropdownMenuItem(
                            value: glass,
                            child: Text(_glassLabel(glass)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      settingsRepository.updateSettings(
                        settings.copyWith(uiGlass: value),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LayoutPresetCard extends StatelessWidget {
  const _LayoutPresetCard({
    required this.settingsRepository,
    required this.settings,
  });

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '布局模式',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '选择聊天/演示优先的布局预设，可随时在聊天页进入布局编辑微调。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5E636F),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<LayoutPreset>(
              segments: const [
                ButtonSegment(
                  value: LayoutPreset.balanced,
                  label: Text('综合'),
                  icon: Icon(Icons.dashboard_outlined),
                ),
                ButtonSegment(
                  value: LayoutPreset.focusChat,
                  label: Text('专注对话'),
                  icon: Icon(Icons.chat_bubble_outline),
                ),
                ButtonSegment(
                  value: LayoutPreset.focusPresentation,
                  label: Text('专注演示'),
                  icon: Icon(Icons.slideshow_outlined),
                ),
              ],
              selected: {settings.layoutPreset},
              onSelectionChanged: (value) {
                final preset = value.first;
                final next = _applyLayoutPreset(settings, preset);
                settingsRepository.updateSettings(next);
              },
            ),
            const SizedBox(height: 10),
            Text(
              _layoutPresetHint(settings.layoutPreset),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5E636F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppSettings _applyLayoutPreset(AppSettings settings, LayoutPreset preset) {
    switch (preset) {
      case LayoutPreset.focusChat:
        return settings.copyWith(
          layoutPreset: preset,
          layoutSidebarWidth: 260.0,
          layoutRightPanelWidth: 380.0,
          layoutShowRightPanel: false,
        );
      case LayoutPreset.focusPresentation:
        return settings.copyWith(
          layoutPreset: preset,
          layoutSidebarWidth: 220.0,
          layoutRightPanelWidth: 520.0,
          layoutShowRightPanel: true,
        );
      case LayoutPreset.balanced:
        return settings.copyWith(
          layoutPreset: preset,
          layoutSidebarWidth: 280.0,
          layoutRightPanelWidth: 380.0,
          layoutShowRightPanel: true,
        );
    }
  }
}

class _MemoryAgentCard extends StatelessWidget {
  const _MemoryAgentCard({
    required this.settingsRepository,
    required this.settings,
  });

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final providers = settingsRepository.providersByKind(ProviderKind.llm);
    final cooldown = settings.memoryAgentCooldownSeconds.clamp(0, 300);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '记忆 Agent（核心记忆 / 日记记忆）',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '参考 MoeChat 的“核心记忆 + 日记记忆”思路：由一个小模型在每轮对话结束后抽取稳定事实写入“核心记忆”，'
              '同时把可追溯的事件写入“日记记忆”（便于回答“昨天聊了什么/上周发生了什么”）。'
              '建议给记忆 Agent 单独配置小模型，避免占用主模型上下文与预算。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5E636F),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用记忆 Agent'),
              subtitle: const Text('抽取并更新核心记忆/日记记忆（后台执行）'),
              value: settings.memoryAgentEnabled,
              onChanged: (value) {
                settingsRepository.updateSettings(
                  settings.copyWith(memoryAgentEnabled: value),
                );
              },
            ),
            _ProviderPicker(
              label: '记忆 Agent 模型（建议小模型）',
              providers: providers,
              selectedId: settings.memoryAgentProviderId,
              onChanged: (id) {
                settingsRepository.updateSettings(
                  settings.copyWith(memoryAgentProviderId: id),
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              '记忆 Agent 冷却：${settings.memoryAgentCooldownSeconds}s',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Slider(
              value: cooldown.toDouble(),
              min: 0,
              max: 300,
              divisions: 300,
              label: '${cooldown}s',
              onChanged: (value) {
                settingsRepository.updateSettings(
                  settings.copyWith(memoryAgentCooldownSeconds: value.round()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceChannelCard extends StatefulWidget {
  const _VoiceChannelCard({
    required this.settingsRepository,
    required this.settings,
  });

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  @override
  State<_VoiceChannelCard> createState() => _VoiceChannelCardState();
}

class _VoiceChannelCardState extends State<_VoiceChannelCard> {
  Future<List<AudioInputDeviceInfo>>? _devicesFuture;

  @override
  void initState() {
    super.initState();
    _reloadDevices();
  }

  void _reloadDevices() {
    setState(() {
      _devicesFuture = WindowsAudioDeviceBridge.listInputDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final settingsRepository = widget.settingsRepository;
    final settings = widget.settings;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              title: '语音频道（Windows）',
              subtitle: '虚拟声卡监听与注入控制',
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用语音频道监听'),
              subtitle: const Text('通过虚拟声卡把语音频道音频接入系统 STT'),
              value: settings.voiceChannelEnabled,
              onChanged: (value) {
                settingsRepository.updateSettings(
                  settings.copyWith(voiceChannelEnabled: value),
                );
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('语音频道注入主对话'),
              subtitle: const Text('关闭后仅保留监听记录，不自动发送到对话'),
              value: settings.voiceChannelInjectEnabled,
              onChanged: (value) {
                settingsRepository.updateSettings(
                  settings.copyWith(voiceChannelInjectEnabled: value),
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              '选择虚拟声卡输入设备',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<AudioInputDeviceInfo>>(
              future: _devicesFuture,
              builder: (context, snapshot) {
                final devices = snapshot.data ?? const [];
                final items = <DropdownMenuItem<String>>[
                  const DropdownMenuItem(value: '', child: Text('跟随系统默认输入设备')),
                  ...devices.map(
                    (device) => DropdownMenuItem(
                      value: device.id,
                      child: Text(device.name),
                    ),
                  ),
                ];
                final selectedId = settings.voiceChannelDeviceId ?? '';
                final hasSelected =
                    selectedId.isEmpty ||
                    devices.any((d) => d.id == selectedId);
                final effectiveValue = hasSelected ? selectedId : '';

                AudioInputDeviceInfo? defaultDevice;
                for (final device in devices) {
                  if (device.isDefault) {
                    defaultDevice = device;
                    break;
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: effectiveValue,
                            items: items,
                            onChanged: (value) {
                              final id = value ?? '';
                              final label = devices
                                  .firstWhere(
                                    (d) => d.id == id,
                                    orElse: () => const AudioInputDeviceInfo(
                                      id: '',
                                      name: '',
                                      isDefault: false,
                                    ),
                                  )
                                  .name;
                              settingsRepository.updateSettings(
                                settings.copyWith(
                                  voiceChannelDeviceId: id.isEmpty ? null : id,
                                  voiceChannelDeviceLabel: id.isEmpty
                                      ? null
                                      : label,
                                ),
                              );
                            },
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '刷新设备列表',
                          onPressed: _reloadDevices,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      defaultDevice == null
                          ? '当前系统默认输入设备：未识别'
                          : '当前系统默认输入设备：${defaultDevice.name}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textSecondary,
                      ),
                    ),
                    if (effectiveValue.isNotEmpty &&
                        defaultDevice != null &&
                        effectiveValue != defaultDevice.id)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '提示：已选择的设备与系统默认不一致，请在系统声音设置中手动切换。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: WindowsAudioDeviceBridge.openSoundSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('打开系统声音设置'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '使用方式：把 Discord/KOOK 的输出设备改为虚拟声卡（如 VB-CABLE 输出），'
                      '再把该虚拟声卡设为 Windows 默认录音设备。CMYKE 中用 🎧 按钮开始/停止监听。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textSecondary,
                        height: 1.25,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolGatewayCard extends StatefulWidget {
  const _ToolGatewayCard({
    required this.settingsRepository,
    required this.settings,
  });

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  @override
  State<_ToolGatewayCard> createState() => _ToolGatewayCardState();
}

class _ToolGatewayCardState extends State<_ToolGatewayCard> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenController;
  final FocusNode _baseUrlFocus = FocusNode();
  final FocusNode _tokenFocus = FocusNode();
  bool _checking = false;
  String? _status;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: widget.settings.toolGatewayBaseUrl,
    );
    _tokenController = TextEditingController(
      text: widget.settings.toolGatewayPairingToken,
    );
  }

  @override
  void didUpdateWidget(covariant _ToolGatewayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_baseUrlFocus.hasFocus &&
        widget.settings.toolGatewayBaseUrl != _baseUrlController.text) {
      _baseUrlController.text = widget.settings.toolGatewayBaseUrl;
    }
    if (!_tokenFocus.hasFocus &&
        widget.settings.toolGatewayPairingToken != _tokenController.text) {
      _tokenController.text = widget.settings.toolGatewayPairingToken;
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _tokenController.dispose();
    _baseUrlFocus.dispose();
    _tokenFocus.dispose();
    super.dispose();
  }

  Future<void> _checkGateway() async {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty) {
      _setStatus('请先填写网关地址。');
      return;
    }
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      final uri = _buildHealthUri(baseUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _setStatus('连接成功：${response.statusCode}');
      } else {
        _setStatus('连接失败：HTTP ${response.statusCode}');
      }
    } catch (error) {
      _setStatus('连接失败：$error');
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _createPairing() async {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty) {
      _setStatus('请先填写网关地址。');
      return;
    }
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      final uri = _buildGatewayUri(baseUrl, '/api/v1/gateway/pairing/create');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mode': 'local',
              'label': 'flutter-ui',
              'expires_in_sec': 3600,
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _setStatus('创建配对失败：HTTP ${response.statusCode}');
        return;
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        _setStatus('配对响应异常。');
        return;
      }
      final pairing = data['pairing'];
      final token = pairing is Map<String, dynamic>
          ? pairing['token']?.toString()
          : null;
      if (token == null || token.isEmpty) {
        _setStatus('配对响应缺少 token。');
        return;
      }
      _tokenController.text = token;
      _updateSettings(widget.settings.copyWith(toolGatewayPairingToken: token));
      _setStatus('已创建配对 token。');
    } catch (error) {
      _setStatus('创建配对失败：$error');
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Uri _buildHealthUri(String baseUrl) {
    var normalized = baseUrl.trim();
    if (!normalized.contains('://')) {
      normalized = 'http://$normalized';
    }
    final uri = Uri.parse(normalized);
    if (uri.path.isEmpty || uri.path == '/') {
      return uri.replace(path: '/api/v1/health');
    }
    return uri.replace(path: '${uri.path}/api/v1/health');
  }

  Uri _buildGatewayUri(String baseUrl, String path) {
    var normalized = baseUrl.trim();
    if (!normalized.contains('://')) {
      normalized = 'http://$normalized';
    }
    final uri = Uri.parse(normalized);
    if (uri.path.isEmpty || uri.path == '/') {
      return uri.replace(path: path);
    }
    return uri.replace(path: '${uri.path}$path');
  }

  void _setStatus(String message) {
    if (!mounted) return;
    setState(() => _status = message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _updateSettings(AppSettings next) {
    widget.settingsRepository.updateSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final settings = widget.settings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              title: '工具网关（SAP / OpenCode）',
              subtitle: '连接本地 Rust 后端，用于 MCP/技能/沙箱调用',
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用工具网关'),
              subtitle: const Text('开启后 ToolRouter 会走 Rust Gateway'),
              value: settings.toolGatewayEnabled,
              onChanged: (value) {
                _updateSettings(settings.copyWith(toolGatewayEnabled: value));
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _baseUrlController,
              focusNode: _baseUrlFocus,
              decoration: const InputDecoration(
                labelText: '网关地址',
                hintText: 'http://127.0.0.1:4891',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) {
                _updateSettings(
                  settings.copyWith(toolGatewayBaseUrl: value.trim()),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              focusNode: _tokenFocus,
              obscureText: !_showToken,
              decoration: InputDecoration(
                labelText: 'Pairing Token',
                hintText: '在网关创建配对后填入',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: _showToken ? '隐藏' : '显示',
                  onPressed: () {
                    setState(() => _showToken = !_showToken);
                  },
                  icon: Icon(
                    _showToken ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
              onChanged: (value) {
                _updateSettings(
                  settings.copyWith(toolGatewayPairingToken: value.trim()),
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _checking ? null : _checkGateway,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: const Text('测试连接'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _checking ? null : _createPairing,
                  icon: const Icon(Icons.vpn_key),
                  label: const Text('创建配对'),
                ),
                const SizedBox(width: 12),
                Text(
                  '网关健康检查：/api/v1/health',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
                ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(
                _status!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppInfoSection extends StatelessWidget {
  const _AppInfoSection();

  static const String _repoUrl = 'https://github.com/BOHUYESHAN-APB/CMYKE';
  static const String _feedback =
      'https://github.com/BOHUYESHAN-APB/CMYKE/issues';
  static const String _license = 'Apache-2.0';
  static const String _fonts = 'MiSans / HarmonyOS Sans SC';
  static const String _fontSource = 'https://hyperos.mi.com/font/download';
  static const String _attributionDoc = 'docs/THIRD_PARTY_ATTRIBUTIONS.md';
  static const List<String> _runtimeThirdParty = [
    'TP-RUN-001 three.js + addons（MIT）',
    'TP-RUN-002 @pixiv/three-vrm（MIT）',
    'TP-RUN-003 @pixiv/three-vrm-animation（MIT）',
    'TP-RUN-004 es-module-shims（MIT）',
    'TP-RUN-008 OpenCode CLI / opencode-ai（MIT）',
  ];
  static const List<String> _studyReferences = [
    'TP-REF-001 free-OKC（MIT）',
    'TP-REF-002 openclaw（MIT）',
    'TP-REF-003 openclaw-skills（MIT）',
  ];

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
                _InfoRow(label: '版本号', value: version),
                const SizedBox(height: 12),
                _InfoRow(label: '代码仓库', value: _repoUrl),
                const SizedBox(height: 12),
                _InfoRow(label: '反馈渠道', value: _feedback),
                const SizedBox(height: 12),
                const _InfoRow(label: '许可协议', value: _license),
                const SizedBox(height: 12),
                const _InfoRow(label: '字体', value: _fonts),
                const SizedBox(height: 8),
                const _InfoRow(label: '字体来源', value: _fontSource),
                const SizedBox(height: 12),
                const _InfoRow(label: '第三方声明', value: _attributionDoc),
                const SizedBox(height: 12),
                Text(
                  '本软件特别注明：界面排版使用了 MiSans 字体。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.chrome.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '运行时第三方（节选）',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ..._runtimeThirdParty.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SelectableText(entry),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '学习/引用项目（节选）',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ..._studyReferences.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SelectableText(entry),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '完整编号、路径、来源与许可证请查看 $_attributionDoc',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.chrome.textSecondary,
                  ),
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
    final chrome = context.chrome;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: chrome.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
  final nameController = TextEditingController(text: provider?.name ?? '');
  final baseUrlController = TextEditingController(
    text: provider?.baseUrl ?? '',
  );
  final modelController = TextEditingController(text: provider?.model ?? '');
  final embeddingModelController = TextEditingController(
    text: provider?.embeddingModel ?? '',
  );
  final notesController = TextEditingController(text: provider?.notes ?? '');
  final selectedCapabilities = <ProviderCapability>{
    ...(provider?.capabilities ?? _defaultCapabilities(kind)),
  };
  final apiKeyController = TextEditingController(text: provider?.apiKey ?? '');
  final audioVoiceController = TextEditingController(
    text: provider?.audioVoice ?? '',
  );
  final audioFormatController = TextEditingController(
    text: provider?.audioFormat ?? '',
  );
  final inputAudioFormatController = TextEditingController(
    text: provider?.inputAudioFormat ?? '',
  );
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
  final contextWindowTokensController = TextEditingController(
    text: provider?.contextWindowTokens?.toString() ?? '',
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
  bool enableEmbedding = provider?.embeddingModel?.isNotEmpty ?? false;
  final embeddingBaseUrlController = TextEditingController(
    text: provider?.embeddingBaseUrl ?? '',
  );
  final embeddingApiKeyController = TextEditingController(
    text: provider?.embeddingApiKey ?? '',
  );
  final wsUrlController = TextEditingController(text: provider?.wsUrl ?? '');
  final showAudioSettings =
      kind == ProviderKind.omni ||
      kind == ProviderKind.tts ||
      kind == ProviderKind.realtime ||
      kind == ProviderKind.stt;
  final showRealtimeSettings =
      kind == ProviderKind.realtime || kind == ProviderKind.omni;
  final showModelTuning =
      kind == ProviderKind.llm ||
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用向量检索'),
                      subtitle: const Text('如需不同 Base URL，可在下方单独填写'),
                      value: enableEmbedding,
                      onChanged: (v) {
                        setState(() => enableEmbedding = v);
                      },
                    ),
                    if (enableEmbedding) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: embeddingBaseUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Embedding Base URL (可选)',
                          hintText: '可与对话 Base URL 不同',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: embeddingApiKeyController,
                        decoration: const InputDecoration(
                          labelText: 'Embedding API Key (可选)',
                          hintText: '若与对话 API Key 不同，可单独填写',
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: embeddingModelController,
                        decoration: const InputDecoration(
                          labelText: 'Embedding Model (向量检索)',
                          hintText: '例如 text-embedding-3-small',
                        ),
                      ),
                    ],
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
                            baseUrlController.text =
                                'https://api.openai.com/v1';
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
                            baseUrlController.text =
                                'https://api.stepfun.com/v1';
                          });
                        },
                      ),
                      _PresetChip(
                        label: 'LM Studio',
                        onTap: () {
                          setState(() {
                            protocol = ProviderProtocol.openaiCompatible;
                            baseUrlController.text = 'http://localhost:1234/v1';
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
                    TextField(
                      controller: contextWindowTokensController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '上下文上限 (Tokens)',
                        hintText: '不填则不启用自动压缩',
                      ),
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
                      final selected = selectedCapabilities.contains(
                        capability,
                      );
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
                    id:
                        provider?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name,
                    kind: kind,
                    baseUrl: baseUrlController.text.trim(),
                    model: modelController.text.trim(),
                    embeddingModel:
                        !enableEmbedding ||
                            embeddingModelController.text.trim().isEmpty
                        ? null
                        : embeddingModelController.text.trim(),
                    embeddingBaseUrl:
                        !enableEmbedding ||
                            embeddingBaseUrlController.text.trim().isEmpty
                        ? null
                        : embeddingBaseUrlController.text.trim(),
                    embeddingApiKey:
                        !enableEmbedding ||
                            embeddingApiKeyController.text.trim().isEmpty
                        ? null
                        : embeddingApiKeyController.text.trim(),
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
                    inputSampleRate: _parseInt(inputSampleRateController.text),
                    outputSampleRate: _parseInt(
                      outputSampleRateController.text,
                    ),
                    audioChannels: _parseInt(audioChannelsController.text),
                    temperature: _parseDouble(temperatureController.text),
                    topP: _parseDouble(topPController.text),
                    maxTokens: _parseInt(maxTokensController.text),
                    contextWindowTokens: _parseInt(
                      contextWindowTokensController.text,
                    ),
                    presencePenalty: _parseDouble(
                      presencePenaltyController.text,
                    ),
                    frequencyPenalty: _parseDouble(
                      frequencyPenaltyController.text,
                    ),
                    seed: _parseInt(seedController.text),
                    enableThinking: kind == ProviderKind.omni
                        ? enableThinking
                        : null,
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
  contextWindowTokensController.dispose();
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

String _personaModeLabel(PersonaMode mode) {
  switch (mode) {
    case PersonaMode.persona:
      return '拟人模式';
    case PersonaMode.standard:
      return '标准模式';
  }
}

String _personaLevelLabel(PersonaLevel level) {
  switch (level) {
    case PersonaLevel.basic:
      return '基础';
    case PersonaLevel.advanced:
      return '增强';
    case PersonaLevel.full:
      return '完整';
  }
}

String _personaStyleLabel(PersonaStyle style) {
  switch (style) {
    case PersonaStyle.none:
      return '无';
    case PersonaStyle.neuro:
      return 'Neuro';
    case PersonaStyle.toxic:
      return '毒舌';
    case PersonaStyle.cute:
      return '软萌';
  }
}

String _paletteLabel(UiPalette palette) {
  switch (palette) {
    case UiPalette.jade:
      return '翡翠绿';
    case UiPalette.ocean:
      return '深海蓝';
    case UiPalette.ember:
      return '琥珀橙';
    case UiPalette.rose:
      return '玫瑰粉';
    case UiPalette.slate:
      return '石板灰';
  }
}

String _glassLabel(UiGlass glass) {
  switch (glass) {
    case UiGlass.soft:
      return '柔和';
    case UiGlass.standard:
      return '标准';
    case UiGlass.strong:
      return '强烈';
  }
}

String _layoutPresetHint(LayoutPreset preset) {
  switch (preset) {
    case LayoutPreset.balanced:
      return '综合模式：会话列表 + 对话区 + 3D 模型同屏显示。';
    case LayoutPreset.focusChat:
      return '专注对话：隐藏 3D 模型，聚焦聊天内容。';
    case LayoutPreset.focusPresentation:
      return '专注演示：扩大 3D 模型区域，并在模型上方显示气泡。';
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
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text(label), onPressed: onTap);
  }
}
