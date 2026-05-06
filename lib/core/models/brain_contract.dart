import 'app_settings.dart';
import 'interaction_contract.dart';
import 'interaction_profile.dart';

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
    final bindings = settings.toInteractionBindings();
    final leftRoute = settings.route;
    final leftProviderId = bindings.leftBrainProviderId;
    final leftLabel = switch (settings.interactionMode) {
      InteractionMode.lightweight => '左脑（lightweight）',
      InteractionMode.nativeRealtime => '左脑（nativeRealtime）',
      InteractionMode.nativeOmni => '左脑（nativeOmni）',
      InteractionMode.composite => '左脑（composite）',
    };
    final escalationMode = switch (settings.interactionMode) {
      InteractionMode.lightweight => BrainEscalationMode.leftOnly,
      InteractionMode.nativeRealtime ||
      InteractionMode.nativeOmni ||
      InteractionMode.composite => BrainEscalationMode.onDemand,
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
        providerId: bindings.rightBrainProviderId,
        primary: false,
      ),
      escalationMode: escalationMode,
    );
  }

  factory BrainContract.fromInteractionContract(InteractionContract contract) {
    final leftRoute = switch (contract.mode) {
      InteractionMode.lightweight => ModelRoute.standard,
      InteractionMode.nativeRealtime => ModelRoute.realtime,
      InteractionMode.nativeOmni => ModelRoute.omni,
      InteractionMode.composite => ModelRoute.standard,
    };
    final leftLabel = switch (contract.mode) {
      InteractionMode.lightweight => '左脑（lightweight）',
      InteractionMode.nativeRealtime => '左脑（nativeRealtime）',
      InteractionMode.nativeOmni => '左脑（nativeOmni）',
      InteractionMode.composite => '左脑（composite）',
    };
    final escalationMode = contract.options.allowRightBrainEscalation
        ? BrainEscalationMode.onDemand
        : BrainEscalationMode.leftOnly;
    return BrainContract(
      sourceRoute: leftRoute,
      leftBrain: BrainEndpointContract(
        role: BrainRole.left,
        label: leftLabel,
        route: leftRoute,
        providerId: contract.leftBrain.providerId,
        primary: true,
      ),
      rightBrain: BrainEndpointContract(
        role: BrainRole.right,
        label: '右脑（深度推理）',
        route: ModelRoute.standard,
        providerId: contract.rightBrain.providerId,
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
