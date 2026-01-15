import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../services/local_database.dart';
import '../services/local_storage.dart';

class ChatRepository extends ChangeNotifier {
  ChatRepository({
    required LocalDatabase database,
    LocalStorage? legacyStorage,
  })  : _database = database,
        _legacyStorage = legacyStorage ?? LocalStorage();

  final LocalDatabase _database;
  final LocalStorage _legacyStorage;
  final List<ChatSession> _sessions = [];
  String? _activeSessionId;

  static const String _storageFile = 'chat_sessions.json';
  static const String _sessionsTable = 'chat_sessions';
  static const String _messagesTable = 'chat_messages';

  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  String? get activeSessionId => _activeSessionId;

  ChatSession? get activeSession => _sessions.firstWhere(
        (session) => session.id == _activeSessionId,
        orElse: () => _sessions.isEmpty ? _createDefaultSession() : _sessions[0],
      );

  Future<void> load() async {
    final db = await _database.database;
    var sessionRows = await db.query(
      _sessionsTable,
      orderBy: 'updated_at DESC',
    );
    if (sessionRows.isEmpty) {
      await _importLegacy(db);
      sessionRows = await db.query(
        _sessionsTable,
        orderBy: 'updated_at DESC',
      );
    }
    if (sessionRows.isEmpty) {
      final session = _createDefaultSession();
      _sessions
        ..clear()
        ..add(session);
      _activeSessionId = session.id;
      await _insertSession(db, session);
      await _insertMessages(db, session);
      notifyListeners();
      return;
    }

    final messageRows = await db.query(
      _messagesTable,
      orderBy: 'created_at ASC',
    );
    final messagesBySession = <String, List<ChatMessage>>{};
    for (final row in messageRows) {
      final sessionId = row['session_id'] as String;
      messagesBySession.putIfAbsent(sessionId, () => []).add(
            ChatMessage(
              id: row['id'] as String,
              role: ChatRole.values.firstWhere(
                (role) => role.name == row['role'],
                orElse: () => ChatRole.assistant,
              ),
              content: row['content'] as String,
              createdAt: DateTime.parse(row['created_at'] as String),
            ),
          );
    }

    _sessions
      ..clear()
      ..addAll(
        sessionRows.map(
          (row) => ChatSession(
            id: row['id'] as String,
            title: row['title'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
            mode: _parseMode(row['mode']),
            messages: messagesBySession[row['id'] as String] ?? [],
          ),
        ),
      );
    _activeSessionId = _sessions.first.id;
    notifyListeners();
  }

  Future<ChatSession> createSession({
    String? title,
    ChatSessionMode mode = ChatSessionMode.standard,
    bool setActive = true,
  }) async {
    final db = await _database.database;
    final session = ChatSession(
      id: _newId(),
      title: title ?? 'New chat',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      mode: mode,
    );
    _sessions.insert(0, session);
    if (setActive) {
      _activeSessionId = session.id;
    }
    notifyListeners();
    await _insertSession(db, session);
    return session;
  }

  Future<void> removeSession(String sessionId) async {
    final db = await _database.database;
    _sessions.removeWhere((session) => session.id == sessionId);
    await db.delete(
      _sessionsTable,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    if (_sessions.isEmpty) {
      final session = _createDefaultSession();
      _sessions.add(session);
      await _insertSession(db, session);
      await _insertMessages(db, session);
    }
    _activeSessionId = _sessions.first.id;
    notifyListeners();
  }

  Future<void> setActive(String sessionId) async {
    _activeSessionId = sessionId;
    notifyListeners();
  }

  Future<void> sendUserMessage(String content) async {
    final message = ChatMessage(
      id: _newId(),
      role: ChatRole.user,
      content: content,
      createdAt: DateTime.now(),
    );
    await addMessage(message);
  }

  Future<void> addAssistantMessage(String content,
      {bool persist = true}) async {
    final message = ChatMessage(
      id: _newId(),
      role: ChatRole.assistant,
      content: content,
      createdAt: DateTime.now(),
    );
    await addMessage(message, persist: persist);
  }

  Future<void> addMessage(ChatMessage message, {bool persist = true}) async {
    final session = activeSession;
    if (session == null) {
      return;
    }
    final db = await _database.database;
    session.messages.add(message);
    session.updatedAt = DateTime.now();
    if (session.title == 'New chat' &&
        session.messages.length == 1 &&
        message.role == ChatRole.user) {
      session.title = _deriveTitle(message.content);
    }
    notifyListeners();
    if (persist) {
      await db.transaction((txn) async {
        await txn.insert(_messagesTable, _messageToRow(message, session.id));
        await txn.update(
          _sessionsTable,
          _sessionToRow(session),
          where: 'id = ?',
          whereArgs: [session.id],
        );
      });
      await _archiveSession(session);
    }
  }

  Future<void> updateMessageContent(
    String messageId,
    String content, {
    bool persist = false,
  }) async {
    final session = activeSession;
    if (session == null) {
      return;
    }
    final index =
        session.messages.indexWhere((message) => message.id == messageId);
    if (index == -1) {
      return;
    }
    session.messages[index] = ChatMessage(
      id: session.messages[index].id,
      role: session.messages[index].role,
      content: content,
      createdAt: session.messages[index].createdAt,
    );
    session.updatedAt = DateTime.now();
    notifyListeners();
    if (persist) {
      final db = await _database.database;
      await db.transaction((txn) async {
        final updated = await txn.update(
          _messagesTable,
          {'content': content},
          where: 'id = ?',
          whereArgs: [messageId],
        );
        if (updated == 0) {
          final message = session.messages[index];
          await txn.insert(
            _messagesTable,
            _messageToRow(message, session.id),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await txn.update(
          _sessionsTable,
          _sessionToRow(session),
          where: 'id = ?',
          whereArgs: [session.id],
        );
      });
      await _archiveSession(session);
    }
  }

  String _deriveTitle(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return 'New chat';
    }
    return trimmed.length <= 20 ? trimmed : '${trimmed.substring(0, 20)}...';
  }

  ChatSession _createDefaultSession() {
    return ChatSession(
      id: _newId(),
      title: 'New chat',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      mode: ChatSessionMode.standard,
      messages: [
        ChatMessage(
          id: _newId(),
          role: ChatRole.assistant,
          content: '你好，我是 Lumi（露米）。现在是 UI 原型阶段，模型接入后会在这里回复。',
          createdAt: DateTime.now(),
        ),
      ],
    );
  }

  Future<void> _insertSession(Database db, ChatSession session) async {
    await db.insert(
      _sessionsTable,
      _sessionToRow(session),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _insertMessages(Database db, ChatSession session) async {
    final batch = db.batch();
    for (final message in session.messages) {
      batch.insert(
        _messagesTable,
        _messageToRow(message, session.id),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _archiveSession(ChatSession session) async {
    try {
      final dir = await _archiveDirectory();
      final baseName = 'session_${session.id}';
      final jsonFile = File(p.join(dir.path, '$baseName.json'));
      final mdFile = File(p.join(dir.path, '$baseName.md'));
      final payload = {
        'saved_at': DateTime.now().toIso8601String(),
        'session': session.toJson(),
      };
      final encoder = const JsonEncoder.withIndent('  ');
      await jsonFile.writeAsString(encoder.convert(payload));
      await mdFile.writeAsString(_sessionToMarkdown(session));
    } catch (_) {
      // Ignore archive failures to avoid blocking chat flow.
    }
  }

  Future<Directory> _archiveDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'cmyke', 'conversations'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _sessionToMarkdown(ChatSession session) {
    final buffer = StringBuffer();
    buffer.writeln('# CMYKE Session');
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
    return buffer.toString().trimRight();
  }

  Map<String, Object?> _sessionToRow(ChatSession session) => {
        'id': session.id,
        'title': session.title,
        'created_at': session.createdAt.toIso8601String(),
        'updated_at': session.updatedAt.toIso8601String(),
        'mode': session.mode.name,
      };

  Map<String, Object?> _messageToRow(ChatMessage message, String sessionId) => {
        'id': message.id,
        'session_id': sessionId,
        'role': message.role.name,
        'content': message.content,
        'created_at': message.createdAt.toIso8601String(),
      };

  Future<void> _importLegacy(Database db) async {
    final data = await _legacyStorage.readJsonList(_storageFile);
    if (data == null || data.isEmpty) {
      return;
    }
    final sessions = data
        .map((entry) => ChatSession.fromJson(entry as Map<String, dynamic>))
        .toList();
    await db.transaction((txn) async {
      for (final session in sessions) {
        await txn.insert(
          _sessionsTable,
          _sessionToRow(session),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        for (final message in session.messages) {
          await txn.insert(
            _messagesTable,
            _messageToRow(message, session.id),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  ChatSessionMode _parseMode(Object? value) {
    if (value is String) {
      return ChatSessionMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => ChatSessionMode.standard,
      );
    }
    return ChatSessionMode.standard;
  }
}
