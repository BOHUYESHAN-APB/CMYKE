import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalStorage {
  Future<Directory> _appDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/cmyke');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _file(String filename) async {
    final dir = await _appDirectory();
    return File('${dir.path}/$filename');
  }

  Future<List<dynamic>?> readJsonList(String filename) async {
    final file = await _file(filename);
    if (!await file.exists()) {
      return null;
    }
    final contents = await file.readAsString();
    return jsonDecode(contents) as List<dynamic>;
  }

  Future<Map<String, dynamic>?> readJsonMap(String filename) async {
    final file = await _file(filename);
    if (!await file.exists()) {
      return null;
    }
    final contents = await file.readAsString();
    return jsonDecode(contents) as Map<String, dynamic>;
  }

  Future<void> writeJson(String filename, Object data) async {
    final file = await _file(filename);
    final encoder = const JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(data));
  }
}
