import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/danmaku_event.dart';
import 'event_bus.dart';

class BilibiliDanmakuService {
  BilibiliDanmakuService({required RuntimeEventBus bus, http.Client? httpClient})
      : _bus = bus,
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null {
    _wbiSigner = _WbiSigner(_http);
  }

  final RuntimeEventBus _bus;
  final http.Client _http;
  final bool _ownsHttp;
  late final _WbiSigner _wbiSigner;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  _BilibiliConfig? _config;
  _DanmuServerInfo? _serverInfo;
  bool _closing = false;
  bool _disposed = false;
  int? _roomId;
  int _seq = 1;

  bool get isConnected => _socket?.readyState == WebSocket.open;
  int? get roomId => _roomId;

  Future<bool> connect({
    required int roomId,
    int uid = 0,
    String? sessData,
    String? biliJct,
    String? buvid3,
    int protocolVersion = 1,
    Duration heartbeatInterval = const Duration(seconds: 30),
    bool autoReconnect = true,
    Duration reconnectDelay = const Duration(seconds: 5),
  }) async {
    if (_disposed) return false;
    final config = _BilibiliConfig(
      roomId: roomId,
      uid: uid,
      sessData: sessData,
      biliJct: biliJct,
      buvid3: buvid3,
      protocolVersion: protocolVersion,
      heartbeatInterval: heartbeatInterval,
      autoReconnect: autoReconnect,
      reconnectDelay: reconnectDelay,
    );
    _config = config;
    _closing = false;
    try {
      await _openWithConfig(config);
      return true;
    } catch (e, st) {
      debugPrint('BilibiliDanmakuService: connect failed: $e');
      debugPrint('$st');
      return false;
    }
  }

  Future<void> disconnect() async {
    _closing = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeSocket();
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    if (_ownsHttp) {
      _http.close();
    }
  }

  Future<void> _openWithConfig(_BilibiliConfig config) async {
    if (_disposed) return;
    await _closeSocket();

    final resolvedRoomId = await _resolveRoomId(config);
    _roomId = resolvedRoomId;

    if (_wbiSigner.needsRefresh) {
      await _wbiSigner.refresh(config);
    }

    _serverInfo = await _fetchDanmuInfo(resolvedRoomId, config);
    if (_serverInfo == null) {
      throw StateError('Unable to fetch danmaku server info.');
    }

    final host = _serverInfo!.nextHost();
    final wsUrl = _buildWsUrl(host);
    final headers = _buildHeaders(config);

    final socket = await WebSocket.connect(wsUrl, headers: headers);
    _socket = socket;

    _socketSub = socket.listen(
      _handleSocketData,
      onError: (Object error, StackTrace st) {
        debugPrint('BilibiliDanmakuService: socket error: $error');
        _scheduleReconnect('socket error');
      },
      onDone: () {
        debugPrint('BilibiliDanmakuService: socket closed.');
        _scheduleReconnect('socket closed');
      },
      cancelOnError: true,
    );

    final authPayload = <String, dynamic>{
      'uid': config.uid,
      'roomid': resolvedRoomId,
      'protover': config.protocolVersion,
      'platform': 'web',
      'type': 2,
    };
    final token = _serverInfo!.token;
    if (token.isNotEmpty) {
      authPayload['key'] = token;
    }

    _sendPacket(
      operation: _BilibiliOp.auth,
      protocolVersion: config.protocolVersion,
      body: utf8.encode(jsonEncode(authPayload)),
    );

    _startHeartbeat(config.heartbeatInterval, config.protocolVersion);
  }

  Future<int> _resolveRoomId(_BilibiliConfig config) async {
    final uri = Uri.parse(
      'https://api.live.bilibili.com/room/v1/Room/room_init?room_id=${config.roomId}',
    );
    final response = await _http.get(uri, headers: _buildHeaders(config));
    if (response.statusCode != HttpStatus.ok) {
      return config.roomId;
    }
    final data = _decodeJson(response.bodyBytes);
    if (data == null) return config.roomId;
    if (data['code'] != 0) return config.roomId;
    final payload = data['data'];
    if (payload is Map<String, dynamic>) {
      final resolved = _toInt(payload['room_id']);
      if (resolved != null && resolved > 0) {
        return resolved;
      }
    }
    return config.roomId;
  }

