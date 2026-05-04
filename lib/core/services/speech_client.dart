import 'dart:io';
import 'dart:typed_data';

import '../models/provider_config.dart';
import '../providers/remote_stt_provider.dart';
import '../providers/remote_tts_provider.dart';
import '../providers/speech_provider.dart';

/// Speech client facade that delegates to protocol-specific providers.
class SpeechClient {
  /// Synthesize speech from text and return complete audio bytes.
  Future<Uint8List> synthesizeSpeechBytes({
    required ProviderConfig provider,
    required String text,
    String responseFormat = 'wav',
  }) {
    final ttsProvider = _createTtsProvider(provider);
    return ttsProvider.synthesize(
      text: text,
      format: responseFormat,
    );
  }

  /// Stream speech synthesis in chunks for real-time playback.
  Stream<Uint8List> streamSpeech({
    required ProviderConfig provider,
    required String text,
  }) {
    final ttsProvider = _createTtsProvider(provider);
    return ttsProvider.synthesizeStream(text: text);
  }

  /// Transcribe audio file to text.
  Future<String> transcribeFile({
    required ProviderConfig provider,
    required File audioFile,
  }) {
    final sttProvider = _createSttProvider(provider);
    return sttProvider.transcribe(audioFile: audioFile);
  }

  /// Transcribe audio bytes to text.
  Future<String> transcribeBytes({
    required ProviderConfig provider,
    required Uint8List audioBytes,
    String? language,
    String? format,
  }) {
    final sttProvider = _createSttProvider(provider);
    return sttProvider.transcribeBytes(
      audioBytes: audioBytes,
      language: language,
      format: format,
    );
  }

  TtsProvider _createTtsProvider(ProviderConfig config) {
    switch (config.protocol) {
      case ProviderProtocol.openaiCompatible:
      case ProviderProtocol.ollamaNative:
        return RemoteTtsProvider(config);
      case ProviderProtocol.deviceBuiltin:
        throw UnsupportedError(
          'Use SystemTtsProvider directly for device builtin TTS.',
        );
    }
  }

  SttProvider _createSttProvider(ProviderConfig config) {
    switch (config.protocol) {
      case ProviderProtocol.openaiCompatible:
      case ProviderProtocol.ollamaNative:
        return RemoteSttProvider(config);
      case ProviderProtocol.deviceBuiltin:
        throw UnsupportedError(
          'Use SystemSttProvider directly for device builtin STT.',
        );
    }
  }
}
