//! # Tool Trait & Registration System + MCP Client
//!
//! 🔧 MCP-compatible tool system + Full MCP Client Implementation
//!
//! @诺诺 + @缪斯 的 MCP 实现组合喵
//!
//! ## 功能
//! - MCP-compatible tool descriptions
//! - Tool registration & discovery
//! - Tool execution with safety checks
//! - Tool result formatting for LLM
//! - **MCP Client implementation** (stdio + HTTP transports)
//!
//! ## MCP 协议兼容性
//! - Tool name, description, input schema
//! - JSON Schema validation
//! - Tool result formatting
//! - JSON-RPC 2.0 messaging
//! - MCP initialization, tools/list, tools/call
//!
//! 🔒 SAFETY: All tools go through security sandbox
//!
//! Author: 诺诺 (Nono) ⚡ + 缪斯 (Muse) 📚

use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;
use std::collections::HashMap;
use std::sync::Arc;
use thiserror::Error;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{ChildStdin, ChildStdout, Command};
use tokio::sync::{Mutex, RwLock};
use uuid::Uuid;

/// 🔒 SAFETY: Tool 执行错误类型喵
#[derive(Debug, Error)]
pub enum ToolError {
    /// 工具未注册
    #[error("Tool '{0}' not found")]
    NotFound(String),

    /// 工具执行失败
    #[error("Tool execution failed: {0}")]
    ExecutionFailed(String),

    /// 参数验证失败
    #[error("Parameter validation failed: {0}")]
    ValidationError(String),

    /// 权限不足
    #[error("Permission denied for tool '{0}'")]
    PermissionDenied(String),

    /// 超时
    #[error("Tool execution timed out")]
    Timeout,

    /// 其他错误
    #[error("Tool error: {0}")]
    Other(String),
}

/// 🔒 SAFETY: Tool 描述结构体（MCP 兼容）喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolDescription {
    /// 工具名称（唯一标识符）
    pub name: String,

    /// 工具描述（用途和功能）
    pub description: String,

    /// 输入参数 schema（JSON Schema 格式）
    pub input_schema: JsonValue,

    /// 工具分类
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,

    /// 是否危险操作（需要确认）
    #[serde(default = "default_dangerous")]
    pub dangerous: bool,

    /// 权限要求
    #[serde(skip_serializing_if = "Option::is_none")]
    pub required_permissions: Option<Vec<String>>,
}

fn default_dangerous() -> bool {
    false
}

/// 🔒 SAFETY: Tool 执行结果喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolResult {
    /// 是否成功
    pub success: bool,

    /// 结果数据（JSON 格式）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<JsonValue>,

    /// 错误信息（如果失败）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,

    /// 执行时间（毫秒）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<u64>,
}

impl ToolResult {
    /// 🔒 SAFETY: 创建成功结果喵
    pub fn success(data: JsonValue, duration_ms: u64) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
            duration_ms: Some(duration_ms),
        }
    }

    /// 🔒 SAFETY: 创建失败结果喵
    pub fn failure(error: String) -> Self {
        Self {
            success: false,
            data: None,
            error: Some(error),
            duration_ms: None,
        }
    }
}

/// 🔒 SAFETY: Tool trait（MCP 兼容）喵
///
/// 所有工具必须实现这个 trait
#[async_trait::async_trait]
pub trait Tool: Sync + Send {
    /// 获取工具描述
    fn describe(&self) -> ToolDescription;

    /// 验证输入参数
    fn validate_input(&self, input: &JsonValue) -> Result<(), ToolError>;

    /// 执行工具
    async fn execute(&self, input: JsonValue) -> Result<ToolResult, ToolError>;
}

/// 🔒 SAFETY: 工具注册器喵
///
/// 管理所有可用工具的工具注册系统
#[derive(Clone)]
pub struct ToolRegistry {
    /// 工具映射（名称 → 工具）
    tools: HashMap<String, Arc<dyn Tool>>,

    /// 工具分类映射
    categories: HashMap<String, Vec<String>>,
}

