import 'dart:async';
import 'dart:math';

import '../models/danmaku_adapter_state.dart';
import 'danmaku_adapter.dart';

/// Mock adapter for testing and development
class MockDanmakuAdapter implements DanmakuAdapter {
  MockDanmakuAdapter({
    this.eventInterval = const Duration(seconds: 2),
    this.autoGenerateEvents = true,
  }) {
    _stateController = StreamController<DanmakuAdapterState>.broadcast();
    _outputController = StreamController<DanmakuAdapterOutput>.broadcast();
  }

  final Duration eventInterval;
  final bool autoGenerateEvents;

  late final StreamController<DanmakuAdapterState> _stateController;
  late final StreamController<DanmakuAdapterOutput> _outputController;

  DanmakuAdapterState _state = const DanmakuAdapterState(phase: DanmakuAdapterPhase.idle);
  int? _roomId;
  Timer? _eventTimer;
  bool _disposed = false;

  static final _random = Random();
  static const _mockUsers = ['用户A', '用户B', '用户C', '观众D', '粉丝E', '路人F'];
  static const _mockMessages = [
    '666',
    '主播好',
    '这个怎么做？',
    '太强了',
    '学到了',
    '有意思',
    '继续继续',
    '问一下',
  ];

  @override
  DanmakuAdapterState get state => _state;

  @override
  Stream<DanmakuAdapterState> get states => _stateController.stream;

  @override
  Stream<DanmakuAdapterOutput> get outputs => _outputController.stream;

  @override
  bool get isConnected => _state.phase == DanmakuAdapterPhase.connected;

  @override
  int? get roomId => _roomId;

  void _updateState(DanmakuAdapterState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
      _outputController.add(DanmakuStateOutput(newState));
    }
  }

  @override
  Future<bool> connect({required int roomId, Map<String, dynamic>? credentials}) async {
    if (_disposed) return false;

    _roomId = roomId;
    _updateState(const DanmakuAdapterState(phase: DanmakuAdapterPhase.connecting));

    // Simulate connection delay
    await Future.delayed(const Duration(milliseconds: 500));

    _updateState(const DanmakuAdapterState(phase: DanmakuAdapterPhase.connected));

    if (autoGenerateEvents) {
      _startEventGeneration();
    }

    return true;
  }

  @override
  Future<void> disconnect() async {
    _updateState(const DanmakuAdapterState(phase: DanmakuAdapterPhase.disconnecting));
    _stopEventGeneration();
    await Future.delayed(const Duration(milliseconds: 200));
    _updateState(const DanmakuAdapterState(phase: DanmakuAdapterPhase.disconnected));
    _roomId = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _stopEventGeneration();
    await _stateController.close();
    await _outputController.close();
  }

  void _startEventGeneration() {
    _stopEventGeneration();
    _eventTimer = Timer.periodic(eventInterval, (_) {
      if (!_disposed && isConnected) {
        _generateMockEvent();
      }
    });
  }

  void _stopEventGeneration() {
    _eventTimer?.cancel();
    _eventTimer = null;
  }

  void _generateMockEvent() {
    final eventType = _random.nextInt(100);
    final user = _mockUsers[_random.nextInt(_mockUsers.length)];
    final userId = 10000 + _random.nextInt(90000);

    Map<String, dynamic> event;

    if (eventType < 80) {
      // 80% danmaku
      final message = _mockMessages[_random.nextInt(_mockMessages.length)];
      event = {
        'type': 'danmaku',
        'roomId': _roomId,
        'timestamp': DateTime.now().toIso8601String(),
        'userId': userId,
        'userName': user,
        'message': message,
      };
    } else if (eventType < 95) {
      // 15% gift
      event = {
        'type': 'gift',
        'roomId': _roomId,
        'timestamp': DateTime.now().toIso8601String(),
        'userId': userId,
        'userName': user,
        'message': '送出了小心心 x1',
        'price': 0.1,
      };
    } else {
      // 5% super chat
      final scMessages = ['支持主播！', '讲得很好', '继续加油'];
      event = {
        'type': 'superChat',
        'roomId': _roomId,
        'timestamp': DateTime.now().toIso8601String(),
        'userId': userId,
        'userName': user,
        'message': scMessages[_random.nextInt(scMessages.length)],
        'price': 10.0 + _random.nextDouble() * 90.0,
      };
    }

    if (!_outputController.isClosed) {
      _outputController.add(DanmakuEventOutput(event));
    }
  }

  /// Manually inject a custom event (for testing)
  void injectEvent(Map<String, dynamic> event) {
    if (!_disposed && isConnected && !_outputController.isClosed) {
      _outputController.add(DanmakuEventOutput(event));
    }
  }
}
