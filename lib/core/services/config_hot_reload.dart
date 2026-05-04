import 'dart:async';

import 'package:flutter/foundation.dart';

import '../repositories/settings_repository.dart';

/// Configuration hot reload service.
/// 
/// Monitors configuration changes and notifies listeners without requiring
/// app restart. Preserves existing connections and only updates configuration.
/// 
/// Design: Simple observer pattern (Level 1 abstraction)
/// Reference: N.E.K.O hot reload mechanism
class ConfigHotReload {
  ConfigHotReload({
    required SettingsRepository settingsRepository,
  }) : _settingsRepository = settingsRepository;

  final SettingsRepository _settingsRepository;
  final List<VoidCallback> _listeners = [];
  StreamSubscription<void>? _subscription;

  /// Register a callback to be invoked when configuration changes.
  void addListener(VoidCallback callback) {
    _listeners.add(callback);
  }

  /// Unregister a callback.
  void removeListener(VoidCallback callback) {
    _listeners.remove(callback);
  }

  /// Start monitoring configuration changes.
  void start() {
    // Listen to SettingsRepository changes
    _settingsRepository.addListener(_onConfigChanged);
  }

  /// Stop monitoring configuration changes.
  void stop() {
    _settingsRepository.removeListener(_onConfigChanged);
    _subscription?.cancel();
    _subscription = null;
  }

  void _onConfigChanged() {
    // Notify all listeners
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        debugPrint('ConfigHotReload: Error in listener: $e');
      }
    }
  }

  /// Dispose resources.
  void dispose() {
    stop();
    _listeners.clear();
  }
}