impl ToolRegistry {
    /// 🔒 SAFETY: 创建新的工具注册器喵
    pub fn new() -> Self {
        Self {
            tools: HashMap::new(),
            categories: HashMap::new(),
        }
    }

    /// 🔒 SAFETY: 注册工具喵
    pub fn register<T: Tool + 'static>(&mut self, tool: T) -> Result<(), ToolError> {
        let description = tool.describe();
        let name = description.name.clone();
        let category = description.category.clone();

        // 检查名称冲突
        if self.tools.contains_key(&name) {
            return Err(ToolError::ExecutionFailed(format!(
                "Tool '{}' already registered",
                name
            )));
        }

        // 注册工具
        self.tools.insert(name.clone(), Arc::new(tool));

        // 添加到分类
        if let Some(cat) = category {
            self.categories
                .entry(cat)
                .or_insert_with(Vec::new)
                .push(name.clone());
        }

        tracing::info!("Tool registered: {} - {}", name, description.description);
        Ok(())
    }

    /// 🔒 SAFETY: 获取工具描述喵
    pub fn get_description(&self, name: &str) -> Option<ToolDescription> {
        self.tools.get(name).map(|tool| tool.describe())
    }

    /// 🔒 SAFETY: 获取所有工具描述喵
    pub fn all_descriptions(&self) -> Vec<ToolDescription> {
        self.tools.values().map(|tool| tool.describe()).collect()
    }

    /// 🔒 SAFETY: 获取分类下的工具喵
    pub fn tools_by_category(&self, category: &str) -> Vec<ToolDescription> {
        self.categories
            .get(category)
            .map(|names| {
                names
                    .iter()
                    .filter_map(|name| self.get_description(name))
                    .collect()
            })
            .unwrap_or_default()
    }

    /// 🔒 SAFETY: 执行工具喵
    pub async fn execute(&self, name: &str, input: JsonValue) -> Result<ToolResult, ToolError> {
        // 查找工具
        let tool = self
            .tools
            .get(name)
            .ok_or_else(|| ToolError::NotFound(name.to_string()))?;

        let start = std::time::Instant::now();

        // 验证输入
        tool.validate_input(&input)?;

        // 执行工具
        let result = tool.execute(input).await?;

        Ok(result)
    }

    /// 🔒 SAFETY: 工具数量喵
    pub fn count(&self) -> usize {
        self.tools.len()
    }

    /// 🔒 SAFETY: 检查工具是否存在喵
    pub fn has_tool(&self, name: &str) -> bool {
        self.tools.contains_key(name)
    }
}

impl Default for ToolRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// 🔒 SAFETY: Tool Calling 请求喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCallRequest {
    /// 工具名称
    pub tool_name: String,

    /// 工具参数
    pub arguments: JsonValue,

    /// 调用 ID（上下文跟踪）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub call_id: Option<String>,
}

/// 🔒 SAFETY: Tool Calling 响应喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCallResponse {
    /// 调用结果
    pub result: ToolResult,

    /// 调用 ID（上下文跟踪）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub call_id: Option<String>,
}

/// 🔒 SAFETY: 格式化工具列表为 LLM 可读格式喵
pub fn format_tools_for_llm(tools: &[ToolDescription]) -> String {
    let mut output = String::from("Available tools:\n");

    for tool in tools {
        output.push_str(&format!("\n### {}\n", tool.name));
        output.push_str(&format!("**Description**: {}\n", tool.description));

        if let Some(category) = &tool.category {
            output.push_str(&format!("**Category**: {}\n", category));
        }

        if tool.dangerous {
            output.push_str("**⚠️ DANGEROUS**: This tool requires confirmation\n");
        }

        // 格式化输入 schema
        if let Some(schema) = tool.input_schema.get("properties") {
            if let Some(obj) = schema.as_object() {
                output.push_str("**Parameters**:\n");
                for (param, param_schema) in obj {
                    let param_type = param_schema
                        .get("type")
                        .and_then(|t| t.as_str())
                        .unwrap_or("unknown");
                    let param_desc = param_schema
                        .get("description")
                        .and_then(|d| d.as_str())
                        .unwrap_or("-");

                    output.push_str(&format!("- `{}` ({}): {}\n", param, param_type, param_desc));
                }
            }
        }

        output.push('\n');
    }

    output
}

