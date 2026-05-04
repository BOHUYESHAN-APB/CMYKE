import 'package:flutter/material.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/danmaku_adapter_state.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/danmaku_adapter.dart';
import '../../core/services/danmaku_batch_summarizer.dart';
import '../../core/services/bilibili_danmaku_service.dart';
import '../../core/services/mock_danmaku_adapter.dart';
import '../../core/services/event_bus.dart';
import '../../ui/theme/cmyke_chrome.dart';

class DanmakuScreen extends StatefulWidget {
  const DanmakuScreen({
    super.key,
    required this.settingsRepository,
    required this.eventBus,
  });

  final SettingsRepository settingsRepository;
  final RuntimeEventBus eventBus;

  @override
  State<DanmakuScreen> createState() => _DanmakuScreenState();
}

class _DanmakuScreenState extends State<DanmakuScreen> {
  DanmakuAdapter? _adapter;
  DanmakuBatchSummarizer? _summarizer;
  final List<Map<String, dynamic>> _events = [];
  final List<DanmakuBatchSummary> _summaries = [];
  final _roomIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = widget.settingsRepository.settings;
    _roomIdController.text = settings.danmakuRoomId?.toString() ?? '';
    if (settings.danmakuEnabled && settings.danmakuRoomId != null) {
      _initializeAdapter();
    }
  }

  @override
  void dispose() {
    _adapter?.dispose();
    _summarizer?.dispose();
    _roomIdController.dispose();
    super.dispose();
  }

  void _initializeAdapter() {
    final settings = widget.settingsRepository.settings;
    
    // Create adapter based on platform
    final adapter = settings.danmakuPlatform == DanmakuPlatform.bilibili
        ? BilibiliDanmakuService(bus: widget.eventBus)
        : MockDanmakuAdapter();
    
    _adapter = adapter;

    // Create summarizer
    _summarizer = DanmakuBatchSummarizer(
      adapter: adapter,
      config: BatchSummarizerConfig(
        intervalSeconds: settings.danmakuBatchIntervalSeconds,
        batchSize: settings.danmakuBatchSize,
        enabled: true,
      ),
    );

    // Listen to events
    adapter.outputs.listen((output) {
      if (output is DanmakuEventOutput) {
        setState(() {
          _events.insert(0, output.event);
          if (_events.length > 100) {
            _events.removeLast();
          }
        });
      }
    });

    // Listen to summaries
    _summarizer!.summaries.listen((summary) {
      setState(() {
        _summaries.insert(0, summary);
        if (_summaries.length > 20) {
          _summaries.removeLast();
        }
      });
    });

    _summarizer!.start();

    // Connect if room ID is set
    if (settings.danmakuRoomId != null) {
      _connect();
    }
  }

  Future<void> _connect() async {
    final settings = widget.settingsRepository.settings;
    final roomId = settings.danmakuRoomId;
    if (roomId == null || _adapter == null) return;

    final credentials = settings.danmakuPlatform == DanmakuPlatform.bilibili
        ? {
            'sessData': settings.danmakuBilibiliSessData,
            'biliJct': settings.danmakuBilibiliBiliJct,
            'buvid3': settings.danmakuBilibiliBuvid3,
          }
        : null;

    await _adapter!.connect(roomId: roomId, credentials: credentials);
    setState(() {});
  }

  Future<void> _disconnect() async {
    await _adapter?.disconnect();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settingsRepository,
      builder: (context, _) {
        final settings = widget.settingsRepository.settings;
        final chrome = context.chrome;
        
        return Scaffold(
          appBar: AppBar(title: const Text('直播弹幕')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildControlCard(settings, chrome),
              const SizedBox(height: 12),
              _buildStatusCard(chrome),
              const SizedBox(height: 12),
              _buildSummariesCard(chrome),
              const SizedBox(height: 12),
              _buildEventsCard(chrome),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlCard(AppSettings settings, CmykeChrome chrome) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '连接控制',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用弹幕监听'),
              value: settings.danmakuEnabled,
              onChanged: (value) {
                widget.settingsRepository.updateSettings(
                  settings.copyWith(danmakuEnabled: value),
                );
                if (value && _adapter == null) {
                  _initializeAdapter();
                } else if (!value) {
                  _disconnect();
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DanmakuPlatform>(
              value: settings.danmakuPlatform,
              decoration: const InputDecoration(
                labelText: '平台',
                border: OutlineInputBorder(),
              ),
              items: DanmakuPlatform.values.map((platform) {
                return DropdownMenuItem(
                  value: platform,
                  child: Text(platform.name),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  widget.settingsRepository.updateSettings(
                    settings.copyWith(danmakuPlatform: value),
                  );
                  if (_adapter != null) {
                    _disconnect();
                    _adapter?.dispose();
                    _adapter = null;
                    _summarizer?.dispose();
                    _summarizer = null;
                    if (settings.danmakuEnabled) {
                      _initializeAdapter();
                    }
                  }
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _roomIdController,
              decoration: const InputDecoration(
                labelText: '房间号',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (value) {
                final roomId = int.tryParse(value);
                if (roomId != null) {
                  widget.settingsRepository.updateSettings(
                    settings.copyWith(danmakuRoomId: roomId),
                  );
                  if (_adapter != null && _adapter!.isConnected) {
                    _disconnect().then((_) => _connect());
                  }
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _adapter != null && !_adapter!.isConnected
                        ? _connect
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('连接'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _adapter != null && _adapter!.isConnected
                        ? _disconnect
                        : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('断开'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(CmykeChrome chrome) {
    final adapter = _adapter;
    final state = adapter?.state;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '状态',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _getPhaseIcon(state?.phase),
                  color: _getPhaseColor(state?.phase),
                ),
                const SizedBox(width: 8),
                Text(
                  state?.phase.name ?? 'idle',
                  style: TextStyle(color: chrome.textSecondary),
                ),
              ],
            ),
            if (state?.failure != null) ...[
              const SizedBox(height: 8),
              Text(
                '错误: ${state!.failure!.message}',
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '房间: ${adapter?.roomId ?? '-'}',
              style: TextStyle(color: chrome.textSecondary),
            ),
            Text(
              '事件数: ${_events.length}',
              style: TextStyle(color: chrome.textSecondary),
            ),
            Text(
              '批次数: ${_summaries.length}',
              style: TextStyle(color: chrome.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummariesCard(CmykeChrome chrome) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '批次总结',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (_summaries.isEmpty)
              Text(
                '暂无批次',
                style: TextStyle(color: chrome.textSecondary),
              )
            else
              ..._summaries.take(5).map((summary) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: chrome.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${summary.timestamp.hour}:${summary.timestamp.minute.toString().padLeft(2, '0')} - ${summary.items.length} 条',
                          style: TextStyle(
                            fontSize: 12,
                            color: chrome.textSecondary,
                          ),
                        ),
                        if (summary.droppedCount > 0)
                          Text(
                            '丢弃: ${summary.droppedCount}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsCard(CmykeChrome chrome) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '实时弹幕',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (_events.isEmpty)
              Text(
                '暂无弹幕',
                style: TextStyle(color: chrome.textSecondary),
              )
            else
              ..._events.take(20).map((event) {
                final type = event['type'] ?? 'unknown';
                final user = event['userName'] ?? 'Unknown';
                final message = event['message'] ?? '';
                final price = event['price'];
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getTypeColor(type),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          _getTypeLabel(type),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 13,
                              color: chrome.textPrimary,
                            ),
                            children: [
                              TextSpan(
                                text: '$user: ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: chrome.textSecondary,
                                ),
                              ),
                              TextSpan(text: message),
                              if (price != null)
                                TextSpan(
                                  text: ' ¥$price',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  IconData _getPhaseIcon(DanmakuAdapterPhase? phase) {
    switch (phase) {
      case DanmakuAdapterPhase.connected:
        return Icons.check_circle;
      case DanmakuAdapterPhase.connecting:
      case DanmakuAdapterPhase.reconnecting:
        return Icons.sync;
      case DanmakuAdapterPhase.failed:
        return Icons.error;
      default:
        return Icons.circle_outlined;
    }
  }

  Color _getPhaseColor(DanmakuAdapterPhase? phase) {
    switch (phase) {
      case DanmakuAdapterPhase.connected:
        return Colors.green;
      case DanmakuAdapterPhase.connecting:
      case DanmakuAdapterPhase.reconnecting:
        return Colors.orange;
      case DanmakuAdapterPhase.failed:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'superChat':
        return Colors.red;
      case 'gift':
        return Colors.purple;
      case 'guardBuy':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'danmaku':
        return '弹';
      case 'superChat':
        return 'SC';
      case 'gift':
        return '礼';
      case 'guardBuy':
        return '舰';
      default:
        return '?';
    }
  }
}
