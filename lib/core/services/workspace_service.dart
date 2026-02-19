import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class WorkspaceService {
  Future<Directory> rootDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'cmyke', 'workspace'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> sessionDirectory(String sessionId) async {
    final root = await rootDirectory();
    final dir = Directory(p.join(root.path, sessionId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> draftsRoot(String sessionId) async {
    final sessionDir = await sessionDirectory(sessionId);
    final dir = Directory(p.join(sessionDir.path, 'drafts'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> deleteSessionWorkspace(String sessionId) async {
    final root = await rootDirectory();
    final dir = Directory(p.join(root.path, sessionId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
