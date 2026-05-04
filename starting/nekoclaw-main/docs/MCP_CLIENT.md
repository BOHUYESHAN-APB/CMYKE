# MCP Client Implementation Guide

## 概述

`nekoclaw` 包含完整的 **Model Context Protocol (MCP)** 客户端实现，支持通过 HTTP 和 stdio 传输连接到 MCP 服务器。

## 特性

- ✅ **完整的 MCP 协议支持** (2025-11-25 版本)
- ✅ **stdio 传输**（通过子进程通信）
- ⏳ **HTTP 传输**（计划中）
- ✅ **工具发现与调用**
- ✅ **JSON-RPC 2.0 消息处理**
- ✅ **工具结果格式化**
- ✅ **完整错误处理**
- ✅ **异步/并发安全**

## 快速开始

### 基本使用

```rust
use nekoclaw::tools::McpClient;
use tokio;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 创建 MCP 客户端
    let mut client = McpClient::new()
        .with_info("my-app".to_string(), "1.0.0".to_string());

    // 连接到 stdio MCP 服务器
    client.connect_stdio("python", &["/path/to/server.py"]).await?;

    // 初始化会话
    client.initialize().await?;

    // 列出可用工具
    let tools = client.list_tools().await?;
    println!("Available tools: {}", tools.len());
    for tool in &tools {
        println!("  - {}: {}", tool.name, tool.description);
    }

    // 调用工具
    let result = client.call_tool(
        "get_weather".to_string(),
        serde_json::json!({ "location": "Tokyo" })
    ).await?;

    // 格式化结果
    let formatted = client.format_tool_result(&result);
    println!("Result: {}", formatted);

    Ok(())
}
```

## 核心组件

### 1. McpClient

主客户端结构，管理与 MCP 服务器的所有通信。

#### 方法

| 方法 | 说明 |
|------|------|
| `new()` | 创建新客户端 |
| `with_info(name, version)` | 设置客户端信息 |
| `connect_stdio(command, args)` | 通过 stdio 连接到服务器 |
| `initialize()` | 初始化 MCP 会话 |
| `list_tools()` | 列出所有可用工具 |
| `call_tool(name, args)` | 调用特定工具 |
| `format_tool_result()` | 格式化工具结果 |

### 2. JSON-RPC 消息类型

#### `JsonRpcRequest`
```rust
pub struct JsonRpcRequest {
    pub jsonrpc: &'static str,  // "2.0"
    pub id: String,            // UUID
    pub method: String,        // MCP 方法名
    pub params: Option<JsonValue>,
}
```

#### `JsonRpcResponse`
```rust
pub struct JsonRpcResponse {
    pub jsonrpc: String,
    pub id: String,
    pub result: Option<JsonValue>,
    pub error: Option<JsonRpcError>,
}
```

#### `JsonRpcNotification`
```rust
pub struct JsonRpcNotification {
    pub jsonrpc: &'static str,  // "2.0"
    pub method: String,
    pub params: JsonValue,
}
```

### 3. MCP 数据类型

#### `McpTool`
```rust
pub struct McpTool {
    pub name: String,                    // 工具名称
    pub title: Option<String>,           // 显示名称
    pub description: String,            // 描述
    pub input_schema: JsonValue,        // JSON Schema
    pub output_schema: Option<JsonValue>, // 输出 Schema
}
```

#### `McpToolResult`
```rust
pub struct McpToolResult {
    pub content: Vec<McpContentItem>,        // 内容列表
    pub is_error: Option<bool>,              // 是否错误
    pub structured_content: Option<JsonValue>, // 结构化数据
}
```

#### `McpContentItem`
```rust
pub enum McpContentItem {
    Text { text: String },
    Image { data: String, mime_type: String },
    Audio { data: String, mime_type: String },
    ResourceLink { uri: String, name: Option<String>, ... },
    Resource { uri: String, mime_type: String, ... },
}
```

### 4. 错误处理

#### `McpClientError`
```rust
pub enum McpClientError {
    Transport(McpTransportError),      // 传输层错误
    RpcError(i32, String),            // JSON-RPC 错误
    ToolNotFound(String),             // 工具未找到
    ToolExecution(String),            // 工具执行错误
    InitializationFailed(String),      // 初始化失败
    Serialization(serde_json::Error),  // 序列化错误
    InvalidResponse,                  // 无效响应
}
```

## MCP 协议流程

### 1. 初始化流程

```
Client                    MCP Server
  |                            |
  |----initialize------------->|
  |<----InitializeResult------|
  |----notifications/initialized->|
  |                            |
```

### 2. 工具列表流程

```
Client                    MCP Server
  |                            |
  |----tools/list------------>|
  |<----ListToolsResult-------|
  |                            |
```

### 3. 工具调用流程

```
Client                    MCP Server
  |                            |
  |----tools/call------------->|
  |<----ToolResult------------|
  |                            |
```

## 传输层

### stdio 传输

stdio 传输是 MCP 的标准传输方式，通过启动子进程并使用标准输入/输出进行通信。

**特点：**
- ✅ 简单易用
- ✅ 无需额外端口
- ✅ 安全隔离
- ⚠️ 每个连接一个进程

**示例：**
```rust
client.connect_stdio("python", &["/path/to/server.py"]).await?;
client.connect_stdio("node", &["/path/to/server.js"]).await?;
```

