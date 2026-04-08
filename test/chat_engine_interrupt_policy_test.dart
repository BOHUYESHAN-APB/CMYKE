import 'package:cmyke/core/services/chat_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sessionToolCancelGroup', () {
    test('uses explicit session id when present', () {
      expect(sessionToolCancelGroup('abc-123'), 'session:abc-123');
    });

    test('trims session id before formatting', () {
      expect(sessionToolCancelGroup('  room-7  '), 'session:room-7');
    });

    test('falls back to default when session id is null or blank', () {
      expect(sessionToolCancelGroup(null), 'session:default');
      expect(sessionToolCancelGroup(''), 'session:default');
      expect(sessionToolCancelGroup('   '), 'session:default');
    });
  });

  group('buildInterruptCoordination', () {
    test('keeps trimmed session id and derived cancel group aligned', () {
      final coordination = buildInterruptCoordination('  room-7  ');

      expect(coordination.sessionId, 'room-7');
      expect(coordination.cancelGroup, 'session:room-7');
      expect(
        coordination.cancelGroup,
        sessionToolCancelGroup(coordination.sessionId),
      );
      expect(coordination.reason, 'chat_interrupt');
      expect(coordination.traceId, startsWith('interrupt_'));
    });

    test('normalizes blank session id to default cancel group', () {
      final coordination = buildInterruptCoordination('   ');

      expect(coordination.sessionId, isNull);
      expect(coordination.cancelGroup, 'session:default');
      expect(
        coordination.cancelGroup,
        sessionToolCancelGroup(coordination.sessionId),
      );
      expect(coordination.reason, 'chat_interrupt');
      expect(coordination.traceId, startsWith('interrupt_'));
    });
  });
}
