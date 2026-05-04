import 'dart:math';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:cmyke/core/models/danmaku_adapter_state.dart';
import 'package:cmyke/core/services/mock_danmaku_adapter.dart';

class _SequenceRandom implements Random {
  _SequenceRandom({required List<int> ints, List<double>? doubles})
      : _ints = Queue<int>.from(ints),
        _doubles = Queue<double>.from(doubles ?? const []);

  final Queue<int> _ints;
  final Queue<double> _doubles;

  @override
  int nextInt(int max) {
    if (_ints.isEmpty) {
      return 0;
    }
    final value = _ints.removeFirst();
    return value % max;
  }

  @override
  double nextDouble() {
    if (_doubles.isEmpty) {
      return 0.0;
    }
    return _doubles.removeFirst();
  }

  @override
  bool nextBool() => nextInt(2) == 0;
}

void main() {
  group('MockDanmakuAdapter', () {
    test('initializes with default config', () {
      final adapter = MockDanmakuAdapter();

      expect(adapter.state.phase, DanmakuAdapterPhase.idle);
      expect(adapter.isConnected, isFalse);
      expect(adapter.roomId, isNull);
    });

    test('generates danmaku, gift, and super chat events', () async {
      final adapter = MockDanmakuAdapter(
        eventInterval: const Duration(milliseconds: 10),
        connectDelay: Duration.zero,
        disconnectDelay: Duration.zero,
        random: _SequenceRandom(
          ints: [
            0, 0, 0, 0,
            80, 1, 1,
            95, 2, 2, 0,
          ],
          doubles: [0.25],
        ),
      );
      final outputs = <DanmakuAdapterOutput>[];
      final sub = adapter.outputs.listen(outputs.add);

      await adapter.connect(roomId: 12345);
      await Future<void>.delayed(const Duration(milliseconds: 35));

      await adapter.disconnect();
      await sub.cancel();
      await adapter.dispose();

      final eventOutputs = outputs.whereType<DanmakuEventOutput>().toList();
      expect(eventOutputs, hasLength(3));
      expect(eventOutputs[0].event['type'], 'danmaku');
      expect(eventOutputs[0].event['message'], '666');
      expect(eventOutputs[1].event['type'], 'gift');
      expect(eventOutputs[1].event['price'], 0.1);
      expect(eventOutputs[2].event['type'], 'superChat');
      expect(eventOutputs[2].event['price'], greaterThanOrEqualTo(10.0));
    });

    test('injectEvent emits a manual event while connected', () async {
      final adapter = MockDanmakuAdapter(
        autoGenerateEvents: false,
        connectDelay: Duration.zero,
        disconnectDelay: Duration.zero,
      );
      final outputs = <DanmakuAdapterOutput>[];
      final sub = adapter.outputs.listen(outputs.add);

      await adapter.connect(roomId: 67890);
      final event = {
        'type': 'danmaku',
        'roomId': 67890,
        'timestamp': '2026-01-01T00:00:00.000Z',
        'message': 'manual event',
      };
      adapter.injectEvent(event);

      await Future<void>.delayed(Duration.zero);

      expect(outputs.whereType<DanmakuEventOutput>().single.event, event);

      await adapter.disconnect();
      await sub.cancel();
      await adapter.dispose();
    });

    test('connect and disconnect transition through states', () async {
      final adapter = MockDanmakuAdapter(
        autoGenerateEvents: false,
        connectDelay: Duration.zero,
        disconnectDelay: Duration.zero,
      );
      final states = <DanmakuAdapterState>[];
      final sub = adapter.states.listen(states.add);

      final connected = adapter.connect(roomId: 24680);
      await Future<void>.delayed(Duration.zero);
      await connected;
      await Future<void>.delayed(Duration.zero);
      await adapter.disconnect();
      await Future<void>.delayed(Duration.zero);

      expect(
        states.map((state) => state.phase),
        containsAllInOrder([
          DanmakuAdapterPhase.connecting,
          DanmakuAdapterPhase.connected,
          DanmakuAdapterPhase.disconnecting,
          DanmakuAdapterPhase.disconnected,
        ]),
      );

      await sub.cancel();
      await adapter.dispose();
    });

    test('auto-generation timer stops after disconnect', () async {
      final adapter = MockDanmakuAdapter(
        eventInterval: const Duration(milliseconds: 10),
        connectDelay: Duration.zero,
        disconnectDelay: Duration.zero,
        random: _SequenceRandom(ints: [0, 0, 0, 0, 0, 0, 0, 0]),
      );
      final outputs = <DanmakuAdapterOutput>[];
      final sub = adapter.outputs.listen(outputs.add);

      await adapter.connect(roomId: 11223);
      await Future<void>.delayed(const Duration(milliseconds: 35));

      final beforeDisconnect = outputs.whereType<DanmakuEventOutput>().length;
      expect(beforeDisconnect, greaterThan(0));

      await adapter.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 35));

      final afterDisconnect = outputs.whereType<DanmakuEventOutput>().length;
      expect(afterDisconnect, beforeDisconnect);

      await sub.cancel();
      await adapter.dispose();
    });
  });
}
