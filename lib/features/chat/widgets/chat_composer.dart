import 'package:flutter/material.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onToggleListening,
    required this.isListening,
    required this.isStreaming,
    this.partialTranscript = '',
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onToggleListening;
  final bool isListening;
  final bool isStreaming;
  final String partialTranscript;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Row(
        children: [
          IconButton(
            tooltip: '上传文件 (占位)',
            onPressed: () {},
            icon: const Icon(Icons.attach_file_outlined),
          ),
          IconButton(
            tooltip: isListening ? '停止语音输入' : '语音输入',
            onPressed: onToggleListening,
            icon: Icon(
              isListening ? Icons.mic : Icons.mic_none_outlined,
              color: isListening ? const Color(0xFF1B9B7B) : null,
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
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: isStreaming ? null : onSend,
            icon: const Icon(Icons.send_rounded),
            label: const Text('发送'),
          ),
        ],
      ),
    );
  }
}
