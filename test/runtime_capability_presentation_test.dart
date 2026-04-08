import 'package:cmyke/core/models/runtime_capability_snapshot.dart';
import 'package:cmyke/features/settings/provider_config_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Runtime capability presentation', () {
    test('maps state labels for operator UI', () {
      expect(RuntimeCapabilityState.unknown.label, '待探测');
      expect(RuntimeCapabilityState.ready.label, '已就绪');
      expect(RuntimeCapabilityState.degraded.label, '降级');
      expect(RuntimeCapabilityState.unavailable.label, '不可用');
    });

    test('builds fallback titles for known capability ids', () {
      expect(runtimeCapabilityFallbackTitle('fast_brain'), '快速对话脑');
      expect(runtimeCapabilityFallbackTitle('slow_brain'), '慢速推理脑');
      expect(runtimeCapabilityFallbackTitle('tool_gateway'), '工具网关');
    });

    test('formats gateway and provider detail lines', () {
      final gateway = RuntimeCapabilitySnapshot(
        capabilityId: 'tool_gateway',
        kind: RuntimeCapabilityKind.toolGateway,
        state: RuntimeCapabilityState.ready,
        enabled: true,
        checkedAt: DateTime(2026),
        routes: const {'/api/v1/opencode/run', '/api/v1/opencode/cancel'},
        features: const {'opencode_run'},
        activeRuns: 2,
      );
      final provider = RuntimeCapabilitySnapshot(
        capabilityId: 'fast_brain',
        state: RuntimeCapabilityState.ready,
        enabled: true,
        checkedAt: DateTime(2026),
        providerLabel: 'Fast Brain',
        providerModel: 'qwen-fast',
      );

      expect(runtimeCapabilityDetail(gateway), '路由 2 · 特性 1 · 活跃任务 2');
      expect(runtimeCapabilityDetail(provider), 'Fast Brain · qwen-fast');
    });
  });
}
