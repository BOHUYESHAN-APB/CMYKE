import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/chat_session.dart';

class ChatExportService {
  Future<String> exportSession(ChatSession session) async {
    final payload = {
      'exported_at': DateTime.now().toIso8601String(),
      'session': session.toJson(),
    };
    return _writeFile(
      filename: 'cmyke_session_${session.id}.json',
      payload: payload,
    );
  }

  Future<String> exportAll(List<ChatSession> sessions) async {
    final payload = {
      'exported_at': DateTime.now().toIso8601String(),
      'sessions': sessions.map((session) => session.toJson()).toList(),
    };
    return _writeFile(
      filename: 'cmyke_sessions_${DateTime.now().millisecondsSinceEpoch}.json',
      payload: payload,
    );
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

  Future<Directory> _exportsDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/cmyke/exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
