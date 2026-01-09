import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

class AudioStreamPlayer {
  AudioStreamPlayer() {
    _stateSubscription = _player.playerStateStream.listen((state) {
      final playing = state.playing &&
          state.processingState != ProcessingState.completed;
      if (playing != _isPlaying) {
        _isPlaying = playing;
        _playingController.add(_isPlaying);
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamController<Uint8List>? _audioController;
  _LiveAudioSource? _source;
  bool _isPlaying = false;

  Stream<bool> get playingStream => _playingController.stream;

  Future<void> start({required String contentType}) async {
    await stop();
    _audioController = StreamController<Uint8List>();
    _source = _LiveAudioSource(_audioController!.stream, contentType);
    await _player.setAudioSource(_source!);
    await _player.play();
  }

  Future<void> addChunk(Uint8List chunk) async {
    if (_audioController == null || _audioController!.isClosed) {
      return;
    }
    _audioController!.add(chunk);
  }

  Future<void> finish() async {
    await _audioController?.close();
  }

  Future<void> stop() async {
    await _player.stop();
    await _audioController?.close();
    _audioController = null;
    _source = null;
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
    await _stateSubscription?.cancel();
    await _playingController.close();
  }
}

class _LiveAudioSource extends StreamAudioSource {
  _LiveAudioSource(this._stream, this._contentType);

  final Stream<Uint8List> _stream;
  final String _contentType;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    return StreamAudioResponse(
      sourceLength: null,
      contentLength: null,
      offset: start ?? 0,
      stream: _stream,
      contentType: _contentType,
    );
  }
}
