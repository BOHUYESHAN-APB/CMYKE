import '../models/brain_contract.dart';
import 'chat_turn_decision.dart';

enum BrainRouteMode { leftOnly, directRightBrain }

class BrainRouteDecision {
  const BrainRouteDecision({required this.mode, required this.reason});

  final BrainRouteMode mode;
  final String reason;

  bool get usesRightBrain => mode == BrainRouteMode.directRightBrain;
}

class BrainRouter {
  const BrainRouter();

  BrainRouteDecision decide({
    required BrainContract contract,
    required ChatTurnDecision turnDecision,
    required String text,
    required bool hasAttachments,
  }) {
    switch (turnDecision.kind) {
      case ChatTurnDecisionKind.tool:
        return const BrainRouteDecision(
          mode: BrainRouteMode.directRightBrain,
          reason: 'tool_request',
        );
      case ChatTurnDecisionKind.agent:
        return const BrainRouteDecision(
          mode: BrainRouteMode.directRightBrain,
          reason: 'agent_request',
        );
      case ChatTurnDecisionKind.help:
      case ChatTurnDecisionKind.info:
        return const BrainRouteDecision(
          mode: BrainRouteMode.leftOnly,
          reason: 'local_command',
        );
      case ChatTurnDecisionKind.chat:
        break;
    }

    if (!contract.canEscalateToRightBrain) {
      return const BrainRouteDecision(
        mode: BrainRouteMode.leftOnly,
        reason: 'left_only_contract',
      );
    }

    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const BrainRouteDecision(
        mode: BrainRouteMode.leftOnly,
        reason: 'empty_turn',
      );
    }

    if (hasAttachments && !_looksAnalytical(normalized)) {
      return const BrainRouteDecision(
        mode: BrainRouteMode.leftOnly,
        reason: 'live_multimodal_turn',
      );
    }

    if (_looksAnalytical(normalized)) {
      return const BrainRouteDecision(
        mode: BrainRouteMode.directRightBrain,
        reason: 'analysis_request',
      );
    }

    return const BrainRouteDecision(
      mode: BrainRouteMode.leftOnly,
      reason: 'live_conversation',
    );
  }

  bool _looksAnalytical(String text) {
    if (text.length >= 120 || text.contains('\n')) {
      return true;
    }
    const keywords = <String>[
      '分析',
      '规划',
      '计划',
      '方案',
      '比较',
      '对比',
      '总结',
      '整理',
      '设计',
      '架构',
      '调研',
      '研究',
      '步骤',
      '实现',
      '优化',
      'analyze',
      'analysis',
      'plan',
      'compare',
      'design',
      'research',
      'implement',
    ];
    for (final keyword in keywords) {
      if (text.contains(keyword)) {
        return true;
      }
    }
    return false;
  }
}
