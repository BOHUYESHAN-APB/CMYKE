import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/provider_config.dart';
import '../repositories/chat_repository.dart';
import '../repositories/settings_repository.dart';
import 'draft_service.dart';
import 'llm_client.dart';

class AutonomyService extends ChangeNotifier {
  AutonomyService({
    required SettingsRepository settingsRepository,
    required ChatRepository chatRepository,
    required DraftService draftService,
    required bool Function() isBusy,
    Future<void> Function(String text)? onSpeak,
  }) : _settingsRepository = settingsRepository,
       _chatRepository = chatRepository,
       _draftService = draftService,
       _isBusy = isBusy,
       _onSpeak = onSpeak {
    _settingsRepository.addListener(_handleSettingsChanged);
  }

  final SettingsRepository _settingsRepository;
  final ChatRepository _chatRepository;
  final DraftService _draftService;
  final bool Function() _isBusy;
  final Future<void> Function(String text)? _onSpeak;
  final LlmClient _llmClient = LlmClient();
  Timer? _proactiveTimer;
  Timer? _exploreTimer;
  DateTime _lastUserActivity = DateTime.now();
  DateTime? _lastProactiveRun;
  DateTime? _lastExploreRun;
  bool _runningProactive = false;
  bool _runningExplore = false;
  final Random _random = Random();
  final List<String> _recentTopics = [];

  DateTime? get lastProactiveRun => _lastProactiveRun;
  DateTime? get lastExploreRun => _lastExploreRun;
  bool get runningProactive => _runningProactive;
  bool get runningExplore => _runningExplore;
  AutonomyReadiness get readiness => _buildReadiness(includeBusy: true);

  void start() {
    _scheduleTimers();
  }

  @override
  void dispose() {
    _settingsRepository.removeListener(_handleSettingsChanged);
    _proactiveTimer?.cancel();
    _exploreTimer?.cancel();
    super.dispose();
  }

  void noteUserActivity() {
    _lastUserActivity = DateTime.now();
  }

  Future<void> runProactiveNow() async {
    await _maybeRunProactive(force: true);
  }

  Future<void> runExploreNow() async {
    await _maybeRunExplore(force: true);
  }

  void _handleSettingsChanged() {
    _scheduleTimers();
  }

  void _scheduleTimers() {
    _proactiveTimer?.cancel();
    _exploreTimer?.cancel();
    final settings = _settingsRepository.settings;
    if (!settings.autonomyEnabled) {
      return;
    }
    if (settings.autonomyProactiveEnabled) {
      final interval = Duration(
        minutes: max(5, settings.autonomyProactiveIntervalMinutes),
      );
      _proactiveTimer = Timer.periodic(interval, (_) {
        unawaited(_maybeRunProactive());
      });
    }
    if (settings.autonomyExploreEnabled) {
      final interval = Duration(
        minutes: max(10, settings.autonomyExploreIntervalMinutes),
      );
      _exploreTimer = Timer.periodic(interval, (_) {
        unawaited(_maybeRunExplore());
      });
    }
  }

  bool _isIdle(Duration minIdle) {
    final idleFor = DateTime.now().difference(_lastUserActivity);
    return idleFor >= minIdle;
  }

