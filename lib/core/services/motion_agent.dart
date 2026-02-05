import 'dart:convert';

import '../models/chat_message.dart';
import '../models/provider_config.dart';
import 'llm_client.dart';

class MotionAgentDecision {
  const MotionAgentDecision({
    required this.action,
    this.id,
    this.confidence = 0.0,
    this.reason,
  });

  final String action; // "play" | "none"
  final String? id;
  final double confidence;
  final String? reason;

  bool get shouldPlay =>
      action == 'play' && id != null && id!.trim().isNotEmpty;
}

/// Picks a single VRMA motion id from a provided catalog.
///
/// This is intentionally separated from the main chat model:
/// - It can use a much smaller model.
/// - It only outputs a tiny JSON decision.
class MotionAgent {
  MotionAgent({required LlmClient llmClient}) : _llmClient = llmClient;

  final LlmClient _llmClient;

  Future<MotionAgentDecision> decide({
    required ProviderConfig provider,
    required String userText,
    required String assistantText,
    required List<Map<String, dynamic>> allowedMotions,
    List<Map<String, String>> contextMessages = const [],
    String? conversationMode,
  }) async {
    final trimmedUser = userText.trim();
    final trimmedAssistant = assistantText.trim();
    if (trimmedUser.isEmpty && trimmedAssistant.isEmpty) {
      return const MotionAgentDecision(action: 'none', confidence: 0.0);
    }
    if (allowedMotions.isEmpty) {
      return const MotionAgentDecision(action: 'none', confidence: 0.0);
    }

    final summarized = _summarizeMotions(allowedMotions);
    final mode = (conversationMode ?? '').trim();
    final trimmedContext = contextMessages
        .where(
          (m) =>
              (m['role'] ?? '').toString().trim().isNotEmpty &&
              (m['content'] ?? '').toString().trim().isNotEmpty,
        )
        .take(10)
        .map(
          (m) => {
            'role': (m['role'] ?? '').toString().trim(),
            'content': (m['content'] ?? '').toString().trim(),
          },
        )
        .toList(growable: false);
    final payload = {
      if (mode.isNotEmpty) 'mode': mode,
      if (trimmedContext.isNotEmpty) 'recent_messages': trimmedContext,
      'user_text': trimmedUser,
      'assistant_text': trimmedAssistant,
      'allowed_motions': summarized,
    };

    final systemPrompt = '''
  You are the CMYKE Motion Agent.

  Goal: decide whether to trigger ONE avatar motion (VRMA) from the allowed list.

  Output: JSON ONLY (no markdown, no extra text).

  Schema:
  1) {"action":"none","confidence":0.0-1.0,"reason":"..."}
  2) {"action":"play","id":"<allowed id>","confidence":0.0-1.0,"reason":"..."}

  Rules:
  - "mode" can be "standard" | "omni" | "realtime". In "realtime", prefer subtle short gestures and avoid long/full-body actions unless the user explicitly requests it.
  - If "recent_messages" is present, use it as conversation context.
  - Choose "none" unless there is a clear cue in the conversation.
  - NEVER invent ids. Only select from allowed_motions[].id.
  - allowed_motions[].agent_tier can be "common" | "rare".
    - If "rare": ONLY choose it when the user explicitly requests it.
  - Avoid violence/weapon actions unless the user explicitly requests it.
  - Avoid long/full-body actions (dance/sit/pose) unless the user explicitly requests it or it clearly fits.
  - Prefer short, friendly gestures.
  ''';

    final response = await _llmClient.completeChat(
      provider: provider,
      systemPrompt: systemPrompt,
      messages: [
        ChatMessage(
          id: 'motion_agent',
          role: ChatRole.user,
          content: jsonEncode(payload),
          createdAt: DateTime.now(),
        ),
      ],
    );
    return _parseDecision(response);
  }

  List<Map<String, dynamic>> _summarizeMotions(
    List<Map<String, dynamic>> motions,
  ) {
    final result = <Map<String, dynamic>>[];
    for (final m in motions) {
      final id = (m['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final name = (m['name'] ?? '').toString().trim();
      final type = (m['type'] ?? '').toString().trim();
      final agentTier = (m['agent'] ?? '').toString().trim();
      final tagsRaw = m['tags'];
      final tags = <String>[];
      if (tagsRaw is List) {
        for (final t in tagsRaw) {
          final tag = t.toString().trim();
          if (tag.isNotEmpty) tags.add(tag);
        }
      }
      result.add({
        'id': id,
        if (name.isNotEmpty)
          'name': name.length > 80 ? name.substring(0, 80) : name,
        if (type.isNotEmpty) 'type': type,
        if (agentTier.isNotEmpty) 'agent_tier': agentTier,
        if (tags.isNotEmpty) 'tags': tags.take(10).toList(),
      });
      if (result.length >= 80) {
        break;
      }
    }
    return result;
  }

  MotionAgentDecision _parseDecision(String raw) {
    final extracted = _extractJsonObject(raw);
    if (extracted == null) {
      return const MotionAgentDecision(action: 'none', confidence: 0.0);
    }
    try {
      final decoded = jsonDecode(extracted);
      if (decoded is! Map) {
        return const MotionAgentDecision(action: 'none', confidence: 0.0);
      }
      final map = Map<String, dynamic>.from(decoded);
      final action = (map['action'] ?? 'none').toString().trim().toLowerCase();
      final id = (map['id'] ?? '').toString().trim();
      final confidenceRaw = map['confidence'];
      double confidence = 0.0;
      if (confidenceRaw is num) {
        confidence = confidenceRaw.toDouble();
      } else if (confidenceRaw is String) {
        confidence = double.tryParse(confidenceRaw.trim()) ?? 0.0;
      }
      if (!confidence.isFinite) {
        confidence = 0.0;
      }
      confidence = confidence.clamp(0.0, 1.0);
      final reason = map['reason']?.toString().trim();
      if (action == 'play' && id.isNotEmpty) {
        return MotionAgentDecision(
          action: 'play',
          id: id,
          confidence: confidence,
          reason: reason,
        );
      }
      return MotionAgentDecision(
        action: 'none',
        confidence: confidence,
        reason: reason,
      );
    } catch (_) {
      return const MotionAgentDecision(action: 'none', confidence: 0.0);
    }
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
