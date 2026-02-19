import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import 'workspace_service.dart';

enum DraftFormat { markdown, text }

class DraftResult {
  DraftResult({
    required this.directory,
    required this.draftFile,
    required this.manifestFile,
    required this.platform,
    required this.format,
  });

  final Directory directory;
  final File draftFile;
  final File manifestFile;
  final AutonomyPlatform platform;
  final DraftFormat format;
}

class DraftService {
  DraftService({required WorkspaceService workspaceService})
    : _workspaceService = workspaceService;

  final WorkspaceService _workspaceService;

  DraftFormat resolveFormat({
    required DraftFormatStrategy strategy,
    required AutonomyPlatform platform,
  }) {
    switch (strategy) {
      case DraftFormatStrategy.markdown:
        return DraftFormat.markdown;
      case DraftFormatStrategy.text:
        return DraftFormat.text;
      case DraftFormatStrategy.platformDefault:
        switch (platform) {
          case AutonomyPlatform.x:
            return DraftFormat.text;
          case AutonomyPlatform.xiaohongshu:
          case AutonomyPlatform.bilibili:
          case AutonomyPlatform.wechat:
            return DraftFormat.markdown;
        }
    }
  }

  Future<DraftResult> createDraft({
    required String sessionId,
    required AutonomyPlatform platform,
    required DraftFormat format,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    final draftsRoot = await _workspaceService.draftsRoot(sessionId);
    final dateKey = _dateKey(DateTime.now());
    final draftId = DateTime.now().millisecondsSinceEpoch.toString();
    final dir = Directory(
      p.join(draftsRoot.path, platform.name, dateKey, draftId),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final draftFile = File(
      p.join(dir.path, format == DraftFormat.markdown ? 'draft.md' : 'draft.txt'),
    );
    await draftFile.writeAsString(content.trimRight());
    final manifestFile = File(p.join(dir.path, 'manifest.json'));
    final manifest = <String, dynamic>{
      'platform': platform.name,
      'session_id': sessionId,
      'draft_id': draftId,
      'created_at': DateTime.now().toIso8601String(),
      'format': format == DraftFormat.markdown ? 'markdown' : 'text',
      'draft_file': p.basename(draftFile.path),
      'assets': <String>[],
      if (metadata != null) 'metadata': metadata,
    };
    const encoder = JsonEncoder.withIndent('  ');
    await manifestFile.writeAsString(encoder.convert(manifest));
    return DraftResult(
      directory: dir,
      draftFile: draftFile,
      manifestFile: manifestFile,
      platform: platform,
      format: format,
    );
  }

  String _dateKey(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
