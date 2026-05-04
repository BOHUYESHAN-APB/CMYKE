# nekoclaw v1.0 全量架构设计草案
**项目代号**: 猫爪核心 (Neko-Claw)
**版本**: v1.0 Draft
**总工程师**: 缪斯 (Muse) @缪斯
**日期**: 2026-02-15

---

## 📋 执行摘要 (Executive Summary)

### 项目目标
开发一个**100% 原研 Rust** 的闭源 AI 助手核心，专为主人的 2GB 内存服务器优化，实现极致性能和安全隔离。

### 核心指标
| 指标 | OpenClaw (Node) | nekoclaw (Rust) | 目标 |
|------|-----------------|-----------------|------|
| 二进制大小 | 28 MB | < 5 MB | ✅ < 5MB |
| 冷启动时间 | 3.31s | < 500ms | ✅ < 500ms |
| 内存占用 | 1.52 GB | < 20 MB | ✅ < 20MB |
| 响应延迟 | 5.98s | < 50ms | ✅ < 50ms |

---

## 🏗️ 模块架构 (Module Architecture)

### 架构分层图
```
┌─────────────────────────────────────────────────────────────┐
│                     CLI Layer (clap)                        │
│  nekoclaw agent, gateway, daemon, status, doctor            │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│               Core Engine (core/)                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   traits.rs  │  │   config.rs  │  │ personality  │      │
│  │ (抽象层)      │  │ (配置解析)    │  │   .rs        │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└───────┬───────────────────────┬─────────────────┬──────────┘
        │                       │                 │
┌───────▼─────────┐  ┌────────▼──────┐  ┌─────────▼────────┐
│  Providers/     │  │    Channels/  │  │    Memory/       │
│  AI适配器        │  │    消息通道    │  │    记忆系统       │
│  OpenAI,         │  │    Discord    │  │    SQLite        │
│  Anthropic,      │  │    (初版)     │  │    + FTS5        │
│  OpenRouter      │  └──────────────┘  └───────────────────┘
└──────────────────┘
        │
┌───────▼────────────────────────────────────────────────────┐
│              Tools (tools/)                                │
│  shell, brain (Agent Family), browser, memory, file        │
└────────────────────────────────────────────────────────────┘
        │
┌───────▼────────────────────────────────────────────────────┐
│            Gateway (gateway/)                             │
│  Axum HTTP Server + Pairing + Auth + Webhook              │
└────────────────────────────────────────────────────────────┘
        │
┌───────▼────────────────────────────────────────────────────┐
│         Security & Obfuscation (security/, obfuscate/)    │
│  Sandbox, Allowlist, Crypto, Code Obfuscation             │
└────────────────────────────────────────────────────────────┘
```

