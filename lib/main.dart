import 'package:flutter/material.dart';

void main() {
  runApp(const CMYKEApp());
}

class CMYKEApp extends StatelessWidget {
  const CMYKEApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CMYKE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B8A9),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F9FB),
        fontFamily: 'Roboto',
        cardTheme: CardTheme(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modules = _cmykeModules;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CMYKE Architecture Explorer'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroCard(isWide: isWide),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: modules
                        .map((m) => SizedBox(
                              width: isWide
                                  ? (constraints.maxWidth - 12 * 3) / 2
                                  : constraints.maxWidth,
                              child: _ModuleCard(module: m),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CMYKE Systems',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cognitive · Multimodal · Yielding · Knowledge · Evolving',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Pill(text: 'Realtime-first', color: color.primary),
                _Pill(text: 'Multimodal native', color: color.secondary),
                _Pill(text: 'Extensible runtime', color: color.tertiary),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '这是一个关于下一代智能体架构的示例项目。后续可以在这里接入实时音频、工具编排、可插拔的 Python/Rust 扩展等能力。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black87,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final CMYKEModule module;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: module.color.withOpacity(0.12),
                      foregroundColor: module.color,
                      child: Text(module.id),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      module.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                    ),
                  ],
                ),
                _Pill(text: module.tagline, color: color.primary),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              module.description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black87,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: module.actions
                  .map((a) => ActionChip(
                        label: Text(a),
                        avatar: const Icon(Icons.play_arrow, size: 16),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('“” 功能待实现'),
                            ),
                          );
                        },
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color.shade700,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class CMYKEModule {
  CMYKEModule({
    required this.id,
    required this.title,
    required this.description,
    required this.tagline,
    required this.actions,
    required this.color,
  });

  final String id;
  final String title;
  final String description;
  final String tagline;
  final List<String> actions;
  final MaterialColor color;
}

final List<CMYKEModule> _cmykeModules = [
  CMYKEModule(
    id: 'C',
    title: 'Cognitive',
    tagline: '推理 · 规划 · 元认知',
    description:
        '支持注意力、记忆、推理与决策的核心脑。未来可挂接实时 LLM、工具调用、上下文记忆与策略治理模块。',
    actions: ['运行推理 Demo', '接入工具编排', '配置会话记忆'],
    color: Colors.blue,
  ),
  CMYKEModule(
    id: 'M',
    title: 'Multimodal',
    tagline: '语音 · 视觉 · 体感',
    description:
        '多模态输入输出的能力层，后续可扩展语音流、图像理解、Live2D/3D 渲染器接入，支持实时口型与表情控制。',
    actions: ['语音转文字 (占位)', '图像理解 (占位)', '渲染器接入 (占位)'],
    color: Colors.teal,
  ),
  CMYKEModule(
    id: 'Y',
    title: 'Yielding / Yottascale',
    tagline: '高质量产出 · 大规模',
    description:
        '强调高效生成与大规模承载，可作为内容生产、长文写作或批量任务的入口，未来支持分片生成与负载调度。',
    actions: ['启动内容生成', '批量任务调度 (占位)'],
    color: Colors.deepPurple,
  ),
  CMYKEModule(
    id: 'K',
    title: 'Knowledge / Key',
    tagline: '知识库 · 关键工具',
    description:
        '面向结构化/非结构化知识与工具的统一入口。可插拔 RAG、MCP 工具、私有数据接入，统一 Schema 与权限治理。',
    actions: ['加载知识源 (占位)', '注册工具 (占位)', '权限配置 (占位)'],
    color: Colors.orange,
  ),
  CMYKEModule(
    id: 'E',
    title: 'Evolving / Empathetic',
    tagline: '进化 · 共情',
    description:
        '持续学习与情感智能。后续可加入在线学习、偏好建模、情绪识别与共情反馈，让智能体更贴近用户体验。',
    actions: ['偏好学习 (占位)', '情绪识别 (占位)'],
    color: Colors.pink,
  ),
];
