import 'platform_definition.dart';

/// Platform registry for centralized platform discovery and management
class PlatformRegistry {
  PlatformRegistry._();

  static final PlatformRegistry instance = PlatformRegistry._();

  final Map<String, PlatformAdapter> _platforms = <String, PlatformAdapter>{};
  final Map<String, Set<String>> _categories = <String, Set<String>>{};
  final Map<String, Set<String>> _tags = <String, Set<String>>{};

  /// Register a platform adapter
  void register(PlatformAdapter adapter) {
    final name = adapter.definition.name;
    if (_platforms.containsKey(name)) {
      throw StateError('Platform "$name" is already registered');
    }

    _platforms[name] = adapter;

    // Index by category
    final category = adapter.definition.category;
    if (category != null && category.isNotEmpty) {
      _categories.putIfAbsent(category, () => <String>{}).add(name);
    }

    // Index by tags
    for (final tag in adapter.definition.tags) {
      if (tag.isNotEmpty) {
        _tags.putIfAbsent(tag, () => <String>{}).add(name);
      }
    }
  }

  /// Unregister a platform adapter
  void unregister(String name) {
    final adapter = _platforms.remove(name);
    if (adapter == null) return;

    // Remove from category index
    final category = adapter.definition.category;
    if (category != null) {
      _categories[category]?.remove(name);
      if (_categories[category]?.isEmpty ?? false) {
        _categories.remove(category);
      }
    }

    // Remove from tag index
    for (final tag in adapter.definition.tags) {
      _tags[tag]?.remove(name);
      if (_tags[tag]?.isEmpty ?? false) {
        _tags.remove(tag);
      }
    }
  }

  /// Get a platform adapter by name
  PlatformAdapter? get(String name) => _platforms[name];

  /// Check if a platform is registered
  bool has(String name) => _platforms.containsKey(name);

  /// Get all registered platform names
  List<String> get allNames => _platforms.keys.toList();

  /// Get all registered platform adapters
  List<PlatformAdapter> get allAdapters => _platforms.values.toList();

  /// Get all platform definitions
  List<PlatformDefinition> get allDefinitions =>
      _platforms.values.map((adapter) => adapter.definition).toList();

  /// Get platforms by category
  List<PlatformAdapter> getByCategory(String category) {
    final names = _categories[category];
    if (names == null) return <PlatformAdapter>[];
    return names.map((name) => _platforms[name]!).toList();
  }

  /// Get platforms by tag
  List<PlatformAdapter> getByTag(String tag) {
    final names = _tags[tag];
    if (names == null) return <PlatformAdapter>[];
    return names.map((name) => _platforms[name]!).toList();
  }

  /// Get all categories
  List<String> get allCategories => _categories.keys.toList();

  /// Get all tags
  List<String> get allTags => _tags.keys.toList();

  /// Get connected platforms
  List<PlatformAdapter> get connectedAdapters => _platforms.values
      .where((adapter) => adapter.status == PlatformStatus.connected)
      .toList();

  /// Get platforms by status
  List<PlatformAdapter> getByStatus(PlatformStatus status) =>
      _platforms.values.where((adapter) => adapter.status == status).toList();

  /// Connect a platform by name
  Future<void> connect(String name) async {
    final adapter = _platforms[name];
    if (adapter == null) {
      throw StateError('Platform "$name" not found');
    }
    await adapter.connect();
  }

  /// Disconnect a platform by name
  Future<void> disconnect(String name) async {
    final adapter = _platforms[name];
    if (adapter == null) {
      throw StateError('Platform "$name" not found');
    }
    await adapter.disconnect();
  }

  /// Send message to a platform
  Future<void> sendMessage(String name, PlatformMessage message) async {
    final adapter = _platforms[name];
    if (adapter == null) {
      throw StateError('Platform "$name" not found');
    }
    if (adapter.status != PlatformStatus.connected) {
      throw StateError('Platform "$name" is not connected');
    }
    await adapter.sendMessage(message);
  }

  /// Dispose all platforms
  Future<void> disposeAll() async {
    for (final adapter in _platforms.values) {
      await adapter.dispose();
    }
    _platforms.clear();
    _categories.clear();
    _tags.clear();
  }

  /// Clear all registrations (for testing)
  void clear() {
    _platforms.clear();
    _categories.clear();
    _tags.clear();
  }
}
