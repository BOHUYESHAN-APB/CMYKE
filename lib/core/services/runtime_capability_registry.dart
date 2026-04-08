import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/brain_contract.dart';
import '../models/provider_config.dart';
import '../models/runtime_capability_snapshot.dart';
import 'tool_router.dart';

typedef RuntimeProviderResolver = ProviderConfig? Function(String? providerId);

class RuntimeCapabilityRegistry extends ChangeNotifier {
  RuntimeCapabilityRegistry({required ToolRouter toolRouter})
    : _toolRouter = toolRouter;

  final ToolRouter _toolRouter;

  RuntimeCapabilitySnapshot _toolGateway = RuntimeCapabilitySnapshot.initial(
    'tool_gateway',
  );
  RuntimeCapabilitySnapshot _fastBrain = RuntimeCapabilitySnapshot.initial(
    'fast_brain',
  );
  RuntimeCapabilitySnapshot _slowBrain = RuntimeCapabilitySnapshot.initial(
    'slow_brain',
  );
  RuntimeCapabilitySnapshot _realtimeBrain = RuntimeCapabilitySnapshot.initial(
    'realtime_brain',
  );
  RuntimeCapabilitySnapshot _omniBrain = RuntimeCapabilitySnapshot.initial(
    'omni_brain',
  );
  RuntimeCapabilitySnapshot _vision = RuntimeCapabilitySnapshot.initial(
    'vision',
  );

  RuntimeCapabilitySnapshot get toolGateway => _toolGateway;
  RuntimeCapabilitySnapshot get fastBrain => _fastBrain;
  RuntimeCapabilitySnapshot get slowBrain => _slowBrain;
  RuntimeCapabilitySnapshot get realtimeBrain => _realtimeBrain;
  RuntimeCapabilitySnapshot get omniBrain => _omniBrain;
  RuntimeCapabilitySnapshot get vision => _vision;

  void updateToolGatewayConfig(AppSettings settings) {
    final enabled =
        settings.toolGatewayEnabled &&
        settings.toolGatewayBaseUrl.trim().isNotEmpty &&
        settings.toolGatewayPairingToken.trim().isNotEmpty;
    _toolGateway = _toolGateway.copyWith(
      kind: RuntimeCapabilityKind.toolGateway,
      enabled: enabled,
      checkedAt: DateTime.now(),
      state: enabled
          ? RuntimeCapabilityState.unknown
          : RuntimeCapabilityState.unavailable,
      summary: enabled ? '工具网关等待探测。' : '工具网关未启用。',
      error: null,
      routes: const <String>{},
      features: const <String>{},
      activeRuns: 0,
    );
    notifyListeners();
  }

  void updateProviderSnapshots({
    required AppSettings settings,
    required RuntimeProviderResolver findProvider,
  }) {
    _fastBrain = _buildFastBrainSnapshot(settings, findProvider);
    _slowBrain = _buildSlowBrainSnapshot(settings, findProvider);
    _realtimeBrain = _buildRealtimeSnapshot(settings, findProvider);
    _omniBrain = _buildOmniSnapshot(settings, findProvider);
    _vision = _buildVisionSnapshot(settings, findProvider);
    notifyListeners();
  }

  Future<RuntimeCapabilitySnapshot> refreshToolGateway({
    bool forceRefresh = false,
  }) async {
    final probe = await _toolRouter.probeCapabilities(
      forceRefresh: forceRefresh,
    );
    _toolGateway = RuntimeCapabilitySnapshot(
      capabilityId: 'tool_gateway',
      kind: RuntimeCapabilityKind.toolGateway,
      state: _mapToolGatewayState(probe),
      enabled: probe.enabled,
      checkedAt: probe.checkedAt,
      summary: _toolGatewaySummary(probe),
      error: probe.error,
      routes: probe.routes,
      features: probe.features,
      activeRuns: probe.activeRuns,
    );
    notifyListeners();
    return _toolGateway;
  }

  RuntimeCapabilityState _mapToolGatewayState(ToolGatewayProbeResult probe) {
    if (!probe.enabled) {
      return RuntimeCapabilityState.unavailable;
    }
    if (probe.ok && probe.supportsRun) {
      return RuntimeCapabilityState.ready;
    }
    if (probe.supportsRun || probe.supportsCancel) {
      return RuntimeCapabilityState.degraded;
    }
    return RuntimeCapabilityState.unavailable;
  }

  String _toolGatewaySummary(ToolGatewayProbeResult probe) {
    if (!probe.enabled) {
      return '工具网关未启用。';
    }
    if (probe.ok && probe.supportsRun && probe.supportsCancel) {
      return probe.activeRuns > 0
          ? '工具网关可用，当前活跃任务 ${probe.activeRuns} 个。'
          : '工具网关可用，支持运行与取消。';
    }
    if (probe.ok && probe.supportsRun) {
      return '工具网关可运行，但取消能力不可用。';
    }
    if (probe.ok && probe.supportsCancel) {
      return '工具网关仅暴露取消能力，运行能力缺失。';
    }
    return probe.error ?? '工具网关不可用。';
  }

