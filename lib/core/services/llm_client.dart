import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/llm_stream_event.dart';
import '../models/provider_config.dart';

class LlmClient {
  Stream<LlmStreamEvent> streamChat({
    required ProviderConfig provider,
    required List<ChatMessage> messages,
    String? systemPrompt,
  }) async* {
    switch (provider.protocol) {
      case ProviderProtocol.openaiCompatible:
        yield* _streamOpenAi(
          provider: provider,
          messages: messages,
          systemPrompt: systemPrompt,
        );
      case ProviderProtocol.ollamaNative:
        yield* _streamOllama(
          provider: provider,
          messages: messages,
          systemPrompt: systemPrompt,
        );
      case ProviderProtocol.deviceBuiltin:
        throw UnsupportedError(
          'Device builtin protocol is not supported for LLM.',
        );
    }
  }

  Future<String> completeChat({
    required ProviderConfig provider,
    required List<ChatMessage> messages,
    String? systemPrompt,
  }) async {
    switch (provider.protocol) {
      case ProviderProtocol.openaiCompatible:
        return _completeOpenAi(
          provider: provider,
          messages: messages,
          systemPrompt: systemPrompt,
        );
      case ProviderProtocol.ollamaNative:
        return _completeOllama(
          provider: provider,
          messages: messages,
          systemPrompt: systemPrompt,
        );
      case ProviderProtocol.deviceBuiltin:
        throw UnsupportedError(
          'Device builtin protocol is not supported for LLM.',
        );
    }
  }

  Future<String> analyzeImageUrls({
    required ProviderConfig provider,
    required String prompt,
    required List<String> imageUrls,
    String? systemPrompt,
  }) async {
    if (imageUrls.isEmpty) {
      return '';
    }
    switch (provider.protocol) {
      case ProviderProtocol.openaiCompatible:
        return _completeOpenAiVision(
          provider: provider,
          prompt: prompt,
          imageUrls: imageUrls,
          systemPrompt: systemPrompt,
        );
      case ProviderProtocol.ollamaNative:
        throw UnsupportedError('Vision is not supported for Ollama native.');
      case ProviderProtocol.deviceBuiltin:
        throw UnsupportedError('Vision is not supported for device builtin.');
    }
  }

  Future<String> analyzeImageBytes({
    required ProviderConfig provider,
    required String prompt,
    required List<LlmImageInput> images,
    String? systemPrompt,
  }) async {
    if (images.isEmpty) {
      return '';
    }
    switch (provider.protocol) {
      case ProviderProtocol.openaiCompatible:
        return _completeOpenAiVisionBytes(
          provider: provider,
          prompt: prompt,
          images: images,
          systemPrompt: systemPrompt,
        );
      case ProviderProtocol.ollamaNative:
        throw UnsupportedError('Vision is not supported for Ollama native.');
      case ProviderProtocol.deviceBuiltin:
        throw UnsupportedError('Vision is not supported for device builtin.');
    }
  }

  Future<List<double>> embedText({
    required ProviderConfig provider,
    required String input,
  }) async {
    final embeddings = await embedTexts(provider: provider, inputs: [input]);
    return embeddings.isEmpty ? [] : embeddings.first;
  }

  Future<List<List<double>>> embedTexts({
    required ProviderConfig provider,
    required List<String> inputs,
  }) async {
    if (inputs.isEmpty) {
      return [];
    }
    switch (provider.protocol) {
      case ProviderProtocol.openaiCompatible:
        return _embedOpenAi(provider: provider, inputs: inputs);
      case ProviderProtocol.ollamaNative:
        return _embedOllama(provider: provider, inputs: inputs);
      case ProviderProtocol.deviceBuiltin:
        throw UnsupportedError(
          'Device builtin protocol is not supported for embeddings.',
        );
    }
  }