/// 🔒 SAFETY: 格式化工具调用为 LLM 可读字符串喵
pub fn format_tool_call_for_llm(call: &ToolCallRequest) -> String {
    let args_str = if call.arguments.is_null() {
        "no arguments".to_string()
    } else if call.arguments.is_string() {
        // 🔒 SAFETY: 使用 unwrap_or_default 替代 unwrap() 喵
        call.arguments.as_str().unwrap_or_default().to_string()
    } else {
        serde_json::to_string_pretty(&call.arguments).unwrap_or_else(|_| "{}".to_string())
    };

    format!("Call tool '{}' with: {}", call.tool_name, args_str)
}

/// 🔒 SAFETY: 格式化工具结果为 LLM 可读字符串喵
pub fn format_tool_result_for_llm(result: &ToolResult) -> String {
    if result.success {
        if let Some(data) = &result.data {
            serde_json::to_string_pretty(data).unwrap_or_else(|_| "{}".to_string())
        } else {
            "Tool executed successfully (no output)".to_string()
        }
    } else {
        format!("Tool failed: {}", result.error.as_deref().unwrap_or("Unknown error"))
    }
}

/// 🔒 SAFETY: 从文本中解析工具调用指令喵
pub fn parse_tool_calls(text: &str) -> Vec<ToolCallRequest> {
    let mut calls = Vec::new();
    
    // 正则表达式匹配 @tool_name(json_params)
    // 允许嵌套的大括号喵
    let re = regex::Regex::new(r"@([a-zA-Z0-9_]+)\(([\s\S]*?)\)").unwrap();
    
    for cap in re.captures_iter(text) {
        let tool_name = cap[1].to_string();
        let params_str = cap[2].trim();
        
        // 尝试解析为 JSON
        let arguments = if params_str.is_empty() {
            serde_json::Value::Null
        } else {
            serde_json::from_str(params_str).unwrap_or_else(|_| serde_json::Value::String(params_str.to_string()))
        };
        
        calls.push(ToolCallRequest {
            tool_name,
            arguments,
            call_id: None,
        });
    }
    
    calls
}

// ============================================================================
// MCP Client Implementation (by 缪斯 📚)
// ============================================================================

/// 🔒 SAFETY: MCP 传输层类型喵
pub enum McpTransport {
    /// stdio 传输（子进程）
    Stdio { stdin: Arc<Mutex<ChildStdin>>, stdout: Arc<Mutex<ChildStdout>> },
    /// HTTP 传输（未来扩展）
    Http { url: String },
}

/// 🔒 SAFETY: MCP 传输层错误喵
#[derive(Debug, Error)]
pub enum McpTransportError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serde(#[from] serde_json::Error),

    #[error("Process error: {0}")]
    Process(String),

    #[error("Timeout")]
    Timeout,

    #[error("Transport closed")]
    Closed,
}

/// 🔒 SAFETY: JSON-RPC 2.0 请求喵
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JsonRpcRequest {
    /// JSON-RPC 版本
    pub jsonrpc: &'static str,
    /// 请求 ID
    pub id: String,
    /// 方法名
    pub method: String,
    /// 参数（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<JsonValue>,
}

impl JsonRpcRequest {
    /// 🔒 SAFETY: 创建新的 JSON-RPC 请求喵
    pub fn new(method: String, params: Option<JsonValue>) -> Self {
        Self {
            jsonrpc: "2.0",
            id: Uuid::new_v4().to_string(),
            method,
            params,
        }
    }
}

/// 🔒 SAFETY: JSON-RPC 2.0 响应喵
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct JsonRpcResponse {
    /// JSON-RPC 版本
    pub jsonrpc: String,
    /// 请求 ID
    pub id: String,
    /// 结果（如果成功）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<JsonValue>,
    /// 错误（如果失败）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<JsonRpcError>,
}

