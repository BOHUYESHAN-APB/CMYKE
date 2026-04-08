import 'package:flutter_test/flutter_test.dart';

import 'package:cmyke/core/models/tool_intent.dart';
import 'package:cmyke/core/services/web_search_orchestrator.dart';

void main() {
  group('WebSearchOrchestrator', () {
    test(
      'searchBatch dispatches all queries in parallel and returns combined',
      () async {
        final seen = <String>[];
        final orchestrator = WebSearchOrchestrator(
          dispatchToolIntent: (intent) async {
            expect(intent.action, ToolAction.search);
            expect(intent.cancelGroup, 'session:s1');
            expect(intent.interruptible, isTrue);
            seen.add(intent.query ?? '');
            return 'result:${intent.query}';
          },
        );

        final out = await orchestrator.searchBatch(
          queries: const ['a', 'b', 'a', '  ', 'B'],
          sessionId: 's1',
          routing: 'standard_chat',
          tracePrefix: 't',
          cancelGroup: 'session:s1',
          maxResultsChars: 2000,
        );

        // Dedup + trim should keep: a, b
        expect(out.queries, const ['a', 'b']);
        expect(out.rawResults.length, 2);
        expect(out.traceIds.length, 2);
        expect(out.combinedSnippet, contains('### Query 1: a'));
        expect(out.combinedSnippet, contains('### Query 2: b'));
        expect(seen, containsAll(const ['a', 'b']));
      },
    );

    test(
      'runSearchLoop stops on shouldStop and dedupes repeated results',
      () async {
        var callCount = 0;
        final orchestrator = WebSearchOrchestrator(
          dispatchToolIntent: (intent) async {
            callCount += 1;
            final q = intent.query ?? '';
            // Return identical content for q=dup to test dedupe across rounds.
            if (q == 'dup') return 'SAME_RESULT';
            return 'R:$q';
          },
        );

        final loop = await orchestrator.runSearchLoop(
          config: WebSearchLoopConfig(
            sessionId: 's1',
            routing: 'deep_research',
            tracePrefix: 'dr',
            cancelGroup: 'session:s1',
            maxRounds: 5,
            fanoutPerRound: 4,
            maxPerRoundChars: 2000,
            maxTotalInjectedChars: 2000,
            roundCooldown: Duration.zero,
            planQueries: ({required round, required priorRounds}) async {
              if (round == 1) return const ['dup', 'x'];
              if (round == 2) return const ['dup', 'y'];
              return const ['z'];
            },
            shouldStop:
                ({
                  required round,
                  required priorRounds,
                  required lastRoundInjectedSnippet,
                  required totalInjectedChars,
                }) async {
                  if (round >= 2) {
                    return const WebSearchStopDecision(
                      stop: true,
                      reason: 'enough',
                    );
                  }
                  return WebSearchStopDecision.continueSearch;
                },
            isFailure: (msg) => msg.startsWith('ERROR'),
          ),
        );

        expect(loop.rounds.length, 2);
        expect(loop.rounds.last.stopReason, 'enough');
        // Round2 should not re-inject SAME_RESULT (dedup across rounds).
        expect(loop.rounds.first.injectedSnippet, contains('SAME_RESULT'));
        expect(
          loop.rounds.last.injectedSnippet,
          isNot(contains('SAME_RESULT')),
        );
        // round2's "dup" is query-deduped (already executed in round1).
        expect(callCount, 3); // round1:2 queries, round2:1 query
      },
    );
  });
}
