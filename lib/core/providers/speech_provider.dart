import 'dart:io';
import 'dart:typed_data';

import '../models/provider_config.dart';

/// Base class for Text-to-Speech providers.
abstract class TtsProvider {
  final ProviderConfig config;

  TtsProvider(this.config);

  /// Synthesize speech from text and return complete audio bytes.
  Future<Uint8List> synthesize({
    required String text,
    String? voice,
    String? format,
    int? sampleRate,
  });

  /// Stream speech synthesis in chunks for real-time playback.
  Stream<Uint8List> synthesizeStream({
    required String text,
    String? voice,
    String? format,
    int? sampleRate,
  });
}

/// Base class for Speech-to-Text providers.
abstract class SttProvider {
  final ProviderConfig config;

  SttProvider(this.config);

  /// Transcribe audio file to text.
  Future<String> transcribe({
    required File audioFile,
    String? language,
  });

  /// Transcribe audio bytes to text.
  Future<String> transcribeBytes({
    required Uint8List audioBytes,
    String? language,
    String? format,
  }) {
    throw UnsupportedError(
      'Byte transcription is not supported for ${config.protocol}',
    );
  }

  /// Stream transcription for real-time audio input.
  Stream<String> transcribeStream({
    required Stream<Uint8List> audioStream,
    String? language,
  }) {
    throw UnsupportedError(
      'Stream transcription is not supported for ${config.protocol}',
    );
  }
}
