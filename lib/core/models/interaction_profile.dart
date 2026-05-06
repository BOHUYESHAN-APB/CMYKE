enum InteractionMode { lightweight, nativeRealtime, nativeOmni, composite }

class InteractionBindings {
  const InteractionBindings({
    this.llmProviderId,
    this.embeddingProviderId,
    this.visionProviderId,
    this.ttsProviderId,
    this.sttProviderId,
    this.realtimeProviderId,
    this.omniProviderId,
    this.leftBrainProviderId,
    this.rightBrainProviderId,
    this.motionAgentProviderId,
    this.memoryAgentProviderId,
  });

  final String? llmProviderId;
  final String? embeddingProviderId;
  final String? visionProviderId;
  final String? ttsProviderId;
  final String? sttProviderId;
  final String? realtimeProviderId;
  final String? omniProviderId;
  final String? leftBrainProviderId;
  final String? rightBrainProviderId;
  final String? motionAgentProviderId;
  final String? memoryAgentProviderId;

  InteractionBindings copyWith({
    String? llmProviderId,
    String? embeddingProviderId,
    String? visionProviderId,
    String? ttsProviderId,
    String? sttProviderId,
    String? realtimeProviderId,
    String? omniProviderId,
    String? leftBrainProviderId,
    String? rightBrainProviderId,
    String? motionAgentProviderId,
    String? memoryAgentProviderId,
  }) {
    return InteractionBindings(
      llmProviderId: llmProviderId ?? this.llmProviderId,
      embeddingProviderId: embeddingProviderId ?? this.embeddingProviderId,
      visionProviderId: visionProviderId ?? this.visionProviderId,
      ttsProviderId: ttsProviderId ?? this.ttsProviderId,
      sttProviderId: sttProviderId ?? this.sttProviderId,
      realtimeProviderId: realtimeProviderId ?? this.realtimeProviderId,
      omniProviderId: omniProviderId ?? this.omniProviderId,
      leftBrainProviderId: leftBrainProviderId ?? this.leftBrainProviderId,
      rightBrainProviderId: rightBrainProviderId ?? this.rightBrainProviderId,
      motionAgentProviderId:
          motionAgentProviderId ?? this.motionAgentProviderId,
      memoryAgentProviderId:
          memoryAgentProviderId ?? this.memoryAgentProviderId,
    );
  }

  Map<String, dynamic> toJson() => {
    'llm_provider_id': llmProviderId,
    'embedding_provider_id': embeddingProviderId,
    'vision_provider_id': visionProviderId,
    'tts_provider_id': ttsProviderId,
    'stt_provider_id': sttProviderId,
    'realtime_provider_id': realtimeProviderId,
    'omni_provider_id': omniProviderId,
    'left_brain_provider_id': leftBrainProviderId,
    'right_brain_provider_id': rightBrainProviderId,
    'motion_agent_provider_id': motionAgentProviderId,
    'memory_agent_provider_id': memoryAgentProviderId,
  };

  factory InteractionBindings.fromJson(Map<String, dynamic> json) {
    return InteractionBindings(
      llmProviderId: json['llm_provider_id'] as String?,
      embeddingProviderId: json['embedding_provider_id'] as String?,
      visionProviderId: json['vision_provider_id'] as String?,
      ttsProviderId: json['tts_provider_id'] as String?,
      sttProviderId: json['stt_provider_id'] as String?,
      realtimeProviderId: json['realtime_provider_id'] as String?,
      omniProviderId: json['omni_provider_id'] as String?,
      leftBrainProviderId: json['left_brain_provider_id'] as String?,
      rightBrainProviderId: json['right_brain_provider_id'] as String?,
      motionAgentProviderId: json['motion_agent_provider_id'] as String?,
      memoryAgentProviderId: json['memory_agent_provider_id'] as String?,
    );
  }
}

class InteractionOptions {
  const InteractionOptions({
    this.incrementalTts = true,
    this.allowBargeIn = false,
    this.useNativeAudioInput = false,
    this.useNativeAudioOutput = false,
    this.allowRightBrainEscalation = false,
  });

  final bool incrementalTts;
  final bool allowBargeIn;
  final bool useNativeAudioInput;
  final bool useNativeAudioOutput;
  final bool allowRightBrainEscalation;

  Map<String, dynamic> toJson() => {
    'incremental_tts': incrementalTts,
    'allow_barge_in': allowBargeIn,
    'use_native_audio_input': useNativeAudioInput,
    'use_native_audio_output': useNativeAudioOutput,
    'allow_right_brain_escalation': allowRightBrainEscalation,
  };

  factory InteractionOptions.fromJson(Map<String, dynamic> json) {
    return InteractionOptions(
      incrementalTts: json['incremental_tts'] as bool? ?? true,
      allowBargeIn: json['allow_barge_in'] as bool? ?? false,
      useNativeAudioInput: json['use_native_audio_input'] as bool? ?? false,
      useNativeAudioOutput:
          json['use_native_audio_output'] as bool? ?? false,
      allowRightBrainEscalation:
          json['allow_right_brain_escalation'] as bool? ?? false,
    );
  }
}

class InteractionProfile {
  const InteractionProfile({
    required this.id,
    required this.name,
    required this.mode,
    required this.bindings,
    this.options = const InteractionOptions(),
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final InteractionMode mode;
  final InteractionBindings bindings;
  final InteractionOptions options;
  final DateTime createdAt;
  final DateTime updatedAt;

  InteractionProfile copyWith({
    String? id,
    String? name,
    InteractionMode? mode,
    InteractionBindings? bindings,
    InteractionOptions? options,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InteractionProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      mode: mode ?? this.mode,
      bindings: bindings ?? this.bindings,
      options: options ?? this.options,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mode': mode.name,
    'bindings': bindings.toJson(),
    'options': options.toJson(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory InteractionProfile.fromJson(Map<String, dynamic> json) {
    return InteractionProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      mode: InteractionMode.values.firstWhere(
        (mode) => mode.name == json['mode'],
        orElse: () => InteractionMode.lightweight,
      ),
      bindings: InteractionBindings.fromJson(
        (json['bindings'] as Map).cast<String, dynamic>(),
      ),
      options: json['options'] is Map<String, dynamic>
          ? InteractionOptions.fromJson(json['options'] as Map<String, dynamic>)
          : const InteractionOptions(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
