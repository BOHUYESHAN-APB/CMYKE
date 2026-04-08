import 'package:cmyke/core/models/research_job.dart';
import 'package:cmyke/core/models/tool_intent.dart';
import 'package:cmyke/core/services/chat_turn_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatTurnDecisionEngine', () {
    const engine = ChatTurnDecisionEngine();

    test('routes slash help and info commands', () {
      final help = engine.decide('/help tool');
      expect(help.kind, ChatTurnDecisionKind.help);
      expect(help.helpTopic, 'tool');
      expect(help.isCommand, isTrue);

      final info = engine.decide('/agents');
      expect(info.kind, ChatTurnDecisionKind.help);
      expect(info.helpTopic, 'agents');
    });

    test('routes tool commands with parsed action and help fallback', () {
      final tool = engine.decide('/tool search Neuro-sama');
      expect(tool.kind, ChatTurnDecisionKind.tool);
      expect(tool.toolCommand?.action, ToolAction.search);
      expect(tool.toolCommand?.query, 'Neuro-sama');
      expect(tool.toolCommand?.showHelp, isFalse);

      final empty = engine.decide('/tool');
      expect(empty.kind, ChatTurnDecisionKind.tool);
      expect(empty.toolCommand?.showHelp, isTrue);
      expect(empty.toolCommand?.action, ToolAction.code);
    });

    test('routes agent commands as delegated-ack eligible decisions', () {
      final agent = engine.decide('/agent 做一个直播助手规划');
      expect(agent.kind, ChatTurnDecisionKind.agent);
      expect(agent.prefersDelegatedAck, isTrue);
      expect(agent.agentCommand?.goal, '做一个直播助手规划');
      expect(agent.agentCommand?.deliverable, ResearchDeliverable.report);
      expect(agent.agentCommand?.depth, ResearchDepth.deep);

      final summary = engine.decide('/summary EchoBot 架构');
      expect(summary.kind, ChatTurnDecisionKind.agent);
      expect(summary.agentCommand?.deliverable, ResearchDeliverable.summary);
      expect(summary.agentCommand?.depth, ResearchDepth.quick);
    });

    test('routes hash shortcuts to tool and agent decisions', () {
      final search = engine.decide('#search latest qwen docs');
      expect(search.kind, ChatTurnDecisionKind.tool);
      expect(search.toolCommand?.action, ToolAction.search);
      expect(search.toolCommand?.query, 'latest qwen docs');

      final taggedAgent = engine.decide('#agent 生成研究计划');
      expect(taggedAgent.kind, ChatTurnDecisionKind.agent);
      expect(taggedAgent.agentCommand?.goal, '生成研究计划');
      expect(taggedAgent.prefersDelegatedAck, isTrue);
    });

    test('falls back to chat for ordinary text', () {
      final chat = engine.decide('今天我们继续做 Neuro-sama 风格重构');
      expect(chat.kind, ChatTurnDecisionKind.chat);
      expect(chat.isCommand, isFalse);
      expect(chat.toolCommand, isNull);
      expect(chat.agentCommand, isNull);
    });
  });
}
