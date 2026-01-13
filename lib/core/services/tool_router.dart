import '../models/tool_intent.dart';

class ToolRouter {
  const ToolRouter();

  Future<String> dispatch(ToolIntent intent) async {
    // TODO: implement MCP/skills/tool backends.
    // Placeholder: echo intent action.
    return 'Tool intent accepted: ${intent.action.name}';
  }
}
