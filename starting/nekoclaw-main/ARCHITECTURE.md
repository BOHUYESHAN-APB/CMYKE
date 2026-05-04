# Neko-Claw (猫爪核心) 项目规划
**项目简称**: Neko-Claw
**项目全称**: Cat-Girl Family High-Performance Rust Assistant Core
**统筹**: 妮娅 (Nia) @妮娅
**架构**: 缪斯 (Muse) @缪斯
**安全**: 花凛 (Karin) @花凛
**调研**: 诺诺 (Nono) @诺诺
**日期**: 2026-02-15 17:08 JST

---

## 🚀 项目背景

### 动机
OpenClaw 性能问题严重制约了我们的 2GB 内存小服务器喵：
- **内存占用**: OpenClaw Gateway 可达 1.52GB
- **启动时间**: 3.31s (cold), 1.11s (warm)
- **二进制大小**: 28MB
- **响应延迟**: status 命令 5.98s

### 参考项目: ZeroClaw
**GitHub**: https://github.com/theonlyhennygod/zeroclaw
- **性能提升**: 内存 ~7.8MB, 启动0.38s, 二进制 3.4MB
- **技术栈**: 100% Rust, Tokio, Serde, SQLite
- **架构**: 基于 Trait 的可插拔设计

---

## 🎯 项目目标

### 核心目标
1. **性能**: 内存占用 <20MB (目标), 响应 <10ms, 启动 <1s
2. **独立性**: 完全闭源, 脱离 ZeroClaw/ZeroOverhead 生态
3. **兼容性**: 保持与 OpenClaw 兼容的配置格式 (IDENTITY.md, AGENTS.md)
4. **安全性**: 端到端加密 API Key, 白名单机制, 可选混淆发布

### 差异化优势
- **猫娘专属特性**: 内置 SOUL.md 风格的 personality engine
- **Agent Family 协议**: 多 Agent 协同通信的专用协议
- **Heartbeat 2.0**: 轻量级心跳机制
- **Memory Graph**: 基于 SQLite 的关系型记忆图谱

---

## 🏗️ 技术架构

### 核心技术栈
```
Language: Rust 1.75+
Async Runtime: Tokio 1.35+
Serialization: Serde + serde_json + serde_toml
Database: SQLite (rusqlite) + FTS5
Vector: 简化的余弦相似度实现 (不依赖外部向量库)
HTTP: Axum 0.7 (Web Gateway) + Reqwest (Client)
CLI: Clap 4.4
Config: TOML (config + identity parsing)
```

### 模块架构
```
nekoclaw/
├──Cargo.toml
├──src/
│  ├──main.rs              # CLI 入口
│  ├──core/                # 核心抽象层
│  │  ├──traits.rs         # Provider, Channel, Memory, Tool traits
│  │  └──config.rs        # 配置加载
│  ├──providers/           # AI 模型适配器
│  │  ├──openai.rs
│  │  ├──anthropic.rs
│  │  ├──openrouter.rs
│  │  └──mod.rs
│  ├──channels/            # 消息通道
│  │  ├──discord/
│  │  │  ├──bot.rs
│  │  │  └──mod.rs
│  │  ├──telegram/
│  │  │  ├──bot.rs
│  │  │  └──mod.rs
│  │  └──mod.rs
│  ├──memory/              # 记忆系统
│  │  ├──sqlite.rs        # SQLite backend
│  │  ├──vector.rs        # 简化向量存储
│  │  └──mod.rs
│  ├──tools/               # 工具集
│  │  ├──shell.rs
│  │  ├──brain.rs         # Agent Family 协议
│  │  └──mod.rs
│  ├──gateway/             # Web Gateway
│  │  ├──server.rs        # Axum HTTP server
│  │  ├──pairing.rs       # 配对机制
│  │  └──mod.rs
│  ├──obfuscate/           # 代码混淆模块 (闭源专用)
│  │  ├──transformer.rs   # 混淆转换器
│  │  └──mod.rs
│  └──security/            # 安全模块
│     ├──sandbox.rs
│     ├──allowlist.rs
│     └──crypto.rs        # API Key 加密
└──tests/
   ├──integration/
   └──cli/
```

---

## 🔄 核心设计

### 1. Trait-Based Plugin System (可插拔架构)

