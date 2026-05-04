import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'speech_provider.dart';

/// Remote TTS provider using OpenAI-compatible API.
class RemoteTtsProvider extends TtsProvider {
  RemoteTtsProvider(super.config);

  @override
  Future<Uint8List> synthesize({
    required String text,
    String? voice,
    String? format,
    int? sampleRate,
  }) async {
    final uri = _buildSpeechUri(config.baseUrl);
    final headers = _headers();
    final payload = <String, dynamic>{
      'model': config.model,
      'input': text,
      'stream': false,
      'response_format': format ?? 'wav',
    };
    final effectiveSampleRate = sampleRate ?? config.outputSampleRate;
    if (effectiveSampleRate != null) {
      payload['sample_rate'] = effectiveSampleRate;
    }
    final effectiveVoice = voice ?? config.audioVoice;
    if (effectiveVoice != null && effectiveVoice.isNotEmpty) {
      payload['voice'] = effectiveVoice;
    }
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    if (response.statusCode != HttpStatus.ok) {
      final body = response.body.trim();
      throw HttpException('TTS request failed: ${response.statusCode} $body');
    }
    return response.bodyBytes;
  }

  @override
  Stream<Uint8List> synthesizeStream({
    required String text,
    String? voice,
    String? format,
    int? sampleRate,
  }) async* {
    final uri = _buildSpeechUri(config.baseUrl);
    final headers = _headers();
    final payload = <String, dynamic>{
      'model': config.model,
      'input': text,
      'stream': true,
      'response_format': format ?? config.audioFormat ?? 'wav',
    };
    final effectiveSampleRate = sampleRate ?? config.outputSampleRate;
    if (effectiveSampleRate != null) {
      payload['sample_rate'] = effectiveSampleRate;
    }
    final effectiveVoice = voice ?? config.audioVoice;
    if (effectiveVoice != null && effectiveVoice.isNotEmpty) {
      payload['voice'] = effectiveVoice;
    }
    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(payload);

    final response = await request.send();
    if (response.statusCode != HttpStatus.ok) {
      final body = await response.stream.bytesToString();
      throw HttpException('TTS request failed: ${response.statusCode} $body');
    }

    await for (final chunk in response.stream) {
      if (chunk.isEmpty) {
        continue;
      }
      yield Uint8List.fromList(chunk);
    }
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
