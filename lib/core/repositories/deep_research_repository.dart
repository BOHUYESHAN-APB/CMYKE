import 'package:flutter/foundation.dart';

import '../models/deep_research_message.dart';
import '../models/deep_research_session.dart';
import '../services/local_storage.dart';

class DeepResearchRepository extends ChangeNotifier {
  DeepResearchRepository({LocalStorage? storage})
    : _storage = storage ?? LocalStorage();

  static const String _storageFile = 'deep_research_sessions.json';

  final LocalStorage _storage;
  final List<DeepResearchSession> _sessions = [];
  String? _activeSessionId;

  List<DeepResearchSession> get sessions => List.unmodifiable(_sessions);
  String? get activeSessionId => _activeSessionId;

  DeepResearchSession? get activeSession {
    if (_sessions.isEmpty) {
      return null;
    }
    final activeId = _activeSessionId;
    if (activeId == null) {
      return _sessions.first;
    }
    final index = _sessions.indexWhere((session) => session.id == activeId);
    if (index == -1) {
      return _sessions.first;
    }
    return _sessions[index];
  }

  Future<void> load() async {
    final data = await _storage.readJsonList(_storageFile);
    _sessions.clear();
    if (data != null) {
      for (final entry in data) {
        if (entry is Map<String, dynamic>) {
          _sessions.add(DeepResearchSession.fromJson(entry));
        }
      }
    }
    _activeSessionId = _sessions.isEmpty ? null : _sessions.first.id;
    notifyListeners();
  }

  Future<DeepResearchSession> createSession({String? title}) async {
    final now = DateTime.now();
    final session = DeepResearchSession(
      id: _newId(),
      title: title?.trim().isEmpty == false ? title!.trim() : '未命名研究',
      createdAt: now,
      updatedAt: now,
    );
    _sessions.insert(0, session);
    _activeSessionId = session.id;
    notifyListeners();
    await _persist();
    return session;
  }

  Future<void> removeSession(String sessionId) async {
    _sessions.removeWhere((session) => session.id == sessionId);
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isEmpty ? null : _sessions.first.id;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setActive(String sessionId) async {
    if (_activeSessionId == sessionId) return;
    _activeSessionId = sessionId;
    notifyListeners();
    await _persist();
  }

  Future<void> renameSession(String sessionId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final index = _sessions.indexWhere((item) => item.id == sessionId);
    if (index == -1) return;
    final session = _sessions[index];
    session.title = trimmed;
    session.updatedAt = DateTime.now();
    notifyListeners();
    await _persist();
  }

  Future<void> addMessage(DeepResearchMessage message) async {
    final session = activeSession;
    if (session == null) return;
    session.messages.add(message);
    session.updatedAt = DateTime.now();
    notifyListeners();
    await _persist();
  }

  Future<void> clearActiveSession() async {
    _activeSessionId = null;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    await _storage.writeJson(
      _storageFile,
      _sessions.map((session) => session.toJson()).toList(),
    );
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