  Future<_DanmuServerInfo?> _fetchDanmuInfo(
    int roomId,
    _BilibiliConfig config,
  ) async {
    final params = <String, String>{'id': roomId.toString(), 'type': '0'};
    for (var attempt = 0; attempt < 2; attempt++) {
      Map<String, String> signedParams = params;
      if (_wbiSigner.isReady) {
        signedParams = _wbiSigner.sign(params);
      }

      final uri = Uri.https(
        'api.live.bilibili.com',
        '/xlive/web-room/v1/index/getDanmuInfo',
        signedParams,
      );

      final response = await _http.get(uri, headers: _buildHeaders(config));
      if (response.statusCode != HttpStatus.ok) {
        debugPrint(
          'BilibiliDanmakuService: getDanmuInfo failed: ${response.statusCode}',
        );
        return null;
      }

      final data = _decodeJson(response.bodyBytes);
      if (data == null) return null;
      final code = data['code'];
      if (code != 0) {
        debugPrint(
          'BilibiliDanmakuService: getDanmuInfo error: $code ${data['message']}',
        );
        if (code == -352 && attempt == 0) {
          _wbiSigner.reset();
          await _wbiSigner.refresh(config);
          continue;
        }
        return null;
      }

      final payload = data['data'];
      if (payload is! Map<String, dynamic>) return null;
      final token = (payload['token'] ?? '').toString();
      final hosts = <_DanmuHost>[];
      final hostList = payload['host_list'];
      if (hostList is List) {
        for (final entry in hostList) {
          if (entry is Map<String, dynamic>) {
            final host = entry['host']?.toString();
            if (host == null || host.isEmpty) continue;
            final wssPort = _toInt(entry['wss_port']);
            final wsPort = _toInt(entry['ws_port']);
            hosts.add(
              _DanmuHost(
                host: host,
                wssPort: wssPort ?? 443,
                wsPort: wsPort ?? 2244,
              ),
            );
          }
        }
      }

      if (hosts.isEmpty) {
        hosts.add(const _DanmuHost(
          host: 'broadcastlv.chat.bilibili.com',
          wssPort: 443,
          wsPort: 2244,
        ));
      }

      return _DanmuServerInfo(token: token, hosts: hosts);
    }
    return null;
  }

  String _buildWsUrl(_DanmuHost host) {
    return 'wss://${host.host}:${host.wssPort}/sub';
  }

