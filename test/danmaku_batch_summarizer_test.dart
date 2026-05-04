import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cmyke/core/services/danmaku_batch_summarizer.dart';
import 'package:cmyke/core/services/mock_danmaku_adapter.dart';

void main() {
  group('DanmakuBatchSummarizer', () {
    test('collects batches and emits periodically', () async {
      FakeAsync().run((async) {
        final adapter = MockDanmakuAdapter(
          autoGenerateEvents: false,
          connectDelay: Duration.zero,
          disconnectDelay: Duration.zero,
        );
        final summarizer = DanmakuBatchSummarizer(
          adapter: adapter,
          config: const BatchSummarizerConfig(intervalSeconds: 1, batchSize: 10),
        );
        final summaries = <DanmakuBatchSummary>[];
        final sub = summarizer.summaries.listen(summaries.add);

        summarizer.start();
        final connectFuture = adapter.connect(roomId: 10001);
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(connectFuture, completes);
        adapter.injectEvent({
          'type': 'danmaku',
          'roomId': 10001,
          'message': 'one',
        });
        adapter.injectEvent({
          'type': 'gift',
          'roomId': 10001,
          'message': 'two',
        });

        async.flushMicrotasks();
        expect(summaries, isEmpty);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(summaries, hasLength(1));
        expect(summaries.single.items, hasLength(2));
        expect(summaries.single.droppedCount, 0);
        expect(summaries.single.totalCount, 2);

        summarizer.dispose();
        sub.cancel();
        adapter.dispose();
      });
    });

    test('caps batch size and tracks dropped count', () async {
      final adapter = MockDanmakuAdapter(
        autoGenerateEvents: false,
        connectDelay: Duration.zero,
        disconnectDelay: Duration.zero,
      );
      final summarizer = DanmakuBatchSummarizer(
        adapter: adapter,
        config: const BatchSummarizerConfig(intervalSeconds: 1, batchSize: 2),
      );
      final summaries = <DanmakuBatchSummary>[];
      final sub = summarizer.summaries.listen(summaries.add);

      summarizer.start();
      await adapter.connect(roomId: 10002);
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 4; i++) {
        adapter.injectEvent({
          'type': 'danmaku',
          'roomId': 10002,
          'message': 'event $i',
        });
      }

      await Future<void>.delayed(Duration.zero);
      summarizer.flush();
      await Future<void>.delayed(Duration.zero);

      expect(summaries, hasLength(1));
      expect(summaries.single.items, hasLength(2));
      expect(summaries.single.droppedCount, 2);
      expect(summaries.single.totalCount, 4);
      expect(summarizer.bufferSize, 0);
      expect(summarizer.droppedCount, 0);

      await summarizer.dispose();
      await sub.cancel();
      await adapter.dispose();
    });

    test('flush emits buffered events and clears state', () async {
      final adapter = MockDanmakuAdapter(
        autoGenerateEvents: false,
        connectDelay: Duration.zero,
        disconnectDelay: Duration.zero,
      );
      final summarizer = DanmakuBatchSummarizer(adapter: adapter);
      final summaries = <DanmakuBatchSummary>[];
      final sub = summarizer.summaries.listen(summaries.add);

      summarizer.start();
      await adapter.connect(roomId: 10003);
      await Future<void>.delayed(Duration.zero);
      adapter.injectEvent({
        'type': 'danmaku',
        'roomId': 10003,
        'message': 'flush me',
      });

      await Future<void>.delayed(Duration.zero);
      summarizer.flush();
      await Future<void>.delayed(Duration.zero);

      expect(summaries, hasLength(1));
      expect(summarizer.bufferSize, 0);
      expect(summarizer.droppedCount, 0);

      await summarizer.dispose();
      await sub.cancel();
      await adapter.dispose();
    });

    test('flush with empty buffer does nothing', () async {
      final adapter = MockDanmakuAdapter(autoGenerateEvents: false);
      final summarizer = DanmakuBatchSummarizer(adapter: adapter);
      final summaries = <DanmakuBatchSummary>[];
      final sub = summarizer.summaries.listen(summaries.add);

      summarizer.start();
      summarizer.flush();
      await Future<void>.delayed(Duration.zero);

      expect(summaries, isEmpty);
      expect(summarizer.bufferSize, 0);
      expect(summarizer.droppedCount, 0);

      await summarizer.dispose();
      await sub.cancel();
      await adapter.dispose();
    });

    test('disabled config prevents start', () async {
      final adapter = MockDanmakuAdapter(
        autoGenerateEvents: false,
        connectDelay: Duration.zero,
        disconnectDelay: Duration.zero,
      );
      final summarizer = DanmakuBatchSummarizer(
        adapter: adapter,
        config: const BatchSummarizerConfig(enabled: false),
      );
      final summaries = <DanmakuBatchSummary>[];
      final sub = summarizer.summaries.listen(summaries.add);

      summarizer.start();
      await adapter.connect(roomId: 10004);
      await Future<void>.delayed(Duration.zero);
      adapter.injectEvent({
        'type': 'danmaku',
        'roomId': 10004,
        'message': 'ignored',
      });
      summarizer.flush();
      await Future<void>.delayed(Duration.zero);

      expect(summaries, isEmpty);
      expect(summarizer.bufferSize, 0);

      await summarizer.dispose();
      await sub.cancel();
      await adapter.dispose();
    });
  });
}
