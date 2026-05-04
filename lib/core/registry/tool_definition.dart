/// Tool parameter definition
class ToolParameter {
  const ToolParameter({
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.defaultValue,
  });

  final String name;
  final String type; // 'string', 'number', 'boolean', 'object', 'array'
  final String description;
  final bool required;
  final dynamic defaultValue;

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'description': description,
        'required': required,
        if (defaultValue != null) 'default': defaultValue,
      };
}

/// Tool definition metadata
class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    this.category,
    this.tags = const <String>[],
    this.requiresAuth = false,
    this.requiresNetwork = false,
  });

  final String name;
  final String description;
  final List<ToolParameter> parameters;
  final String? category;
  final List<String> tags;
  final bool requiresAuth;
  final bool requiresNetwork;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters.map((p) => p.toJson()).toList(),
        if (category != null) 'category': category,
        'tags': tags,
        'requires_auth': requiresAuth,
        'requires_network': requiresNetwork,
      };
}

/// Tool execution context
class ToolContext {
  const ToolContext({
    this.sessionId,
    this.traceId,
    this.userId,
    this.workspace,
    this.metadata = const <String, dynamic>{},
  });

  final String? sessionId;
  final String? traceId;
  final String? userId;
  final String? workspace;
  final Map<String, dynamic> metadata;
}

/// Tool execution result
class ToolResult {
  const ToolResult({
    required this.success,
    this.output,
    this.error,
    this.metadata = const <String, dynamic>{},
  });

  final bool success;
  final dynamic output;
  final String? error;
  final Map<String, dynamic> metadata;

  factory ToolResult.success(dynamic output, {Map<String, dynamic>? metadata}) {
    return ToolResult(
      success: true,
      output: output,
      metadata: metadata ?? const <String, dynamic>{},
    );
  }

  factory ToolResult.failure(String error, {Map<String, dynamic>? metadata}) {
    return ToolResult(
      success: false,
      error: error,
      metadata: metadata ?? const <String, dynamic>{},
    );
  }
}

/// Abstract tool interface
abstract class Tool {
  ToolDefinition get definition;

  Future<ToolResult> execute(
    Map<String, dynamic> parameters,
    ToolContext context,
  );

  Future<void> dispose() async {}
}
