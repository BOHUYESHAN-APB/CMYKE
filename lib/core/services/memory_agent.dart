import 'dart:convert';

import '../models/chat_message.dart';
import '../models/provider_config.dart';
import 'llm_client.dart';

class CoreMemoryOp {
  const CoreMemoryOp({
    required this.action,
    required this.key,
    required this.value,
    required this.confidence,
    this.reason,
    this.title,
    this.tags = const [],
  });

  final String action; // upsert | delete | none
  final String key;
  final String value;
  final double confidence;
  final String? reason;
  final String? title;
  final List<String> tags;

  bool get shouldUpsert =>
      action == 'upsert' && key.trim().isNotEmpty && value.trim().isNotEmpty;
  bool get shouldDelete => action == 'delete' && key.trim().isNotEmpty;
}

class DiaryMemoryOp {
  const DiaryMemoryOp({
    required this.action,
    required this.occurredAt,
    required this.summary,
    required this.confidence,
    this.title,
    this.tags = const [],
  });

  final String action; // add | none
  final DateTime occurredAt;
  final String summary;
  final double confidence;
  final String? title;
  final List<String> tags;

  bool get shouldAdd => action == 'add' && summary.trim().isNotEmpty;
}

class MemoryAgentResult {
  const MemoryAgentResult({this.core = const [], this.diary = const []});

  final List<CoreMemoryOp> core;
  final List<DiaryMemoryOp> diary;
}

/// Extracts structured long-term memory updates:
/// - Core memory: stable facts/preferences (upsert/delete by key)
/// - Diary memory: time-indexed events (add)
///
/// This should use a smaller model than the main assistant when possible.
class MemoryAgent {
  MemoryAgent({required LlmClient llmClient}) : _llmClient = llmClient;

  final LlmClient _llmClient;

  Future<MemoryAgentResult> decide({
    required ProviderConfig provider,
    required String userText,
    required String assistantText,
    required DateTime now,
    List<Map<String, String>> contextMessages = const [],
    List<Map<String, String>> existingCore = const [],
    String? conversationMode,
  }) async {
    final trimmedUser = userText.trim();
    final trimmedAssistant = assistantText.trim();
    if (trimmedUser.isEmpty && trimmedAssistant.isEmpty) {
      return const MemoryAgentResult();
    }

    final mode = (conversationMode ?? '').trim();
    final trimmedContext = contextMessages
        .where(
          (m) =>
              (m['role'] ?? '').toString().trim().isNotEmpty &&
              (m['content'] ?? '').toString().trim().isNotEmpty,
        )
        .take(14)
        .map(
          (m) => {
            'role': (m['role'] ?? '').toString().trim(),
            'content': (m['content'] ?? '').toString().trim(),
          },
        )
        .toList(growable: false);

    final corePairs = existingCore
        .where(
          (m) =>
              (m['key'] ?? '').toString().trim().isNotEmpty &&
              (m['value'] ?? '').toString().trim().isNotEmpty,
        )
        .take(40)
        .map(
          (m) => {
            'key': (m['key'] ?? '').toString().trim(),
            'value': (m['value'] ?? '').toString().trim(),
          },
        )
        .toList(growable: false);

    final payload = {
      'now': now.toIso8601String(),
      if (mode.isNotEmpty) 'mode': mode,
      if (trimmedContext.isNotEmpty) 'recent_messages': trimmedContext,
      if (corePairs.isNotEmpty) 'existing_core': corePairs,
      'user_text': trimmedUser,
      'assistant_text': trimmedAssistant,
    };

    final systemPrompt = '''
You are the CMYKE Memory Agent.

Goal:
- Maintain TWO memory layers:
  1) Core memory: stable facts/preferences/constraints that should persist across sessions.
  2) Diary memory: time-indexed, traceable events for accurate "yesterday/last week" questions.

Output: JSON ONLY (no markdown, no extra text).

Schema:
{
  "core": [
    {
      "action": "upsert" | "delete" | "none",
      "key": "dot.separated.key",
      "value": "string (required for upsert)",
      "title": "optional short title",
      "tags": ["optional","tags"],
      "confidence": 0.0-1.0,
      "reason": "optional"
    }
  ],
  "diary": [
    {
      "action": "add" | "none",
      "occurred_at": "ISO8601 datetime (default: now)",
      "summary": "string (required for add)",
      "title": "optional short title",
      "tags": ["optional","tags"],
      "confidence": 0.0-1.0
    }
  ]
}

Rules:
- JSON only. Do not wrap in ``` fences.
- Keep it small: max 5 core ops and max 5 diary ops.
- Core memory:
  - ONLY store stable, user-provided facts/preferences (name, likes/dislikes, long-term goals, constraints).
  - Do NOT store short-lived details, tool logs, or private keys.
  - Do NOT store chain-of-thought / hidden reasoning.
  - Use upsert with consistent keys. Prefer keys under: user.*, assistant.*, constraints.*
  - If a previous core key becomes invalid, use delete.
- Diary memory:
  - Store event summaries that are useful to recall by time (e.g., "User said they went to ...").
  - If occurred_at is not explicit, use now.
  - Avoid overly long summaries.
- Confidence:
  - Use high confidence only when explicitly supported by the conversation.
''';

    final response = await _llmClient.completeChat(
      provider: provider,
      systemPrompt: systemPrompt,
      messages: [
        ChatMessage(
          id: 'memory_agent',
          role: ChatRole.user,
          content: jsonEncode(payload),
          createdAt: now,
        ),
      ],
    );
    return _parseResult(response, now: now);
  }

