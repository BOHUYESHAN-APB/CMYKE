// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:cmyke/app.dart';

const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _pathProviderChannel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'getApplicationDocumentsDirectory':
          case 'getTemporaryDirectory':
            return '.';
          default:
            return '.';
        }
      },
    );
  });

  testWidgets('CMYKE app loads the chat shell', (WidgetTester tester) async {
    await tester.pumpWidget(const CMYKEApp());
    await tester.pumpAndSettle();

    expect(find.text('CMYKE'), findsWidgets);
    expect(find.text('新对话'), findsWidgets);
  });
}
