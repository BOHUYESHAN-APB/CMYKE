import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'speech_provider.dart';

/// Remote STT provider using OpenAI-compatible API.
class RemoteSttProvider extends SttProvider {
  RemoteSttProvider(super.config);

  @override
  Future<String> transcribe({
    required File audioFile,
    String? language,
  }) async {
    final uri = _buildTranscriptionUri(config.baseUrl);
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers())
      ..fields['model'] = config.model
      ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));
    
    if (language != null && language.isNotEmpty) {
      request.fields['language'] = language;
    }
    
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('STT request failed: ${response.statusCode} $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['text'] as String? ?? '';
  }

  @override
  Future<String> transcribeBytes({
    required Uint8List audioBytes,
    String? language,
    String? format,
  }) async {
    final uri = _buildTranscriptionUri(config.baseUrl);
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers())
      ..fields['model'] = config.model
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        audioBytes,
        filename: 'audio.${format ?? 'wav'}',
      ));
    
    if (language != null && language.isNotEmpty) {
      request.fields['language'] = language;
    }
    
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('STT request failed: ${response.statusCode} $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['text'] as String? ?? '';
  }

  Uri _buildTranscriptionUri(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final path = uri.path;
    if (path.endsWith('/audio/transcriptions')) {
      return uri;
    }
    if (path.endsWith('/v1')) {
      return uri.replace(path: '$path/audio/transcriptions');
    }
    if (path.endsWith('/v1/')) {
      return uri.replace(path: '${path}audio/transcriptions');
    }
    if (path.isEmpty || path == '/') {
      return uri.replace(path: '/v1/audio/transcriptions');
    }
    return uri.replace(path: '$path/v1/audio/transcriptions');
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };
    final apiKey = config.apiKey?.trim();
    if (apiKey != null && apiKey.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $apiKey';
    }
    return headers;
  }
}
