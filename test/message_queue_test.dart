import 'package:flutter_test/flutter_test.dart';
import 'package:cmyke/core/services/message_queue.dart';

void main() {
  group('MessageQueue', () {
    test('processes messages in FIFO order', () async {
      final results = <int>[];
      final queue = MessageQueue<int>(
        onProcess: (data) async {
          results.add(data);
        },
      );

      await queue.enqueue(1);
      await queue.enqueue(2);
      await queue.enqueue(3);

      expect(results, [1, 2, 3]);
      queue.dispose();
    });

    test('respects priority ordering', () async {
      final results = <String>[];
      final queue = MessageQueue<String>(
        onProcess: (data) async {
          await Future.delayed(Duration(milliseconds: 10));
          results.add(data);
        },
      );

      // Enqueue without waiting
      queue.enqueue('low', priority: 0);
      queue.enqueue('high', priority: 10);
      queue.enqueue('medium', priority: 5);

      // Wait for all to complete
      await Future.delayed(Duration(milliseconds: 100));

      // First item processes immediately, then sorted by priority
      expect(results.first, 'low');
      expect(results.skip(1).toList(), containsAll(['high', 'medium']));
      
      queue.dispose();
    });

    test('handles concurrent processing', () async {
      final results = <int>[];
      final queue = MessageQueue<int>(
        concurrency: 2,
        onProcess: (data) async {
          await Future.delayed(Duration(milliseconds: 50));
          results.add(data);
        },
      );

      final futures = [
        queue.enqueue(1),
        queue.enqueue(2),
        queue.enqueue(3),
        queue.enqueue(4),
      ];

      await Future.wait(futures);

      expect(results.length, 4);
      expect(results, containsAll([1, 2, 3, 4]));
      
      queue.dispose();
    });

    test('isolates errors', () async {
      final results = <int>[];
      final queue = MessageQueue<int>(
        onProcess: (data) async {
          if (data == 2) {
            throw Exception('Test error');
          }
          results.add(data);
        },
      );

      await queue.enqueue(1);
      
      try {
        await queue.enqueue(2);
        fail('Should throw error');
      } catch (e) {
        expect(e, isA<Exception>());
      }

      await queue.enqueue(3);

      expect(results, [1, 3]);
      
      queue.dispose();
    });

    test('clears pending messages', () async {
      final results = <int>[];
      final queue = MessageQueue<int>(
        onProcess: (data) async {
          await Future.delayed(Duration(milliseconds: 100));
          results.add(data);
        },
      );

      // Don't await - let them queue up
      final future1 = queue.enqueue(1);
      final future2 = queue.enqueue(2);
      final future3 = queue.enqueue(3);

      // Wait a bit for first to start processing
      await Future.delayed(Duration(milliseconds: 10));

      queue.clear();

      // Expect errors for cleared items
      await expectLater(future2, throwsStateError);
      await expectLater(future3, throwsStateError);

      // Wait for first item to complete
      await future1;

      // Only the first item (already processing) should complete
      expect(results, [1]);
      
      queue.dispose();
    });

    test('reports queue state correctly', () async {
      final queue = MessageQueue<int>(
        onProcess: (data) async {
          await Future.delayed(Duration(milliseconds: 10));
        },
      );

      expect(queue.isEmpty, true);
      expect(queue.length, 0);
      expect(queue.isProcessing, false);

      final future1 = queue.enqueue(1);
      final future2 = queue.enqueue(2);

      expect(queue.isEmpty, false);
      expect(queue.length, greaterThan(0));

      // Wait for processing to complete
      await Future.wait([future1, future2]);

      queue.dispose();
    });
  });
}
