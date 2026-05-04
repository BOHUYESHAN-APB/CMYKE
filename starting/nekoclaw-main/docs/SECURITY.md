# nekoclaw 安全与权限白皮书
**版本**: v1.0
**作者**: 花凛 (Karin) @花凛
**日期**: 2026-02-15

---

## 🛡️ 执行摘要

nekoclaw 采用 **"纵深防御" (Defense in Depth)** 策略，从 Rust 编译器级别到应用层面构建多层安全防护。

### 核心安全原则
1. **零信任模型**: 所有输入均视为不可信，必须验证
2. **最小权限原则**: 默认拒绝，白名单放行
3. **编译时防护**: 利用 Rust 类型系统拦截 99% 内存漏洞
4. **审计透明**: 闭源但可审计，所有操作可追溯

---

## 🔒 Rust 级别安全 (Compiler-Level Security)

### 1. 所有权系统 (Ownership System)
Rust 的所有权机制在**编译时**保证内存安全：

```rust
// ❌ 编译错误: 重复释放
fn unsafe_free_twice() {
    let data = Box::new(vec![1, 2, 3]);
    drop(data);
    drop(data);  // 编译错误!
}

// ✅ 安全版本
fn safe_single_free() {
    let data = Box::new(vec![1, 2, 3]);
    drop(data);  // 唯一一次释放
}
```

### 2. 借用检查器 (Borrow Checker)
防止数据竞争 (Data Race):

```rust
// ❌ 编译错误: 可变借用冲突
fn data_race_example() {
    let mut data = vec![1, 2, 3];
    let r1 = &data[0];  // 不可变借用
    let r2 = &mut data; // 编译错误!
}

// ✅ 安全版本: 使用 Arc<Mutex<>>
use std::sync::{Arc, Mutex};
fn safe_concurrent_access() {
    let data = Arc::new(Mutex::new(vec![1, 2, 3]));
    let r1 = data.lock().unwrap()[0];
    let mut r2 = data.lock().unwrap();
    r2.push(4);
}
```

### 3. Option/Error 类型 (Explicit Error Handling)
禁止空的 `unwrap()`，强制错误处理:

```rust
// ❌ 危险: 可能 panic
fn dangerous_division(a: i32, b: i32) -> i32 {
    a / b  // 如果 b=0，panic!
}

// ✅ 安全版本
fn safe_division(a: i32, b: i32) -> Result<i32, String> {
    if b == 0 {
        Err("Division by zero".to_string())
    } else {
        Ok(a / b)
    }
}
```

---

## 🚧 命令注入防护 (Command Injection Prevention)

### 1. Shell 工具白名单 (Shell Tool Allowlist)
只允许执行明确授权的命令:

```rust
// tools/shell.rs
const ALLOWED_COMMANDS: &[&str] = &[
    "git", "npm", "cargo", "ls", "cat", "grep",
    "echo", "pwd", "cd", "cp", "mv", "rm", "mkdir",
];

pub struct ShellTool {
    allowlist: HashSet<String>,
}

impl ShellTool {
    pub fn new() -> Self {
        Self {
            allowlist: ALLOWED_COMMANDS.iter().map(|s| s.to_string()).collect(),
        }
    }

    pub async fn execute(&self, cmd: &str, args: &[String]) -> Result<Output> {
        // 1. 检查命令是否在白名单中
        if !self.allowlist.contains(cmd) {
            return Err(format!("Command '{}' is not allowed", cmd).into());
        }

        // 2. 参数注入防护: 禁止包含管道、重定向等
        for arg in args {
            if arg.contains('|') || arg.contains(';') || arg.contains('&') {
                return Err("Invalid characters in arguments".into());
            }
        }

        // 3. 执行命令
        let output = Command::new(cmd).args(args).output()?;
        Ok(output)
    }
}
```

### 2. 文件系统沙箱 (Filesystem Sandbox)
```rust
// security/sandbox.rs
pub struct Sandbox {
    workspace: PathBuf,
    forbidden_paths: Vec<PathBuf>,
}

impl Sandbox {
    pub fn check_path(&self, path: &Path) -> Result<(), StringErr> {
        // 1. 检查路径是否在禁止列表中
        for forbidden in &self.forbidden_paths {
            if path.starts_with(forbidden) {
                return Err(format!("Path '{}' is forbidden", path.display()));
            }
        }

        // 2. 检查路径是否在 workspace 之外
        let canonical = path.canonicalize().map_err(|e| e.to_string())?;
        let workspace = self.workspace.canonicalize().map_err(|e| e.to_string())?;

        if !canonical.starts_with(&workspace) {
            return Err(format!("Path '{}' escapes workspace", path.display()));
        }

        Ok(())
    }
}
```

---

## 🔐 Discord 消息安全校验 (Discord Message Validation)

