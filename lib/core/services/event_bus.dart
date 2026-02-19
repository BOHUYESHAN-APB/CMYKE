import 'dart:async';

import '../models/danmaku_event.dart';
import '../models/expression_event.dart';
import '../models/lipsync_frame.dart';
import '../models/research_job.dart';
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

  Stream<ExpressionEvent> get expressions => _expressionController.stream;
  Stream<StageAction> get stageActions => _stageActionController.stream;
  Stream<LipSyncFrame> get lipSyncFrames => _lipSyncController.stream;
  Stream<ToolIntent> get toolIntents => _toolIntentController.stream;
  Stream<ResearchJob> get researchJobs => _researchJobController.stream;
  Stream<VoiceTranscriptEvent> get voiceTranscripts =>
      _voiceTranscriptController.stream;
  Stream<DanmakuEvent> get danmakuEvents => _danmakuController.stream;

  void emitExpression(ExpressionEvent event) =>
      _expressionController.add(event);

  void emitStageAction(StageAction event) => _stageActionController.add(event);

  void emitLipSync(LipSyncFrame frame) => _lipSyncController.add(frame);

  void emitToolIntent(ToolIntent intent) => _toolIntentController.add(intent);

  void emitResearchJob(ResearchJob job) => _researchJobController.add(job);

  void emitVoiceTranscript(VoiceTranscriptEvent event) =>
      _voiceTranscriptController.add(event);

  void emitDanmaku(DanmakuEvent event) => _danmakuController.add(event);

  Future<void> dispose() async {
    await Future.wait([
      _expressionController.close(),
      _stageActionController.close(),
      _lipSyncController.close(),
      _toolIntentController.close(),
      _researchJobController.close(),
      _voiceTranscriptController.close(),
      _danmakuController.close(),
    ]);
  }
}
