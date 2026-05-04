import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';

import 'speech_provider.dart';

/// System TTS provider using platform's built-in TTS engine.
class SystemTtsProvider extends TtsProvider {
  final FlutterTts _tts;

  SystemTtsProvider(super.config, {FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  @override
  Future<Uint8List> synthesize({
    required String text,
    String? voice,
    String? format,
    int? sampleRate,
  }) async {
    // System TTS doesn't support direct byte output
    // This would require platform-specific implementation
    throw UnsupportedError(
      'System TTS does not support byte synthesis. Use speak() instead.',
    );
  }

  @override
  Stream<Uint8List> synthesizeStream({
    required String text,
    String? voice,
    String? format,
    int? sampleRate,
  }) async* {
    // System TTS doesn't support streaming byte output
    throw UnsupportedError(
      'System TTS does not support stream synthesis. Use speak() instead.',
    );
  }

  /// Speak text using system TTS engine.
  Future<void> speak({
    required String text,
    String? voice,
    double? rate,
    double? pitch,
    double? volume,
  }) async {
    if (voice != null) {
      await _tts.setVoice({'name': voice, 'locale': 'en-US'});
    }
    if (rate != null) {
      await _tts.setSpeechRate(rate);
    }
    if (pitch != null) {
      await _tts.setPitch(pitch);
    }
    if (volume != null) {
      await _tts.setVolume(volume);
    }
    await _tts.speak(text);
  }

  /// Stop current speech.
  Future<void> stop() async {
    await _tts.stop();
  }

  /// Pause current speech.
  Future<void> pause() async {
    await _tts.pause();
  }

  /// Get available voices.
  Future<List<dynamic>> getVoices() async {
    return await _tts.getVoices ?? [];
  }

  /// Set completion handler.
  void setCompletionHandler(void Function() handler) {
    _tts.setCompletionHandler(handler);
  }

  /// Set error handler.
  void setErrorHandler(void Function(dynamic) handler) {
    _tts.setErrorHandler(handler);
  }
}