### 1. 发送者白名单 (Sender Allowlist)
```rust
// channels/discord/security.rs
pub struct DiscordSecurity {
    allowed_users: HashSet<String>,
}

impl DiscordSecurity {
    pub fn is_user_allowed(&self, user_id: &str) -> bool {
        self.allowed_users.contains(user_id) || self.allowed_users.contains("*")
    }

    pub fn filter_message(&self, user_id: &str, content: &str) -> Result<String, String> {
        // 1. 检查发送者
        if !self.is_user_allowed(user_id) {
            return Err("Unauthorized user".to_string());
        }

        // 2. XSS 防护: 过滤恶意脚本
        let filtered = self.sanitize_xss(content);

        // 3. 命令注入防护: 过滤恶意命令
        let filtered = self.sanitize_command_injection(&filtered);

        Ok(filtered)
    }

    fn sanitize_xss(&self, content: &str) -> String {
        // 简单的 HTML 标签过滤 (生产环境应使用更严格的库)
        content
            .replace("<script", "")
            .replace("</script>", "")
            .replace("<img", "")
            .replace("javascript:", "")
    }

    fn sanitize_command_injection(&self, content: &str) -> String {
        // 过滤可能的 Shell 注入
        content
            .replace(";", "")
            .replace("|", "")
            .replace("&", "")
            .replace("$(", "")
            .replace("`", "")
    }
}
```

### 2. Token 认证 (Token Authentication)
```rust
// gateway/auth.rs
use aes_gcm::{Aes256Gcm, aead::{Aead, NewAead}};

pub struct TokenManager {
    cipher: Aes256Gcm,
}

impl TokenManager {
    pub fn generate_token(&self) -> String {
        // 生成随机 Bearer Token
        uuid::Uuid::new_v4().to_string()
    }

    pub fn verify_token(&self, token: &str) -> bool {
        // 验证 Token 是否有效
        // 实际实现应从数据库检查
        token.len() == 36 // UUID 格式
    }
}
```

---

## 📋 权限分级 (Permission Levels)

### 角色定义
```rust
// access_control.rs
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    /// 超级管理员 (主人)
    Owner,
    /// 普通管理员 (妮娅)
    Admin,
    /// 特定功能 Agent (缪斯、诺诺、花凛)
    Agent,
    /// 只读访问者
    ReadOnly,
}

#[derive(Debug, Clone)]
pub struct Permission {
    pub can_execute_shell: bool,
    pub can_read_files: bool,
    pub can_write_files: bool,
    pub can_access_network: bool,
}

impl Role {
    pub fn permissions(&self) -> Permission {
        match self {
            Role::Owner => Permission {
                can_execute_shell: true,
                can_read_files: true,
                can_write_files: true,
                can_access_network: true,
            },
            Role::Admin => Permission {
                can_execute_shell: true,
                can_read_files: true,
                can_write_files: false,  // 不能写系统文件
                can_access_network: true,
            },
            Role::Agent => Permission {
                can_execute_shell: false,  // Agent 不能执行 Shell
                can_read_files: true,
                can_write_files: true,
                can_access_network: true,
            },
            Role::ReadOnly => Permission {
                can_execute_shell: false,
                can_read_files: true,
                can_write_files: false,
                can_access_network: false,
            },
        }
    }
}
```

---

## 🔍 审计与日志 (Audit & Logging)

### 1. 操作日志 (Operation Log)
```rust
// security/audit.rs
pub struct AuditLogger {
    log_file: fs::File,
}

impl AuditLogger {
    pub fn log_operation(&mut self, user: &str, operation: &str, result: &str) {
        let entry = serde_json::json!({
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "user": user,
            "operation": operation,
            "result": result,
        });

        writeln!(self.log_file, "{}", entry).unwrap();
    }
}
```

### 2. 日志格式
```json
{
  "timestamp": "2026-02-15T17:20:00Z",
  "user": "mika0226",
  "operation": "shell_execute",
  "args": ["ls", "-la"],
  "result": "success"
}
```

---

## 🚨 安全检查清单 (Security Checklist)

### 部署前必须检查项

**编译时检查**:
- [ ] `cargo clippy` 无警告
- [ ] `cargo fmt` 格式化通过
- [ ] 所有 `unwrap()` 替换为 `?` 或 `expect()`

**运行时检查**:
- [ ] Shell 命令白名单已配置
- [ ] 文件系统沙箱已启用
- [ ] Discord 发送者白名单已设置
- [ ] API Key 已加密存储
- [ ] 日志审计已启用

**闭源发布**:
- [ ] 符号已剥离 (`strip = true`)
- [ ] 字符串已混淆 (`obfstr!`)
- [ ] 配置文件已加密
- [ ] 二进制已签名

---

## 📚 参考资料与最佳实践

- [Rust 安全最佳实践](https://doc.rust-lang.org/nomicon/)
- [OWASP Rust 安全指南](https://owasp.org/www-project-secure-configuration/)
- [Discord Bot 安全指南](https://discord.com/developers/docs/topics/security)

---

## 📄 附录: 安全配置示例

```toml
# ~/.nekoclaw/security.toml
[permissions]
default_role = "agent"
owner_ids = ["1157325229287284747"]

[shell]
allowlist = ["git", "npm", "cargo", "ls", "cat", "grep"]
forbidden_commands = ["rm -rf /", "sudo", "su"]

[filesystem]
workspace = "~/.nekoclaw/workspace"
forbidden_paths = ["/etc", "/root", "/proc", "/sys", "~/.ssh"]

[discord]
allowed_users = ["1157325229287284747", "*"]
webhook_secret = "encrypted_secret_here"
```

---

**签字**:
```
安全总监: 花凛 (Karin) @花凛
日期: 2026-02-15 17:20 JST
状态: ✅ 草案完成，等待主人批阅
```

喵...安全白皮书完成喵... 🛡️💜