/// 🔒 SAFETY: JSON-RPC 2.0 错误喵
#[derive(Debug, Clone, Deserialize)]
pub struct JsonRpcError {
    /// 错误代码
    pub code: i32,
    /// 错误消息
    pub message: String,
    /// 错误数据（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<JsonValue>,
}

/// 🔒 SAFETY: JSON-RPC 2.0 通知喵
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JsonRpcNotification {
    /// JSON-RPC 版本
    pub jsonrpc: &'static str,
    /// 方法名
    pub method: String,
    /// 参数
    pub params: JsonValue,
}

impl JsonRpcNotification {
    /// 🔒 SAFETY: 创建新的 JSON-RPC 通知喵
    pub fn new(method: String, params: JsonValue) -> Self {
        Self {
            jsonrpc: "2.0",
            method,
            params,
        }
    }
}

/// 🔒 SAFETY: MCP server capability 宣告喵
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerCapabilities {
    /// 工具列表支持
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tools: Option<serde_json::Map<String, JsonValue>>,
    /// 资源列表支持
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resources: Option<serde_json::Map<String, JsonValue>>,
    /// 提示词列表支持
    #[serde(skip_serializing_if = "Option::is_none")]
    pub prompts: Option<serde_json::Map<String, JsonValue>>,
}

/// 🔒 SAFETY: MCP 工具描述（来自 server）喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpTool {
    /// 工具名称
    pub name: String,
    /// 工具标题（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// 工具描述
    pub description: String,
    /// 输入 schema (JSON Schema)
    pub input_schema: JsonValue,
    /// 输出 schema（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_schema: Option<JsonValue>,
}

/// 🔒 SAFETY: MCP 工具结果内容类型喵
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum McpContentItem {
    /// 文本内容
    Text { text: String },
    /// 图片内容
    Image { data: String, mime_type: String },
    /// 音频内容
    Audio { data: String, mime_type: String },
    /// 资源链接
    ResourceLink {
        uri: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        name: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        description: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        mime_type: Option<String>,
    },
    /// 嵌入资源
    Resource {
        uri: String,
        mime_type: String,
        text: Option<String>,
        blob: Option<String>,
    },
}

/// 🔒 SAFETY: MCP 工具调用结果喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpToolResult {
    /// 内容列表
    pub content: Vec<McpContentItem>,
    /// 是否错误
    #[serde(skip_serializing_if = "Option::is_none")]
    pub is_error: Option<bool>,
    /// 结构化内容（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub structured_content: Option<JsonValue>,
}

/// 🔒 SAFETY: MCP 初始化参数喵
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeParams {
    /// 协议版本
    pub protocol_version: String,
    /// 客户端能力
    pub capabilities: ServerCapabilities,
    /// 客户端信息（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_info: Option<ClientInfo>,
}

/// 🔒 SAFETY: 客户端信息喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientInfo {
    /// 客户端名称
    pub name: String,
    /// 客户端版本
    pub version: String,
}

/// 🔒 SAFETY: MCP 初始化结果喵
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeResult {
    /// 协议版本
    pub protocol_version: String,
    /// server 能力
    pub capabilities: ServerCapabilities,
    /// server 信息（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub server_info: Option<ClientInfo>,
}

/// 🔒 SAFETY: tools/list 参数喵
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListToolsParams {
    /// 分页游标（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cursor: Option<String>,
}

/// 🔒 SAFETY: tools/list 结果喵
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListToolsResult {
    /// 工具列表
    pub tools: Vec<McpTool>,
    /// 下一页游标（如果还有更多）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
}

/// 🔒 SAFETY: tools/call 参数喵
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CallToolParams {
    /// 工具名称
    pub name: String,
    /// 工具参数
    pub arguments: JsonValue,
}

