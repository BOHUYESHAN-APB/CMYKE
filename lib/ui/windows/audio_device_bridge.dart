import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class AudioInputDeviceInfo {
  const AudioInputDeviceInfo({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  final String id;
  final String name;
  final bool isDefault;

  factory AudioInputDeviceInfo.fromMap(Map<dynamic, dynamic> map) {
    return AudioInputDeviceInfo(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      isDefault: map['isDefault'] == true,
    );
  }
}

class AudioOutputDeviceInfo {
  const AudioOutputDeviceInfo({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  final String id;
  final String name;
  final bool isDefault;

  factory AudioOutputDeviceInfo.fromMap(Map<dynamic, dynamic> map) {
    return AudioOutputDeviceInfo(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      isDefault: map['isDefault'] == true,
    );
  }
}

class WindowsAudioDeviceBridge {
  static const MethodChannel _channel = MethodChannel('cmyke/audio');

  static bool get _enabled =>
      Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST');

  static Future<List<AudioInputDeviceInfo>> listInputDevices() async {
    if (!_enabled) return const [];
    final res = await _channel.invokeMethod('listInputDevices');
    if (res is! List) return const [];
    return res
        .whereType<Map<dynamic, dynamic>>()
        .map(AudioInputDeviceInfo.fromMap)
        .toList();
  }

  static Future<List<AudioOutputDeviceInfo>> listOutputDevices() async {
    if (!_enabled) return const [];
    final res = await _channel.invokeMethod('listOutputDevices');
    if (res is! List) return const [];
    return res
        .whereType<Map<dynamic, dynamic>>()
        .map(AudioOutputDeviceInfo.fromMap)
        .toList();
  }

  static Future<AudioInputDeviceInfo?> getDefaultInputDevice() async {
    if (!_enabled) return null;
    final res = await _channel.invokeMethod('getDefaultInputDevice');
    if (res is! Map) return null;
    return AudioInputDeviceInfo.fromMap(res);
  }

  static Future<AudioOutputDeviceInfo?> getDefaultOutputDevice() async {
    if (!_enabled) return null;
    final res = await _channel.invokeMethod('getDefaultOutputDevice');
    if (res is! Map) return null;
    return AudioOutputDeviceInfo.fromMap(res);
  }

  static Future<void> openSoundSettings() async {
    if (!_enabled) return;
    await _channel.invokeMethod('openSoundSettings');
  }

  static Future<bool> playWavToOutputDevice({
    required Uint8List wavBytes,
    String? deviceId,
  }) async {
    if (!_enabled) return false;
    final res = await _channel.invokeMethod(
      'playWavToOutputDevice',
      {
        'deviceId': (deviceId ?? '').trim(),
        'wavBytes': wavBytes,
      },
    );
    return res == true;
  }

  static Future<void> stopInjectedTts() async {
    if (!_enabled) return;
    await _channel.invokeMethod('stopInjectedTts');
  }
}
