import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/theme/cmyke_chrome.dart';
import '../../../ui/widgets/frosted_surface.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onToggleListening,
    required this.onToggleVoiceChannelMonitoring,
    required this.isListening,
    required this.isVoiceChannelMonitoring,
    required this.isStreaming,
    this.onOpenAgent,
    this.partialTranscript = '',
    this.showVoiceChannelButton = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onToggleListening;
  final VoidCallback onToggleVoiceChannelMonitoring;
  final bool isListening;
  final bool isVoiceChannelMonitoring;
  final bool isStreaming;
  final VoidCallback? onOpenAgent;
  final String partialTranscript;
  final bool showVoiceChannelButton;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  static const double _suggestionGap = 8;
  static const double _suggestionMaxHeight = 220;
  static const double _suggestionMinHeight = 96;

  bool _pendingSendAfterIme = false;
  final FocusNode _inputFocusNode = FocusNode();
  final LayerLink _inputLink = LayerLink();
  final GlobalKey _inputKey = GlobalKey();
  OverlayEntry? _suggestionsOverlay;
  Size _inputSize = Size.zero;
  List<_ComposerSuggestion> _suggestions = const [];
  int _highlightIndex = 0;

  _SuggestionOverlayLayout _resolveSuggestionOverlayLayout(
    BuildContext context,
  ) {
    final box = _inputKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return const _SuggestionOverlayLayout(
        openAbove: true,
        maxHeight: _suggestionMaxHeight,
      );
    }

    final topLeft = box.localToGlobal(Offset.zero);
    final top = topLeft.dy;
    final bottom = top + box.size.height;
    final media = MediaQuery.of(context);
    final viewportTop = media.padding.top;
    final viewportBottom = media.size.height - media.viewInsets.bottom;
    final availableAbove = top - viewportTop - _suggestionGap;
    final availableBelow = viewportBottom - bottom - _suggestionGap;
    final openAbove =
        availableAbove >= _suggestionMinHeight ||
        availableAbove >= availableBelow;
    final available = openAbove ? availableAbove : availableBelow;
    final maxHeight = math.max(
      _suggestionMinHeight,
      math.min(_suggestionMaxHeight, available),
    );

    return _SuggestionOverlayLayout(openAbove: openAbove, maxHeight: maxHeight);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _inputFocusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _inputFocusNode.removeListener(_handleFocusChanged);
    _inputFocusNode.dispose();
    _removeSuggestionsOverlay();
    super.dispose();
  }

  bool _isImeComposing() {
    final composing = widget.controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  void _handleControllerChanged() {
    if (!_pendingSendAfterIme) {
      _updateSuggestions();
      return;
    }
    if (widget.isStreaming) {
      _pendingSendAfterIme = false;
      _updateSuggestions();
      return;
    }
    if (_isImeComposing()) {
      _updateSuggestions();
      return;
    }
    if (widget.controller.text.trim().isEmpty) {
      _pendingSendAfterIme = false;
      _updateSuggestions();
      return;
    }
    _pendingSendAfterIme = false;
    widget.onSend();
    _updateSuggestions();
  }

  void _trySend({bool allowImeQueue = false, bool force = false}) {
    if (widget.isStreaming) {
      return;
    }
    if (!force && _isImeComposing()) {
      if (allowImeQueue) {
        _pendingSendAfterIme = true;
      }
      return;
    }
    widget.onSend();
  }

  void _handleFocusChanged() {
    if (!_inputFocusNode.hasFocus) {
      _removeSuggestionsOverlay();
    } else {
      _updateSuggestions();
    }
  }

  void _updateSuggestions() {
    if (!mounted) {
      return;
    }
    if (!_inputFocusNode.hasFocus || widget.isStreaming || _isImeComposing()) {
      _setSuggestions(const []);
      return;
    }
    final value = widget.controller.value;
    final cursor = value.selection.baseOffset;
    final suggestions = _buildSuggestions(value.text, cursor);
    _setSuggestions(suggestions);
  }

  void _setSuggestions(List<_ComposerSuggestion> next) {
    final same =
        next.length == _suggestions.length &&
        next.asMap().entries.every(
          (entry) => entry.value.label == _suggestions[entry.key].label,
        );
    if (same) {
      _suggestionsOverlay?.markNeedsBuild();
      return;
    }
    setState(() {
      _suggestions = next;
      _highlightIndex = _suggestions.isEmpty
          ? 0
          : _highlightIndex.clamp(0, _suggestions.length - 1);
    });
    if (_suggestions.isEmpty) {
      _removeSuggestionsOverlay();
    } else {
      _showSuggestionsOverlay();
    }
  }

  void _showSuggestionsOverlay() {
    if (_suggestionsOverlay != null) {
      _updateInputSize();
      _suggestionsOverlay?.markNeedsBuild();
      return;
    }
    _updateInputSize();
    _suggestionsOverlay = OverlayEntry(
      builder: (context) {
        if (_suggestions.isEmpty || !_inputFocusNode.hasFocus) {
          return const SizedBox.shrink();
        }
        final chrome = context.chrome;
        final layout = _resolveSuggestionOverlayLayout(context);
        return Positioned.fill(
          child: IgnorePointer(
            ignoring: false,
            child: CompositedTransformFollower(
              link: _inputLink,
              showWhenUnlinked: false,
              targetAnchor: layout.openAbove
                  ? Alignment.topLeft
                  : Alignment.bottomLeft,
              followerAnchor: layout.openAbove
                  ? Alignment.bottomLeft
                  : Alignment.topLeft,
              offset: Offset(
                0,
                layout.openAbove ? -_suggestionGap : _suggestionGap,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: _inputSize.width == 0 ? 480 : _inputSize.width,
                    child: FrostedSurface(
                      borderRadius: BorderRadius.circular(chrome.radiusL),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: layout.maxHeight,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: _suggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            final isActive = index == _highlightIndex;
                            return Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                onTap: () => _applySuggestion(suggestion),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? chrome.surfaceElevated.withValues(
                                            alpha: 0.55,
                                          )
                                        : Colors.transparent,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              suggestion.label,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    color: chrome.textPrimary,
                                                  ),
                                            ),
                                            if (suggestion.subtitle != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 2,
                                                ),
                                                child: Text(
                                                  suggestion.subtitle!,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: chrome
                                                            .textSecondary,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (suggestion.shortcutHint != null)
                                        Text(
                                          suggestion.shortcutHint!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: chrome.textSecondary,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    final overlay = Overlay.of(context, rootOverlay: true);
    overlay.insert(_suggestionsOverlay!);
  }

  void _removeSuggestionsOverlay() {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
  }

  void _updateInputSize() {
    final box = _inputKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      _inputSize = box.size;
    }
  }

  void _applySuggestion(_ComposerSuggestion suggestion) {
    final value = widget.controller.value;
    final text = value.text;
    final start = suggestion.replaceStart.clamp(0, text.length);
    final end = suggestion.replaceEnd.clamp(0, text.length);
    final next = text.replaceRange(start, end, suggestion.insertText);
    final cursor = start + suggestion.insertText.length;
    widget.controller.value = value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
    _setSuggestions(const []);
  }

  void _acceptHighlightedSuggestion() {
    if (_suggestions.isEmpty) {
      return;
    }
    final index = _highlightIndex.clamp(0, _suggestions.length - 1);
    _applySuggestion(_suggestions[index]);
  }

  List<_ComposerSuggestion> _buildSuggestions(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) {
      cursor = text.length;
    }
    final prefix = text.substring(0, cursor);
    final tokenStart = _lastTokenStart(prefix);
    final token = prefix.substring(tokenStart);
    final lowerToken = token.toLowerCase();
    final suggestions = <_ComposerSuggestion>[];

    final toolActionSuggestions = _buildToolActionSuggestions(prefix, cursor);
    suggestions.addAll(toolActionSuggestions);

    if (token.startsWith('/')) {
      suggestions.addAll(
        _slashTemplates
            .where(
              (entry) => entry.trigger.toLowerCase().startsWith(lowerToken),
            )
            .map(
              (entry) => _ComposerSuggestion(
                label: entry.trigger,
                subtitle: entry.description,
                shortcutHint: entry.shortcutHint,
                insertText: entry.trigger + (entry.needsArgument ? ' ' : ''),
                replaceStart: tokenStart,
                replaceEnd: cursor,
              ),
            ),
      );
    }

    if (token.startsWith('#')) {
      suggestions.addAll(
        _hashTemplates
            .where(
              (entry) => entry.trigger.toLowerCase().startsWith(lowerToken),
            )
            .map(
              (entry) => _ComposerSuggestion(
                label: entry.trigger,
                subtitle: entry.description,
                shortcutHint: entry.shortcutHint,
                insertText: entry.trigger + (entry.needsArgument ? ' ' : ''),
                replaceStart: tokenStart,
                replaceEnd: cursor,
              ),
            ),
      );
    }

    if (suggestions.length > 8) {
      return suggestions.sublist(0, 8);
    }
    return suggestions;
  }

  List<_ComposerSuggestion> _buildToolActionSuggestions(
    String prefix,
    int cursor,
  ) {
    final match = RegExp(r'^/tool\s+').firstMatch(prefix);
    if (match == null) {
      return const [];
    }
    final afterIndex = match.end;
    if (cursor < afterIndex) {
      return const [];
    }
    final remainder = prefix.substring(afterIndex);
    final whitespace = remainder.indexOf(RegExp(r'\s'));
    if (whitespace != -1) {
      return const [];
    }
    final fragment = remainder.toLowerCase();
    return _toolActionTemplates
        .where((entry) => entry.trigger.startsWith(fragment))
        .map(
          (entry) => _ComposerSuggestion(
            label: '/tool ${entry.trigger}',
            subtitle: entry.description,
            shortcutHint: entry.shortcutHint,
            insertText: '${entry.trigger} ',
            replaceStart: afterIndex,
            replaceEnd: cursor,
          ),
        )
        .toList(growable: false);
  }

  int _lastTokenStart(String input) {
    Match? last;
    for (final match in RegExp(r'\s').allMatches(input)) {
      last = match;
    }
    if (last == null) {
      return 0;
    }
    return last.end;
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;

    void handleShortcutSend({bool force = false}) {
      _trySend(allowImeQueue: true, force: force);
    }

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter): handleShortcutSend,
      const SingleActivator(LogicalKeyboardKey.numpadEnter): handleShortcutSend,
      const SingleActivator(LogicalKeyboardKey.enter, alt: true): () =>
          handleShortcutSend(force: true),
      const SingleActivator(LogicalKeyboardKey.numpadEnter, alt: true): () =>
          handleShortcutSend(force: true),
      const SingleActivator(LogicalKeyboardKey.enter, control: true):
          handleShortcutSend,
      const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
          handleShortcutSend,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true):
          handleShortcutSend,
      const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true):
          handleShortcutSend,
    };

    if (_suggestions.isNotEmpty) {
      shortcuts[const SingleActivator(LogicalKeyboardKey.tab)] =
          _acceptHighlightedSuggestion;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: FrostedSurface(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: '通用 Agent',
              onPressed: widget.onOpenAgent,
              icon: const Icon(Icons.auto_awesome_outlined),
              color: chrome.textSecondary,
            ),
            IconButton(
              tooltip: widget.isListening ? '停止语音输入' : '语音输入',
              onPressed: widget.onToggleListening,
              icon: Icon(
                widget.isListening ? Icons.mic : Icons.mic_none_outlined,
                color: widget.isListening
                    ? chrome.accent
                    : chrome.textSecondary,
              ),
            ),
            if (widget.showVoiceChannelButton)
              IconButton(
                tooltip: widget.isVoiceChannelMonitoring
                    ? '停止语音频道监听'
                    : '语音频道监听',
                onPressed: widget.onToggleVoiceChannelMonitoring,
                icon: Icon(
                  widget.isVoiceChannelMonitoring
                      ? Icons.headphones
                      : Icons.headphones_outlined,
                  color: widget.isVoiceChannelMonitoring
                      ? chrome.accent
                      : chrome.textSecondary,
                ),
              ),
            Expanded(
              child: CallbackShortcuts(
                bindings: shortcuts,
                child: CompositedTransformTarget(
                  link: _inputLink,
                  child: TextField(
                    key: _inputKey,
                    focusNode: _inputFocusNode,
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(
                      hintText: '发送一条消息...',
                      filled: false,
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _trySend(allowImeQueue: true),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: widget.isStreaming ? null : widget.onSend,
              icon: const Icon(Icons.send_rounded),
              label: const Text('发送'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerSuggestion {
  const _ComposerSuggestion({
    required this.label,
    required this.insertText,
    required this.replaceStart,
    required this.replaceEnd,
    this.subtitle,
    this.shortcutHint,
  });

  final String label;
  final String insertText;
  final int replaceStart;
  final int replaceEnd;
  final String? subtitle;
  final String? shortcutHint;
}

class _SuggestionTemplate {
  const _SuggestionTemplate(
    this.trigger,
    this.description, {
    this.needsArgument = false,
    this.shortcutHint,
  });

  final String trigger;
  final String description;
  final bool needsArgument;
  final String? shortcutHint;
}

class _SuggestionOverlayLayout {
  const _SuggestionOverlayLayout({
    required this.openAbove,
    required this.maxHeight,
  });

  final bool openAbove;
  final double maxHeight;
}

const List<_SuggestionTemplate> _slashTemplates = [
  _SuggestionTemplate('/help', '指令帮助'),
  _SuggestionTemplate('/commands', '指令列表'),
  _SuggestionTemplate('/tool', '工具调用（网关）', needsArgument: true),
  _SuggestionTemplate('/agent', '通用 Agent 会话', needsArgument: true),
  _SuggestionTemplate('/research', '深度研究（报告）', needsArgument: true),
  _SuggestionTemplate('/summary', '快速总结', needsArgument: true),
  _SuggestionTemplate('/persona', '查看当前人设'),
  _SuggestionTemplate('/motions', '查看可用动作'),
  _SuggestionTemplate('/play', '触发动作', needsArgument: true),
  _SuggestionTemplate('/stop', '停止动作'),
  _SuggestionTemplate('/mcp', 'MCP 接入说明'),
  _SuggestionTemplate('/skills', 'Skills 说明'),
  _SuggestionTemplate('/agents', 'Agents 说明'),
];

const List<_SuggestionTemplate> _hashTemplates = [
  _SuggestionTemplate('#help', '指令帮助'),
  _SuggestionTemplate('#tool', '工具调用（默认 code）', needsArgument: true),
  _SuggestionTemplate('#search', '搜索', needsArgument: true),
  _SuggestionTemplate('#crawl', '抓取网页', needsArgument: true),
  _SuggestionTemplate('#analyze', '分析', needsArgument: true),
  _SuggestionTemplate('#summarize', '摘要', needsArgument: true),
  _SuggestionTemplate('#image', '生图（待接入）', needsArgument: true),
  _SuggestionTemplate('#vision', '视觉分析（待接入）', needsArgument: true),
  _SuggestionTemplate('#agent', '通用 Agent 会话', needsArgument: true),
  _SuggestionTemplate('#research', '深度研究', needsArgument: true),
];

const List<_SuggestionTemplate> _toolActionTemplates = [
  _SuggestionTemplate('code', '代码/命令执行', shortcutHint: '默认'),
  _SuggestionTemplate('search', '网络搜索'),
  _SuggestionTemplate('crawl', '抓取网页'),
  _SuggestionTemplate('analyze', '分析'),
  _SuggestionTemplate('summarize', '摘要'),
  _SuggestionTemplate('image', '生图（待接入）'),
  _SuggestionTemplate('vision', '视觉分析（待接入）'),
];
