import '../models/research_job.dart';
import '../models/tool_intent.dart';

enum ChatTurnDecisionKind { chat, help, tool, agent, info }

class ChatTurnDecision {
  const ChatTurnDecision._({
    required this.kind,
    this.helpTopic,
    this.infoTopic,
    this.toolCommand,
    this.agentCommand,
    this.prefersDelegatedAck = false,
  });

  const ChatTurnDecision.chat() : this._(kind: ChatTurnDecisionKind.chat);

  const ChatTurnDecision.help({String topic = ''})
    : this._(kind: ChatTurnDecisionKind.help, helpTopic: topic);

  const ChatTurnDecision.info({required String topic})
    : this._(kind: ChatTurnDecisionKind.info, infoTopic: topic);

  const ChatTurnDecision.tool({required ChatToolCommand toolCommand})
    : this._(kind: ChatTurnDecisionKind.tool, toolCommand: toolCommand);

  const ChatTurnDecision.agent({
    required ChatAgentCommand agentCommand,
    bool prefersDelegatedAck = true,
  }) : this._(
         kind: ChatTurnDecisionKind.agent,
         agentCommand: agentCommand,
         prefersDelegatedAck: prefersDelegatedAck,
       );

  final ChatTurnDecisionKind kind;
  final String? helpTopic;
  final String? infoTopic;
  final ChatToolCommand? toolCommand;
  final ChatAgentCommand? agentCommand;
  final bool prefersDelegatedAck;

  bool get isCommand => kind != ChatTurnDecisionKind.chat;
}

class ChatAgentCommand {
  const ChatAgentCommand({
    required this.goal,
    required this.deliverable,
    required this.depth,
  });

  final String goal;
  final ResearchDeliverable deliverable;
  final ResearchDepth depth;
}

class ChatToolCommand {
  const ChatToolCommand({
    required this.action,
    required this.query,
    this.showHelp = false,
  });

  final ToolAction action;
  final String query;
  final bool showHelp;
}

enum _TagCommandType { tool, agent, help, info }

class _TagCommand {
  const _TagCommand({
    required this.type,
    this.action,
    this.payload = '',
    this.deliverable,
    this.depth,
    this.topic,
  });

  const _TagCommand.tool({required ToolAction action, required String payload})
    : this(type: _TagCommandType.tool, action: action, payload: payload);

  const _TagCommand.agent({
    required String payload,
    required ResearchDeliverable deliverable,
    required ResearchDepth depth,
  }) : this(
         type: _TagCommandType.agent,
         payload: payload,
         deliverable: deliverable,
         depth: depth,
       );

  const _TagCommand.help({String topic = ''})
    : this(type: _TagCommandType.help, topic: topic);

  const _TagCommand.info({required String topic})
    : this(type: _TagCommandType.info, topic: topic);

  final _TagCommandType type;
  final ToolAction? action;
  final String payload;
  final ResearchDeliverable? deliverable;
  final ResearchDepth? depth;
  final String? topic;
}

class ChatTurnDecisionEngine {
  const ChatTurnDecisionEngine();

  ChatTurnDecision decide(String text) {
    final trimmed = text.trim();

    final helpTopic = _parseHelpTopic(trimmed);
    if (helpTopic != null) {
      return ChatTurnDecision.help(topic: helpTopic);
    }

    final toolCommand = _parseToolCommand(trimmed);
    if (toolCommand != null) {
      return ChatTurnDecision.tool(toolCommand: toolCommand);
    }

    final agentCommand = _parseAgentCommand(trimmed);
    if (agentCommand != null) {
      return ChatTurnDecision.agent(agentCommand: agentCommand);
    }

    final tagCommand = _parseTagCommand(trimmed);
    if (tagCommand != null) {
      switch (tagCommand.type) {
        case _TagCommandType.help:
          return ChatTurnDecision.help(topic: tagCommand.topic ?? '');
        case _TagCommandType.info:
          return ChatTurnDecision.info(topic: tagCommand.topic ?? '');
        case _TagCommandType.tool:
          return ChatTurnDecision.tool(
            toolCommand: ChatToolCommand(
              action: tagCommand.action ?? ToolAction.code,
              query: tagCommand.payload,
              showHelp: tagCommand.payload.trim().isEmpty,
            ),
          );
        case _TagCommandType.agent:
          return ChatTurnDecision.agent(
            agentCommand: ChatAgentCommand(
              goal: tagCommand.payload,
              deliverable: tagCommand.deliverable ?? ResearchDeliverable.report,
              depth: tagCommand.depth ?? ResearchDepth.deep,
            ),
          );
      }
    }

    return const ChatTurnDecision.chat();
  }

