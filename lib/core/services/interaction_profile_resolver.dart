import '../models/interaction_contract.dart';
import '../models/interaction_profile.dart';
import '../models/provider_config.dart';

class InteractionProfileResolver {
  const InteractionProfileResolver();

  InteractionContract resolve({
    required InteractionProfile profile,
    required List<ProviderConfig> providers,
  }) {
    ProviderConfig? byId(String? id) {
      if (id == null || id.trim().isEmpty) {
        return null;
      }
      for (final provider in providers) {
        if (provider.id == id) {
          return provider;
        }
      }
      return null;
    }

    final bindings = profile.bindings;
    final mainProvider = switch (profile.mode) {
      InteractionMode.lightweight => byId(bindings.llmProviderId),
      InteractionMode.nativeRealtime => byId(bindings.realtimeProviderId),
      InteractionMode.nativeOmni => byId(bindings.omniProviderId),
      InteractionMode.composite =>
        byId(bindings.leftBrainProviderId) ?? byId(bindings.llmProviderId),
    };

    final leftBrainProvider = byId(bindings.leftBrainProviderId) ?? mainProvider;
    final rightBrainProvider = byId(bindings.rightBrainProviderId);

    return InteractionContract(
      profileId: profile.id,
      mode: profile.mode,
      main: InteractionEndpointContract(slot: 'main', provider: mainProvider),
      embedding: InteractionEndpointContract(
        slot: 'embedding',
        provider: byId(bindings.embeddingProviderId),
      ),
      vision: InteractionEndpointContract(
        slot: 'vision',
        provider: byId(bindings.visionProviderId),
      ),
      tts: InteractionEndpointContract(
        slot: 'tts',
        provider: byId(bindings.ttsProviderId),
      ),
      stt: InteractionEndpointContract(
        slot: 'stt',
        provider: byId(bindings.sttProviderId),
      ),
      realtime: InteractionEndpointContract(
        slot: 'realtime',
        provider: byId(bindings.realtimeProviderId),
      ),
      omni: InteractionEndpointContract(
        slot: 'omni',
        provider: byId(bindings.omniProviderId),
      ),
      leftBrain: InteractionEndpointContract(
        slot: 'left_brain',
        provider: leftBrainProvider,
      ),
      rightBrain: InteractionEndpointContract(
        slot: 'right_brain',
        provider: rightBrainProvider,
      ),
      options: profile.options,
    );
  }
}