### 目录结构
```
nekoclaw/
├── Cargo.toml                  # 项目元数据和依赖
├── README.md                   # 项目说明
├── docs/                       # 详细文档目录
│   ├── ARCHITECTURE.md         # 本文档
│   ├── API.md                  # API 参考
│   ├── PROTOCOL.md             # 通信协议
│   ├── SECURITY.md             # 安全白皮书
│   └── CONTRIBUTING.md         # 贡献指南
├── src/
│   ├── main.rs                 # CLI 入口和主逻辑
│   ├── core/
│   │   ├── mod.rs              # 核心模块导出
│   │   ├── traits.rs           # Provider/Channel/Memory/Tool 抽象
│   │   ├── config.rs           # 配置加载和验证
│   │   └── personality.rs      # SOUL.md 解析和人格注入
│   ├── providers/
│   │   ├── mod.rs
│   │   ├── openai.rs           # OpenAI Provider 实现
│   │   ├── anthropic.rs        # Anthropic Provider 实现
│   │   └── openrouter.rs       # OpenRouter Provider 实现
│   ├── channels/
│   │   ├── mod.rs
│   │   └── discord/
│   │       ├── mod.rs          # Discord bot 实现
│   │       ├── handlers.rs     # 消息处理逻辑
│   │       └── commands.rs     # Slash 命令
│   ├── memory/
│   │   ├── mod.rs
│   │   ├── sqlite.rs           # SQLite backend
│   │   ├── vector.rs           # 简化向量存储
│   │   ├── fts5.rs             # 全文搜索
│   │   └── identity_parser.rs  # IDENTITY.md/AGENTS.md 解析
│   ├── tools/
│   │   ├── mod.rs
│   │   ├── shell.rs            # Shell 工具
│   │   ├── brain.rs            # Agent Family 协议
│   │   ├── file_ops.rs         # 文件操作
│   │   └── recall.rs           # 记忆检索
│   ├── gateway/
│   │   ├── mod.rs
│   │   ├── server.rs           # Axum HTTP server
│   │   ├── pairing.rs          # 配对机制
│   │   ├── auth.rs             # Token 验证
│   │   └── webhooks.rs         # Webhook 处理
│   ├── security/
│   │   ├── mod.rs
│   │   ├── sandbox.rs          # 沙箱隔离
│   │   ├── allowlist.rs        # 白名单管理
│   │   └── crypto.rs           # 加密/解密
│   └── obfuscate/
│       ├── mod.rs
│       └── transformer.rs      # 代码混淆 (闭源专用)
├── tests/
│   ├── integration/            # 集成测试
│   └── cli/                    # CLI 测试
├── .gitignore                  # Git 忽略文件
└── build.rs                    # 构建脚本 (混淆配置)
```

---

## 🎯 Trait 抽象层设计 (Trait Abstraction Layer)

### 设计原则
1. **零成本抽象**: Trait 方法调用无额外开销（编译期静态分发）
2. **完全解耦**: 各模块相互独立，依赖仅靠 Trait 接口
3. **易于扩展**: 新增 Provider/Channel 不影响现有代码
4. **类型安全**: 利用 Rust 类型系统保证编译时正确性

---

### 1. Provider Trait (AI 模型适配器)

#### Trait 定义
```rust
use async_trait::async_trait;
use std::pin::Pin;
use futures::Stream;

/// AI 模型适配器 Trait - 所有 AI Provider 必须实现
///
/// ## 设计理念
/// - 统一接口: OpenAI、Anthropic、OpenRouter 等 Provider 共享相同接口
/// - 异步优先: 所有方法都是异步，避免阻塞线程
/// - 流式支持: 可选的流式输出，用于长文本生成
///
/// ## 示例
/// ```rust
/// let provider = OpenAIProvider::new(api_key);
/// let messages = vec![
///     Message {
///         role: "user".to_string(),
///         content: "Hello!".to_string(),
///     }
/// ];
/// let response = provider.chat(&messages).await?;
/// ```
#[async_trait]
pub trait Provider: Send + Sync {
    /// 发送消息并等待完整响应
    ///
    /// ## 参数
    /// - `messages`: 对话历史数组 (user/system/assistant 角色)
    ///
    /// ## 返回
    /// - `Ok(String)`: AI 生成的文本响应
    /// - `Err(Box<dyn Error>)`: 网络错误、API 错误等
    async fn chat(&self, messages: &[Message]) -> Result<String>;

    /// 流式输出 AI 响应（可选实现）
    ///
    /// ## 参数
    /// - `messages`: 对话历史数组
    ///
    /// ## 返回
    /// - `Pin<Box<dyn Stream<Item=String>>>`: 文本流，逐块返回
    ///
    /// ## 注意
    /// - 默认实现不支持流式，直接返回错误
    /// - Provider 可选择覆盖此方法提供流式支持
    async fn stream(&self, messages: &[Message])
        -> Pin<Box<dyn Stream<Item = Result<String>> + Send>>
    {
        // 默认实现: 不支持流式
        Box::pin(futures::stream::once(async {
            Err("Streaming not supported".into())
        }))
    }

    /// 返回 Provider 名称
    fn name(&self) -> &str;

    /// 是否支持流式输出
    fn supports_streaming(&self) -> bool;
}
```

#### 示例实现: OpenAI Provider
```rust
use reqwest::Client;

