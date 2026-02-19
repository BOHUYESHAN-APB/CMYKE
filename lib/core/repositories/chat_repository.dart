import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/chat_message.dart';
import '../models/chat_attachment.dart';
import '../models/chat_session.dart';
import '../services/local_database.dart';
import '../services/local_storage.dart';
import '../services/workspace_service.dart';

class ChatRepository extends ChangeNotifier {
  ChatRepository({
    required LocalDatabase database,
    LocalStorage? legacyStorage,
    WorkspaceService? workspaceService,
  }) : _database = database,
       _legacyStorage = legacyStorage ?? LocalStorage(),
       _workspaceService = workspaceService;

  final LocalDatabase _database;
  final LocalStorage _legacyStorage;
  final WorkspaceService? _workspaceService;
  final List<ChatSession> _sessions = [];
  String? _activeSessionId;

  static const String _storageFile = 'chat_sessions.json';
  static const String _sessionsTable = 'chat_sessions';
  static const String _messagesTable = 'chat_messages';
  static const String _attachmentsTable = 'chat_attachments';

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
      sessionRows = await db.query(_sessionsTable, orderBy: 'updated_at DESC');
    }
    if (sessionRows.isEmpty) {
      final session = _createDefaultSession();
      _sessions
        ..clear()
        ..add(session);
      _activeSessionId = session.id;
      await _insertSession(db, session);
      await _insertMessages(db, session);
      await _workspaceService?.sessionDirectory(session.id);
      notifyListeners();
      return;
    }

    final messageRows = await db.query(
      _messagesTable,
      orderBy: 'created_at ASC',
    );
    final attachmentRows = await db.query(
      _attachmentsTable,
      orderBy: 'created_at ASC',
    );
    final attachmentsByMessage = <String, List<ChatAttachment>>{};
    for (final row in attachmentRows) {
      final messageId = row['message_id'] as String;
      final tagsRaw = row['tags'] as String?;
      final tags = tagsRaw == null || tagsRaw.trim().isEmpty
          ? const <String>[]
          : tagsRaw
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList(growable: false);
      final kindRaw = (row['kind'] as String?)?.trim() ?? 'file';
      final kind = ChatAttachmentKind.values.firstWhere(
        (k) => k.name == kindRaw,
        orElse: () => ChatAttachmentKind.file,
      );
      final attachment = ChatAttachment(
        id: row['id'] as String,
        kind: kind,
        localPath: row['local_path'] as String? ?? '',
        fileName: row['file_name'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at'] as String),
        mimeType: row['mime_type'] as String?,
        bytes: (row['bytes'] as num?)?.toInt(),
        width: (row['width'] as num?)?.toInt(),
        height: (row['height'] as num?)?.toInt(),
        sha256: row['sha256'] as String?,
        caption: row['caption'] as String?,
        tags: tags,
      );
      attachmentsByMessage
          .putIfAbsent(messageId, () => [])
          .add(attachment);
    }
    final messagesBySession = <String, List<ChatMessage>>{};
    for (final row in messageRows) {
      final sessionId = row['session_id'] as String;
      final messageId = row['id'] as String;
      messagesBySession
          .putIfAbsent(sessionId, () => [])
          .add(
            ChatMessage(
              id: messageId,
              role: ChatRole.values.firstWhere(
                (role) => role.name == row['role'],
                orElse: () => ChatRole.assistant,
              ),
              content: row['content'] as String,
              createdAt: DateTime.parse(row['created_at'] as String),
              sourceKind: _parseSourceKind(row['source_kind']),
              sourceId: row['source_id'] as String?,
              priority: _parsePriority(row['priority']),
              attachments: attachmentsByMessage[messageId] ?? const [],
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
    await _workspaceService?.sessionDirectory(session.id);
    return session;
  }

  Future<void> removeSession(String sessionId) async {
    final db = await _database.database;
    _sessions.removeWhere((session) => session.id == sessionId);
    await db.delete(_sessionsTable, where: 'id = ?', whereArgs: [sessionId]);
    await _workspaceService?.deleteSessionWorkspace(sessionId);
    if (_sessions.isEmpty) {
      final session = _createDefaultSession();
      _sessions.add(session);
      await _insertSession(db, session);
      await _insertMessages(db, session);
      await _workspaceService?.sessionDirectory(session.id);
    }
    _activeSessionId = _sessions.first.id;
    notifyListeners();
  }

  Future<void> setActive(String sessionId) async {
    _activeSessionId = sessionId;
    notifyListeners();
  }

  Future<void> sendUserMessage(
    String content, {
    ChatSourceKind? sourceKind,
    String? sourceId,
    ChatPriority priority = ChatPriority.user,
    List<ChatAttachment> attachments = const [],
  }) async {
    final message = ChatMessage(
      id: _newId(),
      role: ChatRole.user,
      content: content,
      createdAt: DateTime.now(),
      sourceKind: sourceKind ?? ChatSourceKind.user,
      sourceId: sourceId,
      priority: priority,
      attachments: attachments,
    );
    await addMessage(message);
  }

  Future<void> addAssistantMessage(
    String content, {
    bool persist = true,
    ChatSourceKind? sourceKind,
    ChatPriority priority = ChatPriority.normal,
  }) async {
    final message = ChatMessage(
      id: _newId(),
      role: ChatRole.assistant,
      content: content,
      createdAt: DateTime.now(),
      sourceKind: sourceKind,
      priority: priority,
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
        if (message.attachments.isNotEmpty) {
          for (final attachment in message.attachments) {
            await txn.insert(
              _attachmentsTable,
              _attachmentToRow(attachment, message.id),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
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

  Map<String, Object?> _attachmentToRow(
    ChatAttachment attachment,
    String messageId,
  ) {
    return {
      'id': attachment.id,
      'message_id': messageId,
      'kind': attachment.kind.name,
      'local_path': attachment.localPath,
      'file_name': attachment.fileName,
      'created_at': attachment.createdAt.toIso8601String(),
      'mime_type': attachment.mimeType,
      'bytes': attachment.bytes,
      'width': attachment.width,
      'height': attachment.height,
      'sha256': attachment.sha256,
      'caption': attachment.caption,
      'tags': attachment.tags.join(','),
    };
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
    final index = session.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index == -1) {
      return;
    }
    session.messages[index] = ChatMessage(
      id: session.messages[index].id,
      role: session.messages[index].role,
      content: content,
      createdAt: session.messages[index].createdAt,
      sourceKind: session.messages[index].sourceKind,
      sourceId: session.messages[index].sourceId,
      priority: session.messages[index].priority,
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
          sourceKind: ChatSourceKind.system,
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
      final source =
          message.sourceKind == null ? '' : ' · ${message.sourceKind!.name}';
      buffer.writeln(
        '### ${message.role.name}$source · ${message.createdAt.toIso8601String()}',
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
    'source_kind': message.sourceKind?.name,
    'source_id': message.sourceId,
    'priority': message.priority.name,
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

  ChatSourceKind? _parseSourceKind(Object? value) {
    if (value is String) {
      for (final kind in ChatSourceKind.values) {
        if (kind.name == value) return kind;
      }
    }
    return null;
  }

  ChatPriority _parsePriority(Object? value) {
    if (value is String) {
      for (final priority in ChatPriority.values) {
        if (priority.name == value) return priority;
      }
    }
    return ChatPriority.normal;
  }

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
