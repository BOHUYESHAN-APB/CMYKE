import 'package:flutter_test/flutter_test.dart';

import 'package:cmyke/core/models/runtime_event.dart';
import 'package:cmyke/core/models/tool_intent.dart';
import 'package:cmyke/core/services/event_bus.dart';

void main() {
  group('RuntimeEventBus', () {
    test('emits typed tool intent and unified runtime envelope', () async {
      final bus = RuntimeEventBus();
      final typedIntents = <ToolIntent>[];
      final runtimeEvents = <RuntimeEventEnvelope<Object?>>[];

      final typedSub = bus.toolIntents.listen(typedIntents.add);
      final runtimeSub = bus.runtimeEvents.listen(runtimeEvents.add);

      final intent = ToolIntent(
        action: ToolAction.search,
        query: 'latest release notes',
        sessionId: 'sess-1',
        traceId: 'trace-1',
        cancelGroup: 'tool:sess-1',
      );

      bus.emitToolIntent(
        intent,
        source: RuntimeEventSource.controlAgent,
        priority: RuntimeEventPriority.high,
      );

      await Future<void>.delayed(Duration.zero);

      expect(typedIntents, hasLength(1));
      expect(typedIntents.single.query, 'latest release notes');

      final envelope = runtimeEvents.firstWhere(
        (event) => event.meta.kind == RuntimeEventKind.toolIntent,
      );
      expect(envelope.meta.source, RuntimeEventSource.controlAgent);
      expect(envelope.meta.priority, RuntimeEventPriority.high);
      expect(envelope.meta.sessionId, 'sess-1');
      expect(envelope.meta.traceId, 'trace-1');
      expect(envelope.meta.cancelGroup, 'tool:sess-1');
      expect(envelope.meta.attributes['interruptible'], isTrue);

      await typedSub.cancel();
      await runtimeSub.cancel();
      await bus.dispose();
    });

    test('emits interrupt start/end signals with unified metadata', () async {
      final bus = RuntimeEventBus();
      final signals = <RuntimeInterruptSignal>[];
      final runtimeEvents = <RuntimeEventEnvelope<Object?>>[];

      final signalSub = bus.interruptSignals.listen(signals.add);
      final runtimeSub = bus.runtimeEvents.listen(runtimeEvents.add);

      bus.emitInterruptStart(
        cancelGroup: 'chat:sess-2',
        reason: 'manual_stop',
        source: RuntimeEventSource.chatEngine,
        sessionId: 'sess-2',
        traceId: 'interrupt-1',
      );
      bus.emitInterruptEnd(
        cancelGroup: 'chat:sess-2',
        reason: 'manual_stop',
        source: RuntimeEventSource.chatEngine,
        sessionId: 'sess-2',
        traceId: 'interrupt-1',
      );

      await Future<void>.delayed(Duration.zero);

      expect(signals, hasLength(2));
      expect(signals.first.phase, RuntimeInterruptPhase.start);
      expect(signals.last.phase, RuntimeInterruptPhase.end);
      expect(signals.first.cancelGroup, 'chat:sess-2');

      final startEnvelope = runtimeEvents.firstWhere(
        (event) => event.meta.kind == RuntimeEventKind.interrupt,
      );
      final endEnvelope = runtimeEvents.firstWhere(
        (event) => event.meta.kind == RuntimeEventKind.interruptAck,
      );

      expect(startEnvelope.meta.priority, RuntimeEventPriority.critical);
      expect(endEnvelope.meta.priority, RuntimeEventPriority.high);
      expect(startEnvelope.meta.sessionId, 'sess-2');
      expect(endEnvelope.meta.traceId, 'interrupt-1');

      await signalSub.cancel();
      await runtimeSub.cancel();
      await bus.dispose();
    });

    test('emits runtime metrics with named attributes', () async {
      final bus = RuntimeEventBus();
      final runtimeEvents = <RuntimeEventEnvelope<Object?>>[];

      final runtimeSub = bus.runtimeEvents.listen(runtimeEvents.add);

      bus.emitRuntimeMetric(
        name: 'incremental_tts_queue',
        sessionId: 'sess-metric',
        traceId: 'trace-metric',
        attributes: {'phase': 'enqueue'},
        metrics: {'pendingChunkCount': 2, 'pendingCharCount': 24},
      );

      await Future<void>.delayed(Duration.zero);

      final envelope = runtimeEvents.firstWhere(
        (event) => event.meta.kind == RuntimeEventKind.runtimeMetric,
      );
      expect(envelope.meta.source, RuntimeEventSource.chatEngine);
      expect(envelope.meta.priority, RuntimeEventPriority.low);
      expect(envelope.meta.sessionId, 'sess-metric');
      expect(envelope.meta.traceId, 'trace-metric');
      expect(envelope.meta.attributes['name'], 'incremental_tts_queue');
      expect(envelope.meta.attributes['phase'], 'enqueue');
      expect(envelope.payload, {
        'pendingChunkCount': 2,
        'pendingCharCount': 24,
      });

      await runtimeSub.cancel();
      await bus.dispose();
    });
  });
}
