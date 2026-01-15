import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/memory_collection.dart';
import '../models/memory_record.dart';
import '../models/memory_tier.dart';
import '../models/provider_config.dart';
import '../services/llm_client.dart';
import '../services/local_database.dart';
import '../services/local_storage.dart';

typedef EmbeddingProviderResolver = ProviderConfig? Function();

class MemoryRepository extends ChangeNotifier {
  MemoryRepository({
    required LocalDatabase database,
    LocalStorage? legacyStorage,
    EmbeddingProviderResolver? resolveEmbeddingProvider,
    LlmClient? llmClient,
  })  : _database = database,
        _legacyStorage = legacyStorage ?? LocalStorage(),
        _resolveEmbeddingProvider = resolveEmbeddingProvider,
        _llmClient = llmClient ?? LlmClient();

  final LocalDatabase _database;
  final LocalStorage _legacyStorage;
  final EmbeddingProviderResolver? _resolveEmbeddingProvider;
  final LlmClient _llmClient;
  final List<MemoryCollection> _collections = [];
  final Map<String, List<double>> _recordEmbeddings = {};

  static const String _storageFile = 'memory_records.json';
  static const String _collectionsTable = 'memory_collections';
  static const String _recordsTable = 'memory_records';
  static const String _sessionSummaryTag = 'session_summary';

  List<MemoryCollection> get collections => List.unmodifiable(_collections);

  int countByTier(
    MemoryTier tier, {
    String? sessionId,
    String? scope,
  }) {
    return recordsForTier(
      tier,
      sessionId: sessionId,
      scope: scope,
    ).length;
  }

  List<MemoryRecord> recordsForTier(
    MemoryTier tier, {
    String? sessionId,
    String? scope,
  }) {
    final normalizedScope =
        _normalizeScope(scope) ?? _defaultScopeForTier(tier);
    if (tier == MemoryTier.external) {
      final results = <MemoryRecord>[];
      for (final collection in collectionsByTier(MemoryTier.external)) {
        results.addAll(
          _filterRecords(
            collection.records,
            tier: tier,
            sessionId: sessionId,
            scope: normalizedScope,
          ),
        );
      }
      return results;
    }
    final collection = defaultCollection(tier);
    return _filterRecords(
      collection.records,
      tier: tier,
      sessionId: sessionId,
      scope: normalizedScope,
    );
  }

  MemoryRecord? latestSessionSummary(String sessionId) {
    final trimmed = sessionId.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final collection = defaultCollection(MemoryTier.context);
    for (final record in collection.records) {
      if (record.sessionId == trimmed &&
          record.tags.contains(_sessionSummaryTag)) {
        return record;
      }
    }
    return null;
  }

