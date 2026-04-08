import 'dart:async';
import 'dart:convert';

import '../models/tool_intent.dart';

typedef ToolIntentDispatcher = Future<String> Function(ToolIntent intent);

class WebSearchOrchestrator {
  WebSearchOrchestrator({required ToolIntentDispatcher dispatchToolIntent})
    : _dispatchToolIntent = dispatchToolIntent;

  final ToolIntentDispatcher _dispatchToolIntent;

  Future<WebSearchBatchResult> searchBatch({
    required List<String> queries,
    required String? sessionId,
    required String routing,
    required String tracePrefix,
    String? cancelGroup,
    bool interruptible = true,
    int maxResultsChars = 5000,
  }) async {
    final normalized = _normalizeQueries(queries);
    if (normalized.isEmpty) {
      return const WebSearchBatchResult(
        traceIds: [],
        queries: [],
        rawResults: [],
        combinedSnippet: '',
      );
    }

    final traceIds = <String>[];
    final futures = <Future<String>>[];
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < normalized.length; i += 1) {
      final traceId = '${tracePrefix}_${ts}_$i';
      traceIds.add(traceId);
      futures.add(
        _dispatchToolIntent(
          ToolIntent(
            action: ToolAction.search,
            query: normalized[i],
            sessionId: sessionId,
            traceId: traceId,
            routing: routing,
            cancelGroup: cancelGroup,
            interruptible: interruptible,
          ),
        ),
      );
    }

    final rawResults = await Future.wait(futures);
    final combined = _combineResults(
      queries: normalized,
      traceIds: traceIds,
      rawResults: rawResults,
      maxChars: maxResultsChars,
    );
    return WebSearchBatchResult(
      traceIds: traceIds,
      queries: normalized,
      rawResults: rawResults,
      combinedSnippet: combined,
    );
  }

  Future<WebSearchLoopResult> runSearchLoop({
    required WebSearchLoopConfig config,
  }) async {
    final allRounds = <WebSearchRoundResult>[];
    final seenQueryKeys = <String>{};
    final seenResultKeys = <String>{};
    var injectedChars = 0;

    for (var round = 1; round <= config.maxRounds; round += 1) {
      if (allRounds.isNotEmpty) {
        await Future<void>.delayed(config.roundCooldown);
      }

      final plan = await config.planQueries(
        round: round,
        priorRounds: allRounds,
      );
      final normalized = _normalizeQueries(plan)
          .where((q) => q.isNotEmpty)
          .where((q) {
            final key = q.toLowerCase();
            if (seenQueryKeys.contains(key)) return false;
            seenQueryKeys.add(key);
            return true;
          })
          .take(config.fanoutPerRound)
          .toList(growable: false);

      if (normalized.isEmpty) {
        allRounds.add(
          WebSearchRoundResult(
            round: round,
            plannedQueries: const [],
            executedQueries: const [],
            batch: const WebSearchBatchResult(
              traceIds: [],
              queries: [],
              rawResults: [],
              combinedSnippet: '',
            ),
            successful: 0,
            injectedSnippet: '',
            stopReason: 'no_queries',
          ),
        );
        break;
      }

      final batch = await searchBatch(
        queries: normalized,
        sessionId: config.sessionId,
        routing: config.routing,
        tracePrefix: '${config.tracePrefix}_r$round',
        cancelGroup: config.cancelGroup,
        interruptible: config.interruptible,
        maxResultsChars: config.maxPerRoundChars,
      );

      final injected = _extractUniqueSuccessfulSnippet(
        batch,
        seenResultKeys: seenResultKeys,
        isFailure: config.isFailure,
        maxChars: config.maxPerRoundChars,
      );

      final successful = _countSuccessful(batch, isFailure: config.isFailure);
      injectedChars += injected.length;
      final roundResult = WebSearchRoundResult(
        round: round,
        plannedQueries: plan,
        executedQueries: batch.queries,
        batch: batch,
        successful: successful,
        injectedSnippet: injected,
        stopReason: null,
      );
      allRounds.add(roundResult);

      final stop = await config.shouldStop(
        round: round,
        priorRounds: allRounds,
        lastRoundInjectedSnippet: injected,
        totalInjectedChars: injectedChars,
      );
      if (stop.stop) {
        allRounds[allRounds.length - 1] = roundResult.copyWith(
          stopReason: stop.reason ?? 'stop',
        );
        break;
      }
      if (injectedChars >= config.maxTotalInjectedChars) {
        allRounds[allRounds.length - 1] = roundResult.copyWith(
          stopReason: 'max_total_injected_chars',
        );
        break;
      }
    }

    final combined = _combineInjectedRounds(
      allRounds,
      config.maxTotalInjectedChars,
    );
    return WebSearchLoopResult(
      rounds: allRounds,
      combinedInjectedSnippet: combined,
    );
  }

  List<String> _normalizeQueries(List<String> queries) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in queries) {
      final q = raw.trim();
      if (q.isEmpty) continue;
      final key = q.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(q);
    }
    return out;
  }

  int _countSuccessful(
    WebSearchBatchResult batch, {
    required bool Function(String message) isFailure,
  }) {
    var success = 0;
    for (final raw in batch.rawResults) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (isFailure(trimmed)) continue;
      success += 1;
    }
    return success;
  }

  String _extractUniqueSuccessfulSnippet(
    WebSearchBatchResult batch, {
    required Set<String> seenResultKeys,
    required bool Function(String message) isFailure,
    required int maxChars,
  }) {
    final buffer = StringBuffer();
    for (var i = 0; i < batch.queries.length; i += 1) {
      final raw = batch.rawResults[i].trim();
      if (raw.isEmpty || isFailure(raw)) {
        continue;
      }
      final key = _stableKeyForSnippet(raw);
      if (seenResultKeys.contains(key)) {
        continue;
      }
      seenResultKeys.add(key);
      if (buffer.length > 0) buffer.writeln('\n');
      buffer.writeln('### ${batch.queries[i]}');
      buffer.writeln('trace_id: ${batch.traceIds[i]}');
      buffer.writeln(raw);
      if (buffer.length >= maxChars) {
        break;
      }
    }
    final text = buffer.toString().trim();
    if (text.length <= maxChars) {
      return text;
    }
    return '${text.substring(0, maxChars)}...';
  }

  String _combineInjectedRounds(
    List<WebSearchRoundResult> rounds,
    int maxChars,
  ) {
    final buffer = StringBuffer();
    for (final round in rounds) {
      final snippet = round.injectedSnippet.trim();
      if (snippet.isEmpty) continue;
      if (buffer.length > 0) buffer.writeln('\n');
      buffer.writeln('[Round ${round.round}]');
      buffer.writeln(snippet);
      if (buffer.length >= maxChars) {
        break;
      }
    }
    final combined = buffer.toString().trim();
    if (combined.length <= maxChars) {
      return combined;
    }
    return '${combined.substring(0, maxChars)}...';
  }

  String _stableKeyForSnippet(String text) {
    final normalized = text
        .replaceAll('\u200B', '')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length <= 400) {
      return normalized;
    }
    return normalized.substring(0, 400);
  }

  String _combineResults({
    required List<String> queries,
    required List<String> traceIds,
    required List<String> rawResults,
    required int maxChars,
  }) {
    final buffer = StringBuffer();
    for (var i = 0; i < queries.length; i += 1) {
      if (i > 0) buffer.writeln('\n');
      buffer.writeln('### Query ${i + 1}: ${queries[i]}');
      buffer.writeln('trace_id: ${traceIds[i]}');
      final text = rawResults[i].trim();
      buffer.writeln(text.isEmpty ? '(empty)' : text);
      if (buffer.length >= maxChars) {
        break;
      }
    }
    final combined = buffer.toString().trim();
    if (combined.length <= maxChars) {
      return combined;
    }
    return '${combined.substring(0, maxChars)}...';
  }
}

