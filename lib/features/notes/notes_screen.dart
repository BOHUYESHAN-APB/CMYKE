import 'package:flutter/material.dart';

import '../../core/models/memory_record.dart';
import '../../core/models/memory_tier.dart';
import '../../core/models/note.dart';
import '../../core/repositories/memory_repository.dart';
import '../../core/repositories/note_repository.dart';
import '../../ui/theme/cmyke_chrome.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({
    super.key,
    required this.noteRepository,
    required this.memoryRepository,
  });

  final NoteRepository noteRepository;
  final MemoryRepository memoryRepository;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([noteRepository, memoryRepository]),
      builder: (context, _) {
        final notes = noteRepository.notes;
        final reviewEntries = notes
            .map(_buildReviewEntry)
            .whereType<_NoteReviewEntry>()
            .toList(growable: false);
        return Scaffold(
          appBar: AppBar(
            title: const Text('笔记与资料'),
            actions: [
              IconButton(
                tooltip: '新建笔记',
                onPressed: () => _openEditor(context),
                icon: const Icon(Icons.note_add_outlined),
              ),
            ],
          ),
          body: notes.isEmpty
              ? _EmptyNotes(onCreate: () => _openEditor(context))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: notes.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _NotesPolicyCard(reviewEntries: reviewEntries),
                      );
                    }
                    final note = notes[index - 1];
                    return _NoteCard(
                      note: note,
                      reviewEntry: _buildReviewEntry(note),
                      onTap: () => _openEditor(context, note: note),
                      onSync: () => _openMemorySyncDialog(context, note),
                      onDelete: () => _confirmDelete(context, note),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.add),
            label: const Text('新建笔记'),
          ),
        );
      },
    );
  }

  Future<void> _openEditor(BuildContext context, {Note? note}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _NoteEditorScreen(noteRepository: noteRepository, note: note),
      ),
    );
  }

  Future<void> _openMemorySyncDialog(BuildContext context, Note note) async {
    final draft = await showDialog<_MemorySyncDraft>(
      context: context,
      builder: (context) => _MemorySyncDialog(note: note),
    );
    if (draft == null) {
      return;
    }
    final synced = await memoryRepository.syncNoteMemory(
      noteId: note.id,
      title: note.title,
      content: note.content,
      summary: note.summary,
      tier: draft.tier,
      coreKey: draft.coreKey,
      occurredAt: draft.occurredAt,
    );
    if (!context.mounted) {
      return;
    }
    if (synced == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这篇笔记还不能归档到所选记忆层级')));
      return;
    }
    await noteRepository.updateMemoryLink(
      noteId: note.id,
      memoryTier: draft.tier.key,
      memoryRecordId: synced.id,
      syncedAt: DateTime.now(),
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已同步到${draft.tier.label}')));
  }

  Future<void> _confirmDelete(BuildContext context, Note note) async {
    final linkedMemory = _findLinkedMemory(note);
    final action = await showDialog<_DeleteNoteAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记'),
        content: Text(
          linkedMemory == null
              ? '确定删除“${note.title}”吗？'
              : '这篇笔记已归档到${linkedMemory.tier.label}。你可以只删除笔记，或连同联动记忆一起清理，避免留下失去来源的孤立记忆。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          if (linkedMemory != null)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_DeleteNoteAction.noteOnly),
              child: const Text('仅删笔记'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              linkedMemory == null
                  ? _DeleteNoteAction.noteOnly
                  : _DeleteNoteAction.noteAndMemory,
            ),
            child: Text(linkedMemory == null ? '删除' : '一起删除'),
          ),
        ],
      ),
    );
    if (action == null) {
      return;
    }
    if (action == _DeleteNoteAction.noteAndMemory && linkedMemory != null) {
      await memoryRepository.removeRecord(
        collectionId: linkedMemory.collectionId,
        recordId: linkedMemory.record.id,
      );
    }
    await noteRepository.deleteNote(note.id);
  }

  _LinkedMemoryTarget? _findLinkedMemory(Note note) {
    for (final tier in const [
      MemoryTier.crossSession,
      MemoryTier.autonomous,
      MemoryTier.external,
    ]) {
      final record = memoryRepository.noteLinkedRecord(note.id, tier);
      if (record == null) {
        continue;
      }
      final collectionId = memoryRepository.collectionIdForRecord(record.id);
      if (collectionId == null) {
        continue;
      }
      return _LinkedMemoryTarget(
        tier: tier,
        collectionId: collectionId,
        record: record,
      );
    }
    return null;
  }

  _NoteReviewEntry? _buildReviewEntry(Note note) {
    final tierKey = note.memoryTier?.trim();
    if (tierKey == null || tierKey.isEmpty) {
      return _NoteReviewEntry(
        note: note,
        state: _NoteReviewState.unsynced,
        reason: '还没从学习笔记提炼成记忆。',
      );
    }
    final tier = MemoryTier.values
        .where((item) => item.key == tierKey)
        .firstOrNull;
    if (tier == null || tier == MemoryTier.context) {
      return _NoteReviewEntry(
        note: note,
        state: _NoteReviewState.needsReview,
        reason: '当前联动层级无效，需要重新归档。',
      );
    }
    final syncedAt = note.memorySyncedAt;
    if (syncedAt == null) {
      return _NoteReviewEntry(
        note: note,
        state: _NoteReviewState.needsReview,
        reason: '缺少同步时间，无法判断是否过期。',
      );
    }
    if (note.updatedAt.isAfter(syncedAt.add(const Duration(minutes: 1)))) {
      return _NoteReviewEntry(
        note: note,
        tier: tier,
        state: _NoteReviewState.changedAfterSync,
        reason: '笔记在同步后又被编辑，需要重新整理记忆。',
      );
    }
    final windowDays = tier.reviewWindowDays;
    if (windowDays != null &&
        DateTime.now().difference(syncedAt).inDays >= windowDays) {
      return _NoteReviewEntry(
        note: note,
        tier: tier,
        state: _NoteReviewState.needsReview,
        reason: tier.reviewRule,
      );
    }
    return _NoteReviewEntry(
      note: note,
      tier: tier,
      state: _NoteReviewState.stable,
      reason: '当前联动仍在有效复核窗口内。',
    );
  }
}