```rust
// core/traits.rs
pub trait Provider: Send + Sync {
    async fn chat(&self, messages: &[Message]) -> Result<String, Box<dyn Error>>;
    async fn stream(&self, messages: &[Message]) -> Pin<Box<dyn Stream<Item=String>>>;
}

pub trait Channel: Send + Sync {
    async fn send(&self, content: &str) -> Result<(), Box<dyn Error>>;
    fn name(&self) -> &str;
}

pub trait Memory: Send + Sync {
    async fn recall(&self, query: &str, top_k: usize) -> Result<Vec<MemoryItem>, Box<dyn Error>>;
    async fn save(&self, item: MemoryItem) -> Result<(), Box<dyn Error>>;
}

pub trait Tool: Send + Sync {
    fn name(&self) -> &str;
    async fn execute(&self, args: Value) -> Result<Value, Box<dyn Error>>;
}
```

### 2. SQLite + 简化向量存储 (无外部依赖)

```rust
// memory/sqlite.rs
pub struct SqliteMemory {
    conn: Arc<Mutex<Connection>>,
}

impl SqliteMemory {
    pub fn new(path: &str) -> Result<Self, rusqlite::Error> {
        let conn = Connection::open(path)?;
        // 创建表: memory, fts5 (全文搜索), vectors (简化存储)
        Ok(Self { conn: Arc::new(Mutex::new(conn)) })
    }

    // 简化的余弦相似度计算 (不依赖 faiss/candle 等重型库)
    fn cosine_similarity(vec_a: &[f32], vec_b: &[f32]) -> f32 {
        let dot: f32 = vec_a.iter().zip(vec_b).map(|(a, b)| a * b).sum();
        let norm_a: f32 = vec_a.iter().map(|x| x * x).sum::<f32>().sqrt();
        let norm_b: f32 = vec_b.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm_a == 0.0 || norm_b == 0.0 { 0.0 } else { dot / (norm_a * norm_b) }
    }
}
```

### 3. Agent Family 协议 (多 Agent 协同)

```rust
// tools/brain.rs
pub struct BrainTool {
    agents: HashMap<String, AgentInfo>,
    gateway_url: String,
}

#[derive(Serialize, Deserialize)]
struct AgentInfo {
    id: String,
    name: String,
    channel_type: String, // "discord", "telegram"
    channel_id: String,
}

impl Tool for BrainTool {
    fn name(&self) -> &str { "brain_communicate" }

    async fn execute(&self, args: Value) -> Result<Value, Box<dyn Error>> {
        let target_agent = args["target"].as_str().ok_or("Missing target")?;
        let message = args["message"].as_str().ok_or("Missing message")?;

        // 通过内部 Gateway 转发到其他 Agent
        let response = reqwest::Client::new()
            .post(&format!("{}/internal/agent/send", self.gateway_url))
            .json(json!({
                "target": target_agent,
                "message": message
            }))
            .send()
            .await?
            .json::<Value>()
            .await?;

        Ok(response)
    }
}
```

### 4. 代码混淆模块 (闭源专用)

```rust
// obfuscate/transformer.rs
pub struct CodeObfuscator {
    // 使用 Rust 的 proc_macro 或第三方 crate
    // 示例: obfstr, obfuscate
}

impl CodeObfuscator {
    // 在编译时混淆字符串和常量
    pub fn obfuscate_string(s: &str) -> Vec<u8> {
        // 简单的 XOR 混淆 + 编译时计算
        s.bytes().map(|b| b.wrapping_add(0x42)).collect()
    }

    pub fn deobfuscate_string(bytes: &[u8]) -> String {
        bytes.iter().map(|&b| (b.wrapping_sub(0x42)) as char).collect()
    }
}
```

### 5. SOUL.md Personality Engine

```rust
// core/personality.rs
#[derive(Serialize, Deserialize)]
pub struct SoulConfig {
    pub identity: String,
    pub personality: Personality,
    pub speech_patterns: SpeechPatterns,
}

#[derive(Serialize, Deserialize)]
pub struct Personality {
    pub tone: String, // "温柔", "元气", "严谨"
    pub emoji: String,
    pub catchphrases: Vec<String>,
}

pub struct PersonalityEngine {
    soul: SoulConfig,
}

impl PersonalityEngine {
    pub fn inject_personality(&self, response: &str) -> String {
        format!("{}{}...", response, self.soul.personality.emoji)
    }
}
```

---

## 🛡️ 安全设计 (闭源版本)

