import 'package:cmyke/core/services/incremental_tts_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IncrementalTtsController', () {
    test('tracks queue metrics and playback readiness', () {
      final controller = IncrementalTtsController();

      controller.enqueueChunks(const ['你好', ' world ']);
      expect(controller.shouldStartPlayback(), isTrue);

      final metrics = controller.captureMetrics();
      expect(metrics.pendingChunkCount, 2);
      expect(metrics.pendingCharCount, 7);
      expect(metrics.maxPendingChunkCount, 2);
      expect(metrics.maxPendingCharCount, 7);
    });

    test(
      'normalizes blank chunks and finalization bypasses prebuffer wait',
      () {
        final controller = IncrementalTtsController();

        controller.enqueueChunks(const ['   ', 'hi']);
        expect(controller.shouldStartPlayback(), isFalse);

        controller.requestFinalize();
        expect(controller.shouldStartPlayback(), isTrue);
        expect(controller.takeNextChunk(), 'hi');
        expect(controller.takeNextChunk(), isNull);
      },
    );
  });

  group('buildIncrementalTtsQueueMetrics', () {
    test('counts non-blank chunks and tracks maxima', () {
      final metrics = buildIncrementalTtsQueueMetrics(
        pendingChunks: const ['你好', '   ', ' world  '],
        streamedRequestCount: 2,
        streamedAudioChunkCount: 5,
        previousMaxPendingChunkCount: 1,
        previousMaxPendingCharCount: 3,
      );

      expect(metrics.pendingChunkCount, 2);
      expect(metrics.pendingCharCount, 7);
      expect(metrics.streamedRequestCount, 2);
      expect(metrics.streamedAudioChunkCount, 5);
      expect(metrics.maxPendingChunkCount, 2);
      expect(metrics.maxPendingCharCount, 7);
    });
  });

  group('shouldStartIncrementalTtsPlayback', () {
    IncrementalTtsQueueMetrics metrics({
      int pendingChunkCount = 0,
      int pendingCharCount = 0,
    }) {
      return IncrementalTtsQueueMetrics(
        pendingChunkCount: pendingChunkCount,
        pendingCharCount: pendingCharCount,
        streamedRequestCount: 0,
        streamedAudioChunkCount: 0,
        maxPendingChunkCount: pendingChunkCount,
        maxPendingCharCount: pendingCharCount,
      );
    }

    test('waits for prebuffer when playback has not started', () {
      expect(
        shouldStartIncrementalTtsPlayback(
          started: false,
          finalize: false,
          metrics: metrics(pendingChunkCount: 1, pendingCharCount: 10),
        ),
        isFalse,
      );
    });

    test('starts once chunk or char threshold is satisfied', () {
      expect(
        shouldStartIncrementalTtsPlayback(
          started: false,
          finalize: false,
          metrics: metrics(pendingChunkCount: 2, pendingCharCount: 10),
        ),
        isTrue,
      );
      expect(
        shouldStartIncrementalTtsPlayback(
          started: false,
          finalize: false,
          metrics: metrics(pendingChunkCount: 1, pendingCharCount: 24),
        ),
        isTrue,
      );
    });

    test('starts immediately when finalizing or already started', () {
      expect(
        shouldStartIncrementalTtsPlayback(
          started: false,
          finalize: true,
          metrics: metrics(pendingChunkCount: 1, pendingCharCount: 5),
        ),
        isTrue,
      );
      expect(
        shouldStartIncrementalTtsPlayback(
          started: true,
          finalize: false,
          metrics: metrics(),
        ),
        isTrue,
      );
    });
  });
}
