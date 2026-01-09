import 'package:flutter/material.dart';

import '../../core/models/memory_collection.dart';
import '../../core/models/memory_record.dart';
import '../../core/models/memory_tier.dart';
import '../../core/repositories/memory_repository.dart';

class MemoryTierScreen extends StatelessWidget {
  const MemoryTierScreen({
    super.key,
    required this.tier,
    required this.memoryRepository,
  });

  final MemoryTier tier;
  final MemoryRepository memoryRepository;

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
                        )
                      : _SingleTierEditor(
                          tier: tier,
                          memoryRepository: memoryRepository,
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

class _SingleTierEditor extends StatelessWidget {
  const _SingleTierEditor({
    required this.tier,
    required this.memoryRepository,
  });

  final MemoryTier tier;
  final MemoryRepository memoryRepository;

  @override
  Widget build(BuildContext context) {
    final collection = memoryRepository.defaultCollection(tier);
    final records = collection.records;
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
            TextButton.icon(
              onPressed: () {
                _openRecordDialog(
                  context,
                  memoryRepository,
                  tier: tier,
                  collectionId: collection.id,
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
  });

  final MemoryRepository memoryRepository;

  @override
  Widget build(BuildContext context) {
    final collections = memoryRepository.collectionsByTier(MemoryTier.external);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '专业数据库',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
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
  });

  final MemoryCollection collection;
  final MemoryRepository memoryRepository;

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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(title),
        subtitle: Text(
          record.content,
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
      return '会话内上下文记忆，随对话窗口滚动，适合短期信息。';
    case MemoryTier.crossSession:
      return '跨会话记忆会被持续注入系统提示词，用于稳定的人设与偏好。';
    case MemoryTier.autonomous:
      return '自主沉淀由模型或系统记录关键内容，确保长期一致性。';
    case MemoryTier.external:
      return '专业数据库支持多分类，按需检索时调用，适合大型知识库。';
  }
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
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) {
                return;
              }
              if (collection == null) {
                repository.addExternalCollection(name);
              } else {
                repository.renameCollection(collection.id, name);
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
            onPressed: () {
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
              );
              if (record == null) {
                repository.addRecord(
                  tier: tier,
                  record: nextRecord,
                  collectionId: collectionId,
                );
              } else {
                repository.updateRecord(
                  collectionId: collectionId,
                  record: nextRecord,
                );
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