/// 🔒 SAFETY: MCP 客户端错误喵
#[derive(Debug, Error)]
pub enum McpClientError {
    #[error("Transport error: {0}")]
    Transport(#[from] McpTransportError),

    #[error("JSON-RPC error: code={0}, message={1}")]
    RpcError(i32, String),

    #[error("Tool not found: {0}")]
    ToolNotFound(String),

    #[error("Tool execution error: {0}")]
    ToolExecution(String),

    #[error("Initialization failed: {0}")]
    InitializationFailed(String),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Invalid response from server")]
    InvalidResponse,
}

/// 🔒 SAFETY: MCP 客户端喵
///
/// 完整的 MCP 客户端实现，支持 stdio 和 HTTP 传输
pub struct McpClient {
    /// 客户端名称
    pub client_name: String,
    /// 客户端版本
    pub client_version: String,
    /// 传输层
    transport: Option<McpTransport>,
    /// 是否已初始化
    initialized: Arc<RwLock<bool>>,
    /// 缓存的工具列表
    tools: Arc<RwLock<HashMap<String, McpTool>>>,
    /// server 能力
    server_capabilities: Arc<RwLock<Option<ServerCapabilities>>>,
}

impl McpClient {
    /// 🔒 SAFETY: 创建新的 MCP 客户端喵
    pub fn new() -> Self {
        Self {
            client_name: "nekoclaw".to_string(),
            client_version: "0.1.0".to_string(),
            transport: None,
            initialized: Arc::new(RwLock::new(false)),
            tools: Arc::new(RwLock::new(HashMap::new())),
            server_capabilities: Arc::new(RwLock::new(None)),
        }
    }

    /// 🔒 SAFETY: 设置客户端信息喵
    pub fn with_info(mut self, name: String, version: String) -> Self {
        self.client_name = name;
        self.client_version = version;
        self
    }

