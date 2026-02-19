import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../models/chat_attachment.dart';
import 'media_library_service.dart';
import 'workspace_service.dart';

class IngestFileInput {
  const IngestFileInput({required this.fileName, this.path, this.bytes});

  final String fileName;
  final String? path;
  final Uint8List? bytes;
}

class AttachmentIngestService {
  AttachmentIngestService({
    required WorkspaceService workspaceService,
    MediaLibraryService? mediaLibraryService,
  }) : _workspaceService = workspaceService,
       _mediaLibraryService = mediaLibraryService ?? MediaLibraryService();

  final WorkspaceService _workspaceService;
  final MediaLibraryService _mediaLibraryService;

  Future<List<ChatAttachment>> ingestToLibraryAndWorkspace({
    required String sessionId,
    required List<IngestFileInput> inputs,
  }) async {
    if (inputs.isEmpty) {
      return const [];
    }
    final sessionInputs = await _workspaceService.inputsDirectory(sessionId);
    final sessionUserDir = Directory(p.join(sessionInputs.path, 'user_uploads'));
    if (!await sessionUserDir.exists()) {
      await sessionUserDir.create(recursive: true);
    }

    final out = <ChatAttachment>[];
    for (final input in inputs) {
      final fileBytes = await _readBytes(input);
      if (fileBytes.isEmpty) {
        continue;
      }
      final sha256 = crypto.sha256.convert(fileBytes).toString();
      final mimeType =
          lookupMimeType(input.fileName, headerBytes: fileBytes) ??
          _guessMimeByExtension(input.fileName) ??
          'application/octet-stream';
      final kind = mimeType.startsWith('image/')
          ? ChatAttachmentKind.image
          : ChatAttachmentKind.file;
      final ext = _bestExtension(input.fileName, mimeType);
      final id = DateTime.now().microsecondsSinceEpoch.toString();

      final libraryDir = kind == ChatAttachmentKind.image
          ? await _mediaLibraryService.imagesDirectory()
          : await _mediaLibraryService.filesDirectory();
      final libraryName = '${id}_${sha256.substring(0, 12)}.$ext';
      final libraryPath = p.join(libraryDir.path, libraryName);
      await File(libraryPath).writeAsBytes(fileBytes, flush: true);

      final sessionName = _sanitizeFilename(input.fileName);
      final sessionPath = p.join(sessionUserDir.path, '${id}_$sessionName');
      try {
        await File(sessionPath).writeAsBytes(fileBytes, flush: true);
      } catch (_) {
        // Best-effort: the workspace copy is for traceability only.
      }

      int? width;
      int? height;
      if (kind == ChatAttachmentKind.image) {
        final decoded = img.decodeImage(fileBytes);
        if (decoded != null) {
          width = decoded.width;
          height = decoded.height;
        }
      }

      out.add(
        ChatAttachment(
          id: id,
          kind: kind,
          localPath: libraryPath,
          fileName: input.fileName,
          createdAt: DateTime.now(),
          mimeType: mimeType,
          bytes: fileBytes.length,
          width: width,
          height: height,
          sha256: sha256,
        ),
      );
    }
    return out;
  }

  Future<Uint8List> _readBytes(IngestFileInput input) async {
    final bytes = input.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return bytes;
    }
    final path = input.path;
    if (path == null || path.trim().isEmpty) {
      return Uint8List(0);
    }
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return Uint8List(0);
    }
  }

  String _bestExtension(String fileName, String mimeType) {
    final ext = p.extension(fileName).replaceFirst('.', '').trim();
    if (ext.isNotEmpty && ext.length <= 8) {
      return ext.toLowerCase();
    }
    if (mimeType == 'image/jpeg') return 'jpg';
    if (mimeType == 'image/png') return 'png';
    if (mimeType == 'image/webp') return 'webp';
    if (mimeType == 'image/gif') return 'gif';
    if (mimeType == 'application/pdf') return 'pdf';
    if (mimeType.startsWith('text/')) return 'txt';
    return 'bin';
  }

  String? _guessMimeByExtension(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.pdf':
        return 'application/pdf';
      case '.txt':
      case '.md':
        return 'text/plain';
    }
    return null;
  }

  String _sanitizeFilename(String name) {
    var trimmed = name.trim();
    if (trimmed.isEmpty) {
      trimmed = 'file';
    }
    trimmed = trimmed.replaceAll(RegExp(r'[\x00-\x1F<>:"/\\|?*]'), '_');
    trimmed = trimmed.replaceAll(RegExp(r'\s+'), '_');
    trimmed = trimmed.replaceAll(RegExp(r'_+'), '_');
    if (trimmed.isEmpty) {
      trimmed = 'file';
    }
    return trimmed;
  }
}
