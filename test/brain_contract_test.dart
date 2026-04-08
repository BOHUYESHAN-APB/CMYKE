import 'package:cmyke/core/models/app_settings.dart';
import 'package:cmyke/core/models/brain_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrainContract.fromSettings', () {
    test('keeps standard route in left-brain-only mode', () {
      final contract = BrainContract.fromSettings(
        AppSettings(route: ModelRoute.standard, llmProviderId: 'llm-1'),
      );

      expect(contract.leftBrain.route, ModelRoute.standard);
      expect(contract.leftBrain.providerId, 'llm-1');
      expect(contract.escalationMode, BrainEscalationMode.leftOnly);
      expect(contract.canEscalateToRightBrain, isFalse);
      expect(contract.usesDistinctRightBrain, isFalse);
    });

    test('uses omni as left brain and llm as optional right brain', () {
      final contract = BrainContract.fromSettings(
        AppSettings(
          route: ModelRoute.omni,
          llmProviderId: 'llm-1',
          omniProviderId: 'omni-1',
        ),
      );

      expect(contract.leftBrain.route, ModelRoute.omni);
      expect(contract.leftBrain.providerId, 'omni-1');
      expect(contract.rightBrain?.route, ModelRoute.standard);
      expect(contract.rightBrain?.providerId, 'llm-1');
      expect(contract.escalationMode, BrainEscalationMode.onDemand);
      expect(contract.canEscalateToRightBrain, isTrue);
      expect(contract.usesDistinctRightBrain, isTrue);
    });
  });
}