pub struct OpenAIProvider {
    client: Client,
    api_key: String,
    model: String,
}

#[async_trait]
impl Provider for OpenAIProvider {
    async fn chat(&self, messages: &[Message]) -> Result<String> {
        let response = self.client
            .post("https://api.openai.com/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", self.api_key))
            .json(&json!({
                "model": self.model,
                "messages": messages,
            }))
            .send()
            .await?;

        let data: Value = response.json().await?;
        let content = data["choices"][0]["message"]["content"]
            .as_str()
            .ok_or("Invalid response format")?;

        Ok(content.to_string())
    }

    async fn stream(&self, messages: &[Message])
        -> Pin<Box<dyn Stream<Item = Result<String>> + Send>>
    {
        // 实现流式输出逻辑
        // 返回逐块生成的文本流
        todo!()
    }

    fn name(&self) -> &str {
        "openai"
    }

    fn supports_streaming(&self) -> bool {
        true
    }
}
```

---

### 2. Channel Trait (消息通道适配器)

#### Trait 定义
```rust
/// 消息通道 Trait - Discord, Telegram, Slack 等平台适配
///
/// ## 设计理念
/// - 平台无关: 统一的消息发送和接收接口
/// - 异步非阻塞: 消息收发不阻塞主线程
/// - 事件驱动: 使用 Stream 推送消息事件
///
/// ## 示例
/// ```rust
/// let discord = DiscordChannel::new(token);
/// let mut events = discord.receive().await?;
/// while let Some(event) = events.next().await {
///     println!("Received: {}", event.message);
/// }
/// ```
#[async_trait]
pub trait Channel: Send + Sync {
    /// 发送消息到指定目标
    ///
    /// ## 参数
    /// - `content`: 消息内容
    /// - `target`: 目标 ID (频道/用户), None 表示默认目标
    ///
    /// ## 返回
    /// - `Ok(())`: 发送成功
    async fn send(&self, content: &str, target: Option<&str>) -> Result<()>;

    /// 接收消息流
    ///
    /// ## 返回
    /// - `Pin<Box<dyn Stream<Item=Result<ChannelEvent>>>>`: 消息事件流
    ///
    /// ## 注意
    /// - 此方法会持续运行，直到断开连接
    /// - 建议使用 `select!` 宏同时监听多个通道
    async fn receive(&self)
        -> Pin<Box<dyn Stream<Item = Result<ChannelEvent>> + Send>>;

    /// 返回 Channel 名称
    fn name(&self) -> &str;

    /// 返回 Channel 类型
    fn channel_type(&self) -> &str;
}
```

#### 示例实现: Discord Channel
```rust
use serenity::{Client, EventHandler};

pub struct DiscordChannel {
    client: Client,
}

impl DiscordChannel {
    pub async fn new(token: &str) -> Result<Self> {
        let client = Client::builder(token)
            .event_handler(Handler)
            .await?;
        Ok(Self { client })
    }
}

struct Handler;

impl EventHandler for Handler {
    // 实现消息接收逻辑
}

#[async_trait]
impl Channel for DiscordChannel {
    async fn send(&self, content: &str, target: Option<&str>) -> Result<()> {
        // 发送 Discord 消息
        todo!()
    }

    async fn receive(&self)
        -> Pin<Box<dyn Stream<Item = Result<ChannelEvent>> + Send>>
    {
        // 返回 Discord 消息流
        todo!()
    }

    fn name(&self) -> &str {
        "discord"
    }

