# Changelog

All notable changes to this project will be documented in this file.

## [v0.2.0-beta] - 2026-02-16

### Added
- **Headless API Gateway** (Phase 2 Restart)
  - OpenAI Compatible API: `POST /v1/chat/completions`
  - Model List: `GET /v1/models`
  - Tool List: `GET /v1/tools`
  - Prometheus Metrics: `GET /metrics`
  - Health Check: `GET /health`
- **Bearer Token Authentication** Middleware
- **Axum** HTTP Server Integration

### Changed
- `gateway` CLI command now starts real HTTP server
- Updated documentation for v0.2.0

## [v0.1.0] - 2026-02-16

### Added
- **CLI Framework** (clap)
  - `agent`, `gateway`, `version`, `status`, `doctor` commands
- **Configuration System** (JSON + TOML)
- **NVIDIA NIM API Integration**
  - Working models: `z-ai/glm5`, `deepseek-ai/deepseek-v3.2`
- **Tool Calling System** (`@tool_name` format)
  - `fs_read`, `fs_write`, `echo` tools
- **MCP Protocol Client** (stdio transport)
- **Skills Dynamic System** (SKILL.md format)
- **Telemetry Module**
  - SQLite Metrics Storage
  - OpenTelemetry-style Tracing
  - HTML Dashboard
- **Security Module**
  - Command Whitelist Sandbox
  - AES-GCM Encryption

### Performance
- Binary Size: 6.6 MB
- Startup Time: ~7ms
- Memory Usage: ~5 MB

## [v0.1.0-alpha] - 2026-02-15

### Added
- Initial project structure
- Core traits and abstractions
- Basic CLI with clap