  RuntimeCapabilitySnapshot _buildFastBrainSnapshot(
    AppSettings settings,
    RuntimeProviderResolver findProvider,
  ) {
    final contract = BrainContract.fromSettings(settings);
    final provider = findProvider(contract.leftBrain.providerId);
    return _buildProviderSnapshot(
      capabilityId: 'fast_brain',
      label: contract.leftBrain.label,
      providerId: contract.leftBrain.providerId,
      provider: provider,
      requireAudioRealtime:
          settings.route == ModelRoute.realtime ||
          settings.route == ModelRoute.omni,
    );
  }

  RuntimeCapabilitySnapshot _buildSlowBrainSnapshot(
    AppSettings settings,
    RuntimeProviderResolver findProvider,
  ) {
    final contract = BrainContract.fromSettings(settings);
    final providerId = contract.rightBrain?.providerId;
    final provider = findProvider(providerId);
    return _buildProviderSnapshot(
      capabilityId: 'slow_brain',
      label: contract.rightBrain?.label ?? '右脑（未配置）',
      providerId: providerId,
      provider: provider,
      requireAudioRealtime: false,
    );
  }

  RuntimeCapabilitySnapshot _buildRealtimeSnapshot(
    AppSettings settings,
    RuntimeProviderResolver findProvider,
  ) {
    final provider = findProvider(settings.realtimeProviderId);
    return _buildProviderSnapshot(
      capabilityId: 'realtime_brain',
      label: '实时语音脑',
      providerId: settings.realtimeProviderId,
      provider: provider,
      requireAudioRealtime: true,
    );
  }

  RuntimeCapabilitySnapshot _buildOmniSnapshot(
    AppSettings settings,
    RuntimeProviderResolver findProvider,
  ) {
    final provider = findProvider(settings.omniProviderId);
    return _buildProviderSnapshot(
      capabilityId: 'omni_brain',
      label: '全模态脑',
      providerId: settings.omniProviderId,
      provider: provider,
      requireAudioRealtime: true,
    );
  }

  RuntimeCapabilitySnapshot _buildVisionSnapshot(
    AppSettings settings,
    RuntimeProviderResolver findProvider,
  ) {
    final provider =
        findProvider(settings.visionProviderId) ??
        findProvider(settings.omniProviderId) ??
        findProvider(settings.llmProviderId);
    final explicitId = settings.visionProviderId;
    return _buildProviderSnapshot(
      capabilityId: 'vision',
      label: '视觉理解脑',
      providerId: explicitId ?? provider?.id,
      provider: provider,
      requireVision: true,
    );
  }

  RuntimeCapabilitySnapshot _buildProviderSnapshot({
    required String capabilityId,
    required String label,
    required String? providerId,
    required ProviderConfig? provider,
    bool requireVision = false,
    bool requireAudioRealtime = false,
  }) {
    final now = DateTime.now();
    if (providerId == null || providerId.trim().isEmpty) {
      return RuntimeCapabilitySnapshot(
        capabilityId: capabilityId,
        state: RuntimeCapabilityState.unavailable,
        enabled: false,
        checkedAt: now,
        summary: '$label 未配置。',
        error: null,
        providerId: providerId,
      );
    }
    if (provider == null) {
      return RuntimeCapabilitySnapshot(
        capabilityId: capabilityId,
        state: RuntimeCapabilityState.unavailable,
        enabled: false,
        checkedAt: now,
        summary: '$label 找不到已选提供者。',
        error: 'provider_missing',
        providerId: providerId,
      );
    }

    final hasEndpoint =
        provider.baseUrl.trim().isNotEmpty ||
        provider.protocol == ProviderProtocol.deviceBuiltin;
    final hasModel =
        provider.model.trim().isNotEmpty ||
        provider.protocol == ProviderProtocol.deviceBuiltin;
    final hasVision = provider.capabilities.contains(ProviderCapability.vision);
    final hasAudioIn = provider.capabilities.contains(
      ProviderCapability.audioIn,
    );
    final hasAudioOut = provider.capabilities.contains(
      ProviderCapability.audioOut,
    );
    final hasBargeIn = provider.capabilities.contains(
      ProviderCapability.bargeIn,
    );

    var state = RuntimeCapabilityState.ready;
    String? summary = '$label 已就绪：${provider.name}';
    String? error;

    if (!hasEndpoint || !hasModel) {
      state = RuntimeCapabilityState.unavailable;
      summary = '$label 配置不完整。';
      error = 'provider_config_incomplete';
    } else if (requireVision && !hasVision) {
      state = RuntimeCapabilityState.degraded;
      summary = '$label 可用，但缺少视觉能力。';
      error = 'vision_capability_missing';
    } else if (requireAudioRealtime && (!hasAudioIn || !hasAudioOut)) {
      state = RuntimeCapabilityState.degraded;
      summary = hasBargeIn
          ? '$label 可用，但音频输入/输出能力不完整。'
          : '$label 可用，但实时语音能力不足。';
      error = 'realtime_capability_partial';
    }

    return RuntimeCapabilitySnapshot(
      capabilityId: capabilityId,
      state: state,
      enabled: state != RuntimeCapabilityState.unavailable,
      checkedAt: now,
      summary: summary,
      error: error,
      providerId: provider.id,
      providerLabel: provider.name,
      providerModel: provider.model,
    );
  }
}
