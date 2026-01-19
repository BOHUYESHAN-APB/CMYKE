import 'package:flutter/material.dart';

import '../../core/models/memory_collection.dart';
import '../../core/models/memory_record.dart';
import '../../core/models/memory_tier.dart';
import '../../core/models/provider_config.dart';
import '../../core/repositories/memory_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/memory_forge_service.dart';
import '../../core/services/memory_import_export_service.dart';

class MemoryTierScreen extends StatelessWidget {
  const MemoryTierScreen({
    super.key,
    required this.tier,
    required this.memoryRepository,
    required this.settingsRepository,
    this.sessionId,
  });

  final MemoryTier tier;
  final MemoryRepository memoryRepository;
  final SettingsRepository settingsRepository;
  final String? sessionId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: memoryRepository,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(tier.label),
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tierDescription(tier),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5E636F),
                      ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: tier == MemoryTier.external
                      ? _ExternalCollections(
                          memoryRepository: memoryRepository,
                          settingsRepository: settingsRepository,
                        )
                      : _SingleTierEditor(
                          tier: tier,
                          memoryRepository: memoryRepository,
                          settingsRepository: settingsRepository,
                          sessionId: sessionId,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _MemoryTierAction {
  export,
  import,
  forge,
}

enum _KnowledgeBaseAction {
  exportAll,
  importAll,
}

enum _KnowledgeCollectionAction {
  export,
  importInto,
  forge,
}

class _SingleTierEditor extends StatelessWidget {
  const _SingleTierEditor({
    required this.tier,
    required this.memoryRepository,
    required this.settingsRepository,
    this.sessionId,
  });

  final MemoryTier tier;
  final MemoryRepository memoryRepository;
  final SettingsRepository settingsRepository;
  final String? sessionId;

  @override
  Widget build(BuildContext context) {
    final ioService = MemoryImportExportService();
    final forgeService = MemoryForgeService();
    final collection = memoryRepository.defaultCollection(tier);
    final records = memoryRepository.recordsForTier(
      tier,
      sessionId: sessionId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              collection.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            PopupMenuButton<_MemoryTierAction>(
              tooltip: '更多操作',
              onSelected: (action) async {
                switch (action) {
                  case _MemoryTierAction.export:
                    final result = await ioService.exportCollections(
                      collections: [collection],
                      filenamePrefix: 'cmyke_${tier.key}',
                    );
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已导出: ${result.jsonPath}')),
                    );
                    break;
                  case _MemoryTierAction.import:
                    await _openMemoryImportDialog(
                      context,
                      repository: memoryRepository,
                      ioService: ioService,
                      onlyTier: tier,
                    );
                    break;
                  case _MemoryTierAction.forge:
                    await _openMemoryForgeDialog(
                      context,
                      tier: tier,
                      repository: memoryRepository,
                      settingsRepository: settingsRepository,
                      forgeService: forgeService,
                      sessionId: sessionId,
                    );
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _MemoryTierAction.export,
                  child: Text('导出'),
                ),
                PopupMenuItem(
                  value: _MemoryTierAction.import,
                  child: Text('导入'),
                ),
                PopupMenuItem(
                  value: _MemoryTierAction.forge,
                  child: Text('AI 生成记忆'),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
            TextButton.icon(
              onPressed: () {
                _openRecordDialog(
                  context,
                  memoryRepository,
                  tier: tier,
                  collectionId: collection.id,
                  sessionId: sessionId,
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('新增'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          _EmptyState(
            message: '暂无记录，可以新增手动记忆。',
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                return _RecordTile(
                  record: record,
                  onEdit: () {
                    _openRecordDialog(
                      context,
                      memoryRepository,
                      tier: tier,
                      collectionId: collection.id,
                      record: record,
                      sessionId: sessionId,
                    );
                  },
                  onDelete: () {
                    memoryRepository.removeRecord(
                      collectionId: collection.id,
                      recordId: record.id,
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ExternalCollections extends StatelessWidget {
  const _ExternalCollections({
    required this.memoryRepository,
    required this.settingsRepository,
  });

  final MemoryRepository memoryRepository;
  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    final ioService = MemoryImportExportService();
    final collections = memoryRepository.collectionsByTier(MemoryTier.external);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '知识库',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            PopupMenuButton<_KnowledgeBaseAction>(
              tooltip: '更多操作',
              onSelected: (action) async {
                switch (action) {
                  case _KnowledgeBaseAction.exportAll:
                    final result = await ioService.exportCollections(
                      collections: collections,
                      filenamePrefix: 'cmyke_knowledge',
                      tiers: const [MemoryTier.external],
                    );
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已导出: ${result.jsonPath}')),
                    );
                    break;
                  case _KnowledgeBaseAction.importAll:
                    await _openMemoryImportDialog(
                      context,
                      repository: memoryRepository,
                      ioService: ioService,
                      onlyTier: MemoryTier.external,
                    );
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _KnowledgeBaseAction.exportAll,
                  child: Text('导出知识库'),
                ),
                PopupMenuItem(
                  value: _KnowledgeBaseAction.importAll,
                  child: Text('导入知识库'),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
            TextButton.icon(
              onPressed: () {
                _openCollectionDialog(context, memoryRepository);
              },
              icon: const Icon(Icons.add),
              label: const Text('新增分类'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (collections.isEmpty)
          _EmptyState(message: '暂无数据库分类，请新增一个分类。')
        else
          Expanded(
            child: ListView.builder(
              itemCount: collections.length,
              itemBuilder: (context, index) {
                final collection = collections[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    title: Text(collection.name),
                    subtitle: Text('记录 ${collection.records.length}'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: '编辑分类',
                          onPressed: () {
                            _openCollectionDialog(
                              context,
                              memoryRepository,
                              collection: collection,
                            );
                          },
                          icon: const Icon(Icons.edit_outlined, size: 20),
                        ),
                        IconButton(
                          tooltip: '删除分类',
                          onPressed: () {
                            memoryRepository.removeCollection(collection.id);
                          },
                          icon: const Icon(Icons.delete_outline, size: 20),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MemoryCollectionScreen(
                            collection: collection,
                            memoryRepository: memoryRepository,
                            settingsRepository: settingsRepository,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class MemoryCollectionScreen extends StatelessWidget {
  const MemoryCollectionScreen({
    super.key,
    required this.collection,
    required this.memoryRepository,
    required this.settingsRepository,
  });

  final MemoryCollection collection;
  final MemoryRepository memoryRepository;
  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: memoryRepository,
      builder: (context, _) {
        final updated = memoryRepository
            .collectionsByTier(MemoryTier.external)
            .firstWhere(
              (item) => item.id == collection.id,
              orElse: () => collection,
            );
        final ioService = MemoryImportExportService();
        final forgeService = MemoryForgeService();
        return Scaffold(
          appBar: AppBar(
            title: Text(updated.name),
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '外部知识库仅在需要时调用，适合专业资料与用户导入数据。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5E636F),
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      '记录列表',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    PopupMenuButton<_KnowledgeCollectionAction>(
                      tooltip: '更多操作',
                      onSelected: (action) async {
                        switch (action) {
                          case _KnowledgeCollectionAction.export:
                            final result = await ioService.exportCollections(
                              collections: [updated],
                              filenamePrefix: 'cmyke_knowledge_${updated.name}',
                              tiers: const [MemoryTier.external],
                            );
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已导出: ${result.jsonPath}')),
                            );
                            break;
                          case _KnowledgeCollectionAction.importInto:
                            await _openMemoryImportDialog(
                              context,
                              repository: memoryRepository,
                              ioService: ioService,
                              onlyTier: MemoryTier.external,
                              targetExternalCollectionId: updated.id,
                            );
                            break;
                          case _KnowledgeCollectionAction.forge:
                            await _openMemoryForgeDialog(
                              context,
                              tier: MemoryTier.external,
                              repository: memoryRepository,
                              settingsRepository: settingsRepository,
                              forgeService: forgeService,
                              targetExternalCollectionId: updated.id,
                            );
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _KnowledgeCollectionAction.export,
                          child: Text('导出分类'),
                        ),
                        PopupMenuItem(
                          value: _KnowledgeCollectionAction.importInto,
                          child: Text('导入到此分类'),
                        ),
                        PopupMenuItem(
                          value: _KnowledgeCollectionAction.forge,
                          child: Text('AI 生成知识条目'),
                        ),
                      ],
                      icon: const Icon(Icons.more_vert),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        _openRecordDialog(
                          context,
                          memoryRepository,
                          tier: MemoryTier.external,
                          collectionId: updated.id,
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('新增'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (updated.records.isEmpty)
                  _EmptyState(message: '该分类暂无记录。')
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: updated.records.length,
                      itemBuilder: (context, index) {
                        final record = updated.records[index];
                        return _RecordTile(
                          record: record,
                          onEdit: () {
                            _openRecordDialog(
                              context,
                              memoryRepository,
                              tier: MemoryTier.external,
                              collectionId: updated.id,
                              record: record,
                            );
                          },
                          onDelete: () {
                            memoryRepository.removeRecord(
                              collectionId: updated.id,
                              recordId: record.id,
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.record,
    required this.onEdit,
    required this.onDelete,
  });

  final MemoryRecord record;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = record.title ?? _snippet(record.content);
    final scopeLabel = _scopeLabel(record.scope);
    final subtitle = scopeLabel == null
        ? record.content
        : '$scopeLabel · ${record.content}';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(title),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            IconButton(
              tooltip: '编辑',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            IconButton(
              tooltip: '删除',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  String _snippet(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '未命名记录';
    }
    return trimmed.length > 18 ? '${trimmed.substring(0, 18)}...' : trimmed;
  }

  String? _scopeLabel(String? scope) {
    final trimmed = scope?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    switch (trimmed) {
      case 'brain.user':
        return '个人';
      case 'knowledge.docs':
        return '知识库';
      default:
        return trimmed;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF7A7F8A),
            ),
      ),
    );
  }
}

String _tierDescription(MemoryTier tier) {
  switch (tier) {
    case MemoryTier.context:
      return '会话上下文记忆（含会话摘要），仅绑定当前会话，适合短期信息与压缩锚点。';
    case MemoryTier.crossSession:
      return '核心记忆会被持续注入系统提示词，用于稳定的人设、偏好与关键事实（应避免写入短期琐碎信息）。';
    case MemoryTier.autonomous:
      return '日记记忆用于记录可追溯的“发生过的事”（按时间检索更准），适合回答“昨天聊了什么/上周去了哪里”。';
    case MemoryTier.external:
      return '知识库支持多分类，按需检索时调用，适合文档/资料等外部信息。';
  }
}

Future<void> _openMemoryImportDialog(
  BuildContext context, {
  required MemoryRepository repository,
  required MemoryImportExportService ioService,
  MemoryTier? onlyTier,
  String? targetExternalCollectionId,
}) async {
  final rootContext = context;
  final controller = TextEditingController();
  var markImportedTag = true;
  var isImporting = false;

  String title = '导入记忆';
  if (onlyTier != null) {
    title = '导入${onlyTier.label}';
  }

  await showDialog<void>(
    context: rootContext,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('请粘贴导出的 JSON 文件路径（通常在 文档/cmyke/exports）。'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: '文件路径',
                      hintText: r'C:\Users\...\Documents\cmyke\exports\xxx.json',
                    ),
                    minLines: 1,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('为导入记录添加 imported 标签'),
                    value: markImportedTag,
                    onChanged: isImporting
                        ? null
                        : (value) => setState(() {
                              markImportedTag = value ?? true;
                            }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isImporting ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: isImporting
                    ? null
                    : () async {
                        final path = controller.text.trim();
                        if (path.isEmpty) {
                          return;
                        }
                        setState(() => isImporting = true);
                        try {
                          final result = await ioService.importFromFile(
                            path: path,
                            repository: repository,
                            onlyTier: onlyTier,
                            targetExternalCollectionId: targetExternalCollectionId,
                            markImportedTag: markImportedTag,
                            embed: false,
                          );
                          if (!rootContext.mounted) {
                            return;
                          }
                          Navigator.of(dialogContext).pop();
                          final suffix = result.collectionsCreated > 0
                              ? '，新增分类 ${result.collectionsCreated}'
                              : '';
                          final warningSuffix = result.warnings.isEmpty
                              ? ''
                              : '（${result.warnings.join('；')}）';
                          ScaffoldMessenger.of(rootContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                '导入完成：新增 ${result.recordsImported}，更新 ${result.recordsUpdated}，跳过 ${result.recordsSkipped}$suffix$warningSuffix',
                              ),
                            ),
                          );
                        } catch (error) {
                          if (!rootContext.mounted) {
                            return;
                          }
                          setState(() => isImporting = false);
                          ScaffoldMessenger.of(rootContext).showSnackBar(
                            SnackBar(content: Text('导入失败: $error')),
                          );
                        }
                      },
                child: isImporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('导入'),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
}

Future<void> _openMemoryForgeDialog(
  BuildContext context, {
  required MemoryTier tier,
  required MemoryRepository repository,
  required SettingsRepository settingsRepository,
  required MemoryForgeService forgeService,
  String? targetExternalCollectionId,
  String? sessionId,
}) async {
  final rootContext = context;
  final providers = settingsRepository.providersByKind(ProviderKind.llm);
  if (providers.isEmpty) {
    ScaffoldMessenger.of(rootContext).showSnackBar(
      const SnackBar(content: Text('未配置 LLM 模型，无法生成记忆。')),
    );
    return;
  }

  final preferredAgent = settingsRepository.settings.memoryAgentProviderId?.trim();
  final preferredLlm = settingsRepository.settings.llmProviderId?.trim();
  var selectedProviderId = (preferredAgent != null && preferredAgent.isNotEmpty)
      ? preferredAgent
      : (preferredLlm != null && preferredLlm.isNotEmpty)
          ? preferredLlm
          : providers.first.id;
  if (!providers.any((provider) => provider.id == selectedProviderId)) {
    selectedProviderId = providers.first.id;
  }

  final instructionController = TextEditingController();
  final keyController = TextEditingController();
  final titleController = TextEditingController();
  final contentController = TextEditingController();
  final tagsController = TextEditingController();
  final occurredAtController = TextEditingController();
  var fictional = true;
  var isGenerating = false;
  MemoryForgeDraft? draft;

  String dialogTitle = 'AI 生成记忆';
  if (tier == MemoryTier.external) {
    dialogTitle = 'AI 生成知识条目';
  }

  await showDialog<void>(
    context: rootContext,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> generate() async {
            final provider = settingsRepository.findProvider(selectedProviderId);
            if (provider == null) {
              ScaffoldMessenger.of(rootContext).showSnackBar(
                const SnackBar(content: Text('请选择有效的 LLM 配置。')),
              );
              return;
            }
            setState(() => isGenerating = true);
            try {
              final result = await forgeService.generate(
                provider: provider,
                tier: tier,
                instruction: instructionController.text,
                preferredCoreKey: keyController.text,
                fictional: fictional,
              );
              if (result == null) {
                throw StateError('模型未返回可解析的 JSON。');
              }
              draft = result;
              titleController.text = result.title ?? '';
              contentController.text = result.content;
              tagsController.text = result.tags.join(', ');
              if (result.coreKey != null) {
                keyController.text = result.coreKey!;
              }
              if (result.occurredAt != null) {
                occurredAtController.text = result.occurredAt!.toIso8601String();
              }
            } catch (error) {
              if (!rootContext.mounted) {
                return;
              }
              ScaffoldMessenger.of(rootContext).showSnackBar(
                SnackBar(content: Text('生成失败: $error')),
              );
            } finally {
              if (rootContext.mounted) {
                setState(() => isGenerating = false);
              }
            }
          }

          Future<void> save() async {
            final content = contentController.text.trim();
            if (content.isEmpty) {
              return;
            }
            final title = titleController.text.trim();
            final tags = <String>{
              ...tagsController.text
                  .split(RegExp(r'[，,]'))
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty),
              'source:forge',
              if (fictional) 'fictional',
            }.toList(growable: false);

            switch (tier) {
              case MemoryTier.crossSession:
                final key = keyController.text.trim();
                if (key.isEmpty) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('核心记忆需要 core_key。')),
                  );
                  return;
                }
                await repository.upsertCoreMemory(
                  key: key,
                  content: content,
                  title: title.isEmpty ? null : title,
                  tags: tags,
                  includeAgentTag: false,
                );
                break;
              case MemoryTier.autonomous:
                DateTime occurredAt = DateTime.now();
                final raw = occurredAtController.text.trim();
                if (raw.isNotEmpty) {
                  try {
                    occurredAt = DateTime.parse(raw);
                  } catch (_) {
                    occurredAt = DateTime.now();
                  }
                }
                await repository.addDiaryMemory(
                  occurredAt: occurredAt,
                  content: content,
                  title: title.isEmpty ? null : title,
                  tags: tags,
                  includeAgentTag: false,
                );
                break;
              case MemoryTier.external:
                final targetId = targetExternalCollectionId?.trim();
                if (targetId == null || targetId.isEmpty) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('请选择知识库分类后再保存。')),
                  );
                  return;
                }
                await repository.addRecord(
                  tier: MemoryTier.external,
                  collectionId: targetId,
                  record: MemoryRecord(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    tier: MemoryTier.external,
                    content: content,
                    createdAt: DateTime.now(),
                    title: title.isEmpty ? null : title,
                    tags: tags,
                  ),
                );
                break;
              case MemoryTier.context:
                final sid = sessionId?.trim();
                if (sid == null || sid.isEmpty) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('缺少会话 ID，无法写入会话上下文。')),
                  );
                  return;
                }
                await repository.addRecord(
                  tier: MemoryTier.context,
                  collectionId: repository.defaultCollection(MemoryTier.context).id,
                  sessionId: sid,
                  record: MemoryRecord(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    tier: MemoryTier.context,
                    content: content,
                    createdAt: DateTime.now(),
                    title: title.isEmpty ? null : title,
                    tags: tags,
                    sessionId: sid,
                  ),
                );
                break;
            }

            if (!rootContext.mounted) {
              return;
            }
            Navigator.of(dialogContext).pop();
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(content: Text('已写入: ${tier.label}')),
            );
          }

          final canSave = !isGenerating &&
              (draft != null || contentController.text.trim().isNotEmpty);

          return AlertDialog(
            title: Text(dialogTitle),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedProviderId,
                      decoration: const InputDecoration(labelText: 'LLM 模型'),
                      items: providers
                          .map(
                            (provider) => DropdownMenuItem(
                              value: provider.id,
                              child: Text(provider.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: isGenerating
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => selectedProviderId = value);
                            },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('虚构/设定记忆'),
                      subtitle: const Text('勾选后会写入 fictional 标签，方便后续区分。'),
                      value: fictional,
                      onChanged: isGenerating
                          ? null
                          : (value) => setState(() => fictional = value),
                    ),
                    if (tier == MemoryTier.crossSession) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: keyController,
                        enabled: !isGenerating,
                        decoration: const InputDecoration(
                          labelText: 'core_key（可留空让模型生成）',
                          hintText: 'persona.name / user.preference.* / constraints.*',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: instructionController,
                      enabled: !isGenerating,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: '生成指令',
                        hintText: '例如：为助手写一条“人设背景”核心记忆，语气自然，不要自称 AI。',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      enabled: !isGenerating,
                      decoration: const InputDecoration(labelText: '标题（可编辑）'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contentController,
                      enabled: !isGenerating,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(labelText: '内容（可编辑）'),
                    ),
                    const SizedBox(height: 12),
                    if (tier == MemoryTier.autonomous)
                      TextField(
                        controller: occurredAtController,
                        enabled: !isGenerating,
                        decoration: const InputDecoration(
                          labelText: '发生时间（ISO8601，可选）',
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tagsController,
                      enabled: !isGenerating,
                      decoration: const InputDecoration(
                        labelText: '标签（逗号分隔，可选）',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isGenerating ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: isGenerating ? null : generate,
                child: isGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('生成'),
              ),
              FilledButton(
                onPressed: canSave ? save : null,
                child: const Text('写入'),
              ),
            ],
          );
        },
      );
    },
  );

  instructionController.dispose();
  keyController.dispose();
  titleController.dispose();
  contentController.dispose();
  tagsController.dispose();
  occurredAtController.dispose();
}

Future<void> _openCollectionDialog(
  BuildContext context,
  MemoryRepository repository, {
  MemoryCollection? collection,
}) async {
  final controller =
      TextEditingController(text: collection?.name ?? '');
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(collection == null ? '新增分类' : '编辑分类'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '分类名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                return;
              }
              if (collection == null) {
                await repository.addExternalCollection(name);
              } else {
                await repository.renameCollection(collection.id, name);
              }
              if (!context.mounted) {
                return;
              }
              Navigator.of(context).pop();
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  );
  controller.dispose();
}

Future<void> _openRecordDialog(
  BuildContext context,
  MemoryRepository repository, {
  required MemoryTier tier,
  required String collectionId,
  MemoryRecord? record,
  String? sessionId,
}) async {
  final titleController =
      TextEditingController(text: record?.title ?? '');
  final contentController =
      TextEditingController(text: record?.content ?? '');
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(record == null ? '新增记忆' : '编辑记忆'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: '标题 (可选)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '内容'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final content = contentController.text.trim();
              if (content.isEmpty) {
                return;
              }
              final nextRecord = MemoryRecord(
                id: record?.id ??
                    DateTime.now().microsecondsSinceEpoch.toString(),
                tier: tier,
                content: content,
                createdAt: record?.createdAt ?? DateTime.now(),
                title: titleController.text.trim().isEmpty
                    ? null
                    : titleController.text.trim(),
                sourceMessageId: record?.sourceMessageId,
                tags: record?.tags ?? const [],
                sessionId: record?.sessionId ?? sessionId,
                scope: record?.scope,
              );
              if (record == null) {
                await repository.addRecord(
                  tier: tier,
                  record: nextRecord,
                  collectionId: collectionId,
                  sessionId: sessionId,
                );
              } else {
                await repository.updateRecord(
                  collectionId: collectionId,
                  record: nextRecord,
                  sessionId: sessionId,
                );
              }
              if (!context.mounted) {
                return;
              }
              Navigator.of(context).pop();
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  );
  titleController.dispose();
  contentController.dispose();
}
