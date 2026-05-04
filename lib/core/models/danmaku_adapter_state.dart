/// Lifecycle phases for danmaku adapters
enum DanmakuAdapterPhase {
  /// Initial state, not connected
  idle,

  /// Attempting to establish connection
  connecting,

  /// Successfully connected and receiving events
  connected,

  /// Connection lost, attempting to reconnect
  reconnecting,

  /// Disconnecting gracefully
  disconnecting,

  /// Disconnected cleanly
  disconnected,

  /// Failed with error
  failed,
}

/// Failure information for danmaku adapters
class DanmakuAdapterFailure {
  const DanmakuAdapterFailure({
    required this.message,
    this.code,
    this.timestamp,
  });

  final String message;
  final String? code;
  final DateTime? timestamp;

  @override
  String toString() => 'DanmakuAdapterFailure(message: $message, code: $code)';
}

/// State snapshot for danmaku adapters
class DanmakuAdapterState {
  const DanmakuAdapterState({
    required this.phase,
    this.failure,
  });

  final DanmakuAdapterPhase phase;
  final DanmakuAdapterFailure? failure;

  bool get isConnected => phase == DanmakuAdapterPhase.connected;
  bool get isConnecting => phase == DanmakuAdapterPhase.connecting;
  bool get isFailed => phase == DanmakuAdapterPhase.failed;

  @override
  String toString() => 'DanmakuAdapterState(phase: $phase, failure: $failure)';
}

/// Discriminated union for adapter outputs
sealed class DanmakuAdapterOutput {
  const DanmakuAdapterOutput();
}

/// State change output
class DanmakuStateOutput extends DanmakuAdapterOutput {
  const DanmakuStateOutput(this.state);
  final DanmakuAdapterState state;
}

/// Danmaku event output
class DanmakuEventOutput extends DanmakuAdapterOutput {
  const DanmakuEventOutput(this.event);
  final Map<String, dynamic> event;
}
