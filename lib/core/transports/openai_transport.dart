import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/llm_stream_event.dart';
import '../models/provider_config.dart';
import 'base_transport.dart';

/// OpenAI-compatible transport implementation.
/// 
/// Supports OpenAI API and any OpenAI-compatible endpoints.
class OpenAITransport extends ProviderTransport {
  OpenAITransport(super.config);

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
      throw HttpException('LLM request failed: ${response.statusCode} $body');
    }

    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) {
        continue;
      }
      final data = line.substring(5).trim();
      if (data == '[DONE]') {
        break;
      }
      final json = jsonDecode(data) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>? ?? [];
      if (choices.isEmpty) {
        continue;
      }
      final delta =
          (choices.first as Map<String, dynamic>)['delta']
              as Map<String, dynamic>?;
      final audio = delta?['audio'] as Map<String, dynamic>?;
      final content = delta?['content'] as String?;
      final transcript = audio?['transcript'] as String?;
      final textDelta = (content != null && content.isNotEmpty)
          ? content
          : (transcript != null && transcript.isNotEmpty)
          ? transcript
          : null;
      if (textDelta != null && textDelta.isNotEmpty) {
        yield LlmStreamEvent(textDelta: textDelta);
      }
      final audioData = audio?['data'] as String?;
      if (audioData != null && audioData.isNotEmpty) {
        yield LlmStreamEvent(
          audioChunk: base64Decode(audioData),
          audioFormat: audio?['format'] as String?,
        );
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
        'LLM request failed: ${response.statusCode} ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) {
      return '';
    }
    final message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>?;
    return message?['content'] as String? ?? '';
  }

  @override
  Future<String> analyzeImageUrls({
    required String prompt,
    required List<String> imageUrls,
    String? systemPrompt,
  }) async {
    if (imageUrls.isEmpty) {
      return '';
    }
    final uri = _buildChatUri(config.baseUrl);
    final headers = _headers();
    final payload = _visionPayload(
      prompt: prompt,
      imageUrls: imageUrls,
      systemPrompt: systemPrompt,
    );
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Vision request failed: ${response.statusCode} ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) {
      return '';
    }
    final message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>?;
    return message?['content'] as String? ?? '';
  }

  @override
  Future<String> analyzeImageBytes({
    required String prompt,
    required List<LlmImageInput> images,
    String? systemPrompt,
  }) async {
    if (images.isEmpty) {
      return '';
    }
    final uri = _buildChatUri(config.baseUrl);
    final headers = _headers();
    final payload = _visionBytesPayload(
      prompt: prompt,
      images: images,
      systemPrompt: systemPrompt,
    );
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Vision request failed: ${response.statusCode} ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) {
      return '';
    }
    final message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>?;
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
    final payload = {
      'model': _resolveEmbeddingModel(),
      'input': inputs.length == 1 ? inputs.first : inputs,
    };
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Embedding request failed: ${response.statusCode} ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>? ?? [];
    return data
        .map((entry) => _coerceEmbedding((entry as Map)['embedding']))
        .toList();
  }

  // URI builders

  Uri _buildChatUri(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final path = uri.path;
    if (path.endsWith('/v1/chat/completions')) {
      return uri;
    }
    if (path.endsWith('/v1')) {
      return uri.replace(path: '$path/chat/completions');
    }
    if (path.endsWith('/v1/')) {
      return uri.replace(path: '${path}chat/completions');
    }
    if (path.isEmpty || path == '/') {
      return uri.replace(path: '/v1/chat/completions');
    }
    return uri.replace(path: '$path/v1/chat/completions');
  }

  Uri _buildEmbeddingUri(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final path = uri.path;
    if (path.endsWith('/v1/embeddings')) {
      return uri;
    }
    if (path.endsWith('/v1')) {
      return uri.replace(path: '$path/embeddings');
    }
    if (path.endsWith('/v1/')) {
      return uri.replace(path: '${path}embeddings');
    }
    if (path.isEmpty || path == '/') {
      return uri.replace(path: '/v1/embeddings');
    }
    return uri.replace(path: '$path/v1/embeddings');
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
    if (config.temperature != null) {
      payload['temperature'] = config.temperature;
    }
    if (config.topP != null) {
      payload['top_p'] = config.topP;
    }
    if (config.maxTokens != null) {
      payload['max_tokens'] = config.maxTokens;
    }
    if (config.presencePenalty != null) {
      payload['presence_penalty'] = config.presencePenalty;
    }
    if (config.frequencyPenalty != null) {
      payload['frequency_penalty'] = config.frequencyPenalty;
    }
    if (config.seed != null) {
      payload['seed'] = config.seed;
    }
    final wantsAudio = config.capabilities.contains(
      ProviderCapability.audioOut,
    );
    if (config.kind == ProviderKind.omni ||
        config.kind == ProviderKind.realtime) {
      payload['modalities'] = wantsAudio ? ['text', 'audio'] : ['text'];
      if (wantsAudio && config.audioVoice != null) {
        payload['audio'] = {
          'voice': config.audioVoice,
          'format': config.audioFormat ?? 'wav',
        };
      }
      if (config.enableThinking != null) {
        payload['enable_thinking'] = config.enableThinking;
      }
    }
    return payload;
  }

  Map<String, dynamic> _visionPayload({
    required String prompt,
    required List<String> imageUrls,
    String? systemPrompt,
  }) {
    final messages = <Map<String, Object>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    final content = <Map<String, Object>>[
      {'type': 'text', 'text': prompt},
    ];
    for (final url in imageUrls) {
      final trimmed = url.trim();
      if (trimmed.isEmpty) continue;
      content.add({
        'type': 'image_url',
        'image_url': {'url': trimmed, 'detail': 'auto'},
      });
    }
    messages.add({'role': 'user', 'content': content});

    final payload = <String, dynamic>{
      'model': config.model,
      'stream': false,
      'messages': messages,
    };
    if (config.temperature != null) {
      payload['temperature'] = config.temperature;
    }
    if (config.topP != null) {
      payload['top_p'] = config.topP;
    }
    if (config.maxTokens != null) {
      payload['max_tokens'] = config.maxTokens;
    }
    if (config.presencePenalty != null) {
      payload['presence_penalty'] = config.presencePenalty;
    }
    if (config.frequencyPenalty != null) {
      payload['frequency_penalty'] = config.frequencyPenalty;
    }
    if (config.seed != null) {
      payload['seed'] = config.seed;
    }
    return payload;
  }

  Map<String, dynamic> _visionBytesPayload({
    required String prompt,
    required List<LlmImageInput> images,
    String? systemPrompt,
  }) {
    final messages = <Map<String, Object>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    final content = <Map<String, Object>>[
      {'type': 'text', 'text': prompt},
    ];
    for (final image in images) {
      final mime = image.mimeType.trim().isEmpty
          ? 'image/png'
          : image.mimeType.trim();
      final b64 = base64Encode(image.bytes);
      content.add({
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,$b64', 'detail': 'auto'},
      });
    }
    messages.add({'role': 'user', 'content': content});

    final payload = <String, dynamic>{
      'model': config.model,
      'stream': false,
      'messages': messages,
    };
    if (config.temperature != null) {
      payload['temperature'] = config.temperature;
    }
    if (config.topP != null) {
      payload['top_p'] = config.topP;
    }
    if (config.maxTokens != null) {
      payload['max_tokens'] = config.maxTokens;
    }
    if (config.presencePenalty != null) {
      payload['presence_penalty'] = config.presencePenalty;
    }
    if (config.frequencyPenalty != null) {
      payload['frequency_penalty'] = config.frequencyPenalty;
    }
    if (config.seed != null) {
      payload['seed'] = config.seed;
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
