import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cmyke/core/models/danmaku_adapter_state.dart';
import 'package:cmyke/core/models/danmaku_event.dart';
import 'package:cmyke/core/models/runtime_event.dart';
import 'package:cmyke/core/services/bilibili_danmaku_service.dart';
import 'package:cmyke/core/services/danmaku_adapter.dart';
import 'package:cmyke/core/services/event_bus.dart';

class _FakeSocket implements BilibiliSocketClient {
  _FakeSocket();

  final _controller = StreamController<dynamic>.broadcast();
  final sentPackets = <List<int>>[];
  bool closed = false;
  int _readyState = WebSocket.open;

  @override
  int get readyState => _readyState;

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic data) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void add(List<int> data) {
    sentPackets.add(data);
  }

  @override
  Future<void> close() async {
    closed = true;
    _readyState = WebSocket.closed;
    await _controller.close();
  }

  void emit(dynamic data) {
    _controller.add(data);
  }
}

List<int> _buildPacket({
  required int operation,
  required int protocolVersion,
  required List<int> body,
}) {
  final payload = Uint8List.fromList(body);
  final length = 16 + payload.length;
  final buffer = ByteData(length);
  buffer.setUint32(0, length, Endian.big);
  buffer.setUint16(4, 16, Endian.big);
  buffer.setUint16(6, protocolVersion, Endian.big);
  buffer.setUint32(8, operation, Endian.big);
  buffer.setUint32(12, 1, Endian.big);
  final bytes = buffer.buffer.asUint8List();
  bytes.setRange(16, bytes.length, payload);
  return bytes;
}