class WebSearchBatchResult {
  const WebSearchBatchResult({
    required this.traceIds,
    required this.queries,
    required this.rawResults,
    required this.combinedSnippet,
  });

  final List<String> traceIds;
  final List<String> queries;
  final List<String> rawResults;
  final String combinedSnippet;
}

class WebSearchLoopConfig {
  const WebSearchLoopConfig({
    required this.sessionId,
    required this.routing,
    required this.tracePrefix,
    this.cancelGroup,
    this.interruptible = true,
    required this.maxRounds,
    required this.fanoutPerRound,
    required this.maxPerRoundChars,
    required this.maxTotalInjectedChars,
    required this.roundCooldown,
    required this.planQueries,
    required this.shouldStop,
    required this.isFailure,
  });

  final String? sessionId;
  final String routing;
  final String tracePrefix;
  final String? cancelGroup;
  final bool interruptible;
  final int maxRounds;
  final int fanoutPerRound;
  final int maxPerRoundChars;
  final int maxTotalInjectedChars;
  final Duration roundCooldown;
  final Future<List<String>> Function({
    required int round,
    required List<WebSearchRoundResult> priorRounds,
  })
  planQueries;
  final Future<WebSearchStopDecision> Function({
    required int round,
    required List<WebSearchRoundResult> priorRounds,
    required String lastRoundInjectedSnippet,
    required int totalInjectedChars,
  })
  shouldStop;
  final bool Function(String message) isFailure;
}

class WebSearchStopDecision {
  const WebSearchStopDecision({required this.stop, this.reason});

  final bool stop;
  final String? reason;

  static const continueSearch = WebSearchStopDecision(stop: false);
  static const stopDefault = WebSearchStopDecision(stop: true);
}

class WebSearchRoundResult {
  const WebSearchRoundResult({
    required this.round,
    required this.plannedQueries,
    required this.executedQueries,
    required this.batch,
    required this.successful,
    required this.injectedSnippet,
    required this.stopReason,
  });

  final int round;
  final List<String> plannedQueries;
  final List<String> executedQueries;
  final WebSearchBatchResult batch;
  final int successful;
  final String injectedSnippet;
  final String? stopReason;

  WebSearchRoundResult copyWith({String? stopReason}) {
    return WebSearchRoundResult(
      round: round,
      plannedQueries: plannedQueries,
      executedQueries: executedQueries,
      batch: batch,
      successful: successful,
      injectedSnippet: injectedSnippet,
      stopReason: stopReason ?? this.stopReason,
    );
  }

  Map<String, dynamic> toJson() => {
    'round': round,
    'planned_queries': plannedQueries,
    'executed_queries': executedQueries,
    'trace_ids': batch.traceIds,
    'successful': successful,
    'stop_reason': stopReason,
  };
}

class WebSearchLoopResult {
  const WebSearchLoopResult({
    required this.rounds,
    required this.combinedInjectedSnippet,
  });

  final List<WebSearchRoundResult> rounds;
  final String combinedInjectedSnippet;

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert({
    'rounds': rounds.map((r) => r.toJson()).toList(growable: false),
    'combined_len': combinedInjectedSnippet.length,
  });
}
