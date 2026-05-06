import 'provider_config.dart';
import 'interaction_profile.dart';

class InteractionEndpointContract {
  const InteractionEndpointContract({
    required this.slot,
    required this.provider,
  });

  final String slot;
  final ProviderConfig? provider;

  String? get providerId => provider?.id;
  bool get isConfigured => providerId?.trim().isNotEmpty == true;
}

class InteractionContract {
  const InteractionContract({
    required this.profileId,
    required this.mode,
    required this.main,
    required this.embedding,
    required this.vision,
    required this.tts,
    required this.stt,
    required this.realtime,
    required this.omni,
    required this.leftBrain,
    required this.rightBrain,
    required this.options,
  });

  final String profileId;
  final InteractionMode mode;
  final InteractionEndpointContract main;
  final InteractionEndpointContract embedding;
  final InteractionEndpointContract vision;
  final InteractionEndpointContract tts;
  final InteractionEndpointContract stt;
  final InteractionEndpointContract realtime;
  final InteractionEndpointContract omni;
  final InteractionEndpointContract leftBrain;
  final InteractionEndpointContract rightBrain;
  final InteractionOptions options;

  bool get usesNativeAudio =>
      options.useNativeAudioInput || options.useNativeAudioOutput;
}
