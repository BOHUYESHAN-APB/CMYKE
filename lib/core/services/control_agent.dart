import '../models/expression_event.dart';
import '../models/research_job.dart';
import '../models/stage_action.dart';
import '../models/tool_intent.dart';
import 'event_bus.dart';
import 'tool_router.dart';

/// Control/Planner agent stub:
/// - Emits expression/stage events to the runtime bus.
/// - Dispatches tool intents and research jobs via ToolRouter.
class ControlAgent {
  ControlAgent({
    required RuntimeEventBus bus,
    required ToolRouter toolRouter,
  })  : _bus = bus,
        _toolRouter = toolRouter;

  final RuntimeEventBus _bus;
  final ToolRouter _toolRouter;

  Future<void> emitExpression(ExpressionEvent event) async {
    _bus.emitExpression(event);
  }

  Future<void> emitStageAction(StageAction action) async {
    _bus.emitStageAction(action);
  }

  Future<void> emitLipSyncWeights(Map<String, double> weights) async {
    // optional: future extension to translate to LipSyncFrame
  }

  Future<String> dispatchToolIntent(ToolIntent intent) {
    _bus.emitToolIntent(intent);
    return _toolRouter.dispatch(intent);
  }

  Future<void> dispatchResearchJob(ResearchJob job) async {
    _bus.emitResearchJob(job);
    // TODO: wire to research pipeline; for now just emit.
  }
}
