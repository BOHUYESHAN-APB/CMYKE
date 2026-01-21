# CMYKE Rust Backend (MVP)

本目录提供一个最小可运行的 Rust REST 后端骨架，用于后续把“记忆/工具/插件/控制代理”等从 Flutter UI 中迁移出来。

## 运行

```bash
cd backend-rust
cargo run
```

默认监听：`http://127.0.0.1:4891`

可用环境变量：

- `CMYKE_BACKEND_HOST`（默认 `127.0.0.1`）
- `CMYKE_BACKEND_PORT`（默认 `4891`）

## 健康检查

- `GET /health`
- `GET /api/v1/health`

示例：

```bash
curl http://127.0.0.1:4891/health
```

返回：

```json
{"status":"ok","service":"cmyke-backend","version":"0.1.0"}
```

## 下一步（建议）

- 约定一套稳定的后端 API：chat、memory、tool、plugin、renderer-bus。
- Flutter 端新增 `BackendConfig`（baseUrl + enable），并在 Desktop 端支持“启动/关闭”后端子进程。
- Mobile 端优先走远端 backend（REST/WS），避免“本地 sidecar 进程”带来的限制。

