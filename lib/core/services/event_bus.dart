import 'dart:async';

import '../models/danmaku_event.dart';
import '../models/expression_event.dart';
import '../models/lipsync_frame.dart';
import '../models/research_job.dart';
import '../models/runtime_event.dart';
import '../models/stage_action.dart';
import '../models/tool_intent.dart';
import '../models/voice_transcript_event.dart';

class RuntimeEventBus {
  final _expressionController = StreamController<ExpressionEvent>.broadcast();
  final _stageActionController = StreamController<StageAction>.broadcast();
  final _lipSyncController = StreamController<LipSyncFrame>.broadcast();
  final _toolIntentController = StreamController<ToolIntent>.broadcast();
  final _researchJobController = StreamController<ResearchJob>.broadcast();
  final _voiceTranscriptController =
      StreamController<VoiceTranscriptEvent>.broadcast();
  final _danmakuController = StreamController<DanmakuEvent>.broadcast();
  final _interruptController =
      StreamController<RuntimeInterruptSignal>.broadcast();
  final _runtimeEventController =
      StreamController<RuntimeEventEnvelope<Object?>>.broadcast();
  int _eventSeq = 0;

  Stream<ExpressionEvent> get expressions => _expressionController.stream;
  Stream<StageAction> get stageActions => _stageActionController.stream;
  Stream<LipSyncFrame> get lipSyncFrames => _lipSyncController.stream;
  Stream<ToolIntent> get toolIntents => _toolIntentController.stream;
  Stream<ResearchJob> get researchJobs => _researchJobController.stream;
  Stream<VoiceTranscriptEvent> get voiceTranscripts =>
      _voiceTranscriptController.stream;
  Stream<DanmakuEvent> get danmakuEvents => _danmakuController.stream;
  Stream<RuntimeInterruptSignal> get interruptSignals =>
      _interruptController.stream;
  Stream<RuntimeEventEnvelope<Object?>> get runtimeEvents =>
      _runtimeEventController.stream;

  String _nextEventId(RuntimeEventKind kind) {
    _eventSeq += 1;
    return 'evt_${DateTime.now().microsecondsSinceEpoch}_${kind.name}_$_eventSeq';
  }

  void _publish<T>({
    required RuntimeEventKind kind,
    required RuntimeEventSource source,
    required RuntimeEventPriority priority,
    required T payload,
    String? sessionId,
    String? traceId,
    String? cancelGroup,
    Map<String, Object?> attributes = const {},
  }) {
    _runtimeEventController.add(
      RuntimeEventEnvelope<Object?>(
        meta: RuntimeEventMeta(
          id: _nextEventId(kind),
          kind: kind,
          source: source,
          priority: priority,
          createdAt: DateTime.now(),
          sessionId: sessionId,
          traceId: traceId,
          cancelGroup: cancelGroup,
          attributes: attributes,
        ),
        payload: payload,
      ),
    );
  }

  void emitExpression(
    ExpressionEvent event, {
    RuntimeEventSource source = RuntimeEventSource.controlAgent,
    RuntimeEventPriority priority = RuntimeEventPriority.normal,
    String? sessionId,
    String? traceId,
    String? cancelGroup,
  }) {
    _expressionController.add(event);
    _publish(
      kind: RuntimeEventKind.expression,
      source: source,
      priority: priority,
      payload: event,
      sessionId: sessionId,
      traceId: traceId,
      cancelGroup: cancelGroup,
    );
  }

  void emitStageAction(
    StageAction event, {
    RuntimeEventSource source = RuntimeEventSource.controlAgent,
    RuntimeEventPriority priority = RuntimeEventPriority.normal,
    String? sessionId,
    String? traceId,
    String? cancelGroup,
  }) {
    _stageActionController.add(event);
    _publish(
      kind: RuntimeEventKind.stageAction,
      source: source,
      priority: priority,
      payload: event,
      sessionId: sessionId,
      traceId: traceId,
      cancelGroup: cancelGroup,
    );
  }

  void emitLipSync(
    LipSyncFrame frame, {
    RuntimeEventSource source = RuntimeEventSource.chatEngine,
    RuntimeEventPriority priority = RuntimeEventPriority.low,
    String? sessionId,
    String? traceId,
    String? cancelGroup,
  }) {
    _lipSyncController.add(frame);
    _publish(
      kind: RuntimeEventKind.lipSync,
      source: source,
      priority: priority,
      payload: frame,
      sessionId: sessionId,
      traceId: traceId,
      cancelGroup: cancelGroup,
    );
  }

