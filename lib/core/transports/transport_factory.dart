import '../models/provider_config.dart';
import 'base_transport.dart';
import 'openai_transport.dart';
import 'ollama_transport.dart';

/// Factory for creating provider transports based on protocol.
class TransportFactory {
  /// Create a transport instance for the given provider configuration.
  static ProviderTransport create(ProviderConfig config) {
    switch (config.protocol) {
      case ProviderProtocol.openaiCompatible:
        return OpenAITransport(config);
      case ProviderProtocol.ollamaNative:
        return OllamaTransport(config);
      case ProviderProtocol.deviceBuiltin:
        throw UnsupportedError(
          'Device builtin protocol is not supported for LLM transport.',
        );
    }
  }
}
