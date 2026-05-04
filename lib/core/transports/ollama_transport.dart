import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/llm_stream_event.dart';
import 'base_transport.dart';

/// Ollama native transport implementation.
/// 
/// Supports Ollama's native API protocol.
class OllamaTransport extends ProviderTransport {
  OllamaTransport(super.config);

  @override
  Stream<LlmStreamEvent> streamChat({
    required List<Map<String, String>> messages,
    String? systemPrompt,
  }) async* {
    final uri = _buildChatUri(config.baseUrl);
    final headers = _headers();
    final payload = _payload(
      messages: messages,
      systemPrompt: systemPrompt,
      stream: true,
    );
    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(payload);

    final response = await request.send();
    if (response.statusCode != HttpStatus.ok) {
      final body = await response.stream.bytesToString();
      throw HttpException(
        'Ollama request failed: ${response.statusCode} $body',
      );
    }

    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.trim().isEmpty) {
        continue;
      }
      final json = jsonDecode(line) as Map<String, dynamic>;
      final done = json['done'] as bool? ?? false;
      final message = json['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;
      if (content != null && content.isNotEmpty) {
        yield LlmStreamEvent(textDelta: content);
      }
      if (done) {
        break;
      }
    }
  }

  @override
  Future<String> completeChat({
    required List<Map<String, String>> messages,
    String? systemPrompt,
  }) async {
    final uri = _buildChatUri(config.baseUrl);
    final headers = _headers();
    final payload = _payload(
      messages: messages,
      systemPrompt: systemPrompt,
      stream: false,
    );
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Ollama request failed: ${response.statusCode} ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final message = json['message'] as Map<String, dynamic>?;
    return message?['content'] as String? ?? '';
  }

  @override
  Future<List<List<double>>> embedTexts({
    required List<String> inputs,
  }) async {
    if (inputs.isEmpty) {
      return [];
    }
    final base = config.embeddingBaseUrl?.trim().isNotEmpty == true
        ? config.embeddingBaseUrl!.trim()
        : config.baseUrl;
    final uri = _buildEmbeddingUri(base);
    final headers = _embeddingHeaders();
    final model = _resolveEmbeddingModel();
    final embeddings = <List<double>>[];
    for (final input in inputs) {
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({'model': model, 'prompt': input}),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Ollama embedding request failed: ${response.statusCode} ${response.body}',
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      embeddings.add(_coerceEmbedding(json['embedding']));
    }
    return embeddings;
  }

  // URI builders

  Uri _buildChatUri(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final path = uri.path;
    if (path.endsWith('/api/chat')) {
      return uri;
    }
    if (path.isEmpty || path == '/') {
      return uri.replace(path: '/api/chat');
    }
    return uri.replace(path: '$path/api/chat');
  }

  Uri _buildEmbeddingUri(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final path = uri.path;
    if (path.endsWith('/api/embeddings')) {
      return uri;
    }
    if (path.isEmpty || path == '/') {
      return uri.replace(path: '/api/embeddings');
    }
    return uri.replace(path: '$path/api/embeddings');
  }

  // Headers

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

  Map<String, String> _embeddingHeaders() {
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };
    final apiKey = config.embeddingApiKey?.trim().isNotEmpty == true
        ? config.embeddingApiKey!.trim()
        : config.apiKey?.trim();
    if (apiKey != null && apiKey.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $apiKey';
    }
    return headers;
  }

  // Payload builders

  Map<String, dynamic> _payload({
    required List<Map<String, String>> messages,
    required bool stream,
    String? systemPrompt,
  }) {
    final list = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      list.add({'role': 'system', 'content': systemPrompt});
    }
    list.addAll(messages);
    final payload = <String, dynamic>{
      'model': config.model,
      'stream': stream,
      'messages': list,
    };
    final options = <String, dynamic>{};
    if (config.temperature != null) {
      options['temperature'] = config.temperature;
    }
    if (config.topP != null) {
      options['top_p'] = config.topP;
    }
    if (config.maxTokens != null) {
      options['num_predict'] = config.maxTokens;
    }
    if (config.seed != null) {
      options['seed'] = config.seed;
    }
    if (options.isNotEmpty) {
      payload['options'] = options;
    }
    return payload;
  }

  // Helpers

  String _resolveEmbeddingModel() {
    final embeddingModel = config.embeddingModel?.trim();
    if (embeddingModel != null && embeddingModel.isNotEmpty) {
      return embeddingModel;
    }
    return config.model;
  }

  List<double> _coerceEmbedding(Object? raw) {
    if (raw is! List<dynamic>) {
      return [];
    }
    return raw.map((value) => (value as num).toDouble()).toList();
  }
}
