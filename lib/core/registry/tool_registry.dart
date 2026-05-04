import 'tool_definition.dart';

/// Tool registry for centralized tool discovery and dispatch
class ToolRegistry {
  ToolRegistry._();

  static final ToolRegistry instance = ToolRegistry._();

  final Map<String, Tool> _tools = <String, Tool>{};
  final Map<String, Set<String>> _categories = <String, Set<String>>{};
  final Map<String, Set<String>> _tags = <String, Set<String>>{};

  /// Register a tool
  void register(Tool tool) {
    final name = tool.definition.name;
    if (_tools.containsKey(name)) {
      throw StateError('Tool "$name" is already registered');
    }

    _tools[name] = tool;

    // Index by category
    final category = tool.definition.category;
    if (category != null && category.isNotEmpty) {
      _categories.putIfAbsent(category, () => <String>{}).add(name);
    }

    // Index by tags
    for (final tag in tool.definition.tags) {
      if (tag.isNotEmpty) {
        _tags.putIfAbsent(tag, () => <String>{}).add(name);
      }
    }
  }

  /// Unregister a tool
  void unregister(String name) {
    final tool = _tools.remove(name);
    if (tool == null) return;

    // Remove from category index
    final category = tool.definition.category;
    if (category != null) {
      _categories[category]?.remove(name);
      if (_categories[category]?.isEmpty ?? false) {
        _categories.remove(category);
      }
    }

    // Remove from tag index
    for (final tag in tool.definition.tags) {
      _tags[tag]?.remove(name);
      if (_tags[tag]?.isEmpty ?? false) {
        _tags.remove(tag);
      }
    }
  }

  /// Get a tool by name
  Tool? get(String name) => _tools[name];

  /// Check if a tool is registered
  bool has(String name) => _tools.containsKey(name);

  /// Get all registered tool names
  List<String> get allNames => _tools.keys.toList();

  /// Get all registered tools
  List<Tool> get allTools => _tools.values.toList();

  /// Get all tool definitions
  List<ToolDefinition> get allDefinitions =>
      _tools.values.map((tool) => tool.definition).toList();

  /// Get tools by category
  List<Tool> getByCategory(String category) {
    final names = _categories[category];
    if (names == null) return <Tool>[];
    return names.map((name) => _tools[name]!).toList();
  }

  /// Get tools by tag
  List<Tool> getByTag(String tag) {
    final names = _tags[tag];
    if (names == null) return <Tool>[];
    return names.map((name) => _tools[name]!).toList();
  }

  /// Get all categories
  List<String> get allCategories => _categories.keys.toList();

  /// Get all tags
  List<String> get allTags => _tags.keys.toList();

  /// Execute a tool by name
  Future<ToolResult> execute(
    String name,
    Map<String, dynamic> parameters,
    ToolContext context,
  ) async {
    final tool = _tools[name];
    if (tool == null) {
      return ToolResult.failure('Tool "$name" not found');
    }

    try {
      return await tool.execute(parameters, context);
    } catch (error, stackTrace) {
      return ToolResult.failure(
        'Tool execution failed: $error',
        metadata: <String, dynamic>{
          'error': error.toString(),
          'stack_trace': stackTrace.toString(),
        },
      );
    }
  }

  /// Dispose all tools
  Future<void> disposeAll() async {
    for (final tool in _tools.values) {
      await tool.dispose();
    }
    _tools.clear();
    _categories.clear();
    _tags.clear();
  }

  /// Clear all registrations (for testing)
  void clear() {
    _tools.clear();
    _categories.clear();
    _tags.clear();
  }
}
