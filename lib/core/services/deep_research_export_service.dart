import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum DeepResearchExportFormat { docx, pdf, pptx, xlsx }

class DeepResearchExportResult {
  const DeepResearchExportResult({
    required this.htmlPath,
    required this.metadataPath,
    required this.targetFormat,
    this.outputPath,
    this.converter,
    this.warnings = const [],
  });

  final String htmlPath;
  final String metadataPath;
  final DeepResearchExportFormat targetFormat;
  final String? outputPath;
  final String? converter;
  final List<String> warnings;

  bool get converted => outputPath != null && outputPath!.isNotEmpty;
}

class DeepResearchExportService {
  const DeepResearchExportService();

  Future<DeepResearchExportResult> exportHtml({
    required String html,
    required Map<String, dynamic> metadata,
    required DeepResearchExportFormat format,
    String filenamePrefix = 'cmyke_deep_research',
  }) async {
    final exportedAt = DateTime.now();
    final baseName =
        '${_sanitizePrefix(filenamePrefix, metadata)}_${exportedAt.millisecondsSinceEpoch}';
    final dir = await _exportsDirectory();

    final htmlPath = await _writeTextFile(
      dir: dir,
      filename: '$baseName.html',
      contents: html,
    );
    final metadataPath = await _writeJsonFile(
      dir: dir,
      filename: '$baseName.metadata.json',
      payload: _buildMetadataPayload(
        metadata,
        format: format,
        exportedAt: exportedAt,
      ),
    );

    final warnings = <String>[];
    String? outputPath;
    String? converter;

    if (format == DeepResearchExportFormat.docx ||
        format == DeepResearchExportFormat.pdf ||
        format == DeepResearchExportFormat.pptx) {
      final pandocAvailable = await _isPandocAvailable();
      if (!pandocAvailable) {
        warnings.add('Pandoc 未检测到，已仅导出 HTML。');
      } else {
        final extension = _formatExtension(format);
        final candidatePath = '${dir.path}/$baseName.$extension';
        final conversion = await _convertWithPandoc(
          inputHtmlPath: htmlPath,
          outputPath: candidatePath,
          format: format,
        );
        outputPath = conversion.outputPath;
        converter = conversion.converter;
        if (conversion.warnings.isNotEmpty) {
          warnings.addAll(conversion.warnings);
        }
        if (outputPath == null || outputPath.isEmpty) {
          if (!warnings.contains('Pandoc 转换失败，已仅导出 HTML。')) {
            warnings.add('Pandoc 转换失败，已仅导出 HTML。');
          }
        }
      }
    } else {
      warnings.add('目标格式 ${format.name} 尚未实现转换（已导出 HTML）。');
    }

    return DeepResearchExportResult(
      htmlPath: htmlPath,
      metadataPath: metadataPath,
      targetFormat: format,
      outputPath: outputPath,
      converter: converter,
      warnings: warnings,
    );
  }

  Map<String, dynamic> _buildMetadataPayload(
    Map<String, dynamic> metadata, {
    required DeepResearchExportFormat format,
    required DateTime exportedAt,
  }) {
    return {
      'exported_at': exportedAt.toIso8601String(),
      'format': format.name,
      'metadata': _normalizeJsonValue(metadata),
    };
  }

  Future<_ConversionResult> _convertWithPandoc({
    required String inputHtmlPath,
    required String outputPath,
    required DeepResearchExportFormat format,
  }) async {
    try {
      final args = [
        '--from=html',
        '--to=${format.name}',
        inputHtmlPath,
        '-o',
        outputPath,
      ];
      final result = await Process.run('pandoc', args, runInShell: true);
      if (result.exitCode == 0) {
        return _ConversionResult(outputPath: outputPath, converter: 'pandoc');
      }
      final error = result.stderr?.toString().trim();
      return _ConversionResult(
        warnings: [
          if (error != null && error.isNotEmpty)
            'Pandoc 转换失败：$error'
          else
            'Pandoc 转换失败。',
        ],
      );
    } on ProcessException catch (error) {
      return _ConversionResult(warnings: ['Pandoc 调用失败：${error.message}']);
    } catch (error) {
      return _ConversionResult(warnings: ['Pandoc 调用异常：$error']);
    }
  }

  Future<bool> _isPandocAvailable() async {
    try {
      final result = await Process.run('pandoc', const [
        '--version',
      ], runInShell: true);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    } catch (_) {
      return false;
    }
  }

  String _formatExtension(DeepResearchExportFormat format) {
    switch (format) {
      case DeepResearchExportFormat.docx:
        return 'docx';
      case DeepResearchExportFormat.pdf:
        return 'pdf';
      case DeepResearchExportFormat.pptx:
        return 'pptx';
      case DeepResearchExportFormat.xlsx:
        return 'xlsx';
    }
  }

  String _sanitizePrefix(String rawPrefix, Map<String, dynamic> metadata) {
    var prefix = rawPrefix.trim();
    if (prefix.isEmpty) {
      final title = metadata['title'];
      if (title is String && title.trim().isNotEmpty) {
        prefix = title.trim();
      }
    }
    if (prefix.isEmpty) {
      prefix = 'cmyke_deep_research';
    }
    prefix = prefix.replaceAll(RegExp(r'[\x00-\x1F<>:"/\\|?*]'), '_');
    prefix = prefix.replaceAll(RegExp(r'\s+'), '_');
    prefix = prefix.replaceAll(RegExp(r'_+'), '_');
    if (prefix.isEmpty) {
      prefix = 'cmyke_deep_research';
    }
    return prefix;
  }

  dynamic _normalizeJsonValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Map) {
      final normalized = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key?.toString() ?? 'key';
        normalized[key] = _normalizeJsonValue(entry.value);
      }
      return normalized;
    }
    if (value is Iterable) {
      return value.map(_normalizeJsonValue).toList();
    }
    return value.toString();
  }

  Future<String> _writeJsonFile({
    required Directory dir,
    required String filename,
    required Map<String, dynamic> payload,
  }) async {
    final file = File('${dir.path}/$filename');
    final encoder = const JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(payload));
    return file.path;
  }

  Future<String> _writeTextFile({
    required Directory dir,
    required String filename,
    required String contents,
  }) async {
    final file = File('${dir.path}/$filename');
    await file.writeAsString(contents);
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

class _ConversionResult {
  const _ConversionResult({
    this.outputPath,
    this.converter,
    this.warnings = const [],
  });

  final String? outputPath;
  final String? converter;
  final List<String> warnings;
}
