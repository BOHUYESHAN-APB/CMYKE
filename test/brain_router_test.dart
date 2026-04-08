import 'package:cmyke/core/models/app_settings.dart';
import 'package:cmyke/core/models/brain_contract.dart';
import 'package:cmyke/core/models/brain_reintegration.dart';
import 'package:cmyke/core/services/brain_router.dart';
import 'package:cmyke/core/services/chat_turn_decision.dart';
import 'package:cmyke/core/models/tool_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const router = BrainRouter();

  BrainContract contract({
    ModelRoute route = ModelRoute.omni,
    String? llmProviderId = 'llm-1',
    String? omniProviderId = 'omni-1',
  }) {
    return BrainContract.fromSettings(
      AppSettings(
        route: route,
        llmProviderId: llmProviderId,
        omniProviderId: omniProviderId,
      ),
    );
  }

  group('BrainRouter', () {
    test('keeps casual omni chat on the left brain', () {
      final decision = router.decide(
        contract: contract(),
        turnDecision: const ChatTurnDecision.chat(),
        text: '你今天怎么样',
        hasAttachments: false,
      );

      expect(decision.mode, BrainRouteMode.leftOnly);
      expect(decision.reason, 'live_conversation');
    });

    test('escalates analytical omni chat to the right brain', () {
      final decision = router.decide(
        contract: contract(),
        turnDecision: const ChatTurnDecision.chat(),
        text: '请帮我分析当前系统架构并给出三步优化计划',
        hasAttachments: false,
      );

      expect(decision.mode, BrainRouteMode.directRightBrain);
      expect(decision.reason, 'analysis_request');
    });

    test('keeps standard route in left-only contract mode', () {
      final decision = router.decide(
        contract: contract(route: ModelRoute.standard, omniProviderId: null),
        turnDecision: const ChatTurnDecision.chat(),
        text: '请帮我分析当前系统架构并给出三步优化计划',
        hasAttachments: false,
      );

      expect(decision.mode, BrainRouteMode.leftOnly);
      expect(decision.reason, 'left_only_contract');
    });

    test('routes tool requests to the right brain path', () {
      final decision = router.decide(
        contract: contract(),
        turnDecision: const ChatTurnDecision.tool(
          toolCommand: ChatToolCommand(action: ToolAction.code, query: 'test'),
        ),
        text: '/tool code test',
        hasAttachments: false,
      );

      expect(decision.mode, BrainRouteMode.directRightBrain);
      expect(decision.reason, 'tool_request');
    });

    test('keeps ordinary multimodal turns on the left brain', () {
      final decision = router.decide(
        contract: contract(),
        turnDecision: const ChatTurnDecision.chat(),
        text: '看看这张图像不像我现在的直播封面',
        hasAttachments: true,
      );

      expect(decision.mode, BrainRouteMode.leftOnly);
      expect(decision.reason, 'live_multimodal_turn');
    });

    test(
      'brain reintegration state copyWith updates phase and keeps reason',
      () {
        const state = BrainReintegrationState(
          phase: BrainReintegrationPhase.escalating,
          reason: 'analysis_request',
          providerId: 'llm-1',
        );

        final next = state.copyWith(phase: BrainReintegrationPhase.waiting);

        expect(next.phase, BrainReintegrationPhase.waiting);
        expect(next.reason, 'analysis_request');
        expect(next.providerId, 'llm-1');
        expect(next.isActive, isTrue);
        expect(const BrainReintegrationState.idle().isActive, isFalse);
      },
    );
  });
}
