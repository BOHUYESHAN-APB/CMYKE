import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Message queue item.
class QueuedMessage<T> {
  QueuedMessage({
    required this.data,
    required this.completer,
    this.priority = 0,
  });

  final T data;
  final Completer<void> completer;
  final int priority;
}

/// Simple FIFO message queue to avoid concurrency issues.
/// 
/// Design: Level 1-2 abstraction (simple queue + priority support)
/// Reference: airi's queue-based message processing
/// 
/// Features:
/// - FIFO ordering
/// - Optional priority support
/// - Concurrent processing control
/// - Error isolation
class MessageQueue<T> {
  MessageQueue({
    this.concurrency = 1,
    this.onProcess,
  });

  /// Maximum number of concurrent processing tasks.
  final int concurrency;

  /// Callback to process each message.
  final Future<void> Function(T data)? onProcess;

  final Queue<QueuedMessage<T>> _queue = Queue();
  int _activeCount = 0;
  bool _isDisposed = false;

  /// Enqueue a message for processing.
  /// 
  /// Returns a Future that completes when the message is processed.
  Future<void> enqueue(T data, {int priority = 0}) {
    if (_isDisposed) {
      throw StateError('MessageQueue is disposed');
    }

    final completer = Completer<void>();
    final item = QueuedMessage(
      data: data,
      completer: completer,
      priority: priority,
    );

    _queue.add(item);
    _processNext();

    return completer.future;
  }

  /// Get current queue length.
  int get length => _queue.length;

  /// Check if queue is empty.
  bool get isEmpty => _queue.isEmpty;

  /// Check if queue is processing.
  bool get isProcessing => _activeCount > 0;

  void _processNext() {
    if (_isDisposed) return;
    if (_activeCount >= concurrency) return;
    if (_queue.isEmpty) return;

    _activeCount++;

    // Sort by priority if needed (higher priority first)
    if (_queue.length > 1) {
      final list = _queue.toList();
      list.sort((a, b) => b.priority.compareTo(a.priority));
      _queue.clear();
      _queue.addAll(list);
    }

    final item = _queue.removeFirst();

    _processItem(item).then((_) {
      _activeCount--;
      _processNext();
    });
  }

  Future<void> _processItem(QueuedMessage<T> item) async {
    try {
      if (onProcess != null) {
        await onProcess!(item.data);
      }
      item.completer.complete();
    } catch (e, stackTrace) {
      debugPrint('MessageQueue: Error processing item: $e');
      debugPrint('Stack trace: $stackTrace');
      item.completer.completeError(e, stackTrace);
    }
  }

  /// Clear all pending messages.
  void clear() {
    for (final item in _queue) {
      item.completer.completeError(
        StateError('Queue cleared'),
      );
    }
    _queue.clear();
  }

  /// Dispose the queue.
  void dispose() {
    _isDisposed = true;
    clear();
  }
}
