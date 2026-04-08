class ToolGatewaySkillImportSource {
  const ToolGatewaySkillImportSource._({
    required this.type,
    this.url,
    this.path,
    this.ref,
    this.root,
  });

  factory ToolGatewaySkillImportSource.git({
    required String url,
    String? ref,
    String? root,
  }) {
    return ToolGatewaySkillImportSource._(
      type: 'git',
      url: url,
      ref: ref,
      root: root,
    );
  }

  factory ToolGatewaySkillImportSource.local({
    required String path,
    String? root,
  }) {
    return ToolGatewaySkillImportSource._(
      type: 'local',
      path: path,
      root: root,
    );
  }

  final String type;
  final String? url;
  final String? path;
  final String? ref;
  final String? root;

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (url != null && url!.trim().isNotEmpty) 'url': url!.trim(),
      if (path != null && path!.trim().isNotEmpty) 'path': path!.trim(),
      if (ref != null && ref!.trim().isNotEmpty) 'ref': ref!.trim(),
      if (root != null && root!.trim().isNotEmpty) 'root': root!.trim(),
    };
  }
}

class ToolGatewaySkillSourceInfo {
  const ToolGatewaySkillSourceInfo({
    required this.type,
    required this.label,
    required this.location,
    this.root,
    this.ref,
  });

  factory ToolGatewaySkillSourceInfo.fromJson(Map<String, dynamic> json) {
    return ToolGatewaySkillSourceInfo(
      type: json['type']?.toString().trim().isNotEmpty == true
          ? json['type'].toString().trim()
          : 'unknown',
      label: json['label']?.toString().trim().isNotEmpty == true
          ? json['label'].toString().trim()
          : 'unknown',
      location: json['location']?.toString().trim().isNotEmpty == true
          ? json['location'].toString().trim()
          : '',
      root: json['root']?.toString(),
      ref: json['ref']?.toString(),
    );
  }

  final String type;
  final String label;
  final String location;
  final String? root;
  final String? ref;
}

class ToolGatewaySkillRequirements {
  const ToolGatewaySkillRequirements({
    this.bins = const <String>[],
    this.env = const <String>[],
    this.os = const <String>[],
  });

  factory ToolGatewaySkillRequirements.fromJson(Map<String, dynamic>? json) {
    return ToolGatewaySkillRequirements(
      bins: _stringList(json?['bins']),
      env: _stringList(json?['env']),
      os: _stringList(json?['os']),
    );
  }

  final List<String> bins;
  final List<String> env;
  final List<String> os;

  bool get isEmpty => bins.isEmpty && env.isEmpty && os.isEmpty;
}

class ToolGatewaySkillItem {
  const ToolGatewaySkillItem({
    required this.name,
    required this.displayName,
    required this.status,
    this.description,
    this.author,
    this.version,
    this.homepage,
    this.tags = const <String>[],
    this.userInvocable,
    this.relativePath,
    this.manifestPath,
    this.installedAt,
    this.hasFrontmatter = false,
    this.requirements = const ToolGatewaySkillRequirements(),
    this.source,
  });

