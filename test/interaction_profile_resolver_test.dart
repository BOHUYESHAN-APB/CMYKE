import 'package:cmyke/core/models/interaction_profile.dart';
import 'package:cmyke/core/models/provider_config.dart';
import 'package:cmyke/core/services/interaction_profile_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('InteractionProfileResolver resolves lightweight providers', () {
    final llm = ProviderConfig(
      id: 'llm-1',
      name: 'LLM',
      kind: ProviderKind.llm,
      baseUrl: 'https://example.com/v1',
      model: 'model-a',
    );
    final tts = ProviderConfig(
      id: 'tts-1',
      name: 'TTS',
      kind: ProviderKind.tts,
      baseUrl: 'https://example.com/v1',
      model: 'tts-a',
    );
    final profile = InteractionProfile(
      id: 'p1',
      name: '默认',
      mode: InteractionMode.lightweight,
      bindings: const InteractionBindings(
        llmProviderId: 'llm-1',
        leftBrainProviderId: 'llm-1',
        rightBrainProviderId: 'llm-1',
        ttsProviderId: 'tts-1',
      ),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    final contract = const InteractionProfileResolver().resolve(
      profile: profile,
      providers: [llm, tts],
    );

    expect(contract.main.providerId, 'llm-1');
    expect(contract.leftBrain.providerId, 'llm-1');
    expect(contract.tts.providerId, 'tts-1');
  });
}
