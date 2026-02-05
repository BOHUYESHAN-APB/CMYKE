import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST')) {
    await Window.initialize();
  }
  runApp(const CMYKEApp());
}