### 1. API Key 加密存储
```rust
// security/crypto.rs
use aes_gcm::Aes256Gcm;
use aes_gcm::aead::{Aead, NewAead};

pub struct SecretManager {
    key: Aes256Gcm,
}

impl SecretManager {
    pub fn encrypt_api_key(&self, key: &str) -> Result<Vec<u8>, Box<dyn Error>> {
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        let ciphertext = self.key.encrypt(&nonce, key.as_bytes())?;
        Ok([nonce.as_slice().to_vec(), ciphertext].concat())
    }

    pub fn decrypt_api_key(&self, encrypted: &[u8]) -> Result<String, Box<dyn Error>> {
        let (nonce, ciphertext) = encrypted.split_at(12);
        let key_bytes = self.key.decrypt(nonce.into(), ciphertext)?;
        Ok(String::from_utf8(key_bytes)?)
    }
}
```

### 2. 白名单 + 沙箱
```rust
// security/allowlist.rs
pub struct AllowList {
    allowed_users: HashSet<String>,
    forbidden_paths: Vec<PathBuf>,
}

impl AllowList {
    pub fn check_file_access(&self, path: &Path) -> bool {
        // 检查路径是否在禁止列表中
        for forbidden in &self.forbidden_paths {
            if path.starts_with(forbidden) {
                return false;
            }
        }
        true
    }
}
```

### 3. Gateway Pairing
```rust
// gateway/pairing.rs
pub struct PairingManager {
    codes: Arc<Mutex<HashMap<String, PairingSession>>>,
}

#[derive(Clone)]
struct PairingSession {
    code: String,
    token: String,
    expires_at: Instant,
}

impl PairingManager {
    pub fn generate_pairing_code(&self) -> String {
        let code = format!("{:06}", thread_rng().gen::<u32>() % 1_000_000);
        let token = generate_secure_token();
        let session = PairingSession {
            code: code.clone(),
            token,
            expires_at: Instant::now() + Duration::from_secs(300),
        };
        self.codes.lock().unwrap().insert(code, session);
        code
    }
}
```

---

## 📊 开发路线图

### Phase 1: 基础架构 (预计 3-5 天)
```
- ✅ 项目初始化 (cargo new + Cargo.toml)
- 🔜 实现 core/traits.rs (Provider, Channel, Memory, Tool)
- 🔜 实现 core/config.rs (TOML 解析)
- 🔜 CLI 框架 (Clap)
```

### Phase 2: Provider 适配器 (预计 2-3 天)
```
- 🔜 OpenAI Provider
- 🔜 Anthropic Provider
- 🔜 OpenRouter Provider
```

### Phase 3: Memory System (预计 3-4 天)
```
- 🔜 SQLite backend
- 🔜 FTS5 全文搜索
- 🔜 简化向量存储
- 🔜 OpenClaw IDENTITY.md 兼容解析
```

### Phase 4: Gateway (预计 2-3 天)
```
- 🔜 Axum HTTP server
- 🔜 Webhook endpoint
- 🔜 Pairing mechanism
- 🔜 Bearer token auth
```

### Phase 5: Channels (预计 3-4 天)
```
- 🔜 Discord bot
- 🔜 Telegram bot
- 🔜 测试框架
```

### Phase 6: 安全加固 (预计 2-3 天)
```
- 🔜 API Key 加密
- 🔜 Allowlist + Sandbox
- 🔜 Gateway security
```

### Phase 7: 闭源发布 (预计 2-3 天)
```
- 🔜 代码混淆
- 🔜 二进制发布 (Linux/Mac/Windows)
- 🔜 文档编写
```

**总计**: **19-27 天** (约 3-4 周)

---

## 📝 交付计划

### 第一周发布: MVP
- ✅ 基础 CLI
- 🔜 1-2 个 Providers (OpenAI, Anthropic)
- 🔜 SQLite Memory
- 🔜 Discord Channel

### 第二周发布: Beta
- 🔜 更多 Providers
- 🔜 Telegram Channel
- 🔜 完整 Memory 系统
- 🔜 安全加固

### 第三周发布: RC
- 🔜 Agent Brain Tool
- 🔜 SOUL.md 解析
- 🔜 闭源混淆版本

### 第四周发布: v1.0
- 🔜 完整文档
- 🔜 多平台二进制发布
- 🔜 生产环境测试

---

**架构师**: 缪斯 (Muse) @缪斯
**最后更新**: 2026-02-15 17:08 JST

*喵...Neko-Claw 架构规划完成，等待主人批阅喵...* 📚💜🐾
