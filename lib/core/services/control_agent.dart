import '../models/expression_event.dart';
import '../models/research_job.dart';
import '../models/runtime_event.dart';
import '../models/stage_action.dart';
import '../models/tool_intent.dart';
import 'chat_turn_decision.dart';
import 'event_bus.dart';
import 'tool_router.dart';

/// Control/Planner agent stub:
/// - Emits expression/stage events to the runtime bus.
/// - Dispatches tool intents and research jobs via ToolRouter.
class ControlAgent {
  ControlAgent({required RuntimeEventBus bus, required ToolRouter toolRouter})
    : _bus = bus,
      _toolRouter = toolRouter;

  final RuntimeEventBus _bus;
  final ToolRouter _toolRouter;
  final ChatTurnDecisionEngine _turnDecisionEngine =
      const ChatTurnDecisionEngine();

  ChatTurnDecision decideTurn(String text) => _turnDecisionEngine.decide(text);

  RuntimeEventPriority _priorityFromUrgency(IntentUrgency urgency) {
    switch (urgency) {
      case IntentUrgency.high:
        return RuntimeEventPriority.high;
      case IntentUrgency.normal:
        return RuntimeEventPriority.normal;
      case IntentUrgency.low:
        return RuntimeEventPriority.low;
    }
  }

  Future<void> emitExpression(ExpressionEvent event) async {
    _bus.emitExpression(
      event,
      source: RuntimeEventSource.controlAgent,
      priority: RuntimeEventPriority.normal,
    );
  }

  Future<void> emitStageAction(StageAction action) async {
    _bus.emitStageAction(
      action,
      source: RuntimeEventSource.controlAgent,
      priority: RuntimeEventPriority.normal,
    );
  }

  Future<void> emitLipSyncWeights(Map<String, double> weights) async {
    // optional: future extension to translate to LipSyncFrame
  }

  Future<String> dispatchToolIntent(ToolIntent intent) {
    _bus.emitToolIntent(
      intent,
      source: RuntimeEventSource.controlAgent,
      priority: _priorityFromUrgency(intent.urgency),
      sessionId: intent.sessionId,
      traceId: intent.traceId,
      cancelGroup: intent.cancelGroup,
    );
    return _toolRouter.dispatch(intent);
  }

  Future<void> dispatchResearchJob(ResearchJob job) async {
    _bus.emitResearchJob(
      job,
      source: RuntimeEventSource.controlAgent,
      priority: RuntimeEventPriority.normal,
    );
    // TODO: wire to research pipeline; for now just emit.
  }

  Future<void> emitInterruptStart({
    required String cancelGroup,
    String? reason,
    String? sessionId,
    String? traceId,
  }) async {
    _bus.emitInterruptStart(
      cancelGroup: cancelGroup,
      reason: reason,
      source: RuntimeEventSource.controlAgent,
      sessionId: sessionId,
      traceId: traceId,
    );
  }

  Future<void> emitInterruptEnd({
    required String cancelGroup,
    String? reason,
    String? sessionId,
    String? traceId,
  }) async {
    _bus.emitInterruptEnd(
      cancelGroup: cancelGroup,
      reason: reason,
      source: RuntimeEventSource.controlAgent,
      sessionId: sessionId,
      traceId: traceId,
    );
  }
}
