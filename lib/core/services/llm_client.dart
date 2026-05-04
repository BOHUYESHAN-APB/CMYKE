import '../models/llm_stream_event.dart';
import '../models/provider_config.dart';
import '../transports/base_transport.dart';
import '../transports/transport_factory.dart';

export '../transports/base_transport.dart' show LlmImageInput;

/// LLM client that delegates to protocol-specific transports.
class LlmClient {
  Stream<LlmStreamEvent> streamChat(
    ProviderConfig provider,
    List<Map<String, String>> messages, {
    String? systemPrompt,
  }) {
    final transport = TransportFactory.create(provider);
    return transport.streamChat(
      messages: messages,
      systemPrompt: systemPrompt,
    );
  }

  Future<String> completeChat(
    ProviderConfig provider,
    List<Map<String, String>> messages, {
    String? systemPrompt,
  }) {
    final transport = TransportFactory.create(provider);
    return transport.completeChat(
      messages: messages,
      systemPrompt: systemPrompt,
    );
  }

  Future<String> analyzeImageUrls(
    ProviderConfig provider,
    String prompt,
    List<String> imageUrls, {
    String? systemPrompt,
  }) {
    if (imageUrls.isEmpty) {
      return Future.value('');
    }
    final transport = TransportFactory.create(provider);
    return transport.analyzeImageUrls(
      prompt: prompt,
      imageUrls: imageUrls,
      systemPrompt: systemPrompt,
    );
  }

  Future<String> analyzeImageBytes(
    ProviderConfig provider,
    String prompt,
    List<LlmImageInput> images, {
    String? systemPrompt,
  }) {
    if (images.isEmpty) {
      return Future.value('');
    }
    final transport = TransportFactory.create(provider);
    return transport.analyzeImageBytes(
      prompt: prompt,
      images: images,
      systemPrompt: systemPrompt,
    );
  }

  Future<List<double>> embedText(
    ProviderConfig provider,
    String input,
  ) async {
    final embeddings = await embedTexts(provider, [input]);
    return embeddings.isEmpty ? [] : embeddings.first;
  }

  Future<List<List<double>>> embedTexts(
    ProviderConfig provider,
    List<String> inputs,
  ) {
    if (inputs.isEmpty) {
      return Future.value([]);
    }
    final transport = TransportFactory.create(provider);
    return transport.embedTexts(inputs: inputs);
  }
}
