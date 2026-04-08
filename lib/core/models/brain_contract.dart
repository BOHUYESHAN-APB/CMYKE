import 'app_settings.dart';

enum BrainRole { left, right }

enum BrainEscalationMode { leftOnly, onDemand }

class BrainEndpointContract {
  const BrainEndpointContract({
    required this.role,
    required this.label,
    required this.route,
    required this.providerId,
    required this.primary,
  });

  final BrainRole role;
  final String label;
  final ModelRoute route;
  final String? providerId;
  final bool primary;

  bool get isConfigured => providerId?.trim().isNotEmpty == true;
}

class BrainContract {
  const BrainContract({
    required this.sourceRoute,
    required this.leftBrain,
    required this.rightBrain,
    required this.escalationMode,
  });

  factory BrainContract.fromSettings(AppSettings settings) {
    final leftRoute = settings.route;
    final leftProviderId = switch (leftRoute) {
      ModelRoute.standard => settings.llmProviderId,
      ModelRoute.realtime => settings.realtimeProviderId,
      ModelRoute.omni => settings.omniProviderId,
    };
    final leftLabel = switch (leftRoute) {
      ModelRoute.standard => '左脑（standard）',
      ModelRoute.realtime => '左脑（realtime）',
      ModelRoute.omni => '左脑（omni）',
    };
    final escalationMode = switch (leftRoute) {
      ModelRoute.standard => BrainEscalationMode.leftOnly,
      ModelRoute.realtime || ModelRoute.omni => BrainEscalationMode.onDemand,
    };
    return BrainContract(
      sourceRoute: leftRoute,
      leftBrain: BrainEndpointContract(
        role: BrainRole.left,
        label: leftLabel,
        route: leftRoute,
        providerId: leftProviderId,
        primary: true,
      ),
      rightBrain: BrainEndpointContract(
        role: BrainRole.right,
        label: '右脑（深度推理）',
        route: ModelRoute.standard,
        providerId: settings.llmProviderId,
        primary: false,
      ),
      escalationMode: escalationMode,
    );
  }

  final ModelRoute sourceRoute;
  final BrainEndpointContract leftBrain;
  final BrainEndpointContract? rightBrain;
  final BrainEscalationMode escalationMode;

  bool get canEscalateToRightBrain =>
      escalationMode == BrainEscalationMode.onDemand &&
      (rightBrain?.isConfigured ?? false);

  bool get usesDistinctRightBrain =>
      rightBrain != null && rightBrain!.providerId != leftBrain.providerId;
}
