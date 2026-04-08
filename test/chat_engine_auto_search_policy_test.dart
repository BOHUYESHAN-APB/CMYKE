import 'package:cmyke/core/models/app_settings.dart';
import 'package:cmyke/core/models/runtime_capability_snapshot.dart';
import 'package:cmyke/core/services/chat_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('standardModeAutoSearchGatewayDegradeMessage', () {
    AppSettings settings({
      ModelRoute route = ModelRoute.standard,
      bool standardWebSearchEnabled = true,
      bool toolGatewayEnabled = true,
      String toolGatewayBaseUrl = 'http://127.0.0.1:8080',
      String toolGatewayPairingToken = 'token',
    }) {
      return AppSettings(
        route: route,
        standardWebSearchEnabled: standardWebSearchEnabled,
        toolGatewayEnabled: toolGatewayEnabled,
        toolGatewayBaseUrl: toolGatewayBaseUrl,
        toolGatewayPairingToken: toolGatewayPairingToken,
      );
    }

    RuntimeCapabilitySnapshot gatewaySnapshot({
      RuntimeCapabilityState state = RuntimeCapabilityState.ready,
      Set<String> routes = const {'/api/v1/opencode/run'},
      String? summary,
      String? error,
    }) {
      return RuntimeCapabilitySnapshot(
        capabilityId: 'tool_gateway',
        kind: RuntimeCapabilityKind.toolGateway,
        state: state,
        enabled: true,
        checkedAt: DateTime(2026),
        summary: summary,
        error: error,
        routes: routes,
      );
    }

    test('returns null when standard auto search is not active', () {
      expect(
        standardModeAutoSearchGatewayDegradeMessage(
          settings: settings(route: ModelRoute.realtime),
          snapshot: gatewaySnapshot(),
        ),
        isNull,
      );
      expect(
        standardModeAutoSearchGatewayDegradeMessage(
          settings: settings(standardWebSearchEnabled: false),
          snapshot: gatewaySnapshot(),
        ),
        isNull,
      );
      expect(
        standardModeAutoSearchGatewayDegradeMessage(
          settings: settings(toolGatewayPairingToken: ''),
          snapshot: gatewaySnapshot(),
        ),
        isNull,
      );
    });

    test('returns snapshot error or summary when gateway is unusable', () {
      expect(
        standardModeAutoSearchGatewayDegradeMessage(
          settings: settings(),
          snapshot: gatewaySnapshot(
            state: RuntimeCapabilityState.unavailable,
            error: '工具网关请求失败：timeout',
          ),
        ),
        '工具网关请求失败：timeout',
      );

      expect(
        standardModeAutoSearchGatewayDegradeMessage(
          settings: settings(),
          snapshot: gatewaySnapshot(
            state: RuntimeCapabilityState.unavailable,
            summary: '工具网关暂不可用',
          ),
        ),
        '工具网关暂不可用',
      );
    });

    test('returns explicit message when run route is missing', () {
      expect(
        standardModeAutoSearchGatewayDegradeMessage(
          settings: settings(),
          snapshot: gatewaySnapshot(routes: const {'/api/v1/opencode/cancel'}),
        ),
        '基础模式联网搜索跳过：当前工具网关未暴露运行接口。',
      );
    });

    test('returns null when gateway is usable and run route exists', () {
      expect(
        standardModeAutoSearchGatewayDegradeMessage(
          settings: settings(),
          snapshot: gatewaySnapshot(),
        ),
        isNull,
      );
    });
  });
}
