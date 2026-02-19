# agent_bilibili

实现范围
- 从 N-T-AI 的 Bilibili 直播弹幕链路迁移核心逻辑到 CMYKE 服务层
- 实现房间连接、鉴权、心跳、消息解析（弹幕 / SC / 礼物 / 舰长）并以 DanmakuEvent 形式发往 RuntimeEventBus
- 增加 WBI 签名与 room_init 解析以适配短房间号

改动文件
- lib/core/models/danmaku_event.dart
- lib/core/services/bilibili_danmaku_service.dart
- lib/core/services/event_bus.dart
- lib/core/services/runtime_hub.dart
- docs/agents/agent_bilibili.md

未解决问题
- 未实现 brotli 解压（protover=3）；当前默认 protover=1，若服务端强制 brotli 会收不到弹幕
- 未接入 UI/设置页面，本次仅提供服务层；需要手动调用 RuntimeHub.instance.bilibiliDanmaku.connect

对接需求
- 建议在设置页提供 roomId、SESSDATA、bili_jct、buvid3、uid（可选）配置入口
- 若需要 emoticon URL 完整解析或更多事件类型，可在 DanmakuEvent.extra/raw 基础上扩展

配置说明
- 必填：roomId（直播间号，支持短号，内部会调用 room_init 解析）
- 可选：uid（0 表示匿名）
- 可选登录 Cookie：SESSDATA、bili_jct、buvid3（用于更稳定的接口访问/表情权限）
- 默认 protover=1（无压缩），心跳 30s，可设置 autoReconnect/reconnectDelay
