# Agent Input (Chat Composer Enter Send)

## 问题原因
- Enter 触发发送时，IME 处于 composing 状态会直接被拦截，且没有后续补发机制，导致回车发送偶发失效。
- 快捷键仅覆盖标准 Enter，未覆盖小键盘 Enter；Alt+Enter 依赖快捷键触发，遇到 IME/焦点吞掉时同样会失效。

## 修复方案
- 将 `ChatComposer` 改为 `StatefulWidget`，在发送尝试时若 IME 正在 composing，则标记待发送。
- 监听 `TextEditingController` 变化，当 composing 结束且文本非空时自动触发发送，避免回车被 IME 吞掉后不发送。
- 补充快捷键绑定：标准 Enter + 小键盘 Enter，并覆盖 Alt/Ctrl/Meta 组合；Alt+Enter 保持强制发送行为。

## 改动文件
- `lib/features/chat/widgets/chat_composer.dart`

## 未解决问题
- 暂无。