class _NotesPolicyCard extends StatelessWidget {
  const _NotesPolicyCard({required this.reviewEntries});

  final List<_NoteReviewEntry> reviewEntries;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final unsyncedCount = reviewEntries
        .where((item) => item.state == _NoteReviewState.unsynced)
        .length;
    final changedCount = reviewEntries
        .where((item) => item.state == _NoteReviewState.changedAfterSync)
        .length;
    final reviewCount = reviewEntries
        .where((item) => item.state == _NoteReviewState.needsReview)
        .length;
    final queue = reviewEntries
        .where(
          (item) =>
              item.state == _NoteReviewState.changedAfterSync ||
              item.state == _NoteReviewState.needsReview,
        )
        .take(3)
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Neuro-sama 学习导向',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '笔记保留学习原文、项目拆解与临时观察；记忆只沉淀稳定设定、时间性事件和可复用知识。遗忘机制的第一步不是删内容，而是避免把所有学习细节都塞进长期记忆。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: chrome.textSecondary),
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('核心记忆 = 稳定规则 / 偏好')),
                Chip(label: Text('日记记忆 = 阶段事件 / 演进')),
                Chip(label: Text('知识库 = 项目资料 / 外部文档')),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('未归档 $unsyncedCount')),
                Chip(label: Text('待重整 $changedCount')),
                Chip(label: Text('待复核 $reviewCount')),
              ],
            ),
            if (queue.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '当前复核队列',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final entry in queue)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${entry.note.title}: ${entry.reason}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: chrome.textSecondary,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              size: 56,
              color: chrome.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              '还没有迁入笔记',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '先记录学习项目原文，再决定哪些内容应进入核心记忆、日记记忆或知识库。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: chrome.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('创建第一篇笔记'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DeleteNoteAction { noteOnly, noteAndMemory }