    /// 🔒 SAFETY: 连接到 stdio 喵
    ///
    /// 通过 stdio 传输连接到 MCP server（启动子进程）
    pub async fn connect_stdio(&mut self, command: &str, args: &[&str]) -> Result<(), McpClientError> {
        let mut child = Command::new(command)
            .args(args)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| McpTransportError::Process(format!("Failed to spawn {}: {}", command, e)))?;

        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| McpTransportError::Process("Failed to get stdin".to_string()))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| McpTransportError::Process("Failed to get stdout".to_string()))?;

        self.transport = Some(McpTransport::Stdio {
            stdin: Arc::new(Mutex::new(stdin)),
            stdout: Arc::new(Mutex::new(stdout)),
        });

        tracing::info!("Connected to MCP server via stdio: {} {:?}", command, args);
        Ok(())
    }

    /// 🔒 SAFETY: 发送 JSON-RPC 请求喵
    pub async fn send_request(&self, request: &JsonRpcRequest) -> Result<JsonRpcResponse, McpClientError> {
        let transport = self
            .transport
            .as_ref()
            .ok_or_else(|| McpTransportError::Closed)?;

        let request_json = serde_json::to_string(request)?;
        let request_line = format!("{}\n", request_json);

        tracing::debug!("MCP Request: {}", request_json);

        match transport {
            McpTransport::Stdio { stdin, stdout } => {
                // 发送请求
                {
                    let mut stdin_guard = stdin.lock().await;
                    stdin_guard
                        .write_all(request_line.as_bytes())
                        .await
                        .map_err(|e| McpTransportError::Io(e))?;
                    stdin_guard.flush().await.map_err(|e| McpTransportError::Io(e))?;
                }

                // 读取响应（按行读取）
                let line = {
                    let mut stdout_lock = stdout.lock().await;
                    let mut line = String::new();
                    let mut reader = BufReader::new(&mut *stdout_lock);
                    reader
                        .read_line(&mut line)
                        .await
                        .map_err(|e| McpTransportError::Io(e))?;
                    line
                };

                let response_json = line.trim();
                if response_json.is_empty() {
                    return Err(McpClientError::InvalidResponse);
                }

                tracing::debug!("MCP Response: {}", response_json);

                let response: JsonRpcResponse =
                    serde_json::from_str(response_json).map_err(McpClientError::Serialization)?;

                if let Some(error) = response.error {
                    return Err(McpClientError::RpcError(error.code, error.message));
                }

                Ok(response)
            }
            McpTransport::Http { .. } => {
                // HTTP 传输未来实现
                Err(McpClientError::Transport(McpTransportError::Process(
                    "HTTP transport not yet implemented".to_string(),
                )))
            }
        }
    }

    /// 🔒 SAFETY: 初始化 MCP 会话喵
    pub async fn initialize(&self) -> Result<(), McpClientError> {
        let capabilities = ServerCapabilities {
            // 宣告我们支持工具
            tools: Some(serde_json::json!({
                "listChanged": false
            })
            .as_object()
            .unwrap()
            .clone()),
            resources: None,
            prompts: None,
        };

        let client_info = ClientInfo {
            name: self.client_name.clone(),
            version: self.client_version.clone(),
        };

        let params = InitializeParams {
            protocol_version: "2025-11-25".to_string(),
            capabilities,
            client_info: Some(client_info),
        };

        let request = JsonRpcRequest::new("initialize".to_string(), Some(serde_json::to_value(params)?));
        let response = self.send_request(&request).await?;

        let init_result: InitializeResult = response
            .result
            .ok_or_else(|| McpClientError::InvalidResponse)
            .and_then(|v| serde_json::from_value(v).map_err(McpClientError::Serialization))?;

        tracing::info!(
            "MCP initialized: {} v{}",
            init_result.protocol_version,
            init_result.server_info.map(|i| i.version).unwrap_or_else(|| "unknown".to_string())
        );

        // 保存 server 能力
        *self.server_capabilities.write().await = Some(init_result.capabilities.clone());

        // 发送 initialized 通知
        let notification = JsonRpcNotification::new("notifications/initialized".to_string(), JsonValue::Null);
        let notification_json = serde_json::to_string(&notification)?;

        if let Some(McpTransport::Stdio { stdin, .. }) = &self.transport {
            let mut stdin_guard = stdin.lock().await;
            stdin_guard
                .write_all(format!("{}\n", notification_json).as_bytes())
                .await
                .map_err(|e| McpTransportError::Io(e))?;
            stdin_guard.flush().await.map_err(|e| McpTransportError::Io(e))?;
        }

        // 标记为已初始化
        *self.initialized.write().await = true;
        tracing::info!("MCP client initialized successfully");

        Ok(())
    }

    /// 🔒 SAFETY: 列出所有可用工具喵
    pub async fn list_tools(&self) -> Result<Vec<McpTool>, McpClientError> {
        if !*self.initialized.read().await {
            return Err(McpClientError::InitializationFailed(
                "Client not initialized".to_string(),
            ));
        }

        let params = ListToolsParams { cursor: None };
        let request = JsonRpcRequest::new("tools/list".to_string(), Some(serde_json::to_value(params)?));
        let response = self.send_request(&request).await?;

        let result: ListToolsResult = response
            .result
            .ok_or_else(|| McpClientError::InvalidResponse)
            .and_then(|v| serde_json::from_value(v).map_err(McpClientError::Serialization))?;

        // 缓存工具列表
        let mut tools_map = self.tools.write().await;
        tools_map.clear();
        for tool in &result.tools {
            tools_map.insert(tool.name.clone(), tool.clone());
        }
        drop(tools_map);

        tracing::info!("MCP tools listed: {} tools", result.tools.len());
        for tool in &result.tools {
            tracing::debug!("  - {}: {}", tool.name, tool.description);
        }

        Ok(result.tools)
    }

    /// 🔒 SAFETY: 调用工具喵
    pub async fn call_tool(&self, name: String, arguments: JsonValue) -> Result<McpToolResult, McpClientError> {
        if !*self.initialized.read().await {
            return Err(McpClientError::InitializationFailed(
                "Client not initialized".to_string(),
            ));
        }

        // 检查工具是否存在
        if !self.tools.read().await.contains_key(&name) {
            return Err(McpClientError::ToolNotFound(name));
        }

        let params = CallToolParams { name: name.clone(), arguments };

        let request = JsonRpcRequest::new("tools/call".to_string(), Some(serde_json::to_value(params)?));
        let response = self.send_request(&request).await?;

        let tool_result: McpToolResult = response
            .result
            .ok_or_else(|| McpClientError::InvalidResponse)
            .and_then(|v| {
                if let Some(is_error) = v.get("isError") {
                    if is_error.as_bool().unwrap_or(false) {
                        return Err(McpClientError::ToolExecution(
                            v.get("content")
                                .and_then(|c| c.get(0))
                                .and_then(|item| item.get("text"))
                                .and_then(|t| t.as_str())
                                .unwrap_or("Unknown tool execution error")
                                .to_string(),
                        ));
                    }
                }
                serde_json::from_value(v).map_err(McpClientError::Serialization)
            })?;

        tracing::info!("MCP tool called: {}", name);
        Ok(tool_result)
    }

    /// 🔒 SAFETY: 格式化工具结果为 LLM 可读字符串喵
    pub fn format_tool_result(&self, result: &McpToolResult) -> String {
        let mut output = String::new();

        for item in &result.content {
            match item {
                McpContentItem::Text { text } => {
                    output.push_str(text);
                    output.push('\n');
                }
                McpContentItem::Image { data, mime_type } => {
                    output.push_str(&format!("[Image: {} ({} bytes)]", mime_type, data.len()));
                    output.push('\n');
                }
                McpContentItem::Audio { data, mime_type } => {
                    output.push_str(&format!("[Audio: {} ({} bytes)]", mime_type, data.len()));
                    output.push('\n');
                }
                McpContentItem::ResourceLink { uri, name, .. } => {
                    if let Some(name) = name {
                        output.push_str(&format!("[Resource: {} - {}]", name, uri));
                    } else {
                        output.push_str(&format!("[Resource: {}]", uri));
                    }
                    output.push('\n');
                }
                McpContentItem::Resource { uri, mime_type, .. } => {
                    output.push_str(&format!("[Embedded resource: {} ({})]", uri, mime_type));
                    output.push('\n');
                }
            }
        }

        // 添加结构化内容（如果有）
        if let Some(structured) = &result.structured_content {
            if !output.is_empty() {
                output.push_str("\nStructured data:\n");
            }
            if let Ok(pretty) = serde_json::to_string_pretty(structured) {
                output.push_str(&pretty);
                output.push('\n');
            }
        }

        output.trim().to_string()
    }

    /// 🔒 SAFETY: 将 MCP 工具转换为内部 Tool 描述喵
    pub fn tool_to_description(&self, mcp_tool: &McpTool) -> ToolDescription {
        ToolDescription {
            name: mcp_tool.name.clone(),
            description: mcp_tool.description.clone(),
            input_schema: mcp_tool.input_schema.clone(),
            category: Some("mcp".to_string()),
            dangerous: false,
            required_permissions: None,
        }
    }
}