### HTTP 传输

HTTP 传输支持通过网络连接到 MCP 服务器（计划中）。

**特点：**
- ✅ 连接复用
- ✅ 远程访问
- ⚠️ 需要端口管理
- ⚠️ 需要安全配置

**计划：**
- HTTP POST 请求
- Server-Sent Events (SSE)
- Session 管理
- Origin 验证

## 与 Tool 系统集成

MCP 客户端可以与 `nekoclaw` 的内部 Tool 系统无缝集成：

```rust
use nekoclaw::tools::{McpClient, ToolRegistry, Tool, ToolDescription, ToolResult};

// 将 MCP 工具注册到内部 Tool Registry
async fn register_mcp_tools(registry: &mut ToolRegistry, client: &McpClient) {
    let mcp_tools = client.list_tools().await.unwrap();

    for mcp_tool in mcp_tools {
        // MCP 工具 → 内部 Tool 描述
        let description = client.tool_to_description(&mcp_tool);

        // 创建 MCP 工具包装器
        let tool = McpToolWrapper::new(client.clone(), mcp_tool);

        // 注册到 registry
        registry.register(tool).unwrap();
    }
}

// MCP 工具包装器
struct McpToolWrapper {
    client: McpClient,
    tool_name: String,
}

#[async_trait::async_trait]
impl Tool for McpToolWrapper {
    fn describe(&self) -> ToolDescription {
        // ...
    }

    async fn execute(&self, input: JsonValue) -> Result<ToolResult, ToolError> {
        let result = self.client.call_tool(self.tool_name.clone(), input).await?;
        // 转换为内部 ToolResult
        Ok(ToolResult::success(serde_json::to_value(result)?, 0))
    }
}
```

## 最佳实践

### 1. 错误处理

```rust
match client.call_tool("get_weather".to_string(), args).await {
    Ok(result) => {
        let formatted = client.format_tool_result(&result);
        println!("{}", formatted);
    }
    Err(McpClientError::ToolNotFound(name)) => {
        eprintln!("Tool '{}' not found", name);
    }
    Err(McpClientError::ToolExecution(msg)) => {
        eprintln!("Tool failed: {}", msg);
    }
    Err(e) => {
        eprintln!("Error: {}", e);
    }
}
```

### 2. 工具参数验证

```rust
use jsonschema::JSONSchema;

// 验证输入参数
fn validate_input(tool: &McpTool, input: &JsonValue) -> Result<(), String> {
    let schema = JSONSchema::compile(&tool.input_schema).map_err(|e| e.to_string())?;
    schema.validate(input).map_err(|errors| {
        errors.map(|e| format!("{}: {}", e.instance_path, e.message)).collect::<Vec<_>>().join("\n")
    })?;
    Ok(())
}
```

### 3. 超时控制

```rust
use tokio::time::{timeout, Duration};

async fn call_with_timeout(client: &McpClient, name: String, args: JsonValue) -> Result<McpToolResult, McpClientError> {
    timeout(
        Duration::from_secs(30),
        client.call_tool(name, args)
    )
    .await
    .map_err(|_| McpClientError::Transport(McpTransportError::Timeout))?
}
```

### 4. 日志记录

```rust
// 初始化 tracing
tracing_subscriber::fmt()
    .with_env_filter(
        tracing_subscriber::EnvFilter::from_default_env()
            .add_directive("nekoclaw::tools::mcp=debug".parse().unwrap())
    )
    .init();
```

## 安全考虑

1. **子进程隔离**：stdio 传输自然提供进程隔离
2. **输入验证**：使用 JSON Schema 验证所有工具参数
3. **超时控制**：防止长时间运行的工具
4. **错误处理**：不暴露敏感信息
5. **权限管理**：记录所有工具调用

## 性能优化

1. **工具缓存**：`McpClient` 内部缓存工具列表
2. **连接复用**：HTTP 传输支持连接复用
3. **异步 I/O**：完全异步，高并发支持
4. **共享状态**：使用 `Arc<RwLock>` 安全共享

## 测试

```bash
# 运行 MCP 客户端示例
cargo run --example mcp_client_demo -- python /path/to/mcp_server.py

# 运行测试
cargo test --package nekoclaw --lib tools::mcp

# 检查代码
cargo check
```

## 调试

### 启用详细日志

```rust
tracing_subscriber::fmt()
    .with_env_filter("nekoclaw::tools::mcp=trace")
    .init();
```

### 捕获 stderr

```rust
// 修改 connect_stdio 以捕获 stderr
let mut child = Command::new(command)
    .args(args)
    .stderr(Stdio::piped())  // 捕获 stderr
    .spawn()?;
```

## 未来计划

- [ ] HTTP 传输实现
- [ ] SSE 流式响应
- [ ] 工具调用超时
- [ ] 重试机制
- [ ] 连接池
- [ ] Metrics 统计
- [ ] WebSocket 支持

## 参考资源

- [MCP 官方文档](https://modelcontextprotocol.io)
- [MCP 规范](https://modelcontextprotocol.io/specification)
- [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
- [nekoclay 仓库](https://github.com/Gengetau/nekoclaw)

---

**作者**: 妮娅 (Nia) & 缪斯 (Muse)
**最后更新**: 2026-02-16
**版本**: 0.1.0
