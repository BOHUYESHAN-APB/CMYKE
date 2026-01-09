import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../services/local_storage.dart';

class ChatRepository extends ChangeNotifier {
  ChatRepository({required LocalStorage storage}) : _storage = storage;

  final LocalStorage _storage;
  final List<ChatSession> _sessions = [];
  String? _activeSessionId;

  static const String _storageFile = 'chat_sessions.json';

  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  String? get activeSessionId => _activeSessionId;

  ChatSession? get activeSession => _sessions.firstWhere(
        (session) => session.id == _activeSessionId,
        orElse: () => _sessions.isEmpty ? _createDefaultSession() : _sessions[0],
      );

  Future<void> load() async {
    final data = await _storage.readJsonList(_storageFile);
    if (data == null) {
      _sessions.add(_createDefaultSession());
      _activeSessionId = _sessions.first.id;
      await _persist();
      return;
    }
    _sessions
      ..clear()
      ..addAll(
        data.map((entry) => ChatSession.fromJson(entry as Map<String, dynamic>)),
      );
    if (_sessions.isEmpty) {
      _sessions.add(_createDefaultSession());
    }
    _activeSessionId = _sessions.first.id;
    notifyListeners();
  }

  Future<void> createSession({String? title}) async {
    final session = ChatSession(
      id: _newId(),
      title: title ?? 'New chat',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _sessions.insert(0, session);
    _activeSessionId = session.id;
    notifyListeners();
    await _persist();
  }

  Future<void> removeSession(String sessionId) async {
    _sessions.removeWhere((session) => session.id == sessionId);
    if (_sessions.isEmpty) {
      _sessions.add(_createDefaultSession());
    }
    _activeSessionId = _sessions.first.id;
    notifyListeners();
    await _persist();
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
    session.messages.add(message);
    session.updatedAt = DateTime.now();
    if (session.title == 'New chat' &&
        session.messages.length == 1 &&
        message.role == ChatRole.user) {
      session.title = _deriveTitle(message.content);
    }
    notifyListeners();
    if (persist) {
      await _persist();
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
      await _persist();
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
      messages: [
        ChatMessage(
          id: _newId(),
          role: ChatRole.assistant,
          content: '你好，我是 CMYKE。现在是 UI 原型阶段，模型接入后会在这里回复。',
          createdAt: DateTime.now(),
        ),
      ],
    );
  }

  Future<void> _persist() async {
    await _storage.writeJson(
      _storageFile,
      _sessions.map((session) => session.toJson()).toList(),
    );
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