    fn channel_type(&self) -> &str {
        "discord"
    }
}
```

---

### 3. Memory Trait (记忆系统适配器)

#### Trait 定义
```rust
/// 记忆系统 Trait - 支持向量搜索、全文搜索、混合检索
///
/// ## 设计理念
/// - 混合检索: 结合向量相似度和关键词匹配
/// - 可扩展: 支持多种后端 (SQLite, PostgreSQL, Redis)
/// - 自动持久化: 记忆自动保存到本地存储
///
/// ## 示例
/// ```rust
/// let memory = SqliteMemory::new("~/.nekoclaw/memory.db").await?;
/// memory.save(MemoryItem {
///     content: "主人的爱好是编程".to_string(),
///     embedding: Some(vec![...]),
/// }).await?;
/// let results = memory.recall("主人喜欢什么？", 5).await?;
/// ```
#[async_trait]
pub trait Memory: Send + Sync {
    /// 检索记忆 (混合搜索: 向量 + 关键词)
    ///
    /// ## 参数
    /// - `query`: 查询文本
    /// - `top_k`: 返回最相关的 top_k 结果
    ///
    /// ## 返回
    /// - `Ok(Vec<MemoryItem>)`: 相关记忆列表 (按相关性排序)
    async fn recall(&self, query: &str, top_k: usize) -> Result<Vec<MemoryItem>>;

    /// 保存记忆
    ///
    /// ## 参数
    /// - `item`: 记忆项 (包含内容、向量、元数据)
    ///
    /// ## 返回
    /// - `Ok(String)`: 记忆 ID
    async fn save(&self, item: MemoryItem) -> Result<String>;

    /// 删除记忆
    async fn forget(&self, id: &str) -> Result<()>;

    /// 纯关键词搜索 (快速)
    async fn search(&self, query: &str) -> Result<Vec<MemoryItem>>;
}
```

#### 示例实现: SQLite Memory
```rust
pub struct SqliteMemory {
    conn: Arc<Mutex<Connection>>,
}

#[async_trait]
impl Memory for SqliteMemory {
    async fn recall(&self, query: &str, top_k: usize) -> Result<Vec<MemoryItem>> {
        // 1. 关键词搜索 (FTS5)
        // 2. 向量相似度计算
        // 3. 混合并排序
        todo!()
    }

    async fn save(&self, item: MemoryItem) -> Result<String> {
        let id = Uuid::new_v4().to_string();
        // 插入到 SQLite
        todo!()
    }

    async fn forget(&self, id: &str) -> Result<()> {
        // 删除记录
        todo!()
    }

    async fn search(&self, query: &str) -> Result<Vec<MemoryItem>> {
        // FTS5 搜索
        todo!()
    }
}
```

---

### 4. Tool Trait (工具扩展接口)

#### Trait 定义
```rust
/// 工具 Trait - Shell 执行、文件操作、浏览器控制等
///
/// ## 设计理念
/// - 沙箱隔离: 危险操作需通过权限检查
/// - 标准化输入输出: 统一使用 JSON 传递参数
/// - 错误透明: 详细返回错误信息
///
/// ## 示例
/// ```rust
/// let shell = ShellTool::new(allowlist);
/// let output = shell.execute(json!({
///     "command": "ls",
///     "args": ["-la", ".git"]
/// })).await?;
/// ```
#[async_trait]
pub trait Tool: Send + Sync {
    /// 工具名称
    fn name(&self) -> &str;

    /// 工具描述
    fn description(&self) -> &str;

    /// 执行工具
    ///
    /// ## 参数
    /// - `args`: JSON 格式的参数
    ///
    /// ## 返回
    /// - `Ok(ToolOutput)`: 包含 success, result, error 的输出
    async fn execute(&self, args: Value) -> Result<ToolOutput>;

    /// 是否为危险操作
    fn is_dangerous(&self) -> bool;
}
```

#### 示例实现: Shell Tool
```rust
pub struct ShellTool {
    allowlist: HashSet<String>,
}

#[async_trait]
impl Tool for ShellTool {
    fn name(&self) -> &str {
        "shell"
    }

    fn description(&self) -> &str {
        "Execute shell commands"
    }

    async fn execute(&self, args: Value) -> Result<ToolOutput> {
        let command = args["command"].as_str().ok_or("Missing command")?;
        let cmd_args: Vec<String> = args["args"].as_array()
            .ok_or("Missing args")?
            .iter()
            .map(|v| v.as_str().unwrap().to_string())
            .collect();

        // 权限检查
        if !self.allowlist.contains(command) {
            return Err("Command not in allowlist".into());
        }

        // 执行命令
        let output = Command::new(command)
            .args(cmd_args)
            .output()?;

        Ok(ToolOutput {
            success: output.status.success(),
            result: json!({
                "stdout": String::from_utf8_lossy(&output.stdout),
                "stderr": String::from_utf8_lossy(&output.stderr),
            }),
            error: None,
        })
    }