class _LinkedMemoryTarget {
  const _LinkedMemoryTarget({
    required this.tier,
    required this.collectionId,
    required this.record,
  });

  final MemoryTier tier;
  final String collectionId;
  final MemoryRecord record;
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.reviewEntry,
    required this.onTap,
    required this.onSync,
    required this.onDelete,
  });

  final Note note;
  final _NoteReviewEntry? reviewEntry;
  final VoidCallback onTap;
  final VoidCallback onSync;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final linkedTier = _tierLabel(note.memoryTier);
    final reviewTone = _reviewTone(context, reviewEntry?.state);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: chrome.accent.withValues(alpha: 0.12),
                foregroundColor: chrome.accent,
                child: const Icon(Icons.description_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      note.summary.isEmpty ? '暂无摘要' : note.summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: chrome.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '更新于 ${_formatTime(note.updatedAt)}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: chrome.textSecondary),
                        ),
                        if (linkedTier != null)
                          Chip(
                            label: Text('已归档到$linkedTier'),
                            visualDensity: VisualDensity.compact,
                          )
                        else
                          Chip(
                            label: const Text('仅笔记'),
                            visualDensity: VisualDensity.compact,
                          ),
                        if (reviewEntry != null)
                          Chip(
                            label: Text(_reviewLabel(reviewEntry!.state)),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: reviewTone?.background,
                            labelStyle: TextStyle(
                              color: reviewTone?.foreground,
                            ),
                          ),
                      ],
                    ),
                    if (reviewEntry != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        reviewEntry!.reason,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: reviewTone?.foreground ?? chrome.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    tooltip: '归档到记忆',
                    onPressed: onSync,
                    icon: const Icon(Icons.account_tree_outlined),
                  ),
                  IconButton(
                    tooltip: '删除笔记',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _tierLabel(String? key) {
    if (key == null || key.trim().isEmpty) {
      return null;
    }
    for (final tier in MemoryTier.values) {
      if (tier.key == key) {
        return tier.label;
      }
    }
    return null;
  }

  String _reviewLabel(_NoteReviewState state) {
    switch (state) {
      case _NoteReviewState.unsynced:
        return '待归档';
      case _NoteReviewState.changedAfterSync:
        return '需重整';
      case _NoteReviewState.needsReview:
        return '待复核';
      case _NoteReviewState.stable:
        return '稳定';
    }
  }

  _ReviewTone? _reviewTone(BuildContext context, _NoteReviewState? state) {
    if (state == null) {
      return null;
    }
    final scheme = Theme.of(context).colorScheme;
    switch (state) {
      case _NoteReviewState.unsynced:
        return _ReviewTone(
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        );
      case _NoteReviewState.changedAfterSync:
      case _NoteReviewState.needsReview:
        return _ReviewTone(
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
        );
      case _NoteReviewState.stable:
        return _ReviewTone(
          background: scheme.primaryContainer,
          foreground: scheme.onPrimaryContainer,
        );
    }
  }

  String _formatTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}

class _MemorySyncDialog extends StatefulWidget {
  const _MemorySyncDialog({required this.note});

  final Note note;

  @override
  State<_MemorySyncDialog> createState() => _MemorySyncDialogState();
}

class _MemorySyncDialogState extends State<_MemorySyncDialog> {
  late MemoryTier _tier;
  late final TextEditingController _coreKeyController;
  late final TextEditingController _occurredAtController;

  @override
  void initState() {
    super.initState();
    _tier = _initialTier();
    _coreKeyController = TextEditingController(text: _defaultCoreKey());
    _occurredAtController = TextEditingController(
      text: _formatTime(widget.note.updatedAt),
    );
  }