  factory ToolGatewaySkillItem.fromJson(Map<String, dynamic> json) {
    return ToolGatewaySkillItem(
      name: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString().trim()
          : 'skill',
      displayName: json['display_name']?.toString().trim().isNotEmpty == true
          ? json['display_name'].toString().trim()
          : (json['name']?.toString().trim().isNotEmpty == true
                ? json['name'].toString().trim()
                : 'skill'),
      status: json['status']?.toString().trim().isNotEmpty == true
          ? json['status'].toString().trim()
          : 'installed',
      description: _nullableText(json['description']),
      author: _nullableText(json['author']),
      version: _nullableText(json['version']),
      homepage: _nullableText(json['homepage']),
      tags: _stringList(json['tags']),
      userInvocable: json['user_invocable'] is bool
          ? json['user_invocable'] as bool
          : null,
      relativePath: _nullableText(json['relative_path']),
      manifestPath: _nullableText(json['manifest_path']),
      installedAt: json['installed_at'] is num
          ? (json['installed_at'] as num).toInt()
          : null,
      hasFrontmatter: json['has_frontmatter'] == true,
      requirements: ToolGatewaySkillRequirements.fromJson(
        json['requirements'] is Map<String, dynamic>
            ? json['requirements'] as Map<String, dynamic>
            : null,
      ),
      source: json['source'] is Map<String, dynamic>
          ? ToolGatewaySkillSourceInfo.fromJson(
              json['source'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  factory ToolGatewaySkillItem.fromLegacyName(String name) {
    final normalized = name.trim().isEmpty ? 'skill' : name.trim();
    return ToolGatewaySkillItem(
      name: normalized,
      displayName: normalized,
      status: 'installed',
    );
  }

  final String name;
  final String displayName;
  final String status;
  final String? description;
  final String? author;
  final String? version;
  final String? homepage;
  final List<String> tags;
  final bool? userInvocable;
  final String? relativePath;
  final String? manifestPath;
  final int? installedAt;
  final bool hasFrontmatter;
  final ToolGatewaySkillRequirements requirements;
  final ToolGatewaySkillSourceInfo? source;

  String get title => displayName.trim().isEmpty ? name : displayName;
}

class ToolGatewaySkillsCatalogResult {
  const ToolGatewaySkillsCatalogResult({
    required this.skills,
    required this.legacyNames,
    required this.opencodeRoot,
    required this.configPath,
    required this.configDir,
    required this.skillDir,
  });

  factory ToolGatewaySkillsCatalogResult.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ToolGatewaySkillItem.fromJson)
        .toList();
    final legacyNames = _stringList(json['skills']);
    return ToolGatewaySkillsCatalogResult(
      skills: items.isNotEmpty
          ? items
          : legacyNames.map(ToolGatewaySkillItem.fromLegacyName).toList(),
      legacyNames: legacyNames,
      opencodeRoot: json['opencode_root']?.toString() ?? '',
      configPath: json['config_path']?.toString() ?? '',
      configDir: json['config_dir']?.toString() ?? '',
      skillDir: json['skill_dir']?.toString() ?? '',
    );
  }

  final List<ToolGatewaySkillItem> skills;
  final List<String> legacyNames;
  final String opencodeRoot;
  final String configPath;
  final String configDir;
  final String skillDir;
}

class ToolGatewaySkillsPreviewResult {
  const ToolGatewaySkillsPreviewResult({
    required this.items,
    required this.errors,
    required this.skillDir,
    required this.total,
    required this.ready,
    required this.conflicts,
    required this.overwrites,
  });

  factory ToolGatewaySkillsPreviewResult.fromJson(Map<String, dynamic> json) {
    return ToolGatewaySkillsPreviewResult(
      items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ToolGatewaySkillItem.fromJson)
          .toList(),
      errors: _stringList(json['errors']),
      skillDir: json['skill_dir']?.toString() ?? '',
      total: json['total'] is num ? (json['total'] as num).toInt() : 0,
      ready: json['ready'] is num ? (json['ready'] as num).toInt() : 0,
      conflicts: json['conflicts'] is num
          ? (json['conflicts'] as num).toInt()
          : 0,
      overwrites: json['overwrites'] is num
          ? (json['overwrites'] as num).toInt()
          : 0,
    );
  }

  final List<ToolGatewaySkillItem> items;
  final List<String> errors;
  final String skillDir;
  final int total;
  final int ready;
  final int conflicts;
  final int overwrites;
}

class ToolGatewaySkillsInstallResult {
  const ToolGatewaySkillsInstallResult({
    required this.installed,
    required this.skipped,
    required this.errors,
    required this.skillDir,
  });

  factory ToolGatewaySkillsInstallResult.fromJson(Map<String, dynamic> json) {
    return ToolGatewaySkillsInstallResult(
      installed: _stringList(json['installed']),
      skipped: _stringList(json['skipped']),
      errors: _stringList(json['errors']),
      skillDir: json['skill_dir']?.toString() ?? '',
    );
  }

  final List<String> installed;
  final List<String> skipped;
  final List<String> errors;
  final String skillDir;
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

List<String> _stringList(Object? value) {
  final raw = (value as List<dynamic>? ?? const <dynamic>[])
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
  final unique = <String>[];
  for (final entry in raw) {
    if (!unique.contains(entry)) {
      unique.add(entry);
    }
  }
  return unique;
}
