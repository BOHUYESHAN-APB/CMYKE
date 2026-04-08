import 'dart:collection';
import 'dart:math';

class IncrementalTtsQueueMetrics {
  const IncrementalTtsQueueMetrics({
    required this.pendingChunkCount,
    required this.pendingCharCount,
    required this.streamedRequestCount,
    required this.streamedAudioChunkCount,
    required this.maxPendingChunkCount,
    required this.maxPendingCharCount,
  });

  final int pendingChunkCount;
  final int pendingCharCount;
  final int streamedRequestCount;
  final int streamedAudioChunkCount;
  final int maxPendingChunkCount;
  final int maxPendingCharCount;
}

IncrementalTtsQueueMetrics buildIncrementalTtsQueueMetrics({
  required Iterable<String> pendingChunks,
  int streamedRequestCount = 0,
  int streamedAudioChunkCount = 0,
  int previousMaxPendingChunkCount = 0,
  int previousMaxPendingCharCount = 0,
}) {
  var pendingChunkCount = 0;
  var pendingCharCount = 0;
  for (final chunk in pendingChunks) {
    final trimmed = chunk.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    pendingChunkCount += 1;
    pendingCharCount += trimmed.length;
  }
  return IncrementalTtsQueueMetrics(
    pendingChunkCount: pendingChunkCount,
    pendingCharCount: pendingCharCount,
    streamedRequestCount: streamedRequestCount,
    streamedAudioChunkCount: streamedAudioChunkCount,
    maxPendingChunkCount: max(previousMaxPendingChunkCount, pendingChunkCount),
    maxPendingCharCount: max(previousMaxPendingCharCount, pendingCharCount),
  );
}

bool shouldStartIncrementalTtsPlayback({
  required bool started,
  required bool finalize,
  required IncrementalTtsQueueMetrics metrics,
  int minBufferedChunks = 2,
  int minBufferedChars = 24,
}) {
  if (started) {
    return true;
  }
  if (metrics.pendingChunkCount <= 0) {
    return false;
  }
  if (finalize) {
    return true;
  }
  return metrics.pendingChunkCount >= minBufferedChunks ||
      metrics.pendingCharCount >= minBufferedChars;
}

class IncrementalTtsController {
  IncrementalTtsController();

  final Queue<String> _pendingChunks = Queue<String>();

  bool _draining = false;
  bool _finalize = false;
  bool _completed = false;
  bool _started = false;
  bool _producedAudio = false;
  bool _failed = false;
  int _requestCount = 0;
  int _audioChunkCount = 0;
  int _maxPendingChunkCount = 0;
  int _maxPendingCharCount = 0;

  bool get isDraining => _draining;
  bool get isFinalizeRequested => _finalize;
  bool get isCompleted => _completed;
  bool get hasStarted => _started;
  bool get hasProducedAudio => _producedAudio;
  bool get hasFailed => _failed;
  bool get hasPendingChunks => _pendingChunks.isNotEmpty;

  Iterable<String> get pendingChunks => _pendingChunks;

  void enqueueChunks(Iterable<String> chunks) {
    _pendingChunks.addAll(chunks);
  }

  void clearPendingChunks() {
    _pendingChunks.clear();
  }

  void beginDrain() {
    _draining = true;
  }

  void endDrain() {
    _draining = false;
  }

  void requestFinalize() {
    _finalize = true;
  }

  void markCompleted() {
    _completed = true;
  }

  void markStarted() {
    _started = true;
  }

  void markProducedAudio() {
    _producedAudio = true;
  }

  void markFailed() {
    _failed = true;
  }

  void recordRequest() {
    _requestCount += 1;
  }

  void recordAudioChunk() {
    _audioChunkCount += 1;
  }

  IncrementalTtsQueueMetrics captureMetrics() {
    final metrics = buildIncrementalTtsQueueMetrics(
      pendingChunks: _pendingChunks,
      streamedRequestCount: _requestCount,
      streamedAudioChunkCount: _audioChunkCount,
      previousMaxPendingChunkCount: _maxPendingChunkCount,
      previousMaxPendingCharCount: _maxPendingCharCount,
    );
    _maxPendingChunkCount = metrics.maxPendingChunkCount;
    _maxPendingCharCount = metrics.maxPendingCharCount;
    return metrics;
  }

  bool shouldStartPlayback({
    int minBufferedChunks = 2,
    int minBufferedChars = 24,
  }) {
    return shouldStartIncrementalTtsPlayback(
      started: _started,
      finalize: _finalize,
      metrics: captureMetrics(),
      minBufferedChunks: minBufferedChunks,
      minBufferedChars: minBufferedChars,
    );
  }

  String? takeNextChunk() {
    while (_pendingChunks.isNotEmpty) {
      final chunk = _pendingChunks.removeFirst();
      if (chunk.trim().isEmpty) {
        continue;
      }
      return chunk;
    }
    return null;
  }
}
