//! MCP Client Demo
//!
//! 演示如何使用 nekoclaw 的 MCP 客户端喵
//!
//! Usage:
//! ```bash
//! cargo run --example mcp_client_demo -- <server-command> [args...]
//! ```
//!
//! Example:
//! ```bash
//! cargo run --example mcp_client_demo -- python /path/to/mcp_server.py
//! ```

use nekoclaw::tools::{McpClient, McpClientError};
use tokio;

#[tokio::main]
async fn main() -> Result<(), McpClientError> {
    // 初始化日志
    tracing_subscriber::fmt()
        .with_env_filter("debug")
        .init();

    // 获取命令行参数
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: {} <server-command> [args...]", args[0]);
        eprintln!("Example: {} python /path/to/mcp_server.py", args[0]);
        std::process::exit(1);
    }

    let command = &args[1];
    let server_args: Vec<&str> = args[2..].iter().map(|s| s.as_str()).collect();

    println!("📚 MCP Client Demo - by 缪斯 (Muse)\n");
    println!("Connecting to MCP server:");
    println!("  Command: {}", command);
    println!("  Args: {:?}\n", server_args);

    // 创建 MCP 客户端
    let mut client = McpClient::new().with_info("nekoclaw-demo".to_string(), "0.1.0".to_string());

    // 连接到服务器
    println!("\n🔌 Connecting to server...");
    client.connect_stdio(command, &server_args).await?;
    println!("✅ Connected!\n");

    // 初始化会话
    println!("🚀 Initializing MCP session...");
    client.initialize().await?;
    println!("✅ Initialized!\n");

    // 列出可用工具
    println!("🔍 Listing available tools...\n");
    let tools = client.list_tools().await?;

    if tools.is_empty() {
        println!("No tools found.");
        return Ok(());
    }

    println!("Found {} tool(s):\n", tools.len());
    for tool in &tools {
        println!("📦 {} - {}", tool.name, tool.description);

        // 显示参数信息
        if let Some(props) = tool.input_schema.get("properties") {
            if let Some(obj) = props.as_object() {
                if !obj.is_empty() {
                    println!("   Parameters:");
                    for (param_name, param_schema) in obj {
                        let param_type = param_schema
                            .get("type")
                            .and_then(|t| t.as_str())
                            .unwrap_or("unknown");
                        let desc = param_schema
                            .get("description")
                            .and_then(|d| d.as_str())
                            .unwrap_or("-");

                        println!("     - {} ({}): {}", param_name, param_type, desc);
                    }
                } else {
                    println!("   No parameters");
                }
            }
        }
        println!();
    }

    // 如果有工具，演示调用第一个工具（如果有参数则需要修改）
    if !tools.is_empty() {
        let first_tool = &tools[0];

        println!("🎯 Would you like to call '{}'?", first_tool.name);
        println!("This is a demo - actual tool calling would require arguments.\n");

        // 示例：调用工具（需要根据实际工具调整参数）
        // let result = client.call_tool(
        //     first_tool.name.clone(),
        //     serde_json::json!({ "param": "value" })
        // ).await?;
        //
        // let formatted = client.format_tool_result(&result);
        // println!("Tool result:\n{}", formatted);
    }

    println!("\n✅ Demo completed successfully!");
    Ok(())
}
