# Neko-Claw 构建与运行指南

## 🔨 本地构建

### 前置要求

```bash
# 检查 Rust 版本
rustc --version  # 要求: 1.75+
cargo --version

# （如果没有 Rust）安装 Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### 构建

```bash
# 进入项目目录
cd nekoclaw

# 测试编译
cargo check

# 完整构建 (Debug 模式)
cargo build

# Release 构建 (优化模式)
cargo build --release
```

### 构建产物

- **Debug 模式**: `target/debug/nekoclaw` (~50MB)
- **Release 模式**: `target/release/nekoclaw` (~3.4MB，带 strip 和 LTO)

---

## 🚀 运行

### 1. Agent 模式 (聊天)

```bash
# 交互式模式
cargo run -- agent

# 单条消息模式
cargo run -- agent -m "Hello, nekoclaw!"

# 指定 Provider
cargo run -- agent -m "Hello!" -P openai -M gpt-4
```

### 2. Gateway 模式 (Webhook 服务器)

```bash
# 启动 Gateway (默认 127.0.0.1:8080)
cargo run -- gateway

# 自定义端口
cargo run -- gateway --host 0.0.0.0 --port 9090

# 随机端口模式 (安全增强)
cargo run -- gateway --port-random
```

### 3. Daemon 模式 (后台服务)

```bash
# 启动后台服务
cargo run -- daemon

# 后台启动 + 断开终端运行
cargo run -- daemon --background
```

### 4. 系统管理

```bash
# 查看状态
cargo run -- status

# 运行诊断
cargo run -- doctor

# 管理服务 (Linux/Mac)
cargo run -- service --install   # 安装为系统服务
cargo run -- service --start     # 启动服务
cargo run -- service --stop      # 停止服务
cargo run -- service --status    # 查看服务状态
cargo run -- service --uninstall # 卸载服务
```

---

## ⚙️ 配置

### 配置文件位置

```
~/.nekoclaw/
├── config.toml        # 主配置文件
├── workspace/         # 工作区
│   ├── skills/        # Skills 扩展
│   ├── memory/        # 记忆文件
│   └── .identity/     # 身份文件
└── log/              # 日志文件
```

### 配置示例

```toml
# ~/.nekoclaw/config.toml
api_key = "sk-xxxxxxxxxxxxxxxx"
default_provider = "openai"
default_model = "gpt-4"
default_temperature = 0.7

[memory]
backend = "sqlite"
auto_save = true
vector_weight = 0.7
keyword_weight = 0.3

[gateway]
require_pairing = true
allow_public_bind = false

[discord]
token = "your-discord-bot-token"
allowed_users = ["your-user-id"]

[security]
workspace_only = true
forbidden_paths = ["/etc", "/root", "~/.ssh"]
```

---

## 🧪 测试

```bash
# 运行所有测试
cargo test

# 运行集成测试
cargo test --test integration

# 运行 CLI 测试
cargo test --test cli

# 带详细输出
cargo test -- --nocapture
```

---

## 📦 分发

### 创建二进制包

```bash
# 构建 Release
cargo build --release

# 打包 (Linux)
tar -czf nekoclaw-linux-x64.tar.gz -C target/release nekoclaw

# 打包 (Mac)
tar -czf nekoclaw-macos-x64.tar.gz -C target/release nekoclaw

# 打包 (Windows)
powershell Compress-Archive -Path target\release\nekoclaw.exe -DestinationPath nekoclaw-windows-x64.zip
```

### 安装到系统

```bash
# 安装到 ~/.cargo/bin
cargo install --path .

# 卸载
cargo uninstall nekoclaw
```

---

## 🐛 调试

### 启用调试日志

```bash
# 环境变量启用详细日志
RUST_LOG=nekoclaw=debug cargo run -- agent

# 启用所有模块日志
RUST_LOG=debug cargo run -- agent
```

### Lint 检查

```bash
# 运行 Clippy
cargo clippy

# 检查并修复
cargo clippy --fix

# 格式化代码
cargo fmt
```

---

## ⚠️ 常见问题

### Q: 构建失败，提示 `async-trait` 未找到?
```bash
# 清理并重新构建
cargo clean
cargo build
```

### Q: 编译太慢?
```bash
# 使用 sccache 加速
cargo install sccache
export RUSTC_WRAPPER=sccache
```

### Q: 二进制文件太大?
```bash
# 确保使用 Release 模式 + LTO + strip
cargo build --release --release-opt-level=z
```

---

**🐾 喵...祝主人构建顺利喵...** 💜
