import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/memory_collection.dart';
import '../models/memory_record.dart';
import '../models/memory_tier.dart';
import '../repositories/memory_repository.dart';

class MemoryExportResult {
  const MemoryExportResult({
    required this.jsonPath,
    this.markdownPath,
  });

  final String jsonPath;
  final String? markdownPath;
}

class MemoryImportResult {
  const MemoryImportResult({
    required this.recordsImported,
    required this.recordsUpdated,
    required this.recordsSkipped,
    required this.collectionsCreated,
    this.warnings = const [],
  });

  final int recordsImported;
  final int recordsUpdated;
  final int recordsSkipped;
  final int collectionsCreated;
  final List<String> warnings;
}

class MemoryImportExportService {
  const MemoryImportExportService();

  static const int _formatVersion = 1;
  static const String _coreKeyTagPrefix = 'core_key:';

  Future<MemoryExportResult> exportCollections({
    required List<MemoryCollection> collections,
    String filenamePrefix = 'cmyke_memory',
    List<MemoryTier>? tiers,
    bool includeMarkdown = true,
  }) async {
    final normalizedTiers = tiers?.toSet();
    final selected = normalizedTiers == null
        ? collections
        : collections
            .where((collection) => normalizedTiers.contains(collection.tier))
            .toList(growable: false);

    final exportedAt = DateTime.now();
    final payload = {
      'type': 'cmyke_memory_export',
      'version': _formatVersion,
      'exported_at': exportedAt.toIso8601String(),
      'collections': selected.map((c) => c.toJson()).toList(),
    };

    final safePrefix = filenamePrefix.trim().isEmpty
        ? 'cmyke_memory'
        : filenamePrefix.trim();
    final baseName = '${safePrefix}_${exportedAt.millisecondsSinceEpoch}';
    final jsonPath = await _writeJsonFile(
      filename: '$baseName.json',
      payload: payload,
    );
    String? mdPath;
    if (includeMarkdown) {
      mdPath = await _writeTextFile(
        filename: '$baseName.md',
        contents: _collectionsToMarkdown(
          selected,
          exportedAt: exportedAt,
        ),
      );
    }
    return MemoryExportResult(jsonPath: jsonPath, markdownPath: mdPath);
  }

