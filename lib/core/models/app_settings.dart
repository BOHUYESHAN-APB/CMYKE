enum ModelRoute {
  standard,
  realtime,
  omni,
}

class AppSettings {
  AppSettings({
    required this.route,
    this.llmProviderId,
    this.visionProviderId,
    this.ttsProviderId,
    this.sttProviderId,
    this.realtimeProviderId,
    this.omniProviderId,
  });

  ModelRoute route;
  String? llmProviderId;
  String? visionProviderId;
  String? ttsProviderId;
  String? sttProviderId;
  String? realtimeProviderId;
  String? omniProviderId;

  AppSettings copyWith({
    ModelRoute? route,
    String? llmProviderId,
    String? visionProviderId,
    String? ttsProviderId,
    String? sttProviderId,
    String? realtimeProviderId,
    String? omniProviderId,
  }) {
    return AppSettings(
      route: route ?? this.route,
      llmProviderId: llmProviderId ?? this.llmProviderId,
      visionProviderId: visionProviderId ?? this.visionProviderId,
      ttsProviderId: ttsProviderId ?? this.ttsProviderId,
      sttProviderId: sttProviderId ?? this.sttProviderId,
      realtimeProviderId: realtimeProviderId ?? this.realtimeProviderId,
      omniProviderId: omniProviderId ?? this.omniProviderId,
    );
  }

  Map<String, dynamic> toJson() => {
        'route': route.name,
        'llm_provider_id': llmProviderId,
        'vision_provider_id': visionProviderId,
        'tts_provider_id': ttsProviderId,
        'stt_provider_id': sttProviderId,
        'realtime_provider_id': realtimeProviderId,
        'omni_provider_id': omniProviderId,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        route: ModelRoute.values.firstWhere(
          (route) => route.name == json['route'],
          orElse: () => ModelRoute.standard,
        ),
        llmProviderId: json['llm_provider_id'] as String?,
        visionProviderId: json['vision_provider_id'] as String?,
        ttsProviderId: json['tts_provider_id'] as String?,
        sttProviderId: json['stt_provider_id'] as String?,
        realtimeProviderId: json['realtime_provider_id'] as String?,
        omniProviderId: json['omni_provider_id'] as String?,
      );
}
