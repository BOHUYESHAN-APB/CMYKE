import 'package:flutter/foundation.dart';

import '../models/memory_collection.dart';
import '../models/memory_record.dart';
import '../models/memory_tier.dart';
import '../services/local_storage.dart';

class MemoryRepository extends ChangeNotifier {
  MemoryRepository({required LocalStorage storage}) : _storage = storage;

  final LocalStorage _storage;
  final List<MemoryCollection> _collections = [];

  static const String _storageFile = 'memory_records.json';

  List<MemoryCollection> get collections => List.unmodifiable(_collections);

  int countByTier(MemoryTier tier) => collectionsByTier(tier)
      .fold<int>(0, (sum, collection) => sum + collection.records.length);

  List<MemoryCollection> collectionsByTier(MemoryTier tier) => _collections
      .where((collection) => collection.tier == tier)
      .toList(growable: false);

  MemoryCollection defaultCollection(MemoryTier tier) =>
      collectionsByTier(tier).first;

  Future<void> load() async {
    final data = await _storage.readJsonList(_storageFile);
    _collections
      ..clear()
      ..addAll(_bootstrapCollections());
    if (data != null) {
      if (_isLegacyRecordList(data)) {
        _hydrateFromLegacy(data);
      } else {
        _collections
          ..clear()
          ..addAll(
            data.map(
              (entry) =>
                  MemoryCollection.fromJson(entry as Map<String, dynamic>),
            ),
          );
        _ensureSystemCollections();
      }
    }
    notifyListeners();
    await _persist();
  }

  Future<void> addRecord({
    required MemoryTier tier,
    required MemoryRecord record,
    String? collectionId,
  }) async {
    final collection = collectionId == null
        ? defaultCollection(tier)
        : _collections.firstWhere((item) => item.id == collectionId);
    collection.records.insert(0, record);
    notifyListeners();
    await _persist();
  }

  Future<void> updateRecord({
    required String collectionId,
    required MemoryRecord record,
  }) async {
    final collection =
        _collections.firstWhere((item) => item.id == collectionId);
    final index = collection.records.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      return;
    }
    collection.records[index] = record;
    notifyListeners();
    await _persist();
  }

  Future<void> removeRecord({
    required String collectionId,
    required String recordId,
  }) async {
    final collection =
        _collections.firstWhere((item) => item.id == collectionId);
    collection.records.removeWhere((record) => record.id == recordId);
    notifyListeners();
    await _persist();
  }

  Future<void> addExternalCollection(String name) async {
    _collections.add(
      MemoryCollection(
        id: _newId(),
        tier: MemoryTier.external,
        name: name,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> renameCollection(String collectionId, String name) async {
    final collection =
        _collections.firstWhere((item) => item.id == collectionId);
    if (collection.locked) {
      return;
    }
    collection.name = name;
    notifyListeners();
    await _persist();
  }

  Future<void> removeCollection(String collectionId) async {
    final collection =
        _collections.firstWhere((item) => item.id == collectionId);
    if (collection.locked || collection.tier != MemoryTier.external) {
      return;
    }
    _collections.removeWhere((item) => item.id == collectionId);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    await _storage.writeJson(
      _storageFile,
      _collections.map((collection) => collection.toJson()).toList(),
    );
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

  void _ensureSystemCollections() {
    for (final tier in [
      MemoryTier.context,
      MemoryTier.crossSession,
      MemoryTier.autonomous,
    ]) {
      if (_collections.any((item) => item.tier == tier)) {
        continue;
      }
      _collections.add(
        MemoryCollection(
          id: _newId(),
          tier: tier,
          name: tier.label,
          createdAt: DateTime.now(),
          locked: true,
        ),
      );
    }
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

  void _hydrateFromLegacy(List<dynamic> data) {
    _collections
      ..clear()
      ..addAll(_bootstrapCollections());
    for (final entry in data) {
      final record = MemoryRecord.fromJson(entry as Map<String, dynamic>);
      final collection = defaultCollection(record.tier);
      collection.records.add(record);
    }
    _ensureSystemCollections();
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