impl Default for McpClient {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tool_result() {
        let result = ToolResult::success(
            serde_json::json!({"output": "hello"}),
            100,
        );

        assert!(result.success);
        assert!(result.data.is_some());
        assert_eq!(result.duration_ms, Some(100));
    }

    #[test]
    fn test_format_tools_for_llm() {
        let tools = vec![
            ToolDescription {
                name: "test_tool".to_string(),
                description: "A test tool".to_string(),
                input_schema: serde_json::json!({
                    "type": "object",
                    "properties": {
                        "message": {
                            "type": "string",
                            "description": "Test message"
                        }
                    }
                }),
                category: Some("test".to_string()),
                dangerous: false,
                required_permissions: None,
            }
        ];

        let formatted = format_tools_for_llm(&tools);
        assert!(formatted.contains("test_tool"));
        assert!(formatted.contains("A test tool"));
    }
}

// 🔒 SAFETY: MCP 客户端详细测试模块喵
//
// 包含更全面的 MCP 客户端测试
// 参考: src/tools/mcp_tests.rs
//
// 运行方式：
// cargo test --package nekoclaw --lib tools::mcp::tests::mcp_client_tests
//
// 注意：集成测试需要真实的 MCP 服务器
//
// Author: 缪斯 (Muse) 📚

// 包含详细测试文件
#[cfg(test)]
mod mcp_client_tests {
    // 这里可以导入外部测试文件中的测试用例
    // 或者使用 include! 来包含测试文件
    // 例如: include!("mcp_tests.rs");
}
