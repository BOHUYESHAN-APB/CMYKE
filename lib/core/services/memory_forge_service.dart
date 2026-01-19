import 'dart:convert';

import '../models/chat_message.dart';
import '../models/memory_tier.dart';
import '../models/provider_config.dart';
import 'llm_client.dart';

class MemoryForgeDraft {
  const MemoryForgeDraft({
    required this.tier,
    required this.content,
    this.title,
    this.coreKey,
    this.occurredAt,
    this.tags = const [],
  });

  final MemoryTier tier;
  final String content;
  final String? title;
  final String? coreKey;
  final DateTime? occurredAt;
  final List<String> tags;
}

class MemoryForgeService {
  MemoryForgeService({LlmClient? llmClient}) : _llmClient = llmClient ?? LlmClient();

  final LlmClient _llmClient;

  Future<MemoryForgeDraft?> generate({
    required ProviderConfig provider,
    required MemoryTier tier,
    required String instruction,
    DateTime? now,
    String? preferredCoreKey,
    bool fictional = true,
  }) async {
    final trimmedInstruction = instruction.trim();
    if (trimmedInstruction.isEmpty) {
      return null;
    }
    final timestamp = now ?? DateTime.now();

    final payload = {
      'tier': tier.key,
      if (preferredCoreKey != null && preferredCoreKey.trim().isNotEmpty)
        'preferred_core_key': preferredCoreKey.trim(),
      'fictional': fictional,
      'instruction': trimmedInstruction,
    };

    final systemPrompt = _systemPromptForTier(tier);
    final response = await _llmClient.completeChat(
      provider: provider,
      systemPrompt: systemPrompt,
      messages: [
        ChatMessage(
          id: 'memory_forge',
          role: ChatRole.user,
          content: jsonEncode(payload),
          createdAt: timestamp,
        ),
      ],
    );
    return _parseDraft(response, tier: tier, now: timestamp);
  }

  String _systemPromptForTier(MemoryTier tier) {
    final tierName = tier.label;
    final rules = '''
You are the CMYKE Memory Forge.

Task:
- Create ONE memory record for: $tierName
- The user may explicitly request a fictional/setup memory; follow the instruction.

Output: JSON ONLY (no markdown, no extra text).
Do not output chain-of-thought or hidden reasoning.

Common fields:
- "title": optional short title (<= 40 chars)
- "content": required; concise but complete
- "tags": optional array of short tags (<= 12 tags)

''';

    switch (tier) {
      case MemoryTier.crossSession:
        return '''
$rules
Schema (core memory):
{
  "core_key": "dot.separated.key (required)",
  "title": "optional",
  "content": "required",
  "tags": ["optional","tags"]
}

Rules:
- Core memory MUST be a stable fact, preference, persona setting, or constraint.
- If user provided "preferred_core_key", use it unless clearly wrong.
- Keep keys under: user.*, assistant.*, persona.*, constraints.*
''';
      case MemoryTier.autonomous:
        return '''
$rules
Schema (diary memory):
{
  "occurred_at": "ISO8601 datetime (optional; default: now)",
  "title": "optional",
  "content": "required",
  "tags": ["optional","tags"]
}

Rules:
- Diary memory should describe a time-indexed event or note.
- Keep it factual within the given instruction context.
''';
      case MemoryTier.external:
        return '''
$rules
Schema (knowledge base record):
{
  "title": "optional",
  "content": "required",
  "tags": ["optional","tags"]
}

Rules:
- Knowledge base records should be reusable information or notes.
''';
      case MemoryTier.context:
        return '''
$rules
Schema (session context record):
{
  "title": "optional",
  "content": "required",
  "tags": ["optional","tags"]
}

Rules:
- Session context should be short-lived information; avoid long-term facts.
''';
    }
  }

  MemoryForgeDraft? _parseDraft(
    String raw, {
    required MemoryTier tier,
    required DateTime now,
  }) {
    final extracted = _extractJsonObject(raw);
    if (extracted == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(extracted);
      if (decoded is! Map) {
        return null;
      }
      final map = Map<String, dynamic>.from(decoded);
      final title = (map['title'] ?? '').toString().trim();
      final content = (map['content'] ?? '').toString().trim();
      if (content.isEmpty) {
        return null;
      }
      final tags = _coerceStringList(map['tags']).take(12).toList(growable: false);

      String? coreKey;
      DateTime? occurredAt;
      if (tier == MemoryTier.crossSession) {
        coreKey = (map['core_key'] ?? '').toString().trim();
        if (coreKey.isEmpty) {
          return null;
        }
      }
      if (tier == MemoryTier.autonomous) {
        final occurredRaw = (map['occurred_at'] ?? '').toString().trim();
        if (occurredRaw.isNotEmpty) {
          try {
            occurredAt = DateTime.parse(occurredRaw);
          } catch (_) {
            occurredAt = now;
          }
        } else {
          occurredAt = now;
        }
      }

      return MemoryForgeDraft(
        tier: tier,
        title: title.isEmpty ? null : title,
        content: content,
        tags: tags,
        coreKey: coreKey,
        occurredAt: occurredAt,
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _coerceStringList(Object? value) {
    if (value is! List) return const [];
    final out = <String>[];
    for (final v in value) {
      final s = v.toString().trim();
      if (s.isNotEmpty) out.add(s);
      if (out.length >= 24) break;
    }
    return out;
  }

  String? _extractJsonObject(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final candidate = trimmed.substring(start, end + 1).trim();
    return candidate.startsWith('{') && candidate.endsWith('}') ? candidate : null;
  }
}

