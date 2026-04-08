import 'package:flutter_test/flutter_test.dart';

import 'package:cmyke/core/services/runtime_event_arbitrator.dart';

void main() {
  group('RuntimeEventArbitrator', () {
    test('dequeues by lane priority then FIFO sequence', () {
      final arbitrator = RuntimeEventArbitrator(maxPending: 16);
      final now = DateTime(2026, 1, 1, 10, 0, 0);

      arbitrator.enqueue<String>(
        id: 'danmaku-1',
        lane: RuntimeArbitrationLane.danmaku,
        payload: 'd1',
        now: now,
      );
      arbitrator.enqueue<String>(
        id: 'voice-1',
        lane: RuntimeArbitrationLane.voice,
        payload: 'v1',
        now: now,
      );
      arbitrator.enqueue<String>(
        id: 'voice-2',
        lane: RuntimeArbitrationLane.voice,
        payload: 'v2',
        now: now,
      );

      final first = arbitrator.dequeueReady(now: now);
      final second = arbitrator.dequeueReady(now: now);
      final third = arbitrator.dequeueReady(now: now);

      expect(first?.id, 'voice-1');
      expect(second?.id, 'voice-2');
      expect(third?.id, 'danmaku-1');
    });

    test('respects notBefore scheduling', () {
      final arbitrator = RuntimeEventArbitrator(maxPending: 16);
      final now = DateTime(2026, 1, 1, 10, 0, 0);

      arbitrator.enqueue<String>(
        id: 'voice-later',
        lane: RuntimeArbitrationLane.voice,
        payload: 'v-later',
        now: now,
        notBefore: now.add(const Duration(seconds: 1)),
      );
      arbitrator.enqueue<String>(
        id: 'chat-now',
        lane: RuntimeArbitrationLane.chat,
        payload: 'c-now',
        now: now,
      );

      final first = arbitrator.dequeueReady(now: now);
      final second = arbitrator.dequeueReady(now: now);
      final third = arbitrator.dequeueReady(
        now: now.add(const Duration(seconds: 1)),
      );

      expect(first?.id, 'chat-now');
      expect(second, isNull);
      expect(third?.id, 'voice-later');
    });

    test('drops lower-priority task when full', () {
      final arbitrator = RuntimeEventArbitrator(maxPending: 2);
      final now = DateTime(2026, 1, 1, 10, 0, 0);

      arbitrator.enqueue<String>(
        id: 'danmaku-1',
        lane: RuntimeArbitrationLane.danmaku,
        payload: 'd1',
        now: now,
      );
      arbitrator.enqueue<String>(
        id: 'proactive-1',
        lane: RuntimeArbitrationLane.proactive,
        payload: 'p1',
        now: now,
      );

      final accepted = arbitrator.enqueue<String>(
        id: 'voice-1',
        lane: RuntimeArbitrationLane.voice,
        payload: 'v1',
        now: now,
      );

      expect(accepted, isTrue);
      expect(arbitrator.pendingCount, 2);

      final first = arbitrator.dequeueReady(now: now);
      final second = arbitrator.dequeueReady(now: now);

      expect(first?.id, 'voice-1');
      expect(second?.id, 'proactive-1');
    });
  });
}