  @override
  void dispose() {
    _coreKeyController.dispose();
    _occurredAtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('笔记归档到记忆'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '把学习项目笔记压缩成更稳定的记忆，而不是原样复制全部内容。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<MemoryTier>(
                value: _tier,
                decoration: const InputDecoration(labelText: '归档层级'),
                items: const [
                  DropdownMenuItem(
                    value: MemoryTier.crossSession,
                    child: Text('核心记忆'),
                  ),
                  DropdownMenuItem(
                    value: MemoryTier.autonomous,
                    child: Text('日记记忆'),
                  ),
                  DropdownMenuItem(
                    value: MemoryTier.external,
                    child: Text('知识库'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _tier = value);
                },
              ),
              const SizedBox(height: 12),
              _TierHintCard(tier: _tier),
              if (_tier == MemoryTier.crossSession) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _coreKeyController,
                  decoration: const InputDecoration(
                    labelText: 'core_key',
                    hintText: '例如 learning_target / style_preference',
                  ),
                ),
              ],
              if (_tier == MemoryTier.autonomous) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _occurredAtController,
                  decoration: const InputDecoration(
                    labelText: '事件时间',
                    hintText: 'YYYY-MM-DD HH:mm',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_tier == MemoryTier.crossSession &&
                _coreKeyController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('核心记忆需要填写 core_key')),
              );
              return;
            }
            Navigator.of(context).pop(
              _MemorySyncDraft(
                tier: _tier,
                coreKey: _coreKeyController.text.trim(),
                occurredAt: _tier == MemoryTier.autonomous
                    ? _parseOccurredAt(_occurredAtController.text)
                    : null,
              ),
            );
          },
          child: const Text('归档'),
        ),
      ],
    );
  }

  MemoryTier _initialTier() {
    final existing = widget.note.memoryTier;
    if (existing != null) {
      for (final tier in MemoryTier.values) {
        if (tier.key == existing && tier != MemoryTier.context) {
          return tier;
        }
      }
    }
    if (widget.note.content.length > 240) {
      return MemoryTier.external;
    }
    return MemoryTier.crossSession;
  }

  String _defaultCoreKey() {
    final existing = widget.note.title.trim().toLowerCase();
    if (existing.isEmpty) {
      return '';
    }
    return existing
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  DateTime _parseOccurredAt(String raw) {
    final normalized = raw.trim().replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized) ?? widget.note.updatedAt;
  }

  String _formatTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}

class _TierHintCard extends StatelessWidget {
  const _TierHintCard({required this.tier});

  final MemoryTier tier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tier.shortHint,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(tier.writeRule, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              '复核：${tier.reviewRule}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              '避免：${tier.avoidRule}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
            const SizedBox(height: 6),
            Text(
              '遗忘策略：${tier.forgettingRule}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MemorySyncDraft {
  const _MemorySyncDraft({
    required this.tier,
    required this.coreKey,
    this.occurredAt,
  });

  final MemoryTier tier;
  final String coreKey;
  final DateTime? occurredAt;
}

enum _NoteReviewState { unsynced, changedAfterSync, needsReview, stable }

class _NoteReviewEntry {
  const _NoteReviewEntry({
    required this.note,
    required this.state,
    required this.reason,
    this.tier,
  });

  final Note note;
  final MemoryTier? tier;
  final _NoteReviewState state;
  final String reason;
}

class _ReviewTone {
  const _ReviewTone({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

class _NoteEditorScreen extends StatefulWidget {
  const _NoteEditorScreen({required this.noteRepository, this.note});

  final NoteRepository noteRepository;
  final Note? note;

  @override
  State<_NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<_NoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(
      text: widget.note?.content ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.note != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑笔记' : '新建笔记'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中...' : '保存'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '可留空，系统会按正文自动生成',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _contentController,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  labelText: '正文',
                  hintText: '先记录学习项目，再决定哪些内容要进入核心记忆、日记记忆或知识库。',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正文不能为空')));
      return;
    }
    setState(() => _saving = true);
    await widget.noteRepository.saveNote(
      id: widget.note?.id,
      title: _titleController.text,
      content: content,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}
