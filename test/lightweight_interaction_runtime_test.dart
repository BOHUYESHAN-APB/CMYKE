import 'dart:async';
import 'dart:typed_data';

import 'package:cmyke/core/models/interaction_contract.dart';
import 'package:cmyke/core/models/interaction_profile.dart';
import 'package:cmyke/core/models/llm_stream_event.dart';
import 'package:cmyke/core/models/provider_config.dart';
import 'package:cmyke/core/runtime/interaction_event.dart';
import 'package:cmyke/core/runtime/lightweight_interaction_runtime.dart';
import 'package:cmyke/core/services/llm_client.dart';
import 'package:cmyke/core/services/speech_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLlmClient extends LlmClient {
  @override
  Stream<LlmStreamEvent> streamChat(
    ProviderConfig provider,
    List<Map<String, String>> messages, {
    String? systemPrompt,
  }) async* {
    yield const LlmStreamEvent(textDelta: '你好');
    yield const LlmStreamEvent(textDelta: '世界');
  }
}

class _FakeSpeechClient extends SpeechClient {
  @override
  Stream<Uint8List> streamSpeech({
    required ProviderConfig provider,
    required String text,
  }) async* {
    yield Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  test('LightweightInteractionRuntime emits text and tts events', () async {
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
      audioFormat: 'wav',
    );
    final contract = InteractionContract(
      profileId: 'p1',
      mode: InteractionMode.lightweight,
      main: InteractionEndpointContract(slot: 'main', provider: llm),
      embedding: const InteractionEndpointContract(slot: 'embedding', provider: null),
      vision: const InteractionEndpointContract(slot: 'vision', provider: null),
      tts: InteractionEndpointContract(slot: 'tts', provider: tts),
      stt: const InteractionEndpointContract(slot: 'stt', provider: null),
      realtime: const InteractionEndpointContract(slot: 'realtime', provider: null),
      omni: const InteractionEndpointContract(slot: 'omni', provider: null),
      leftBrain: InteractionEndpointContract(slot: 'left_brain', provider: llm),
      rightBrain: InteractionEndpointContract(slot: 'right_brain', provider: llm),
      options: const InteractionOptions(),
    );

    final runtime = LightweightInteractionRuntime(
      llmClient: _FakeLlmClient(),
      speechClient: _FakeSpeechClient(),
    );
    final session = runtime.createSession(contract: contract);

    final events = <InteractionEvent>[];
    final sub = session.events.listen(events.add);
    await session.start();
    await session.sendUserText('测试');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      events.any((event) => event.type == InteractionEventType.textDelta),
      isTrue,
    );
    expect(
      events.any(
        (event) =>
            event.type == InteractionEventType.textComplete && event.text == '你好世界',
      ),
      isTrue,
    );
    expect(
      events.any((event) => event.type == InteractionEventType.audioChunk),
      isTrue,
    );
    expect(events.last.type, InteractionEventType.done);

    await sub.cancel();
    await session.dispose();
  });
}
