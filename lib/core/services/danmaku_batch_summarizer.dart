import 'dart:async';

import 'danmaku_adapter.dart';
import '../models/danmaku_adapter_state.dart';

/// Configuration for batch summarization
class BatchSummarizerConfig {
  const BatchSummarizerConfig({
    this.intervalSeconds = 20,
    this.batchSize = 50,
    this.enabled = true,
  });

  final int intervalSeconds;
  final int batchSize;
  final bool enabled;
}

/// Batch summary output
class DanmakuBatchSummary {
  const DanmakuBatchSummary({
    required this.items,
    required this.timestamp,
    this.droppedCount = 0,
  });

  final List<Map<String, dynamic>> items;
  final DateTime timestamp;
  final int droppedCount;

  int get totalCount => items.length + droppedCount;
}

/// Service that batches danmaku events and emits summaries periodically
class DanmakuBatchSummarizer {
  DanmakuBatchSummarizer({
    required DanmakuAdapter adapter,
    BatchSummarizerConfig config = const BatchSummarizerConfig(),
  })  : _adapter = adapter,
        _config = config {
    _summaryController = StreamController<DanmakuBatchSummary>.broadcast();
    _buffer = [];
    _droppedCount = 0;
  }

  final DanmakuAdapter _adapter;
  final BatchSummarizerConfig _config;
  late final StreamController<DanmakuBatchSummary> _summaryController;
  late List<Map<String, dynamic>> _buffer;
  late int _droppedCount;

  StreamSubscription<DanmakuAdapterOutput>? _adapterSub;
  Timer? _batchTimer;
  bool _disposed = false;

  /// Stream of batch summaries
  Stream<DanmakuBatchSummary> get summaries => _summaryController.stream;

  /// Current buffer size
  int get bufferSize => _buffer.length;

  /// Total dropped events since last summary
  int get droppedCount => _droppedCount;

  /// Start listening to adapter and batching events
  void start() {
    if (_disposed || !_config.enabled) return;
    
    stop(); // Stop any existing subscription

    _adapterSub = _adapter.outputs.listen((output) {
      if (output is DanmakuEventOutput) {
        _addToBuffer(output.event);
      }
    });

    _startBatchTimer();
  }

  /// Stop batching
  void stop() {
    _adapterSub?.cancel();
    _adapterSub = null;
    _batchTimer?.cancel();
    _batchTimer = null;
  }

  /// Dispose resources
  Future<void> dispose() async {
    _disposed = true;
    stop();
    await _summaryController.close();
  }

  void _addToBuffer(Map<String, dynamic> event) {
    if (_buffer.length >= _config.batchSize) {
      // Buffer full, drop oldest or increment dropped count
      _droppedCount++;
      return;
    }
    _buffer.add(event);
  }

  void _startBatchTimer() {
    _batchTimer?.cancel();
    _batchTimer = Timer.periodic(
      Duration(seconds: _config.intervalSeconds),
      (_) => _processBatch(),
    );
  }

  void _processBatch() {
    if (_buffer.isEmpty && _droppedCount == 0) return;

    final summary = DanmakuBatchSummary(
      items: List.unmodifiable(_buffer),
      timestamp: DateTime.now(),
      droppedCount: _droppedCount,
    );

    _buffer.clear();
    _droppedCount = 0;

    if (!_summaryController.isClosed) {
      _summaryController.add(summary);
    }
  }

  /// Manually trigger batch processing (for testing)
  void flush() {
    _processBatch();
  }
}
