import '../models/llm_stream_event.dart';
import '../models/provider_config.dart';

/// Base class for LLM provider transports.
/// 
/// Each transport implementation handles protocol-specific communication
/// with LLM providers (OpenAI, Ollama, Anthropic, etc.).
abstract class ProviderTransport {
  final ProviderConfig config;

  ProviderTransport(this.config);

  /// Stream chat completion with the provider.
  Stream<LlmStreamEvent> streamChat({
    required List<Map<String, String>> messages,
    String? systemPrompt,
  });

  /// Complete chat (non-streaming) with the provider.
  Future<String> completeChat({
    required List<Map<String, String>> messages,
    String? systemPrompt,
  });

  /// Analyze images with vision-capable models.
  Future<String> analyzeImageUrls({
    required String prompt,
    required List<String> imageUrls,
    String? systemPrompt,
  }) {
    throw UnsupportedError(
      'Vision is not supported for ${config.protocol}',
    );
  }

  /// Analyze images from bytes with vision-capable models.
  Future<String> analyzeImageBytes({
    required String prompt,
    required List<LlmImageInput> images,
    String? systemPrompt,
  }) {
    throw UnsupportedError(
      'Vision is not supported for ${config.protocol}',
    );
  }

  /// Generate embeddings for a single text input.
  Future<List<double>> embedText({
    required String input,
  }) async {
    final embeddings = await embedTexts(inputs: [input]);
    return embeddings.isEmpty ? [] : embeddings.first;
  }

  /// Generate embeddings for multiple text inputs.
  Future<List<List<double>>> embedTexts({
    required List<String> inputs,
  }) {
    throw UnsupportedError(
      'Embeddings are not supported for ${config.protocol}',
    );
  }
}

/// Image input for vision models.
class LlmImageInput {
  final List<int> bytes;
  final String mimeType;

  LlmImageInput({
    required this.bytes,
    required this.mimeType,
  });
}
