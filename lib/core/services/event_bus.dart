import 'dart:async';

import '../models/expression_event.dart';
import '../models/lipsync_frame.dart';
import '../models/research_job.dart';
import '../models/stage_action.dart';
import '../models/tool_intent.dart';

class RuntimeEventBus {
  final _expressionController = StreamController<ExpressionEvent>.broadcast();
  final _stageActionController = StreamController<StageAction>.broadcast();
  final _lipSyncController = StreamController<LipSyncFrame>.broadcast();
  final _toolIntentController = StreamController<ToolIntent>.broadcast();
  final _researchJobController = StreamController<ResearchJob>.broadcast();

  Stream<ExpressionEvent> get expressions => _expressionController.stream;
  Stream<StageAction> get stageActions => _stageActionController.stream;
  Stream<LipSyncFrame> get lipSyncFrames => _lipSyncController.stream;
  Stream<ToolIntent> get toolIntents => _toolIntentController.stream;
  Stream<ResearchJob> get researchJobs => _researchJobController.stream;

  void emitExpression(ExpressionEvent event) =>
      _expressionController.add(event);

  void emitStageAction(StageAction event) => _stageActionController.add(event);

  void emitLipSync(LipSyncFrame frame) => _lipSyncController.add(frame);

  void emitToolIntent(ToolIntent intent) => _toolIntentController.add(intent);

  void emitResearchJob(ResearchJob job) => _researchJobController.add(job);

  Future<void> dispose() async {
    await Future.wait([
      _expressionController.close(),
      _stageActionController.close(),
      _lipSyncController.close(),
      _toolIntentController.close(),
      _researchJobController.close(),
    ]);
  }
}