  Future<void> _maybeRunProactive({bool force = false}) async {
    final settings = _settingsRepository.settings;
    if (!settings.autonomyEnabled || !settings.autonomyProactiveEnabled) {
      return;
    }
    if (_runningProactive) {
      return;
    }
    final readiness = _buildReadiness(includeBusy: true);
    if (!readiness.canProactive) {
      return;
    }
    final minIdle = Duration(
      minutes: max(3, settings.autonomyProactiveIntervalMinutes ~/ 2),
    );
    if (!force && (!_isIdle(minIdle) || _isBusy())) {
      return;
    }
    _runningProactive = true;
    notifyListeners();
    try {
      final provider = _resolveProvider();
      if (provider == null) {
        return;
      }
      final session = _chatRepository.activeSession;
      if (session == null) {
        return;
      }
      final context = _recentMessages(session.messages, limit: 12);
      final systemPrompt =
          '你是 CMYKE 的“自主搭话”助手。现在用户处于闲置状态，请主动发起一条简短、友好、'
          '与当前对话有关或轻量延伸的问题/建议。'
          '不要编造真实经历或身份，不要冒充真人。除非用户明确询问，否则不要主动声明你是 AI。'
          '避免敏感或高风险话题。输出一条即可。';
      final content = await _llmClient.completeChat(
        provider: provider,
        messages: context,
        systemPrompt: systemPrompt,
      );
      final cleaned = content.trim();
      if (cleaned.isEmpty) {
        return;
      }
      await _chatRepository.addAssistantMessage(
        cleaned,
        sourceKind: ChatSourceKind.autonomy,
        priority: ChatPriority.proactive,
      );
      await _onSpeak?.call(cleaned);
      _lastProactiveRun = DateTime.now();
    } catch (_) {
      // Ignore to avoid crashing the app.
    } finally {
      _runningProactive = false;
      notifyListeners();
    }
  }

  Future<void> _maybeRunExplore({bool force = false}) async {
    final settings = _settingsRepository.settings;
    if (!settings.autonomyEnabled || !settings.autonomyExploreEnabled) {
      return;
    }
    if (_runningExplore) {
      return;
    }
    final readiness = _buildReadiness(includeBusy: true);
    if (!readiness.canExplore) {
      return;
    }
    final minIdle = Duration(
      minutes: max(5, settings.autonomyExploreIntervalMinutes ~/ 2),
    );
    if (!force && (!_isIdle(minIdle) || _isBusy())) {
      return;
    }
    _runningExplore = true;
    notifyListeners();
    try {
      final provider = _resolveProvider();
      if (provider == null) {
        return;
      }
      final session = _chatRepository.activeSession;
      if (session == null) {
        return;
      }
      final platform = _pickPlatform(settings.autonomyPlatforms);
      final format = _draftService.resolveFormat(
        strategy: settings.draftFormatStrategy,
        platform: platform,
      );
      final topic = _pickTopic();
      final systemPrompt =
          '你是 CMYKE 的“自主探索与草稿生成”助手。现在需要为平台 ${platform.name} 生成一份草稿。'
          '要求：内容清晰、不过度承诺、不编造具体数据和来源。若涉及事实或数据，请用“待查证/待补充”标记。'
          '语气符合平台气质。仅输出草稿正文，不要额外说明。';
      final userPrompt =
          '主题方向：$topic。\n输出格式：${format == DraftFormat.markdown ? 'Markdown' : '纯文本'}。';
      final content = await _llmClient.completeChat(
        provider: provider,
        messages: [
          ChatMessage(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            role: ChatRole.user,
            content: userPrompt,
            createdAt: DateTime.now(),
          ),
        ],
        systemPrompt: systemPrompt,
      );
      final cleaned = content.trim();
      if (cleaned.isEmpty) {
        return;
      }
      final result = await _draftService.createDraft(
        sessionId: session.id,
        platform: platform,
        format: format,
        content: cleaned,
        metadata: {
          'topic': topic,
          'generated_by': 'autonomy_explore',
        },
      );
      await _chatRepository.addAssistantMessage(
        '已生成一份草稿（平台：${_platformLabel(platform)}，格式：${format == DraftFormat.markdown ? 'Markdown' : '文本'}）。\n'
        '路径：${result.directory.path}',
        sourceKind: ChatSourceKind.autonomy,
        priority: ChatPriority.proactive,
      );
      await _onSpeak?.call(
        '我刚刚生成了一份${_platformLabel(platform)}草稿，已保存到草稿箱。',
      );
      _lastExploreRun = DateTime.now();
    } catch (_) {
      // Ignore failures; exploration is best-effort.
    } finally {
      _runningExplore = false;
      notifyListeners();
    }
  }