  Stream<LlmStreamEvent> _streamOpenAi({
    required ProviderConfig provider,
    required List<ChatMessage> messages,
    String? systemPrompt,
  }) async* {
    final uri = _buildChatUri(provider.baseUrl);
    final headers = _headers(provider);
    final payload = _payload(
      provider: provider,
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

  Stream<LlmStreamEvent> _streamOllama({
    required ProviderConfig provider,
    required List<ChatMessage> messages,
    String? systemPrompt,
  }) async* {
    final uri = _buildOllamaChatUri(provider.baseUrl);
    final headers = _headers(provider);
    final payload = _ollamaPayload(
      provider: provider,
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

  Future<String> _completeOpenAi({
    required ProviderConfig provider,
    required List<ChatMessage> messages,
    String? systemPrompt,
  }) async {
    final uri = _buildChatUri(provider.baseUrl);
    final headers = _headers(provider);
    final payload = _payload(
      provider: provider,
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

  Future<String> _completeOpenAiVision({
    required ProviderConfig provider,
    required String prompt,
    required List<String> imageUrls,
    String? systemPrompt,
  }) async {
    final uri = _buildChatUri(provider.baseUrl);
    final headers = _headers(provider);
    final payload = _visionPayload(
      provider: provider,
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

  Future<String> _completeOpenAiVisionBytes({
    required ProviderConfig provider,
    required String prompt,
    required List<LlmImageInput> images,
    String? systemPrompt,
  }) async {
    final uri = _buildChatUri(provider.baseUrl);
    final headers = _headers(provider);
    final payload = _visionBytesPayload(
      provider: provider,
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

  Future<String> _completeOllama({
    required ProviderConfig provider,
    required List<ChatMessage> messages,
    String? systemPrompt,
  }) async {
    final uri = _buildOllamaChatUri(provider.baseUrl);
    final headers = _headers(provider);
    final payload = _ollamaPayload(
      provider: provider,
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

  Uri _buildOllamaChatUri(String baseUrl) {
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

  Uri _buildOllamaEmbeddingUri(String baseUrl) {
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

  Map<String, String> _embeddingHeaders(ProviderConfig provider) {
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };
    final apiKey = provider.embeddingApiKey?.trim().isNotEmpty == true
        ? provider.embeddingApiKey!.trim()
        : provider.apiKey?.trim();
    if (apiKey != null && apiKey.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $apiKey';
    }
    return headers;
  }

  Map<String, dynamic> _payload({
    required ProviderConfig provider,
    required List<ChatMessage> messages,
    required bool stream,
    String? systemPrompt,
  }) {
    final list = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      list.add({'role': 'system', 'content': systemPrompt});
    }
    list.addAll(
      messages.map(
        (message) => {'role': message.role.name, 'content': message.content},
      ),
    );
    final payload = <String, dynamic>{
      'model': provider.model,
      'stream': stream,
      'messages': list,
    };
    if (provider.temperature != null) {
      payload['temperature'] = provider.temperature;
    }
    if (provider.topP != null) {
      payload['top_p'] = provider.topP;
    }
    if (provider.maxTokens != null) {
      payload['max_tokens'] = provider.maxTokens;
    }
    if (provider.presencePenalty != null) {
      payload['presence_penalty'] = provider.presencePenalty;
    }
    if (provider.frequencyPenalty != null) {
      payload['frequency_penalty'] = provider.frequencyPenalty;
    }
    if (provider.seed != null) {
      payload['seed'] = provider.seed;
    }
    final wantsAudio = provider.capabilities.contains(
      ProviderCapability.audioOut,
    );
    if (provider.kind == ProviderKind.omni ||
        provider.kind == ProviderKind.realtime) {
      payload['modalities'] = wantsAudio ? ['text', 'audio'] : ['text'];
      if (wantsAudio && provider.audioVoice != null) {
        payload['audio'] = {
          'voice': provider.audioVoice,
          'format': provider.audioFormat ?? 'wav',
        };
      }
      if (provider.enableThinking != null) {
        payload['enable_thinking'] = provider.enableThinking;
      }
    }
    return payload;
  }

  Map<String, dynamic> _visionPayload({
    required ProviderConfig provider,
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
      'model': provider.model,
      'stream': false,
      'messages': messages,
    };
    if (provider.temperature != null) {
      payload['temperature'] = provider.temperature;
    }
    if (provider.topP != null) {
      payload['top_p'] = provider.topP;
    }
    if (provider.maxTokens != null) {
      payload['max_tokens'] = provider.maxTokens;
    }
    if (provider.presencePenalty != null) {
      payload['presence_penalty'] = provider.presencePenalty;
    }
    if (provider.frequencyPenalty != null) {
      payload['frequency_penalty'] = provider.frequencyPenalty;
    }
    if (provider.seed != null) {
      payload['seed'] = provider.seed;
    }
    return payload;
  }

  Future<List<List<double>>> _embedOpenAi({
    required ProviderConfig provider,
    required List<String> inputs,
  }) async {
    final base = provider.embeddingBaseUrl?.trim().isNotEmpty == true
        ? provider.embeddingBaseUrl!.trim()
        : provider.baseUrl;
    final uri = _buildEmbeddingUri(base);
    final headers = _embeddingHeaders(provider);
    final payload = {
      'model': _resolveEmbeddingModel(provider),
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

  Future<List<List<double>>> _embedOllama({
    required ProviderConfig provider,
    required List<String> inputs,
  }) async {
    final base = provider.embeddingBaseUrl?.trim().isNotEmpty == true
        ? provider.embeddingBaseUrl!.trim()
        : provider.baseUrl;
    final uri = _buildOllamaEmbeddingUri(base);
    final headers = _embeddingHeaders(provider);
    final model = _resolveEmbeddingModel(provider);
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

  List<double> _coerceEmbedding(Object? raw) {
    if (raw is! List<dynamic>) {
      return [];
    }
    return raw.map((value) => (value as num).toDouble()).toList();
  }

  String _resolveEmbeddingModel(ProviderConfig provider) {
    final embeddingModel = provider.embeddingModel?.trim();
    if (embeddingModel != null && embeddingModel.isNotEmpty) {
      return embeddingModel;
    }
    return provider.model;
  }

  Map<String, dynamic> _ollamaPayload({
    required ProviderConfig provider,
    required List<ChatMessage> messages,
    required bool stream,
    String? systemPrompt,
  }) {
    final list = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      list.add({'role': 'system', 'content': systemPrompt});
    }
    list.addAll(
      messages.map(
        (message) => {'role': message.role.name, 'content': message.content},
      ),
    );
    final payload = <String, dynamic>{
      'model': provider.model,
      'stream': stream,
      'messages': list,
    };
    final options = <String, dynamic>{};
    if (provider.temperature != null) {
      options['temperature'] = provider.temperature;
    }
    if (provider.topP != null) {
      options['top_p'] = provider.topP;
    }
    if (provider.maxTokens != null) {
      options['num_predict'] = provider.maxTokens;
    }
    if (provider.seed != null) {
      options['seed'] = provider.seed;
    }
    if (options.isNotEmpty) {
      payload['options'] = options;
    }
    return payload;
  }

  Map<String, dynamic> _visionBytesPayload({
    required ProviderConfig provider,
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
      'model': provider.model,
      'stream': false,
      'messages': messages,
    };
    if (provider.temperature != null) {
      payload['temperature'] = provider.temperature;
    }
    if (provider.topP != null) {
      payload['top_p'] = provider.topP;
    }
    if (provider.maxTokens != null) {
      payload['max_tokens'] = provider.maxTokens;
    }
    if (provider.presencePenalty != null) {
      payload['presence_penalty'] = provider.presencePenalty;
    }
    if (provider.frequencyPenalty != null) {
      payload['frequency_penalty'] = provider.frequencyPenalty;
    }
    if (provider.seed != null) {
      payload['seed'] = provider.seed;
    }
    return payload;
  }
}

class LlmImageInput {
  const LlmImageInput({required this.bytes, required this.mimeType});

  final List<int> bytes;
  final String mimeType;
}
