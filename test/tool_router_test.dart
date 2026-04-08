import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cmyke/core/models/tool_gateway_skill.dart';
import 'package:cmyke/core/models/tool_intent.dart';
import 'package:cmyke/core/services/tool_router.dart';

void main() {
  group('ToolRouter', () {
    test('probeCapabilities parses response and caches it briefly', () async {
      var capabilityCalls = 0;
      final router = ToolRouter(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/gateway/capabilities') {
            capabilityCalls += 1;
            return http.Response(
              jsonEncode({
                'ok': true,
                'routes': ['/api/v1/opencode/run', '/api/v1/opencode/cancel'],
                'features': ['opencode_run', 'opencode_cancel'],
                'runtime': {'active_runs': 2},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      );
      router.updateGatewayConfig(
        const ToolGatewayConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:4891',
          pairingToken: 'pair',
        ),
      );

      final first = await router.probeCapabilities();
      final second = await router.probeCapabilities();

      expect(first.ok, isTrue);
      expect(first.supportsRun, isTrue);
      expect(first.supportsCancel, isTrue);
      expect(first.supportsFeature('opencode_cancel'), isTrue);
      expect(first.activeRuns, 2);
      expect(second.activeRuns, 2);
      expect(capabilityCalls, 1);
    });

    test('cancelActiveRun posts session cancel payload', () async {
      Map<String, dynamic>? cancelPayload;
      final router = ToolRouter(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/gateway/capabilities') {
            return http.Response(
              jsonEncode({
                'ok': true,
                'routes': ['/api/v1/opencode/run', '/api/v1/opencode/cancel'],
                'features': ['opencode_run', 'opencode_cancel'],
                'runtime': {'active_runs': 1},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/v1/opencode/cancel') {
            cancelPayload = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'ok': true,
                'accepted': true,
                'active_runs_signaled': 1,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      );
      router.updateGatewayConfig(
        const ToolGatewayConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:4891',
          pairingToken: 'pair',
        ),
      );

      final result = await router.cancelActiveRun(
        sessionId: 's1',
        cancelGroup: 'session:s1',
        reason: 'chat_interrupt',
      );

      expect(result.ok, isTrue);
      expect(result.accepted, isTrue);
      expect(result.activeRunsSignaled, 1);
      expect(cancelPayload?['pairing_token'], 'pair');
      expect(cancelPayload?['session_id'], 's1');
      expect(cancelPayload?['cancel_group'], 'session:s1');
      expect(cancelPayload?['reason'], 'chat_interrupt');
    });

    test(
      'dispatch sends cancel group and interruptible to run endpoint',
      () async {
        Map<String, dynamic>? runPayload;
        final router = ToolRouter(
          client: MockClient((request) async {
            if (request.url.path == '/api/v1/gateway/capabilities') {
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'routes': ['/api/v1/opencode/run'],
                  'features': ['opencode_run'],
                  'runtime': {'active_runs': 0},
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/api/v1/opencode/run') {
              runPayload = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode({'ok': true, 'stdout': 'done', 'stderr': ''}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }),
        );
        router.updateGatewayConfig(
          const ToolGatewayConfig(
            enabled: true,
            baseUrl: 'http://127.0.0.1:4891',
            pairingToken: 'pair',
          ),
        );

        final output = await router.dispatch(
          const ToolIntent(
            action: ToolAction.search,
            query: 'latest release notes',
            sessionId: 's1',
            traceId: 'trace_1',
            cancelGroup: 'session:s1',
            interruptible: false,
            routing: 'standard_chat',
          ),
        );

        expect(output, 'done');
        expect(runPayload?['pairing_token'], 'pair');
        expect(runPayload?['session_id'], 's1');
        expect(runPayload?['trace_id'], 'trace_1');
        expect(runPayload?['cancel_group'], 'session:s1');
        expect(runPayload?['interruptible'], isFalse);
      },
    );

    test('fetchInstalledSkills parses structured catalog payload', () async {
      Map<String, dynamic>? catalogPayload;
      final router = ToolRouter(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/gateway/capabilities') {
            return http.Response(
              jsonEncode({
                'ok': true,
                'routes': ['/api/v1/opencode/skills/installed'],
                'features': ['skills_catalog'],
                'runtime': {'active_runs': 0},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/v1/opencode/skills/installed') {
            catalogPayload = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'ok': true,
                'skills': ['legacy_name'],
                'items': [
                  {
                    'name': 'zweack__git-summary',
                    'display_name': 'Git Summary',
                    'description': 'Summarize repository changes.',
                    'author': 'zweack',
                    'version': '1.2.0',
                    'tags': ['git', 'summary'],
                    'status': 'installed',
                    'relative_path': 'zweack/git-summary',
                    'has_frontmatter': true,
                    'requirements': {
                      'bins': ['git'],
                      'env': ['GITHUB_TOKEN'],
                      'os': ['windows'],
                    },
                    'source': {
                      'type': 'git',
                      'label': 'owner/repo',
                      'location': 'https://github.com/acme/skills.git',
                    },
                  },
                ],
                'opencode_root': 'workspace/_shared/opencode',
                'config_path': 'workspace/_shared/opencode/config.json',
                'config_dir': 'workspace/_shared/opencode',
                'skill_dir': 'workspace/_shared/opencode/.opencode/skill',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      );
      router.updateGatewayConfig(
        const ToolGatewayConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:4891',
          pairingToken: 'pair',
        ),
      );

      final result = await router.fetchInstalledSkills();

      expect(catalogPayload?['pairing_token'], 'pair');
      expect(result.skills, hasLength(1));
      expect(result.skills.single.title, 'Git Summary');
      expect(result.skills.single.requirements.bins, ['git']);
      expect(
        result.skills.single.source?.location,
        'https://github.com/acme/skills.git',
      );
      expect(result.skillDir, 'workspace/_shared/opencode/.opencode/skill');
    });

    test(
      'previewSkillsImport posts git source and parses preview counts',
      () async {
        Map<String, dynamic>? previewPayload;
        final router = ToolRouter(
          client: MockClient((request) async {
            if (request.url.path == '/api/v1/gateway/capabilities') {
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'routes': ['/api/v1/opencode/skills/preview'],
                  'features': ['skills_preview'],
                  'runtime': {'active_runs': 0},
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/api/v1/opencode/skills/preview') {
              previewPayload = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'items': [
                    {
                      'name': 'author__skill__variant',
                      'display_name': 'Skill Variant',
                      'status': 'will_overwrite',
                      'source': {
                        'type': 'git',
                        'label': 'acme/skills',
                        'location': 'https://github.com/acme/skills.git',
                        'root': 'skills',
                        'ref': 'main',
                      },
                    },
                  ],
                  'errors': ['missing optional env'],
                  'skill_dir': 'workspace/_shared/opencode/.opencode/skill',
                  'total': 1,
                  'ready': 0,
                  'conflicts': 0,
                  'overwrites': 1,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }),
        );
        router.updateGatewayConfig(
          const ToolGatewayConfig(
            enabled: true,
            baseUrl: 'http://127.0.0.1:4891',
            pairingToken: 'pair',
          ),
        );

        final result = await router.previewSkillsImport(
          source: ToolGatewaySkillImportSource.git(
            url: 'https://github.com/acme/skills.git',
            ref: 'main',
            root: 'skills',
          ),
          overwrite: true,
          limit: 99,
        );

        expect(previewPayload?['pairing_token'], 'pair');
        expect(previewPayload?['overwrite'], isTrue);
        expect(previewPayload?['limit'], 99);
        expect(previewPayload?['source']['type'], 'git');
        expect(
          previewPayload?['source']['url'],
          'https://github.com/acme/skills.git',
        );
        expect(result.overwrites, 1);
        expect(result.errors, ['missing optional env']);
        expect(result.items.single.status, 'will_overwrite');
      },
    );

    test(
      'installSkills posts local source and parses install result',
      () async {
        Map<String, dynamic>? installPayload;
        final router = ToolRouter(
          client: MockClient((request) async {
            if (request.url.path == '/api/v1/gateway/capabilities') {
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'routes': ['/api/v1/opencode/skills/install'],
                  'features': ['skills_install'],
                  'runtime': {'active_runs': 0},
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/api/v1/opencode/skills/install') {
              installPayload = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'installed': ['author__skill'],
                  'skipped': ['author__existing'],
                  'errors': [],
                  'skill_dir': 'workspace/_shared/opencode/.opencode/skill',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }),
        );
        router.updateGatewayConfig(
          const ToolGatewayConfig(
            enabled: true,
            baseUrl: 'http://127.0.0.1:4891',
            pairingToken: 'pair',
          ),
        );

        final result = await router.installSkills(
          source: ToolGatewaySkillImportSource.local(
            path: 'Studying/deep_research/openclaw-skills',
            root: 'skills',
          ),
        );

        expect(installPayload?['pairing_token'], 'pair');
        expect(installPayload?['overwrite'], isFalse);
        expect(installPayload?['source']['type'], 'local');
        expect(
          installPayload?['source']['path'],
          'Studying/deep_research/openclaw-skills',
        );
        expect(result.installed, ['author__skill']);
        expect(result.skipped, ['author__existing']);
      },
    );
  });
}