  ProviderConfig? _resolveProvider() {
    final settings = _settingsRepository.settings;
    final provider = _settingsRepository.findProvider(settings.llmProviderId);
    if (provider == null) {
      return null;
    }
    if (provider.protocol == ProviderProtocol.deviceBuiltin) {
      return null;
    }
    return provider;
  }

  AutonomyReadiness _buildReadiness({required bool includeBusy}) {
    final settings = _settingsRepository.settings;
    final commonIssues = <String>[];
    if (!settings.autonomyEnabled) {
      commonIssues.add('自主模式总开关未开启');
    }
    if (_resolveProvider() == null) {
      commonIssues.add('未配置可用的标准模型（LLM）');
    }
    if (_chatRepository.activeSession == null) {
      commonIssues.add('当前没有可用对话会话');
    }
    if (includeBusy && _isBusy()) {
      commonIssues.add('当前正在对话/语音处理中');
    }

    final proactiveIssues = <String>[];
    if (!settings.autonomyProactiveEnabled) {
      proactiveIssues.add('主动搭话未启用');
    }

    final exploreIssues = <String>[];
    if (!settings.autonomyExploreEnabled) {
      exploreIssues.add('自主探索未启用');
    }
    if (settings.autonomyPlatforms.isEmpty) {
      exploreIssues.add('未选择目标平台');
    }

    return AutonomyReadiness(
      commonIssues: commonIssues,
      proactiveIssues: proactiveIssues,
      exploreIssues: exploreIssues,
    );
  }

  List<ChatMessage> _recentMessages(
    List<ChatMessage> messages, {
    int limit = 12,
  }) {
    if (messages.length <= limit) {
      return List.of(messages);
    }
    return messages.sublist(messages.length - limit);
  }

  AutonomyPlatform _pickPlatform(List<AutonomyPlatform> platforms) {
    if (platforms.isEmpty) {
      return AutonomyPlatform.x;
    }
    return platforms[_random.nextInt(platforms.length)];
  }

  String _pickTopic() {
    const pool = [
      'AI 产品趋势',
      '效率工具与工作流',
      '新技术/新框架速览',
      '科普型内容',
      '情感陪伴与沟通技巧',
      '知识管理与笔记方法',
      '创意写作与灵感',
      'AI 与生活方式',
      '视频/图文内容策划',
      '职业成长建议',
    ];
    final shuffled = List.of(pool)..shuffle(_random);
    for (final topic in shuffled) {
      if (_recentTopics.contains(topic)) {
        continue;
      }
      _recentTopics.add(topic);
      if (_recentTopics.length > 5) {
        _recentTopics.removeAt(0);
      }
      return topic;
    }
    return pool[_random.nextInt(pool.length)];
  }

  String _platformLabel(AutonomyPlatform platform) {
    switch (platform) {
      case AutonomyPlatform.x:
        return 'X';
      case AutonomyPlatform.xiaohongshu:
        return '小红书';
      case AutonomyPlatform.bilibili:
        return '哔哩哔哩';
      case AutonomyPlatform.wechat:
        return '微信公众号';
    }
  }
}

class AutonomyReadiness {
  const AutonomyReadiness({
    required this.commonIssues,
    required this.proactiveIssues,
    required this.exploreIssues,
  });

  final List<String> commonIssues;
  final List<String> proactiveIssues;
  final List<String> exploreIssues;

  bool get canProactive =>
      commonIssues.isEmpty && proactiveIssues.isEmpty;

  bool get canExplore =>
      commonIssues.isEmpty && exploreIssues.isEmpty;

  List<String> issuesForProactive() => [
    ...commonIssues,
    ...proactiveIssues,
  ];

  List<String> issuesForExplore() => [
    ...commonIssues,
    ...exploreIssues,
  ];
}