  MemoryAgentResult _parseResult(String raw, {required DateTime now}) {
    final extracted = _extractJsonObject(raw);
    if (extracted == null) {
      return const MemoryAgentResult();
    }
    try {
      final decoded = jsonDecode(extracted);
      if (decoded is! Map) {
        return const MemoryAgentResult();
      }
      final map = Map<String, dynamic>.from(decoded);
      final core = _parseCoreOps(map['core']);
      final diary = _parseDiaryOps(map['diary'], now: now);
      return MemoryAgentResult(core: core, diary: diary);
    } catch (_) {
      return const MemoryAgentResult();
    }
  }

  List<CoreMemoryOp> _parseCoreOps(Object? raw) {
    if (raw is! List) return const [];
    final out = <CoreMemoryOp>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      final action = (m['action'] ?? 'none').toString().trim().toLowerCase();
      final key = (m['key'] ?? '').toString().trim();
      final value = (m['value'] ?? '').toString().trim();
      final title = (m['title'] ?? '').toString().trim();
      final reason = (m['reason'] ?? '').toString().trim();
      final tags = _coerceStringList(
        m['tags'],
      ).take(12).toList(growable: false);
      final confidence = _coerceConfidence(m['confidence']);
      out.add(
        CoreMemoryOp(
          action: action,
          key: key,
          value: value,
          title: title.isEmpty ? null : title,
          tags: tags,
          confidence: confidence,
          reason: reason.isEmpty ? null : reason,
        ),
      );
      if (out.length >= 5) break;
    }
    return out;
  }

  List<DiaryMemoryOp> _parseDiaryOps(Object? raw, {required DateTime now}) {
    if (raw is! List) return const [];
    final out = <DiaryMemoryOp>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      final action = (m['action'] ?? 'none').toString().trim().toLowerCase();
      final summary = (m['summary'] ?? '').toString().trim();
      final title = (m['title'] ?? '').toString().trim();
      final tags = _coerceStringList(
        m['tags'],
      ).take(12).toList(growable: false);
      final confidence = _coerceConfidence(m['confidence']);
      final occurredAtRaw = (m['occurred_at'] ?? '').toString().trim();
      DateTime occurredAt = now;
      if (occurredAtRaw.isNotEmpty) {
        try {
          occurredAt = DateTime.parse(occurredAtRaw);
        } catch (_) {
          occurredAt = now;
        }
      }
      out.add(
        DiaryMemoryOp(
          action: action,
          occurredAt: occurredAt,
          summary: summary,
          title: title.isEmpty ? null : title,
          tags: tags,
          confidence: confidence,
        ),
      );
      if (out.length >= 5) break;
    }
    return out;
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

  double _coerceConfidence(Object? value) {
    double confidence = 0.0;
    if (value is num) {
      confidence = value.toDouble();
    } else if (value is String) {
      confidence = double.tryParse(value.trim()) ?? 0.0;
    }
    if (!confidence.isFinite) confidence = 0.0;
    return confidence.clamp(0.0, 1.0);
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
    return candidate.startsWith('{') && candidate.endsWith('}')
        ? candidate
        : null;
  }
}
