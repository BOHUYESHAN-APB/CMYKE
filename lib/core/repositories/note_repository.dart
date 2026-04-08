import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/note.dart';
import '../services/local_database.dart';

class NoteRepository extends ChangeNotifier {
  NoteRepository({required LocalDatabase database}) : _database = database;

  final LocalDatabase _database;
  final List<Note> _notes = [];

  static const String _table = 'notes';

  List<Note> get notes => List.unmodifiable(_notes);

  Future<void> load() async {
    final db = await _database.database;
    final rows = await db.query(_table, orderBy: 'updated_at DESC');
    _notes
      ..clear()
      ..addAll(rows.map(_noteFromRow));
    notifyListeners();
  }

  Future<Note> saveNote({
    String? id,
    required String title,
    required String content,
    String type = 'text',
    String category = 'default',
    String? memoryTier,
    String? memoryRecordId,
    DateTime? memorySyncedAt,
  }) async {
    final now = DateTime.now();
    final existing = id == null
        ? null
        : _notes.where((item) => item.id == id).cast<Note?>().firstOrNull;
    final normalizedTitle = title.trim().isEmpty
        ? _deriveTitle(content)
        : title.trim();
    final note = Note(
      id: existing?.id ?? _newId(),
      title: normalizedTitle,
      content: content.trim(),
      summary: _buildSummary(content),
      type: type,
      category: category,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      memoryTier: memoryTier ?? existing?.memoryTier,
      memoryRecordId: memoryRecordId ?? existing?.memoryRecordId,
      memorySyncedAt: memorySyncedAt ?? existing?.memorySyncedAt,
    );
    final db = await _database.database;
    await db.insert(
      _table,
      _noteToRow(note),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final index = _notes.indexWhere((item) => item.id == note.id);
    if (index == -1) {
      _notes.insert(0, note);
    } else {
      _notes[index] = note;
      _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    notifyListeners();
    return note;
  }

  Future<void> deleteNote(String id) async {
    final db = await _database.database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _notes.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  Note? getById(String id) {
    for (final note in _notes) {
      if (note.id == id) {
        return note;
      }
    }
    return null;
  }

  Future<Note?> updateMemoryLink({
    required String noteId,
    required String memoryTier,
    required String memoryRecordId,
    DateTime? syncedAt,
  }) async {
    final note = getById(noteId);
    if (note == null) {
      return null;
    }
    final updated = note.copyWith(
      memoryTier: memoryTier,
      memoryRecordId: memoryRecordId,
      memorySyncedAt: syncedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _persistNote(updated);
    return updated;
  }

  Future<Note?> clearMemoryLink(String noteId) async {
    final note = getById(noteId);
    if (note == null) {
      return null;
    }
    final updated = note.copyWith(
      updatedAt: DateTime.now(),
      clearMemoryLink: true,
    );
    await _persistNote(updated);
    return updated;
  }

  Note _noteFromRow(Map<String, Object?> row) {
    return Note(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      content: row['content'] as String? ?? '',
      summary: row['summary'] as String? ?? '',
      type: row['type'] as String? ?? 'text',
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      category: row['category'] as String? ?? 'default',
      memoryTier: row['memory_tier'] as String?,
      memoryRecordId: row['memory_record_id'] as String?,
      memorySyncedAt: (row['memory_synced_at'] as String?) == null
          ? null
          : DateTime.parse(row['memory_synced_at'] as String),
    );
  }

  Map<String, Object?> _noteToRow(Note note) => {
    'id': note.id,
    'title': note.title,
    'content': note.content,
    'summary': note.summary,
    'type': note.type,
    'created_at': note.createdAt.toIso8601String(),
    'updated_at': note.updatedAt.toIso8601String(),
    'category': note.category,
    'memory_tier': note.memoryTier,
    'memory_record_id': note.memoryRecordId,
    'memory_synced_at': note.memorySyncedAt?.toIso8601String(),
  };

  Future<void> _persistNote(Note note) async {
    final db = await _database.database;
    await db.insert(
      _table,
      _noteToRow(note),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final index = _notes.indexWhere((item) => item.id == note.id);
    if (index == -1) {
      _notes.insert(0, note);
    } else {
      _notes[index] = note;
      _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    notifyListeners();
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _deriveTitle(String content) {
    final compact = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '未命名笔记');
    return compact.length <= 28 ? compact : '${compact.substring(0, 28)}...';
  }

  String _buildSummary(String content) {
    final compact = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) {
      return '';
    }
    return compact.length <= 96 ? compact : '${compact.substring(0, 96)}...';
  }
}