  String? _parseHelpTopic(String text) {
    if (text == '/help' || text == '/commands' || text == '/?') {
      return '';
    }
    if (text.startsWith('/help ')) {
      return text.substring(6).trim();
    }
    if (text.startsWith('/commands ')) {
      return text.substring(10).trim();
    }
    if (text == '/mcp') {
      return 'mcp';
    }
    if (text == '/skills') {
      return 'skills';
    }
    if (text == '/agents') {
      return 'agents';
    }
    return null;
  }

  ChatAgentCommand? _parseAgentCommand(String text) {
    if (text.startsWith('/agent ')) {
      return ChatAgentCommand(
        goal: text.substring(7).trim(),
        deliverable: ResearchDeliverable.report,
        depth: ResearchDepth.deep,
      );
    }
    if (text.startsWith('/research ')) {
      return ChatAgentCommand(
        goal: text.substring(10).trim(),
        deliverable: ResearchDeliverable.report,
        depth: ResearchDepth.deep,
      );
    }
    if (text.startsWith('/summary ')) {
      return ChatAgentCommand(
        goal: text.substring(9).trim(),
        deliverable: ResearchDeliverable.summary,
        depth: ResearchDepth.quick,
      );
    }
    return null;
  }

  ChatToolCommand? _parseToolCommand(String text) {
    if (!(text == '/tool' || text.startsWith('/tool '))) {
      return null;
    }
    final rest = text.substring(5).trim();
    if (rest.isEmpty || rest == 'help' || rest == '?' || rest == 'h') {
      return const ChatToolCommand(
        action: ToolAction.code,
        query: '',
        showHelp: true,
      );
    }
    final parts = rest.split(RegExp(r'\s+'));
    if (parts.isEmpty) {
      return null;
    }
    final action = _parseToolAction(parts.first);
    if (action != null) {
      final query = rest.substring(parts.first.length).trim();
      return ChatToolCommand(
        action: action,
        query: query,
        showHelp: query.isEmpty,
      );
    }
    return ChatToolCommand(action: ToolAction.code, query: rest);
  }

  ToolAction? _parseToolAction(String token) {
    final normalized = token.trim().toLowerCase();
    switch (normalized) {
      case 'code':
      case 'shell':
      case 'run':
      case 'cli':
        return ToolAction.code;
      case 'search':
      case 'web':
      case 'find':
        return ToolAction.search;
      case 'crawl':
      case 'fetch':
      case 'http':
        return ToolAction.crawl;
      case 'analyze':
      case 'analysis':
        return ToolAction.analyze;
      case 'summarize':
      case 'summary':
      case 'sum':
        return ToolAction.summarize;
      case 'image':
      case 'img':
      case 'imagegen':
      case 'imagine':
        return ToolAction.imageGen;
      case 'vision':
      case 'imageanalyze':
      case 'imganalyze':
        return ToolAction.imageAnalyze;
      default:
        return null;
    }
  }

  _TagCommand? _parseTagCommand(String text) {
    if (!text.startsWith('#')) {
      return null;
    }
    final match = RegExp(r'^#([A-Za-z][\w-]*)(?:\s+(.+))?$').firstMatch(text);
    if (match == null) {
      return null;
    }
    final tag = match.group(1)!.toLowerCase();
    final payload = (match.group(2) ?? '').trim();
    if (tag == 'help' || tag == '?') {
      return _TagCommand.help(topic: payload);
    }
    if (tag == 'mcp' || tag == 'skills' || tag == 'agents') {
      return _TagCommand.info(topic: tag);
    }
    if (tag == 'agent' || tag == 'research') {
      return _TagCommand.agent(
        payload: payload,
        deliverable: ResearchDeliverable.report,
        depth: ResearchDepth.deep,
      );
    }
    if (tag == 'summary') {
      return _TagCommand.tool(action: ToolAction.summarize, payload: payload);
    }
    if (tag == 'tool') {
      return _TagCommand.tool(action: ToolAction.code, payload: payload);
    }
    final action = _parseToolAction(tag);
    if (action != null) {
      return _TagCommand.tool(action: action, payload: payload);
    }
    return null;
  }
}