  void emitToolIntent(
    ToolIntent intent, {
    RuntimeEventSource source = RuntimeEventSource.controlAgent,
    RuntimeEventPriority priority = RuntimeEventPriority.normal,
    String? sessionId,
    String? traceId,
    String? cancelGroup,
  }) {
    _toolIntentController.add(intent);
    _publish(
      kind: RuntimeEventKind.toolIntent,
      source: source,
      priority: priority,
      payload: intent,
      sessionId: sessionId ?? intent.sessionId,
      traceId: traceId ?? intent.traceId,
      cancelGroup: cancelGroup ?? intent.cancelGroup,
      attributes: {'interruptible': intent.interruptible},
    );
  }

  void emitResearchJob(
    ResearchJob job, {
    RuntimeEventSource source = RuntimeEventSource.controlAgent,
    RuntimeEventPriority priority = RuntimeEventPriority.normal,
    String? sessionId,
    String? traceId,
    String? cancelGroup,
  }) {
    _researchJobController.add(job);
    _publish(
      kind: RuntimeEventKind.researchJob,
      source: source,
      priority: priority,
      payload: job,
      sessionId: sessionId,
      traceId: traceId,
      cancelGroup: cancelGroup,
    );
  }

  void emitRuntimeMetric({
    required String name,
    required Map<String, Object?> metrics,
    Map<String, Object?> attributes = const {},
    RuntimeEventSource source = RuntimeEventSource.chatEngine,
    RuntimeEventPriority priority = RuntimeEventPriority.low,
    String? sessionId,
    String? traceId,
    String? cancelGroup,
  }) {
    _publish(
      kind: RuntimeEventKind.runtimeMetric,
      source: source,
      priority: priority,
      payload: metrics,
      sessionId: sessionId,
      traceId: traceId,
      cancelGroup: cancelGroup,
      attributes: {'name': name, ...attributes},
    );
  }

  void emitVoiceTranscript(
    VoiceTranscriptEvent event, {
    RuntimeEventSource source = RuntimeEventSource.voiceChannel,
    RuntimeEventPriority priority = RuntimeEventPriority.high,
    String? sessionId,
    String? traceId,
    String? cancelGroup,
  }) {
    _voiceTranscriptController.add(event);
    _publish(
      kind: RuntimeEventKind.voiceTranscript,
      source: source,
      priority: priority,
      payload: event,
      sessionId: sessionId,
      traceId: traceId,
      cancelGroup: cancelGroup,
    );
  }

  void emitDanmaku(
    DanmakuEvent event, {
    RuntimeEventSource source = RuntimeEventSource.danmaku,
    RuntimeEventPriority priority = RuntimeEventPriority.low,
    String? sessionId,
    String? traceId,
    String? cancelGroup,
  }) {
    _danmakuController.add(event);
    _publish(
      kind: RuntimeEventKind.danmaku,
      source: source,
      priority: priority,
      payload: event,
      sessionId: sessionId,
      traceId: traceId,
      cancelGroup: cancelGroup,
    );
  }

  void emitInterruptStart({
    required String cancelGroup,
    String? reason,
    RuntimeEventSource source = RuntimeEventSource.system,
    String? sessionId,
    String? traceId,
  }) {
    final signal = RuntimeInterruptSignal(
      phase: RuntimeInterruptPhase.start,
      cancelGroup: cancelGroup,
      reason: reason,
    );
    _interruptController.add(signal);
    _publish(
      kind: RuntimeEventKind.interrupt,
      source: source,
      priority: RuntimeEventPriority.critical,
      payload: signal,
      sessionId: sessionId,
      traceId: traceId,
      cancelGroup: cancelGroup,
    );
  }

  void emitInterruptEnd({
    required String cancelGroup,
    String? reason,
    RuntimeEventSource source = RuntimeEventSource.system,
    String? sessionId,
    String? traceId,
  }) {
    final signal = RuntimeInterruptSignal(
      phase: RuntimeInterruptPhase.end,
      cancelGroup: cancelGroup,
      reason: reason,
    );
    _interruptController.add(signal);
    _publish(
      kind: RuntimeEventKind.interruptAck,
      source: source,
      priority: RuntimeEventPriority.high,
      payload: signal,
      sessionId: sessionId,
      traceId: traceId,
      cancelGroup: cancelGroup,
    );
  }

  Future<void> dispose() async {
    await Future.wait([
      _expressionController.close(),
      _stageActionController.close(),
      _lipSyncController.close(),
      _toolIntentController.close(),
      _researchJobController.close(),
      _voiceTranscriptController.close(),
      _danmakuController.close(),
      _interruptController.close(),
      _runtimeEventController.close(),
    ]);
  }
}
