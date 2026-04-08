import 'package:cmyke/core/models/app_settings.dart';
import 'package:cmyke/core/models/provider_config.dart';
import 'package:cmyke/core/models/runtime_capability_snapshot.dart';
import 'package:cmyke/core/services/runtime_capability_registry.dart';
import 'package:cmyke/core/services/tool_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('RuntimeCapabilityRegistry', () {
    test('marks tool gateway ready when run endpoint is available', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"ok":true,"routes":["/api/v1/opencode/run","/api/v1/opencode/cancel"],"features":["cancel"],"runtime":{"active_runs":2}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final router = ToolRouter(client: client)
        ..updateGatewayConfig(
          const ToolGatewayConfig(
            enabled: true,
            baseUrl: 'http://127.0.0.1:4891',
            pairingToken: 'pair',
          ),
        );
      final registry = RuntimeCapabilityRegistry(toolRouter: router);

      final snapshot = await registry.refreshToolGateway(forceRefresh: true);

      expect(snapshot.state, RuntimeCapabilityState.ready);
      expect(snapshot.activeRuns, 2);
      expect(snapshot.routes.contains('/api/v1/opencode/run'), isTrue);
      expect(snapshot.summary, contains('当前活跃任务 2 个'));
    });

    test('marks tool gateway unavailable when disabled by settings', () {
      final registry = RuntimeCapabilityRegistry(toolRouter: ToolRouter());

      registry.updateToolGatewayConfig(
        AppSettings(route: ModelRoute.standard, toolGatewayEnabled: false),
      );

      expect(registry.toolGateway.state, RuntimeCapabilityState.unavailable);
      expect(registry.toolGateway.summary, '工具网关未启用。');
    });

    test(
      'marks tool gateway degraded when only cancel endpoint exists',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            '{"ok":true,"routes":["/api/v1/opencode/cancel"],"features":[],"runtime":{"active_runs":0}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final router = ToolRouter(client: client)
          ..updateGatewayConfig(
            const ToolGatewayConfig(
              enabled: true,
              baseUrl: 'http://127.0.0.1:4891',
              pairingToken: 'pair',
            ),
          );
        final registry = RuntimeCapabilityRegistry(toolRouter: router);

        final snapshot = await registry.refreshToolGateway(forceRefresh: true);

        expect(snapshot.state, RuntimeCapabilityState.degraded);
        expect(snapshot.summary, contains('取消能力'));
      },
    );

    test('builds provider snapshots for fast slow and vision brains', () {
      final registry = RuntimeCapabilityRegistry(toolRouter: ToolRouter());
      final llm = ProviderConfig(
        id: 'llm-1',
        name: 'LLM One',
        kind: ProviderKind.llm,
        protocol: ProviderProtocol.openaiCompatible,
        baseUrl: 'http://127.0.0.1:1234/v1',
        model: 'qwen-fast',
        capabilities: [ProviderCapability.tools],
      );
      final vision = ProviderConfig(
        id: 'vision-1',
        name: 'Vision One',
        kind: ProviderKind.visionAgent,
        protocol: ProviderProtocol.openaiCompatible,
        baseUrl: 'http://127.0.0.1:2345/v1',
        model: 'qwen-vision',
        capabilities: [ProviderCapability.vision],
      );

      registry.updateProviderSnapshots(
        settings: AppSettings(
          route: ModelRoute.standard,
          llmProviderId: 'llm-1',
          visionProviderId: 'vision-1',
        ),
        findProvider: (providerId) {
          switch (providerId) {
            case 'llm-1':
              return llm;
            case 'vision-1':
              return vision;
            default:
              return null;
          }
        },
      );

      expect(registry.fastBrain.state, RuntimeCapabilityState.ready);
      expect(registry.fastBrain.providerId, 'llm-1');
      expect(registry.fastBrain.providerLabel, 'LLM One');
      expect(registry.slowBrain.providerId, 'llm-1');
      expect(registry.vision.state, RuntimeCapabilityState.ready);
      expect(registry.vision.providerId, 'vision-1');
      expect(registry.vision.providerModel, 'qwen-vision');
    });

    test(
      'marks realtime brain degraded when audio capabilities are incomplete',
      () {
        final registry = RuntimeCapabilityRegistry(toolRouter: ToolRouter());
        final realtime = ProviderConfig(
          id: 'rt-1',
          name: 'Realtime One',
          kind: ProviderKind.realtime,
          protocol: ProviderProtocol.openaiCompatible,
          baseUrl: 'http://127.0.0.1:3456/v1',
          model: 'rt-model',
          capabilities: [ProviderCapability.audioIn],
        );

        registry.updateProviderSnapshots(
          settings: AppSettings(
            route: ModelRoute.realtime,
            realtimeProviderId: 'rt-1',
          ),
          findProvider: (providerId) => providerId == 'rt-1' ? realtime : null,
        );

        expect(registry.fastBrain.providerId, 'rt-1');
        expect(registry.fastBrain.state, RuntimeCapabilityState.degraded);
        expect(registry.realtimeBrain.state, RuntimeCapabilityState.degraded);
        expect(registry.realtimeBrain.error, 'realtime_capability_partial');
        expect(registry.realtimeBrain.summary, contains('实时语音能力不足'));
      },
    );

    test(
      'falls back to slow brain for vision and reports missing capability',
      () {
        final registry = RuntimeCapabilityRegistry(toolRouter: ToolRouter());
        final llm = ProviderConfig(
          id: 'llm-1',
          name: 'LLM One',
          kind: ProviderKind.llm,
          protocol: ProviderProtocol.openaiCompatible,
          baseUrl: 'http://127.0.0.1:1234/v1',
          model: 'qwen-fast',
        );

        registry.updateProviderSnapshots(
          settings: AppSettings(
            route: ModelRoute.standard,
            llmProviderId: 'llm-1',
          ),
          findProvider: (providerId) => providerId == 'llm-1' ? llm : null,
        );

        expect(registry.vision.providerId, 'llm-1');
        expect(registry.vision.state, RuntimeCapabilityState.degraded);
        expect(registry.vision.error, 'vision_capability_missing');
        expect(registry.vision.summary, contains('缺少视觉能力'));
      },
    );

    test('maps fast brain from route while slow brain stays on llm', () {
      final registry = RuntimeCapabilityRegistry(toolRouter: ToolRouter());
      final llm = ProviderConfig(
        id: 'llm-1',
        name: 'LLM One',
        kind: ProviderKind.llm,
        protocol: ProviderProtocol.openaiCompatible,
        baseUrl: 'http://127.0.0.1:1234/v1',
        model: 'qwen-fast',
      );
      final omni = ProviderConfig(
        id: 'omni-1',
        name: 'Omni One',
        kind: ProviderKind.omni,
        protocol: ProviderProtocol.openaiCompatible,
        baseUrl: 'http://127.0.0.1:4567/v1',
        model: 'qwen-omni',
        capabilities: [
          ProviderCapability.vision,
          ProviderCapability.audioIn,
          ProviderCapability.audioOut,
        ],
      );

      registry.updateProviderSnapshots(
        settings: AppSettings(
          route: ModelRoute.omni,
          llmProviderId: 'llm-1',
          omniProviderId: 'omni-1',
        ),
        findProvider: (providerId) {
          switch (providerId) {
            case 'llm-1':
              return llm;
            case 'omni-1':
              return omni;
            default:
              return null;
          }
        },
      );

      expect(registry.fastBrain.providerId, 'omni-1');
      expect(registry.fastBrain.state, RuntimeCapabilityState.ready);
      expect(registry.slowBrain.providerId, 'llm-1');
      expect(registry.slowBrain.state, RuntimeCapabilityState.ready);
      expect(registry.vision.providerId, 'omni-1');
      expect(registry.omniBrain.providerId, 'omni-1');
    });
  });
}
