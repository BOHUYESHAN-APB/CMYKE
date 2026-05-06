import '../models/interaction_contract.dart';
import 'interaction_session.dart';

abstract class InteractionRuntime {
  InteractionSession createSession({
    required InteractionContract contract,
    String? systemPrompt,
  });
}
