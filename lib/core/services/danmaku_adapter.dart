import '../models/danmaku_adapter_state.dart';

/// Abstract interface for danmaku platform adapters
abstract class DanmakuAdapter {
  /// Current state snapshot
  DanmakuAdapterState get state;

  /// Stream of state changes
  Stream<DanmakuAdapterState> get states;

  /// Unified output stream (states + events)
  Stream<DanmakuAdapterOutput> get outputs;

  /// Whether currently connected
  bool get isConnected;

  /// Current room ID (null if not connected)
  int? get roomId;

  /// Connect to a room
  Future<bool> connect({required int roomId, Map<String, dynamic>? credentials});

  /// Disconnect from current room
  Future<void> disconnect();

  /// Dispose resources
  Future<void> dispose();
}