void main() {
  group('BilibiliDanmakuService', () {
    test('implements DanmakuAdapter interface', () async {
      final fakeSocket = _FakeSocket();
      final bus = RuntimeEventBus();
      final service = BilibiliDanmakuService(
        bus: bus,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/room_init')) {
            return http.Response(
              jsonEncode({'code': 0, 'data': {'room_id': 12345}}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/nav')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'wbi_img': {
                    'img_url': 'https://i0.hdslb.com/bfs/wbi/abc.png',
                    'sub_url': 'https://i0.hdslb.com/bfs/wbi/def.png',
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/getDanmuInfo')) {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  'token': 'token',
                  'host_list': [
                    {'host': 'example.com', 'wss_port': 443, 'ws_port': 2244},
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
        socketConnector: (url, {headers}) async => fakeSocket,
      );

      expect(service, isA<DanmakuAdapter>());

      await service.dispose();
      await bus.dispose();
    });

    test('emits state stream transitions', () async {
      final fakeSocket = _FakeSocket();
      final bus = RuntimeEventBus();
      final service = BilibiliDanmakuService(
        bus: bus,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/room_init')) {
            return http.Response(
              jsonEncode({'code': 0, 'data': {'room_id': 12345}}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/nav')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'wbi_img': {
                    'img_url': 'https://i0.hdslb.com/bfs/wbi/abc.png',
                    'sub_url': 'https://i0.hdslb.com/bfs/wbi/def.png',
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/getDanmuInfo')) {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  'token': 'token',
                  'host_list': [
                    {'host': 'example.com', 'wss_port': 443, 'ws_port': 2244},
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
        socketConnector: (url, {headers}) async => fakeSocket,
      );
      final states = <DanmakuAdapterState>[];
      final sub = service.states.listen(states.add);

      final connected = service.connect(
        roomId: 12345,
        credentials: {
          'heartbeatInterval': const Duration(milliseconds: 10),
          'autoReconnect': false,
        },
      );
      await Future<void>.delayed(Duration.zero);
      await connected;
      await Future<void>.delayed(Duration.zero);
      await service.disconnect();
      await Future<void>.delayed(Duration.zero);

      expect(
        states.map((state) => state.phase),
        containsAllInOrder([
          DanmakuAdapterPhase.connecting,
          DanmakuAdapterPhase.connected,
          DanmakuAdapterPhase.disconnecting,
          DanmakuAdapterPhase.disconnected,
        ]),
      );

      await sub.cancel();
      await service.dispose();
      await bus.dispose();
    });

    test('emits state and event outputs', () async {
      final fakeSocket = _FakeSocket();
      final bus = RuntimeEventBus();
      final service = BilibiliDanmakuService(
        bus: bus,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/room_init')) {
            return http.Response(
              jsonEncode({'code': 0, 'data': {'room_id': 12345}}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/nav')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'wbi_img': {
                    'img_url': 'https://i0.hdslb.com/bfs/wbi/abc.png',
                    'sub_url': 'https://i0.hdslb.com/bfs/wbi/def.png',
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/getDanmuInfo')) {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  'token': 'token',
                  'host_list': [
                    {'host': 'example.com', 'wss_port': 443, 'ws_port': 2244},
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
        socketConnector: (url, {headers}) async => fakeSocket,
      );
      final outputs = <DanmakuAdapterOutput>[];
      final sub = service.outputs.listen(outputs.add);

      await service.connect(
        roomId: 12345,
        credentials: {
          'heartbeatInterval': const Duration(milliseconds: 10),
          'autoReconnect': false,
        },
      );
      fakeSocket.emit(
        _buildPacket(
          operation: 5,
          protocolVersion: 1,
          body: utf8.encode(jsonEncode({
            'cmd': 'SEND_GIFT',
            'data': {
              'uname': 'tester',
              'uid': 99,
              'giftName': 'heart',
              'num': 1,
              'action': 'sent',
              'coin_type': 'silver',
              'total_coin': 100,
              'timestamp': 1700000000,
            },
          })),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(outputs.any((output) => output is DanmakuStateOutput), isTrue);
      expect(outputs.any((output) => output is DanmakuEventOutput), isTrue);

      await sub.cancel();
      await service.dispose();
      await bus.dispose();
    });

    test('still calls RuntimeEventBus.emitDanmaku for events', () async {
      final fakeSocket = _FakeSocket();
      final bus = _SpyRuntimeEventBus();
      final service = BilibiliDanmakuService(
        bus: bus,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/room_init')) {
            return http.Response(
              jsonEncode({'code': 0, 'data': {'room_id': 12345}}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/nav')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'wbi_img': {
                    'img_url': 'https://i0.hdslb.com/bfs/wbi/abc.png',
                    'sub_url': 'https://i0.hdslb.com/bfs/wbi/def.png',
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/getDanmuInfo')) {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  'token': 'token',
                  'host_list': [
                    {'host': 'example.com', 'wss_port': 443, 'ws_port': 2244},
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
        socketConnector: (url, {headers}) async => fakeSocket,
      );

      await service.connect(
        roomId: 12345,
        credentials: {
          'heartbeatInterval': const Duration(milliseconds: 10),
          'autoReconnect': false,
        },
      );
      fakeSocket.emit(
        _buildPacket(
          operation: 5,
          protocolVersion: 1,
          body: utf8.encode(jsonEncode({
            'cmd': 'DANMU_MSG',
            'info': [
              [],
              'hello world',
              [1001, 'viewer'],
            ],
          })),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(bus.emittedDanmaku, hasLength(1));
      expect(bus.emittedDanmaku.single.message, 'hello world');

      await service.dispose();
      await bus.dispose();
    });
  });
}

class _SpyRuntimeEventBus extends RuntimeEventBus {
  final emittedDanmaku = <DanmakuEvent>[];

  @override
  void emitDanmaku(
    DanmakuEvent event, {
    RuntimeEventSource source = RuntimeEventSource.danmaku,
    RuntimeEventPriority priority = RuntimeEventPriority.low,
    String? sessionId,
    String? traceId,
    String? cancelGroup,
  }) {
    emittedDanmaku.add(event);
    super.emitDanmaku(
      event,
      source: source,
      priority: priority,
      sessionId: sessionId,
      traceId: traceId,
      cancelGroup: cancelGroup,
    );
  }
}