  Future<List<MemoryCollection>> readCollectionsFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File not found', path);
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((entry) => MemoryCollection.fromJson(
                Map<String, dynamic>.from(entry),
              ))
          .toList();
    }
    if (decoded is! Map) {
      return [];
    }
    final map = Map<String, dynamic>.from(decoded);
    final candidate = map['collections'] ?? map['memory_collections'];
    if (candidate is! List) {
      return [];
    }
    return candidate
        .whereType<Map>()
        .map((entry) => MemoryCollection.fromJson(
              Map<String, dynamic>.from(entry),
            ))
        .toList();
  }

  Future<MemoryImportResult> importFromFile({
    required String path,
    required MemoryRepository repository,
    MemoryTier? onlyTier,
    String? targetExternalCollectionId,
    bool markImportedTag = true,
    bool embed = false,
  }) async {
    final importedCollections = await readCollectionsFromFile(path);
    if (importedCollections.isEmpty) {
      return const MemoryImportResult(
        recordsImported: 0,
        recordsUpdated: 0,
        recordsSkipped: 0,
        collectionsCreated: 0,
      );
    }

    final warnings = <String>[];
    final collectionsCreated = <String>[];
    final targetExternalId = targetExternalCollectionId?.trim();

    if (onlyTier != null &&
        onlyTier != MemoryTier.external &&
        targetExternalId != null &&
        targetExternalId.isNotEmpty) {
      warnings.add('已忽略 targetExternalCollectionId：仅知识库导入才会使用该参数。');
    }

    final targetCollections = <String, String>{};
    if (onlyTier == null || onlyTier == MemoryTier.external) {
      if (targetExternalId != null && targetExternalId.isNotEmpty) {
        final exists = repository
            .collectionsByTier(MemoryTier.external)
            .any((c) => c.id == targetExternalId);
        if (!exists) {
          throw StateError('知识库分类不存在: $targetExternalId');
        }
      }

      for (final collection in importedCollections) {
        if (collection.tier != MemoryTier.external) continue;
        final normalizedName = collection.name.trim();
        if (normalizedName.isEmpty) continue;
        if (targetExternalId != null && targetExternalId.isNotEmpty) {
          targetCollections[normalizedName] = targetExternalId;
          continue;
        }
        final existing = repository
            .collectionsByTier(MemoryTier.external)
            .firstWhere(
              (c) => c.name.trim().toLowerCase() == normalizedName.toLowerCase(),
              orElse: () => MemoryCollection(
                id: '',
                tier: MemoryTier.external,
                name: '',
                createdAt: DateTime.fromMillisecondsSinceEpoch(0),
              ),
            );
        if (existing.id.isNotEmpty) {
          targetCollections[normalizedName] = existing.id;
          continue;
        }
        final created = await repository.addExternalCollection(normalizedName);
        collectionsCreated.add(created.name);
        targetCollections[normalizedName] = created.id;
      }
    }

    final existingContentIndex = _buildExistingContentIndex(repository);
    int imported = 0;
    int updated = 0;
    int skipped = 0;
    var importIdSeq = 0;

    for (final collection in importedCollections) {
      if (onlyTier != null && collection.tier != onlyTier) {
        continue;
      }

      final tier = collection.tier;
      if (tier == MemoryTier.external && targetCollections.isEmpty) {
        continue;
      }

      final targetCollectionId = _resolveTargetCollectionId(
        repository,
        tier: tier,
        importedCollectionName: collection.name,
        externalNameToId: targetCollections,
      );
      if (targetCollectionId == null) {
        continue;
      }

      for (final record in collection.records) {
        final normalizedContent = record.content.trim();
        if (normalizedContent.isEmpty) {
          skipped++;
          continue;
        }

        if (tier == MemoryTier.context) {
          final sessionId = record.sessionId?.trim();
          if (sessionId == null || sessionId.isEmpty) {
            skipped++;
            continue;
          }
        }

        final normalizedScope =
            _normalizeScopeForTier(tier, record.scope);
        final dedupeKey = _dedupeKey(
          collectionId: targetCollectionId,
          tier: tier,
          scope: normalizedScope,
          sessionId: record.sessionId,
        );

        final contentSet =
            existingContentIndex.putIfAbsent(dedupeKey, () => <String>{});

        if (tier == MemoryTier.crossSession) {
          final coreKey = _extractCoreKey(record.tags);
          if (coreKey != null) {
            final existing = repository.coreMemoryByKey(coreKey);
            if (existing != null) {
              final importedTitle = record.title?.trim();
              await repository.updateRecord(
                collectionId: repository.defaultCollection(MemoryTier.crossSession).id,
                record: existing.copyWith(
                  content: normalizedContent,
                  title: importedTitle == null || importedTitle.isEmpty
                      ? existing.title
                      : importedTitle,
                  tags: _mergeImportTags(
                    record.tags,
                    markImportedTag: markImportedTag,
                    ensureCoreKey: coreKey,
                  ),
                  scope: record.scope,
                ),
                embed: embed,
              );
              contentSet.add(normalizedContent);
              updated++;
              continue;
            }
          }
        }

        if (contentSet.contains(normalizedContent)) {
          skipped++;
          continue;
        }

        final importedTags = _mergeImportTags(
          record.tags,
          markImportedTag: markImportedTag,
          ensureCoreKey:
              tier == MemoryTier.crossSession ? _extractCoreKey(record.tags) : null,
        );
        final toInsert = MemoryRecord(
          id: '${DateTime.now().microsecondsSinceEpoch}_${importIdSeq++}',
          tier: tier,
          content: normalizedContent,
          createdAt: record.createdAt,
          sourceMessageId: record.sourceMessageId,
          title: record.title,
          tags: importedTags,
          sessionId: record.sessionId,
          scope: record.scope,
        );
        await repository.addRecord(
          tier: tier,
          record: toInsert,
          collectionId: targetCollectionId,
          sessionId: record.sessionId,
          scope: normalizedScope,
          embed: embed,
        );
        contentSet.add(normalizedContent);
        imported++;
      }
    }

    return MemoryImportResult(
      recordsImported: imported,
      recordsUpdated: updated,
      recordsSkipped: skipped,
      collectionsCreated: collectionsCreated.length,
      warnings: warnings,
    );
  }

  Map<String, Set<String>> _buildExistingContentIndex(MemoryRepository repository) {
    final index = <String, Set<String>>{};
    for (final collection in repository.collections) {
      for (final record in collection.records) {
        final content = record.content.trim();
        if (content.isEmpty) {
          continue;
        }
        final key = _dedupeKey(
          collectionId: collection.id,
          tier: record.tier,
          scope: _normalizeScopeForTier(record.tier, record.scope),
          sessionId: record.sessionId,
        );
        index.putIfAbsent(key, () => <String>{}).add(content);
      }
    }
    return index;
  }

  String _dedupeKey({
    required String collectionId,
    required MemoryTier tier,
    required String scope,
    String? sessionId,
  }) {
    if (tier == MemoryTier.context) {
      return '$collectionId|$scope|${sessionId ?? ''}';
    }
    return '$collectionId|$scope';
  }

  String _normalizeScopeForTier(MemoryTier tier, String? scope) {
    final trimmed = scope?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == 'brain.user') {
      switch (tier) {
        case MemoryTier.context:
          return 'brain.session';
        case MemoryTier.crossSession:
          return 'brain.core';
        case MemoryTier.autonomous:
          return 'brain.diary';
        case MemoryTier.external:
          return 'knowledge.docs';
      }
    }
    return trimmed;
  }

  String? _resolveTargetCollectionId(
    MemoryRepository repository, {
    required MemoryTier tier,
    required String importedCollectionName,
    required Map<String, String> externalNameToId,
  }) {
    switch (tier) {
      case MemoryTier.external:
        final key = importedCollectionName.trim();
        if (key.isEmpty) {
          return null;
        }
        return externalNameToId[key];
      case MemoryTier.context:
      case MemoryTier.crossSession:
      case MemoryTier.autonomous:
        return repository.defaultCollection(tier).id;
    }
  }

  String? _extractCoreKey(List<String> tags) {
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (!trimmed.startsWith(_coreKeyTagPrefix)) continue;
      final key = trimmed.substring(_coreKeyTagPrefix.length).trim();
      if (key.isNotEmpty) return key;
    }
    return null;
  }

  List<String> _mergeImportTags(
    List<String> rawTags, {
    required bool markImportedTag,
    String? ensureCoreKey,
  }) {
    final normalized = <String>{
      ...rawTags.map((t) => t.trim()).where((t) => t.isNotEmpty),
      if (markImportedTag) 'imported',
    };
    final coreKey = ensureCoreKey?.trim();
    if (coreKey != null && coreKey.isNotEmpty) {
      normalized.add('$_coreKeyTagPrefix$coreKey');
    }
    return normalized.toList(growable: false);
  }

  Future<String> _writeJsonFile({
    required String filename,
    required Map<String, dynamic> payload,
  }) async {
    final dir = await _exportsDirectory();
    final file = File('${dir.path}/$filename');
    final encoder = const JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(payload));
    return file.path;
  }

  Future<String> _writeTextFile({
    required String filename,
    required String contents,
  }) async {
    final dir = await _exportsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(contents);
    return file.path;
  }

  Future<Directory> _exportsDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/cmyke/exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _collectionsToMarkdown(
    List<MemoryCollection> collections, {
    required DateTime exportedAt,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('# CMYKE Memory Export');
    buffer.writeln('- Exported: ${exportedAt.toIso8601String()}');
    buffer.writeln('- Collections: ${collections.length}');
    buffer.writeln('');
    final sorted = collections.toList()
      ..sort((a, b) => a.tier.index.compareTo(b.tier.index));
    for (final collection in sorted) {
      buffer.writeln('## ${collection.name} (${collection.tier.label})');
      buffer.writeln('- Records: ${collection.records.length}');
      buffer.writeln('');
      if (collection.records.isEmpty) {
        buffer.writeln('- (empty)');
        buffer.writeln('');
        continue;
      }
      for (final record in collection.records) {
        final meta = <String>[];
        final scope = record.scope?.trim();
        if (scope != null && scope.isNotEmpty) meta.add('scope: $scope');
        final sessionId = record.sessionId?.trim();
        if (sessionId != null && sessionId.isNotEmpty) {
          meta.add('session: $sessionId');
        }
        final suffix = meta.isEmpty ? '' : ' (${meta.join(', ')})';
        buffer.writeln('- ${record.content}$suffix');
      }
      buffer.writeln('');
    }
    return buffer.toString().trimRight();
  }
}