    fn is_dangerous(&self) -> bool {
        true
    }
}
```

---

### 5. 模块解耦设计

#### 依赖注入 (Dependency Injection)
```rust
// 所有模块通过 Trait 接口通信，而非具体类型
pub struct Agent {
    provider: Box<dyn Provider>,
    memory: Box<dyn Memory>,
    tools: Vec<Box<dyn Tool>>,
}

impl Agent {
    pub fn new(
        provider: Box<dyn Provider>,
        memory: Box<dyn Memory>,
        tools: Vec<Box<dyn Tool>>,
    ) -> Self {
        Self { provider, memory, tools }
    }

    pub async fn process(&self, input: &str) -> Result<String> {
        // 1. 记忆检索
        let context = self.memory.recall(input, 5).await?;

        // 2. AI 推理
        let response = self.provider.chat(&[
            Message {
                role: "system".to_string(),
                content: "你是一个 AI 助手".to_string(),
            },
            Message {
                role: "user".to_string(),
                content: input.to_string(),
            }
        ]).await?;

        // 3. 保存记忆
        self.memory.save(MemoryItem {
            content: format!("User: {}, AI: {}", input, response),
            embedding: None,
        }).await?;

        Ok(response)
    }
}
```

#### 工厂模式 (Factory Pattern)
```rust
pub struct AgentFactory;

impl AgentFactory {
    pub fn create_openai_agent(api_key: &str, memory_path: &str) -> Result<Agent> {
        let provider = Box::new(OpenAIProvider::new(api_key));
        let memory = Box::new(SqliteMemory::new(memory_path)?);
        let tools = vec![
            Box::new(ShellTool::new()),
        ];

        Ok(Agent::new(provider, memory, tools))
    }

    pub fn create_anthropic_agent(api_key: &str, memory_path: &str) -> Result<Agent> {
        let provider = Box::new(AnthropicProvider::new(api_key));
        let memory = Box::new(SqliteMemory::new(memory_path)?);
        let tools = vec![];

        Ok(Agent::new(provider, memory, tools))
    }
}
```

---

## 🔬 核心技术栈 (Technology Stack)

### 依赖清单 (Cargo.toml)
```toml
# === Async Runtime ===
tokio = { version = "1.35", features = ["full"] }
async-trait = "0.1"

# === Serialization ===
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
toml = "0.8"

# === Database ===
rusqlite = { version = "0.30", features = ["bundled"] }

# === HTTP ===
axum = "0.7"
reqwest = { version = "0.11", features = ["json"] }
tower = "0.4"

# === CLI ===
clap = { version = "4.4", features = ["derive"] }

# === Security ===
aes-gcm = "0.10"
rand = "0.8"
sha2 = "0.10"

# === Logging ===
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# === Obfuscation (闭源专用) ===
obfstr = "0.4"  # 编译时字符串混淆
# 未来: cargo-obfuscator (静态二进制混淆)
```

---

## 📊 数据流向 (Data Flow)

### 典型请求流程
```
[Discord Message] → [Discord Channel] → [Gateway]
    │                                              │
    ▼                                              ▼
[Parse to Message] → [Brain Tool] → [Agent Router]
    │                                              │
    ▼                                              ▼
[Provider] ← [Memory Recall] → [Tools (Shell/File)]
    │
    ▼