  void _startHeartbeat(Duration interval, int protocolVersion) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) {
      if (_socket == null || _socket?.readyState != WebSocket.open) {
        return;
      }
      _sendPacket(
        operation: _BilibiliOp.heartbeat,
        protocolVersion: protocolVersion,
        body: const [],
      );
    });
  }

  void _scheduleReconnect(String reason) {
    final config = _config;
    if (config == null || !config.autoReconnect) return;
    if (_closing || _disposed) return;
    if (_reconnectTimer != null) return;

    _reconnectTimer = Timer(config.reconnectDelay, () async {
      _reconnectTimer = null;
      if (_closing || _disposed) return;
      debugPrint('BilibiliDanmakuService: reconnecting ($reason)...');
      try {
        await _openWithConfig(config);
      } catch (e, st) {
        debugPrint('BilibiliDanmakuService: reconnect failed: $e');
        debugPrint('$st');
        _scheduleReconnect('retry');
      }
    });
  }

  Future<void> _closeSocket() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  void _handleSocketData(dynamic data) {
    if (data is String) {
      return;
    }
    if (data is List<int>) {
      _parsePackets(Uint8List.fromList(data));
    }
  }

  void _parsePackets(Uint8List data) {
    var offset = 0;
    while (offset + _packetHeaderLength <= data.length) {
      final header = ByteData.sublistView(
        data,
        offset,
        offset + _packetHeaderLength,
      );
      final packetLen = header.getUint32(0, Endian.big);
      final headerLen = header.getUint16(4, Endian.big);
      final ver = header.getUint16(6, Endian.big);
      final op = header.getUint32(8, Endian.big);
      if (packetLen <= 0 || offset + packetLen > data.length) {
        break;
      }
      final body = data.sublist(offset + headerLen, offset + packetLen);
      _handlePacket(op, ver, body);
      offset += packetLen;
    }
  }

  void _handlePacket(int op, int ver, Uint8List body) {
    if (ver == 2) {
      try {
        final inflated = ZLibDecoder().convert(body);
        _parsePackets(Uint8List.fromList(inflated));
      } catch (e) {
        debugPrint('BilibiliDanmakuService: zlib decode failed: $e');
      }
      return;
    }

    if (ver == 3) {
      debugPrint('BilibiliDanmakuService: brotli payload not supported.');
      return;
    }

    switch (op) {
      case _BilibiliOp.heartbeatReply:
        return;
      case _BilibiliOp.authReply:
        return;
      case _BilibiliOp.message:
        _handleMessagePayload(body);
        return;
      default:
        return;
    }
  }

  void _handleMessagePayload(Uint8List body) {
    String text;
    try {
      text = utf8.decode(body);
    } catch (_) {
      return;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return;
    }

    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          _handleCommand(item);
        }
      }
      return;
    }

    if (decoded is Map<String, dynamic>) {
      _handleCommand(decoded);
    }
  }

  void _handleCommand(Map<String, dynamic> payload) {
    final cmdRaw = payload['cmd']?.toString() ?? '';
    if (cmdRaw.isEmpty) return;
    final cmd = cmdRaw.split(':').first;
    DanmakuEvent? event;

    switch (cmd) {
      case 'DANMU_MSG':
        event = _parseDanmaku(payload);
        break;
      case 'SUPER_CHAT_MESSAGE':
      case 'SUPER_CHAT_MESSAGE_JP':
        event = _parseSuperChat(payload);
        break;
      case 'SEND_GIFT':
        event = _parseGift(payload);
        break;
      case 'GUARD_BUY':
        event = _parseGuardBuy(payload);
        break;
      default:
        return;
    }

    if (event != null) {
      _bus.emitDanmaku(event);
    }
  }

  DanmakuEvent? _parseDanmaku(Map<String, dynamic> payload) {
    final info = payload['info'];
    if (info is! List || info.length < 3) return null;

    final message = info[1]?.toString();
    final userInfo = info[2];
    int? userId;
    String? userName;
    if (userInfo is List) {
      if (userInfo.isNotEmpty) {
        userId = _toInt(userInfo[0]);
      }
      if (userInfo.length > 1) {
        userName = userInfo[1]?.toString();
      }
    }

    DateTime timestamp = DateTime.now();
    final meta = info[0];
    if (meta is List && meta.length > 4) {
      timestamp = _parseTimestamp(meta[4]);
    }

    String? emoticonUnique;
    String? emoticonUrl;
    if (meta is List) {
      for (final entry in meta) {
        if (entry is Map) {
          emoticonUnique =
              entry['emoticon_unique']?.toString() ?? emoticonUnique;
          emoticonUrl = entry['url']?.toString() ?? emoticonUrl;
        }
      }
    }

    return DanmakuEvent(
      type: DanmakuEventType.danmaku,
      roomId: _roomId ?? 0,
      timestamp: timestamp,
      userId: userId,
      userName: userName,
      message: message,
      emoticonUnique: emoticonUnique,
      emoticonUrl: emoticonUrl,
      raw: payload,
    );
  }

  DanmakuEvent? _parseSuperChat(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is! Map) return null;
    final map = data.cast<String, dynamic>();
    final message = map['message']?.toString();
    final userInfo = map['user_info'];
    int? userId;
    String? userName;
    if (userInfo is Map) {
      final userMap = userInfo.cast<String, dynamic>();
      userName = userMap['uname']?.toString();
      userId = _toInt(userMap['uid']);
    }
    userName ??= map['uname']?.toString();
    userId ??= _toInt(map['uid']);

    final price = _toDouble(map['price']);
    final timestamp = _parseTimestamp(map['start_time'] ?? map['timestamp']);

    return DanmakuEvent(
      type: DanmakuEventType.superChat,
      roomId: _roomId ?? 0,
      timestamp: timestamp,
      userId: userId,
      userName: userName,
      message: message,
      price: price,
      extra: map,
      raw: payload,
    );
  }

  DanmakuEvent? _parseGift(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is! Map) return null;
    final map = data.cast<String, dynamic>();
    final userName = map['uname']?.toString();
    final userId = _toInt(map['uid']);
    final giftName = map['giftName']?.toString() ?? '';
    final num = _toInt(map['num']) ?? 1;
    final action = map['action']?.toString() ?? 'sent';
    final message = '$action $giftName x$num';

    double? price;
    final coinType = map['coin_type']?.toString();
    final totalCoin = _toDouble(map['total_coin']);
    if (coinType == 'gold' && totalCoin != null) {
      price = totalCoin / 1000.0;
    }

    final timestamp = _parseTimestamp(map['timestamp'] ?? map['time']);

    return DanmakuEvent(
      type: DanmakuEventType.gift,
      roomId: _roomId ?? 0,
      timestamp: timestamp,
      userId: userId,
      userName: userName,
      message: message,
      price: price,
      extra: map,
      raw: payload,
    );
  }

  DanmakuEvent? _parseGuardBuy(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is! Map) return null;
    final map = data.cast<String, dynamic>();
    final userName = map['username']?.toString();
    final userId = _toInt(map['uid']);
    final num = _toInt(map['num']) ?? 1;
    final giftName = map['gift_name']?.toString() ?? 'guard';
    final message = '购买了 $giftName x$num';
    final price = _toDouble(map['price']);
    final timestamp = _parseTimestamp(map['start_time'] ?? map['timestamp']);

    return DanmakuEvent(
      type: DanmakuEventType.guardBuy,
      roomId: _roomId ?? 0,
      timestamp: timestamp,
      userId: userId,
      userName: userName,
      message: message,
      price: price != null ? price / 1000.0 : null,
      extra: map,
      raw: payload,
    );
  }

  DateTime _parseTimestamp(dynamic raw) {
    final value = _toInt(raw);
    if (value == null || value <= 0) return DateTime.now();
    if (value < 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  void _sendPacket({
    required int operation,
    required int protocolVersion,
    required List<int> body,
  }) {
    final payload = Uint8List.fromList(body);
    final packetLength = _packetHeaderLength + payload.length;
    final buffer = ByteData(packetLength);
    buffer.setUint32(0, packetLength, Endian.big);
    buffer.setUint16(4, _packetHeaderLength, Endian.big);
    buffer.setUint16(6, protocolVersion, Endian.big);
    buffer.setUint32(8, operation, Endian.big);
    buffer.setUint32(12, _seq++, Endian.big);
    final packet = buffer.buffer.asUint8List();
    packet.setRange(_packetHeaderLength, packet.length, payload);
    _socket?.add(packet);
  }
}

class _BilibiliConfig {
  const _BilibiliConfig({
    required this.roomId,
    required this.uid,
    required this.protocolVersion,
    required this.heartbeatInterval,
    required this.autoReconnect,
    required this.reconnectDelay,
    this.sessData,
    this.biliJct,
    this.buvid3,
  });

  final int roomId;
  final int uid;
  final String? sessData;
  final String? biliJct;
  final String? buvid3;
  final int protocolVersion;
  final Duration heartbeatInterval;
  final bool autoReconnect;
  final Duration reconnectDelay;
}

class _DanmuServerInfo {
  const _DanmuServerInfo({required this.token, required this.hosts});

  final String token;
  final List<_DanmuHost> hosts;

  static int _globalIndex = 0;

  _DanmuHost nextHost() {
    if (hosts.isEmpty) {
      return const _DanmuHost(
        host: 'broadcastlv.chat.bilibili.com',
        wssPort: 443,
        wsPort: 2244,
      );
    }
    final host = hosts[_globalIndex % hosts.length];
    _globalIndex++;
    return host;
  }
}

class _DanmuHost {
  const _DanmuHost({
    required this.host,
    required this.wssPort,
    required this.wsPort,
  });

  final String host;
  final int wssPort;
  final int wsPort;
}

class _BilibiliOp {
  static const heartbeat = 2;
  static const heartbeatReply = 3;
  static const message = 5;
  static const auth = 7;
  static const authReply = 8;
}

class _WbiSigner {
  _WbiSigner(this._http);

  static const _wbiKeyIndexTable = <int>[
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
  ];

  static const _ttl = Duration(hours: 11, minutes: 59, seconds: 30);

  final http.Client _http;
  String _wbiKey = '';
  DateTime? _lastRefresh;
  Future<void>? _refreshFuture;

  bool get needsRefresh {
    if (_wbiKey.isEmpty) return true;
    final last = _lastRefresh;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _ttl;
  }

  bool get isReady => _wbiKey.isNotEmpty;

  void reset() {
    _wbiKey = '';
    _lastRefresh = null;
  }

  Future<void> refresh(_BilibiliConfig config) {
    if (_refreshFuture != null) return _refreshFuture!;
    final future = _doRefresh(config);
    _refreshFuture = future.whenComplete(() {
      _refreshFuture = null;
    });
    return _refreshFuture!;
  }

  Future<void> _doRefresh(_BilibiliConfig config) async {
    final key = await _fetchWbiKey(config);
    if (key.isEmpty) return;
    _wbiKey = key;
    _lastRefresh = DateTime.now();
  }

  Future<String> _fetchWbiKey(_BilibiliConfig config) async {
    final uri = Uri.parse('https://api.bilibili.com/x/web-interface/nav');
    final response = await _http.get(uri, headers: _buildHeaders(config));
    if (response.statusCode != HttpStatus.ok) return '';

    final data = _decodeJson(response.bodyBytes);
    if (data == null) return '';
    final payload = data['data'];
    if (payload is! Map<String, dynamic>) return '';
    final wbiImg = payload['wbi_img'];
    if (wbiImg is! Map<String, dynamic>) return '';
    final imgUrl = wbiImg['img_url']?.toString();
    final subUrl = wbiImg['sub_url']?.toString();
    if (imgUrl == null || subUrl == null) return '';

    final imgKey = imgUrl.split('/').last.split('.').first;
    final subKey = subUrl.split('/').last.split('.').first;
    final shuffled = imgKey + subKey;
    final buffer = StringBuffer();
    for (final index in _wbiKeyIndexTable) {
      if (index < shuffled.length) {
        buffer.write(shuffled[index]);
      }
    }
    return buffer.toString();
  }

  Map<String, String> sign(Map<String, String> params) {
    if (_wbiKey.isEmpty) return params;
    final wts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final toSign = <String, String>{...params, 'wts': wts};
    final keys = toSign.keys.toList()..sort();
    final filtered = <String, String>{};
    for (final key in keys) {
      final value = toSign[key] ?? '';
      filtered[key] = value.replaceAll(RegExp(r"[!'()*]"), '');
    }
    final query = _encodeQuery(filtered);
    final wRid = _md5Hex(utf8.encode(query + _wbiKey));
    return {...params, 'wts': wts, 'w_rid': wRid};
  }
}

const _packetHeaderLength = 16;
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

Map<String, dynamic>? _decodeJson(List<int> bytes) {
  try {
    final body = utf8.decode(bytes);
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {}
  return null;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _toDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

Map<String, String> _buildHeaders(_BilibiliConfig config) {
  final headers = <String, String>{
    'User-Agent': _userAgent,
    'Origin': 'https://live.bilibili.com',
    'Referer': 'https://live.bilibili.com/',
  };
  final cookies = <String>[];
  if (config.sessData != null && config.sessData!.isNotEmpty) {
    cookies.add('SESSDATA=${config.sessData}');
  }
  if (config.biliJct != null && config.biliJct!.isNotEmpty) {
    cookies.add('bili_jct=${config.biliJct}');
  }
  if (config.buvid3 != null && config.buvid3!.isNotEmpty) {
    cookies.add('buvid3=${config.buvid3}');
  }
  if (cookies.isNotEmpty) {
    headers['Cookie'] = cookies.join('; ');
  }
  return headers;
}

String _encodeQuery(Map<String, String> params) {
  final parts = <String>[];
  for (final entry in params.entries) {
    final key = Uri.encodeQueryComponent(entry.key);
    final value = Uri.encodeQueryComponent(entry.value).replaceAll('%20', '+');
    parts.add('$key=$value');
  }
  return parts.join('&');
}

String _md5Hex(List<int> input) {
  final digest = _md5(input);
  final buffer = StringBuffer();
  for (final byte in digest) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

List<int> _md5(List<int> input) {
  final data = Uint8List.fromList(input);
  final length = data.length;
  final bitLength = length * 8;

  final padLength = ((56 - (length + 1) % 64) + 64) % 64;
  final totalLength = length + 1 + padLength + 8;
  final buffer = Uint8List(totalLength);
  buffer.setRange(0, length, data);
  buffer[length] = 0x80;
  for (var i = 0; i < 8; i++) {
    buffer[totalLength - 8 + i] = (bitLength >> (8 * i)) & 0xff;
  }

  var a0 = 0x67452301;
  var b0 = 0xefcdab89;
  var c0 = 0x98badcfe;
  var d0 = 0x10325476;

  for (var offset = 0; offset < totalLength; offset += 64) {
    final chunk = ByteData.sublistView(buffer, offset, offset + 64);
    final m = List<int>.filled(16, 0);
    for (var i = 0; i < 16; i++) {
      m[i] = chunk.getUint32(i * 4, Endian.little);
    }

    var a = a0;
    var b = b0;
    var c = c0;
    var d = d0;

    for (var i = 0; i < 64; i++) {
      int f;
      int g;
      if (i < 16) {
        f = (b & c) | ((~b) & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | ((~d) & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | (~d));
        g = (7 * i) % 16;
      }
      f &= 0xffffffff;

      final temp = d;
      d = c;
      c = b;
      final sum = _add32(_add32(_add32(a, f), _k[i]), m[g]);
      b = _add32(b, _leftRotate(sum, _s[i]));
      a = temp;
    }

    a0 = _add32(a0, a);
    b0 = _add32(b0, b);
    c0 = _add32(c0, c);
    d0 = _add32(d0, d);
  }

  final out = ByteData(16);
  out.setUint32(0, a0, Endian.little);
  out.setUint32(4, b0, Endian.little);
  out.setUint32(8, c0, Endian.little);
  out.setUint32(12, d0, Endian.little);
  return out.buffer.asUint8List();
}

int _leftRotate(int x, int c) {
  return ((x << c) | ((x & 0xffffffff) >> (32 - c))) & 0xffffffff;
}

int _add32(int a, int b) => (a + b) & 0xffffffff;

const _k = <int>[
  0xd76aa478,
  0xe8c7b756,
  0x242070db,
  0xc1bdceee,
  0xf57c0faf,
  0x4787c62a,
  0xa8304613,
  0xfd469501,
  0x698098d8,
  0x8b44f7af,
  0xffff5bb1,
  0x895cd7be,
  0x6b901122,
  0xfd987193,
  0xa679438e,
  0x49b40821,
  0xf61e2562,
  0xc040b340,
  0x265e5a51,
  0xe9b6c7aa,
  0xd62f105d,
  0x02441453,
  0xd8a1e681,
  0xe7d3fbc8,
  0x21e1cde6,
  0xc33707d6,
  0xf4d50d87,
  0x455a14ed,
  0xa9e3e905,
  0xfcefa3f8,
  0x676f02d9,
  0x8d2a4c8a,
  0xfffa3942,
  0x8771f681,
  0x6d9d6122,
  0xfde5380c,
  0xa4beea44,
  0x4bdecfa9,
  0xf6bb4b60,
  0xbebfbc70,
  0x289b7ec6,
  0xeaa127fa,
  0xd4ef3085,
  0x04881d05,
  0xd9d4d039,
  0xe6db99e5,
  0x1fa27cf8,
  0xc4ac5665,
  0xf4292244,
  0x432aff97,
  0xab9423a7,
  0xfc93a039,
  0x655b59c3,
  0x8f0ccc92,
  0xffeff47d,
  0x85845dd1,
  0x6fa87e4f,
  0xfe2ce6e0,
  0xa3014314,
  0x4e0811a1,
  0xf7537e82,
  0xbd3af235,
  0x2ad7d2bb,
  0xeb86d391,
];

const _s = <int>[
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
];
