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
        throw UnsupportedError('Device builtin protocol is not supported for LLM.');
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
        throw UnsupportedError('Device builtin protocol is not supported for LLM.');
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
      throw HttpException(
        'LLM request failed: ${response.statusCode} $body',
      );
    }

    await for (final line in response.stream
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
          (choices.first as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
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

    await for (final line in response.stream
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
    final message = (choices.first as Map<String, dynamic>)['message']
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

  Map<String, dynamic> _payload({
    required ProviderConfig provider,
    required List<ChatMessage> messages,
    required bool stream,
    String? systemPrompt,
  }) {
    final list = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      list.add({
        'role': 'system',
        'content': systemPrompt,
      });
    }
    list.addAll(
      messages.map(
        (message) => {
          'role': message.role.name,
          'content': message.content,
        },
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
    final wantsAudio = provider.capabilities.contains(ProviderCapability.audioOut);
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

  Map<String, dynamic> _ollamaPayload({
    required ProviderConfig provider,
    required List<ChatMessage> messages,
    required bool stream,
    String? systemPrompt,
  }) {
    final list = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      list.add({
        'role': 'system',
        'content': systemPrompt,
      });
    }
    list.addAll(
      messages.map(
        (message) => {
          'role': message.role.name,
          'content': message.content,
        },
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
}