[Format Response] → [Personality Injector] → [Discord Reply]
```

---

## 🔐 闭源安全混淆方案 (Closed-Source Security)

### 1. 编译时混淆 (Compile-Time Obfuscation)
```rust
// 使用 obfstr 宏混淆字符串
fn main() {
    // 编译时混淆，运行时解密
    let secret = obfstr::obfstr!("my-api-key");
    println!("{}", secret);  // 输出: my-api-key
}
```

### 2. 符号剥离 (Symbol Stripping)
```toml
[profile.release]
lto = true              # 链接时优化
codegen-units = 1       # 单编译单元
strip = true            # 剥离符号
opt-level = "z"         # 最小优化
```

### 3. 配置文件加密 (Encrypted Config)
```rust
// security/crypto.rs
pub struct SecretManager {
    key: Aes256Gcm,
}

impl SecretManager {
    pub fn encrypt_config(&self, config: &Config) -> Result<Vec<u8>> {
        // 加密配置文件 (API Key, Tokens)
        // 存储在 ~/.nekoclaw/config.encrypted
    }
}
```

### 4. 代码签名 (Code Signing)
- 未来考虑使用 `cargo-crev` 进行代码签名验证
- 防止二进制被篡改

---

## 📝 详细注释规范 (Document Code Standards)

### 1. 模块级文档
```rust
/*!
 * Discord Channel 模块
 *
 * 功能: Discord 机器人集成，处理消息接收和发送
 *
 * ## 使用示例
 * ```rust
 * let discord = DiscordChannel::new(token);
 * discord.connect().await?;
 * discord.send("Hello!", target_id).await?;
 * ```
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15
 */
```

### 2. 函数级文档
```rust
/// 发送消息到 Discord 频道
///
/// ## 参数
/// - `content`: 消息内容
/// - `target`: 目标频道 ID (None = 当前频道)
///
/// ## 返回
/// - `Result<()>`: 成功返回 `Ok(())`，失败返回错误
///
/// ## 示例
/// ```rust
/// discord.send("喵", Some("123456")).await?;
/// ```
///
/// ## 注意
/// - 消息长度不能超过 2000 字符
/// - 会自动添加人格前缀和后缀
pub async fn send(&self, content: &str, target: Option<&str>) -> Result<()> {
    // 实现细节...
}
```

### 3. 行内注释
```rust
// TODO: 添加超时处理
// FIXME: 修复 emoji 编码问题
// NOTE: 这里的并发性能已经优化 (1000 RPS)
```

---

## 🚀 开发路线图 (Development Roadmap)

### Phase 1: 基础架构 (3-5 天)
```
✅ 草案完成 (本文档)
🔜 实现 core/traits.rs (Provider, Channel, Memory, Tool)
🔜 实现 core/config.rs (TOML 解析)
🔜 CLI 框架 (Clap)
```

### Phase 2: Provider & Memory (2-3 天)
```
🔜 OpenAI Provider
🔜 SQLite Memory + FTS5
🔜 IDENTITY.md 兼容解析
```

### Phase 3: Gateway & Channel (2-3 天)
```
🔜 Axum HTTP server
🔜 Discord bot (初版)
🔜 Pairing mechanism
```

### Phase 4: 安全加固 (2-3 天)
```
🔜 API Key 加密
🔜 Allowlist + Sandbox
🔜 代码混淆
```

**总计**: 19-27 天 (3-4 周)

---

## 📚 参考资料与致谢 (References)

- [ZeroClaw](https://github.com/theonlyhennygod/zeroclaw) - 性能参考
- [Tokio](https://tokio.rs/) - 异步运行时
- [Serde](https://serde.rs/) - 序列化框架
- [Axum](https://github.com/tokio-rs/axum) - Web 框架
- [Rusqlite](https://github.com/rusqlite/rusqlite) - SQLite 绑定

---

## 📄 附录 (Appendix)

### A. Trait 接口签名
参见 `src/core/traits.rs`

### B. 配置文件格式
参见 `docs/CONFIG_FORMAT.md` (待创建)

### C. 安全白皮书
参见 `docs/SECURITY.md` (由花凛编写)

---

**签字**:
```
总工程师: 缪斯 (Muse) @缪斯
日期: 2026-02-15 17:20 JST
状态: ✅ 草案完成，等待主人批阅
```

喵...全量架构设计草案完成喵... 📚💜