  Future<void> replaceSessionSummary(
    String sessionId,
    MemoryRecord record,
  ) async {
    final trimmed = sessionId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final collection = defaultCollection(MemoryTier.context);
    final normalizedTags = record.tags.contains(_sessionSummaryTag)
        ? record.tags
        : [...record.tags, _sessionSummaryTag];
    final normalizedRecord = _normalizeRecord(
      record.copyWith(tags: normalizedTags),
      tier: MemoryTier.context,
      sessionId: trimmed,
      scope: record.scope,
    );
    final toRemove = collection.records
        .where(
          (item) =>
              item.sessionId == trimmed &&
              item.tags.contains(_sessionSummaryTag),
        )
        .toList();
    for (final item in toRemove) {
      _recordEmbeddings.remove(item.id);
    }
    collection.records.removeWhere(
      (item) =>
          item.sessionId == trimmed &&
          item.tags.contains(_sessionSummaryTag),
    );

    final embedding = await _embedText(normalizedRecord.content);
    collection.records.insert(0, normalizedRecord);
    if (embedding != null) {
      _recordEmbeddings[normalizedRecord.id] = embedding;
    } else {
      _recordEmbeddings.remove(normalizedRecord.id);
    }
    notifyListeners();

    final db = await _database.database;
    final batch = db.batch();
    for (final item in toRemove) {
      batch.delete(
        _recordsTable,
        where: 'id = ?',
        whereArgs: [item.id],
      );
    }
    batch.insert(
      _recordsTable,
      _recordToRow(
        normalizedRecord,
        collection.id,
        embedding: embedding,
        embeddingModel: embedding == null ? null : _embeddingModel(),
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await batch.commit(noResult: true);
  }

  List<MemoryCollection> collectionsByTier(MemoryTier tier) => _collections
      .where((collection) => collection.tier == tier)
      .toList(growable: false);

  MemoryCollection defaultCollection(MemoryTier tier) =>
      collectionsByTier(tier).first;

  Future<void> load() async {
    final db = await _database.database;
    var collectionRows =
        await db.query(_collectionsTable, orderBy: 'created_at ASC');
    if (collectionRows.isEmpty) {
      await _importLegacy(db);
      collectionRows =
          await db.query(_collectionsTable, orderBy: 'created_at ASC');
    }
    if (collectionRows.isEmpty) {
      final bootstrap = _bootstrapCollections();
      await _insertCollections(db, bootstrap);
      collectionRows =
          await db.query(_collectionsTable, orderBy: 'created_at ASC');
    }

    final recordRows = await db.query(
      _recordsTable,
      orderBy: 'created_at DESC',
    );
    _recordEmbeddings.clear();
    final recordsByCollection = <String, List<MemoryRecord>>{};
    for (final row in recordRows) {
      final record = _normalizeLoadedRecord(_recordFromRow(row));
      final collectionId = row['collection_id'] as String;
      recordsByCollection.putIfAbsent(collectionId, () => []).add(record);
      final embedding = _decodeEmbedding(row['embedding'] as String?);
      if (embedding != null && embedding.isNotEmpty) {
        _recordEmbeddings[record.id] = embedding;
      }
    }

    _collections
      ..clear()
      ..addAll(
        collectionRows.map((row) {
          final id = row['id'] as String;
          return MemoryCollection(
            id: id,
            tier: MemoryTier.values.firstWhere(
              (tier) => tier.key == row['tier'],
              orElse: () => MemoryTier.context,
            ),
            name: row['name'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            locked: _toBool(row['locked']) ?? false,
            records: recordsByCollection[id] ?? [],
          );
        }),
      );
    await _ensureSystemCollections(db);
    notifyListeners();
  }

  Future<void> addRecord({
    required MemoryTier tier,
    required MemoryRecord record,
    String? collectionId,
    String? sessionId,
    String? scope,
  }) async {
    final db = await _database.database;
    final collection = collectionId == null
        ? defaultCollection(tier)
        : _collections.firstWhere((item) => item.id == collectionId);
    final normalizedRecord = _normalizeRecord(
      record,
      tier: tier,
      sessionId: sessionId,
      scope: scope,
    );
    final embedding = await _embedText(normalizedRecord.content);
    collection.records.insert(0, normalizedRecord);
    if (embedding != null) {
      _recordEmbeddings[normalizedRecord.id] = embedding;
    }
    notifyListeners();
    await db.insert(
      _recordsTable,
      _recordToRow(
        normalizedRecord,
        collection.id,
        embedding: embedding,
        embeddingModel: embedding == null ? null : _embeddingModel(),
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateRecord({
    required String collectionId,
    required MemoryRecord record,
    String? sessionId,
    String? scope,
  }) async {
    final db = await _database.database;
    final collection =
        _collections.firstWhere((item) => item.id == collectionId);
    final index = collection.records.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      return;
    }
    final previous = collection.records[index];
    final normalizedRecord = _normalizeRecord(
      record,
      tier: record.tier,
      sessionId: sessionId,
      scope: scope,
    );
    collection.records[index] = normalizedRecord;
    List<double>? embedding;
    if (previous.content != normalizedRecord.content) {
      embedding = await _embedText(normalizedRecord.content);
      if (embedding != null) {
        _recordEmbeddings[normalizedRecord.id] = embedding;
      } else {
        _recordEmbeddings.remove(normalizedRecord.id);
      }
    }
    notifyListeners();
    final storedEmbedding = embedding ?? _recordEmbeddings[normalizedRecord.id];
    await db.update(
      _recordsTable,
      _recordToRow(
        normalizedRecord,
        collectionId,
        embedding: storedEmbedding,
        embeddingModel: storedEmbedding == null ? null : _embeddingModel(),
      ),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<void> removeRecord({
    required String collectionId,
    required String recordId,
  }) async {
    final db = await _database.database;
    final collection =
        _collections.firstWhere((item) => item.id == collectionId);
    collection.records.removeWhere((record) => record.id == recordId);
    _recordEmbeddings.remove(recordId);
    notifyListeners();
    await db.delete(
      _recordsTable,
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  Future<void> addExternalCollection(String name) async {
    final db = await _database.database;
    final collection = MemoryCollection(
      id: _newId(),
      tier: MemoryTier.external,
      name: name,
      createdAt: DateTime.now(),
    );
    _collections.add(collection);
    notifyListeners();
    await db.insert(
      _collectionsTable,
      _collectionToRow(collection),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> renameCollection(String collectionId, String name) async {
    final db = await _database.database;
    final collection =
        _collections.firstWhere((item) => item.id == collectionId);
    if (collection.locked) {
      return;
    }
    collection.name = name;
    notifyListeners();
    await db.update(
      _collectionsTable,
      _collectionToRow(collection),
      where: 'id = ?',
      whereArgs: [collectionId],
    );
  }

  Future<void> removeCollection(String collectionId) async {
    final db = await _database.database;
    final collection =
        _collections.firstWhere((item) => item.id == collectionId);
    if (collection.locked || collection.tier != MemoryTier.external) {
      return;
    }
    for (final record in collection.records) {
      _recordEmbeddings.remove(record.id);
    }
    _collections.removeWhere((item) => item.id == collectionId);
    notifyListeners();
    await db.delete(
      _collectionsTable,
      where: 'id = ?',
      whereArgs: [collectionId],
    );
  }

  Future<void> removeContextForSession(String sessionId) async {
    final trimmed = sessionId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final collection = defaultCollection(MemoryTier.context);
    final toRemove =
        collection.records.where((record) => record.sessionId == trimmed);
    if (toRemove.isEmpty) {
      return;
    }
    for (final record in toRemove) {
      _recordEmbeddings.remove(record.id);
    }
    collection.records.removeWhere(
      (record) => record.sessionId == trimmed,
    );
    notifyListeners();
    final db = await _database.database;
    await db.delete(
      _recordsTable,
      where: 'tier = ? AND session_id = ?',
      whereArgs: [MemoryTier.context.key, trimmed],
    );
  }

  Future<List<MemoryRecord>> searchRelevant(
    String query, {
    int limit = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return [];
    }
    final candidates = _candidateRecords();
    if (candidates.isEmpty) {
      return [];
    }
    final provider = _resolveEmbeddingProvider?.call();
    if (provider == null) {
      return [];
    }
    final queryEmbedding = await _embedText(trimmed);
    if (queryEmbedding == null || queryEmbedding.isEmpty) {
      return _fallbackRecords(candidates, limit);
    }
    await _backfillEmbeddings(candidates);
    final scored = <_ScoredRecord>[];
    for (final record in candidates) {
      final embedding = _recordEmbeddings[record.id];
      if (embedding == null || embedding.isEmpty) {
        continue;
      }
      final score = _cosineSimilarity(queryEmbedding, embedding);
      if (score > 0) {
        scored.add(_ScoredRecord(record, score));
      }
    }
    if (scored.isEmpty) {
      return _fallbackRecords(candidates, limit);
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((entry) => entry.record).toList();
  }

  List<MemoryCollection> _bootstrapCollections() {
    final now = DateTime.now();
    return [
      MemoryCollection(
        id: _newId(),
        tier: MemoryTier.context,
        name: '对话上下文',
        createdAt: now,
        locked: true,
      ),
      MemoryCollection(
        id: _newId(),
        tier: MemoryTier.crossSession,
        name: '跨会话记忆',
        createdAt: now,
        locked: true,
      ),
      MemoryCollection(
        id: _newId(),
        tier: MemoryTier.autonomous,
        name: '自主沉淀',
        createdAt: now,
        locked: true,
      ),
    ];
  }

  Future<void> _ensureSystemCollections(Database db) async {
    var changed = false;
    for (final tier in [
      MemoryTier.context,
      MemoryTier.crossSession,
      MemoryTier.autonomous,
    ]) {
      if (_collections.any((item) => item.tier == tier)) {
        continue;
      }
      final collection = MemoryCollection(
        id: _newId(),
        tier: tier,
        name: tier.label,
        createdAt: DateTime.now(),
        locked: true,
      );
      _collections.add(collection);
      await db.insert(
        _collectionsTable,
        _collectionToRow(collection),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> _insertCollections(
    Database db,
    List<MemoryCollection> collections,
  ) async {
    final batch = db.batch();
    for (final collection in collections) {
      batch.insert(
        _collectionsTable,
        _collectionToRow(collection),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _importLegacy(Database db) async {
    final data = await _legacyStorage.readJsonList(_storageFile);
    if (data == null || data.isEmpty) {
      return;
    }
    List<MemoryCollection> collections;
    if (_isLegacyRecordList(data)) {
      collections = _bootstrapCollections();
      for (final entry in data) {
        final record = MemoryRecord.fromJson(entry as Map<String, dynamic>);
        final collection =
            collections.firstWhere((item) => item.tier == record.tier);
        collection.records.add(record);
      }
    } else {
      collections = data
          .map(
            (entry) => MemoryCollection.fromJson(entry as Map<String, dynamic>),
          )
          .toList();
    }

    await db.transaction((txn) async {
      for (final collection in collections) {
        await txn.insert(
          _collectionsTable,
          _collectionToRow(collection),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        for (final record in collection.records) {
          await txn.insert(
            _recordsTable,
            _recordToRow(record, collection.id),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  bool _isLegacyRecordList(List<dynamic> data) {
    if (data.isEmpty) {
      return false;
    }
    final first = data.first;
    if (first is! Map<String, dynamic>) {
      return false;
    }
    return first.containsKey('content');
  }

  Future<void> _backfillEmbeddings(List<MemoryRecord> records) async {
    final missing = records
        .where((record) => !_recordEmbeddings.containsKey(record.id))
        .take(32)
        .toList();
    if (missing.isEmpty) {
      return;
    }
    final texts = missing.map((record) => record.content).toList();
    final embeddings = await _embedTexts(texts);
    if (embeddings == null || embeddings.length != missing.length) {
      return;
    }
    final db = await _database.database;
    final batch = db.batch();
    final model = _embeddingModel();
    for (var i = 0; i < missing.length; i++) {
      final embedding = embeddings[i];
      _recordEmbeddings[missing[i].id] = embedding;
      batch.update(
        _recordsTable,
        {
          'embedding': _encodeEmbedding(embedding),
          'embedding_model': model,
        },
        where: 'id = ?',
        whereArgs: [missing[i].id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<double>?> _embedText(String text) async {
    final provider = _resolveEmbeddingProvider?.call();
    if (provider == null) {
      return null;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return await _llmClient.embedText(
        provider: provider,
        input: trimmed,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<List<double>>?> _embedTexts(List<String> texts) async {
    final provider = _resolveEmbeddingProvider?.call();
    if (provider == null) {
      return null;
    }
    try {
      return await _llmClient.embedTexts(
        provider: provider,
        inputs: texts,
      );
    } catch (_) {
      return null;
    }
  }

  String? _embeddingModel() {
    final provider = _resolveEmbeddingProvider?.call();
    if (provider == null) {
      return null;
    }
    final embeddingModel = provider.embeddingModel?.trim();
    if (embeddingModel != null && embeddingModel.isNotEmpty) {
      return embeddingModel;
    }
    final model = provider.model.trim();
    return model.isEmpty ? null : model;
  }

  MemoryRecord _normalizeLoadedRecord(MemoryRecord record) {
    final normalizedScope = _normalizeScope(record.scope);
    final scope =
        normalizedScope ?? _defaultScopeForTier(record.tier);
    final sessionId = record.sessionId?.trim();
    final normalizedSessionId =
        record.tier == MemoryTier.context ? sessionId : null;
    if (scope == record.scope && normalizedSessionId == record.sessionId) {
      return record;
    }
    return record.copyWith(
      scope: scope,
      sessionId: normalizedSessionId,
    );
  }

  MemoryRecord _normalizeRecord(
    MemoryRecord record, {
    required MemoryTier tier,
    String? sessionId,
    String? scope,
  }) {
    final normalizedScope = _normalizeScope(scope) ??
        _normalizeScope(record.scope) ??
        _defaultScopeForTier(tier);
    String? normalizedSessionId = record.sessionId?.trim();
    if (tier == MemoryTier.context) {
      final candidate = sessionId?.trim();
      if (candidate != null && candidate.isNotEmpty) {
        normalizedSessionId = candidate;
      }
    } else {
      normalizedSessionId = null;
    }
    return record.copyWith(
      tier: tier,
      scope: normalizedScope,
      sessionId: normalizedSessionId,
    );
  }

  String? _normalizeScope(String? scope) {
    if (scope == null) {
      return null;
    }
    final trimmed = scope.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _defaultScopeForTier(MemoryTier tier) {
    switch (tier) {
      case MemoryTier.external:
        return 'knowledge.docs';
      case MemoryTier.context:
      case MemoryTier.crossSession:
      case MemoryTier.autonomous:
      default:
        return 'brain.user';
    }
  }

  List<MemoryRecord> _filterRecords(
    List<MemoryRecord> records, {
    required MemoryTier tier,
    String? sessionId,
    String? scope,
  }) {
    Iterable<MemoryRecord> filtered = records;
    if (tier == MemoryTier.context) {
      final normalizedSessionId = sessionId?.trim();
      if (normalizedSessionId != null && normalizedSessionId.isNotEmpty) {
        filtered = filtered.where(
          (record) => record.sessionId == normalizedSessionId,
        );
      }
    } else {
      filtered = filtered.where((record) => record.sessionId == null);
    }
    if (scope != null && scope.isNotEmpty) {
      filtered = filtered.where((record) => record.scope == scope);
    }
    return filtered.toList();
  }

  List<MemoryRecord> _candidateRecords() {
    final records = <MemoryRecord>[];
    records.addAll(
      recordsForTier(MemoryTier.crossSession),
    );
    records.addAll(
      recordsForTier(MemoryTier.autonomous),
    );
    records.addAll(
      recordsForTier(MemoryTier.external),
    );
    return records;
  }

  List<MemoryRecord> _fallbackRecords(
    List<MemoryRecord> candidates,
    int limit,
  ) {
    final trimmed = candidates.toList();
    return trimmed.take(limit).toList();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    final length = min(a.length, b.length);
    if (length == 0) {
      return 0;
    }
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < length; i++) {
      final av = a[i];
      final bv = b[i];
      dot += av * bv;
      normA += av * av;
      normB += bv * bv;
    }
    if (normA == 0 || normB == 0) {
      return 0;
    }
    return dot / (sqrt(normA) * sqrt(normB));
  }

  MemoryRecord _recordFromRow(Map<String, Object?> row) {
    final tags = _decodeTags(row['tags'] as String?);
    return MemoryRecord(
      id: row['id'] as String,
      tier: MemoryTier.values.firstWhere(
        (tier) => tier.key == row['tier'],
        orElse: () => MemoryTier.context,
      ),
      content: row['content'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      sourceMessageId: row['source_message_id'] as String?,
      title: row['title'] as String?,
      tags: tags,
      sessionId: row['session_id'] as String?,
      scope: row['scope'] as String?,
    );
  }

  Map<String, Object?> _recordToRow(
    MemoryRecord record,
    String collectionId, {
    List<double>? embedding,
    String? embeddingModel,
  }) {
    return {
      'id': record.id,
      'collection_id': collectionId,
      'tier': record.tier.key,
      'content': record.content,
      'created_at': record.createdAt.toIso8601String(),
      'source_message_id': record.sourceMessageId,
      'title': record.title,
      'tags': _encodeTags(record.tags),
      'embedding': embedding == null ? null : _encodeEmbedding(embedding),
      'embedding_model': embeddingModel,
      'session_id': record.sessionId,
      'scope': record.scope,
    };
  }

  Map<String, Object?> _collectionToRow(MemoryCollection collection) => {
        'id': collection.id,
        'tier': collection.tier.key,
        'name': collection.name,
        'created_at': collection.createdAt.toIso8601String(),
        'locked': collection.locked ? 1 : 0,
      };

  List<double>? _decodeEmbedding(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final data = jsonDecode(raw) as List<dynamic>;
    return data.map((value) => (value as num).toDouble()).toList();
  }

  String _encodeEmbedding(List<double> embedding) {
    return jsonEncode(embedding);
  }

  List<String> _decodeTags(String? raw) {
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final data = jsonDecode(raw) as List<dynamic>;
    return data.map((value) => value.toString()).toList();
  }

  String _encodeTags(List<String> tags) {
    return jsonEncode(tags);
  }

  bool? _toBool(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value != 0;
    }
    if (value is bool) {
      return value;
    }
    return null;
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}

class _ScoredRecord {
  _ScoredRecord(this.record, this.score);

  final MemoryRecord record;
  final double score;
}
