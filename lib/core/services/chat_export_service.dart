import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/chat_session.dart';
import '../models/memory_collection.dart';
import '../models/memory_tier.dart';

class ChatExportService {
  Future<String> exportSession(
    ChatSession session, {
    List<MemoryCollection>? memoryCollections,
    String? sessionId,
  }) async {
    final baseName = 'cmyke_session_${session.id}';
    final scopedCollections = _scopeCollectionsForSession(
      memoryCollections,
      sessionId ?? session.id,
    );
    final payload = {
      'exported_at': DateTime.now().toIso8601String(),
      'session': session.toJson(),
      if (scopedCollections != null)
        'memory_collections':
            scopedCollections.map((collection) => collection.toJson()).toList(),
    };
    final jsonPath = await _writeFile(
      filename: '$baseName.json',
      payload: payload,
    );
    await _writeTextFile(
      filename: '$baseName.md',
      contents: _sessionToMarkdown(
        session,
        memoryCollections: scopedCollections,
      ),
    );
    return jsonPath;
  }

  Future<String> exportAll(
    List<ChatSession> sessions, {
    List<MemoryCollection>? memoryCollections,
  }) async {
    final baseName =
        'cmyke_sessions_${DateTime.now().millisecondsSinceEpoch}';
    final payload = {
      'exported_at': DateTime.now().toIso8601String(),
      'sessions': sessions.map((session) => session.toJson()).toList(),
      if (memoryCollections != null)
        'memory_collections':
            memoryCollections.map((collection) => collection.toJson()).toList(),
    };
    final jsonPath = await _writeFile(
      filename: '$baseName.json',
      payload: payload,
    );
    await _writeTextFile(
      filename: '$baseName.md',
      contents: _sessionsToMarkdown(
        sessions,
        memoryCollections: memoryCollections,
      ),
    );
    return jsonPath;
  }

  Future<String> _writeFile({
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

  String _sessionToMarkdown(
    ChatSession session, {
    List<MemoryCollection>? memoryCollections,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('# CMYKE Session Export');
    buffer.writeln('- Session: ${session.title}');
    buffer.writeln('- Session ID: ${session.id}');
    buffer.writeln('- Created: ${session.createdAt.toIso8601String()}');
    buffer.writeln('- Updated: ${session.updatedAt.toIso8601String()}');
    buffer.writeln('');
    buffer.writeln('## Messages');
    for (final message in session.messages) {
      buffer.writeln(
        '### ${message.role.name} · ${message.createdAt.toIso8601String()}',
      );
      buffer.writeln(message.content);
      buffer.writeln('');
    }
    _appendMemoryMarkdown(buffer, memoryCollections);
    return buffer.toString().trimRight();
  }

  String _sessionsToMarkdown(
    List<ChatSession> sessions, {
    List<MemoryCollection>? memoryCollections,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('# CMYKE Sessions Export');
    buffer.writeln('- Exported: ${DateTime.now().toIso8601String()}');
    buffer.writeln('');
    for (final session in sessions) {
      buffer.writeln('## ${session.title}');
      buffer.writeln('- Session ID: ${session.id}');
      buffer.writeln('- Created: ${session.createdAt.toIso8601String()}');
      buffer.writeln('- Updated: ${session.updatedAt.toIso8601String()}');
      buffer.writeln('');
      for (final message in session.messages) {
        buffer.writeln(
          '### ${message.role.name} · ${message.createdAt.toIso8601String()}',
        );
        buffer.writeln(message.content);
        buffer.writeln('');
      }
    }
    _appendMemoryMarkdown(buffer, memoryCollections);
    return buffer.toString().trimRight();
  }

  void _appendMemoryMarkdown(
    StringBuffer buffer,
    List<MemoryCollection>? memoryCollections,
  ) {
    if (memoryCollections == null || memoryCollections.isEmpty) {
      return;
    }
    buffer.writeln('## Memory');
    final sorted = memoryCollections.toList()
      ..sort((a, b) => a.tier.index.compareTo(b.tier.index));
    for (final collection in sorted) {
      buffer.writeln('### ${collection.name} (${collection.tier.label})');
      if (collection.records.isEmpty) {
        buffer.writeln('- (empty)');
        buffer.writeln('');
        continue;
      }
      for (final record in collection.records) {
        final meta = <String>[];
        if (record.scope != null && record.scope!.trim().isNotEmpty) {
          meta.add('scope: ${record.scope}');
        }
        if (record.sessionId != null && record.sessionId!.trim().isNotEmpty) {
          meta.add('session: ${record.sessionId}');
        }
        if (record.sourceMessageId != null &&
            record.sourceMessageId!.trim().isNotEmpty) {
          meta.add('source: ${record.sourceMessageId}');
        }
        final suffix = meta.isEmpty ? '' : ' (${meta.join(', ')})';
        buffer.writeln('- ${record.content}$suffix');
      }
      buffer.writeln('');
    }
  }

  List<MemoryCollection>? _scopeCollectionsForSession(
    List<MemoryCollection>? collections,
    String sessionId,
  ) {
    if (collections == null || collections.isEmpty) {
      return collections;
    }
    final trimmed = sessionId.trim();
    if (trimmed.isEmpty) {
      return collections;
    }
    return collections.map((collection) {
      if (collection.tier != MemoryTier.context) {
        return collection;
      }
      final filtered = collection.records
          .where((record) => record.sessionId == trimmed)
          .toList();
      return MemoryCollection(
        id: collection.id,
        tier: collection.tier,
        name: collection.name,
        createdAt: collection.createdAt,
        locked: collection.locked,
        records: filtered,
      );
    }).toList();
  }

  Future<Directory> _exportsDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/cmyke/exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
