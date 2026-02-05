import 'package:flutter/material.dart';

import '../../../ui/theme/cmyke_chrome.dart';
import '../../../ui/widgets/frosted_surface.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onToggleListening,
    required this.isListening,
    required this.isStreaming,
    this.onOpenAgent,
    this.partialTranscript = '',
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onToggleListening;
  final bool isListening;
  final bool isStreaming;
  final VoidCallback? onOpenAgent;
  final String partialTranscript;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: FrostedSurface(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: '通用 Agent',
              onPressed: onOpenAgent,
              icon: const Icon(Icons.auto_awesome_outlined),
              color: chrome.textSecondary,
            ),
            IconButton(
              tooltip: isListening ? '停止语音输入' : '语音输入',
              onPressed: onToggleListening,
              icon: Icon(
                isListening ? Icons.mic : Icons.mic_none_outlined,
                color: isListening ? chrome.accent : chrome.textSecondary,
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '发送一条消息...',
                  filled: false,
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: isStreaming ? null : onSend,
              icon: const Icon(Icons.send_rounded),
              label: const Text('发送'),
            ),
          ],
        ),
      ),
    );
  }
}
