import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:speech_to_text/speech_to_text.dart';

import 'speech_provider.dart';

/// System STT provider using platform's built-in speech recognition.
class SystemSttProvider extends SttProvider {
  final SpeechToText _stt;
  final _transcriptController = StreamController<String>.broadcast();

  SystemSttProvider(super.config, {SpeechToText? stt}) 
      : _stt = stt ?? SpeechToText();

  @override
  Future<String> transcribe({
    required File audioFile,
    String? language,
  }) async {
    // System STT doesn't support file transcription directly
    throw UnsupportedError(
      'System STT does not support file transcription. Use listen() instead.',
    );
  }

  @override
  Stream<String> transcribeStream({
    required Stream<Uint8List> audioStream,
    String? language,
  }) {
    // System STT uses microphone input, not byte streams
    throw UnsupportedError(
      'System STT does not support byte stream transcription. Use listen() instead.',
    );
  }

  /// Initialize speech recognition.
  Future<bool> initialize() async {
    return await _stt.initialize(
      onError: (error) {
        _transcriptController.addError(error);
      },
      onStatus: (status) {
        // Status updates can be handled here
      },
    );
  }

  /// Start listening to microphone input.
  Future<void> listen({
    String? localeId,
    Duration? listenFor,
    Duration? pauseFor,
    bool partialResults = true,
    void Function(String)? onResult,
  }) async {
    if (!_stt.isAvailable) {
      throw StateError('Speech recognition is not available');
    }

    await _stt.listen(
      onResult: (result) {
        final text = result.recognizedWords;
        if (text.isNotEmpty) {
          _transcriptController.add(text);
          onResult?.call(text);
        }
      },
      localeId: localeId,
      listenFor: listenFor,
      pauseFor: pauseFor,
      listenOptions: SpeechListenOptions(
        partialResults: partialResults,
      ),
    );
  }

  /// Stop listening.
  Future<void> stop() async {
    await _stt.stop();
  }

  /// Cancel listening.
  Future<void> cancel() async {
    await _stt.cancel();
  }

  /// Check if currently listening.
  bool get isListening => _stt.isListening;

  /// Check if speech recognition is available.
  bool get isAvailable => _stt.isAvailable;

  /// Get available locales.
  Future<List<LocaleName>> getLocales() async {
    return await _stt.locales();
  }

  /// Stream of transcription results.
  Stream<String> get transcripts => _transcriptController.stream;

  /// Dispose resources.
  void dispose() {
    _transcriptController.close();
  }
}
