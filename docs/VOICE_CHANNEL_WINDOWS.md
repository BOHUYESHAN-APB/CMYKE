# Windows 语音频道监听（虚拟声卡方案）

目标：把 Discord/KOOK 等语音频道的音频，通过虚拟声卡导入 CMYKE，再由系统 STT 转写成文本，并以“语音频道输入”注入对话（用于让 AI 能对语音频道内容做出回应）。

## 前置

- Windows 10/11
- 一个虚拟声卡驱动
  - 典型选择：VB-Audio Virtual Cable（VB-CABLE）

## 推荐接线方式（Discord 示例）

1. 安装虚拟声卡驱动（例如 VB-CABLE）。
2. Discord 设置：
   - `语音和视频`：
     - `输出设备`：选择 `CABLE Input (VB-Audio Virtual Cable)`（让语音频道声音“打到虚拟声卡”）
     - 你自己的耳机听声音：
       - 建议用系统的“监听此设备”或额外的虚拟混音方案；不想折腾可以先只做转写验证
3. Windows 声音设置（二选一）：
   - 方案 A：把 `CABLE Output (VB-Audio Virtual Cable)` 设为系统默认录音设备（应用未手动选设备时会使用默认设备）
   - 方案 B：不改系统默认，在 CMYKE 内直接选择 `CABLE Output` 作为语音频道输入设备
4. CMYKE：
   - `模型与能力配置` 中打开 `启用语音频道监听（Windows）`
   - 在聊天输入栏点 `🎧` 开始监听

## 现状与边界

- 当前实现基于系统 STT：**已支持在应用内选择输入设备**（`模型与能力配置 -> 语音频道（Windows）`）。
  - 若不手动选择，则跟随系统默认录音设备。
- Android 端默认不开放语音频道监听入口。
- 语音频道转写注入聊天时使用 `source=voiceChannel` 元数据，并在消息气泡上显示“语音频道”标签。
