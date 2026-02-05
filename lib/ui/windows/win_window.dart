import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class WinWindow {
  const WinWindow._();

  static const MethodChannel _channel = MethodChannel('cmyke/window');

  static bool get _enabled =>
      Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST');

  static Future<void> setAlwaysOnTop(bool value) async {
    if (!_enabled) return;
    await _channel.invokeMethod('setAlwaysOnTop', {'value': value});
  }

  static Future<void> setSkipTaskbar(bool value) async {
    if (!_enabled) return;
    await _channel.invokeMethod('setSkipTaskbar', {'value': value});
  }

  static Future<void> setFrameless(bool value) async {
    if (!_enabled) return;
    await _channel.invokeMethod('setFrameless', {'value': value});
  }

  static Future<void> setIgnoreMouseEvents(bool value) async {
    if (!_enabled) return;
    await _channel.invokeMethod('setIgnoreMouseEvents', {'value': value});
  }

  static Future<void> startDragging() async {
    if (!_enabled) return;
    await _channel.invokeMethod('startDragging');
  }

  static Future<void> setSize({required int width, required int height}) async {
    if (!_enabled) return;
    await _channel.invokeMethod('setSize', {'width': width, 'height': height});
  }

  static Future<void> setBounds({
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    if (!_enabled) return;
    await _channel.invokeMethod('setBounds', {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    });
  }

  static Future<Map<String, int>?> getBounds() async {
    if (!_enabled) return null;
    final res = await _channel.invokeMethod('getBounds');
    if (res is! Map) return null;
    int readInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    }

    return {
      'x': readInt(res['x']),
      'y': readInt(res['y']),
      'width': readInt(res['width']),
      'height': readInt(res['height']),
    };
  }

  static Future<void> setResizable(bool value) async {
    if (!_enabled) return;
    await _channel.invokeMethod('setResizable', {'value': value});
  }

  static Future<void> show() async {
    if (!_enabled) return;
    await _channel.invokeMethod('show');
  }

  static Future<void> hide() async {
    if (!_enabled) return;
    await _channel.invokeMethod('hide');
  }

  static Future<void> close() async {
    if (!_enabled) return;
    await _channel.invokeMethod('close');
  }
}
