import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/provider_config.dart';

class SpeechClient {
  Stream<Uint8List> streamSpeech({
    required ProviderConfig provider,
    required String text,
  }) async* {
    final uri = _buildSpeechUri(provider.baseUrl);
    final headers = _headers(provider);
    final payload = <String, dynamic>{
      'model': provider.model,
      'input': text,
      'stream': true,
      'response_format': provider.audioFormat ?? 'wav',
    };
    if (provider.outputSampleRate != null) {
      payload['sample_rate'] = provider.outputSampleRate;
    }
    if (provider.audioVoice != null && provider.audioVoice!.isNotEmpty) {
      payload['voice'] = provider.audioVoice;
    }
    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(payload);

    final response = await request.send();
    if (response.statusCode != HttpStatus.ok) {
      final body = await response.stream.bytesToString();
      throw HttpException(
        'TTS request failed: ${response.statusCode} $body',
      );
    }

    await for (final chunk in response.stream) {
      if (chunk.isEmpty) {
        continue;
      }
      yield Uint8List.fromList(chunk);
    }
  }

  Future<String> transcribeFile({
    required ProviderConfig provider,
    required File audioFile,
  }) async {
    final uri = _buildTranscriptionUri(provider.baseUrl);
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers(provider))
      ..fields['model'] = provider.model
      ..files.add(
        await http.MultipartFile.fromPath('file', audioFile.path),
      );
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'STT request failed: ${response.statusCode} $body',
      );
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['text'] as String? ?? '';
  }

  Uri _buildSpeechUri(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final path = uri.path;
    if (path.endsWith('/audio/speech')) {
      return uri;
    }
    if (path.endsWith('/v1')) {
      return uri.replace(path: '$path/audio/speech');
    }
    if (path.endsWith('/v1/')) {
      return uri.replace(path: '${path}audio/speech');
    }
    if (path.isEmpty || path == '/') {
      return uri.replace(path: '/v1/audio/speech');
    }
    return uri.replace(path: '$path/v1/audio/speech');
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

  Map<String, String> _headers(ProviderConfig provider) {
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };
    final apiKey = provider.apiKey?.trim();
    if (apiKey != null && apiKey.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $apiKey';
    }
    return headers;
  }
}
