// MCP Client Tests 🧪
//
// 测试 nekoclaw 的 MCP 客户端实现
//
// 注意：这些测试需要真实的 MCP 服务器
//
// 用法：
// cargo test --package nekoclaw --lib tools::mcp::tests -- --nocapture

#[cfg(test)]
mod mcp_client_tests {
    use super::super::*;
    use tokio;

    /// 🔒 SAFETY: 测试 JSON-RPC 请求序列化喵
    #[test]
    fn test_jsonrpc_request_serialization() {
        let request = JsonRpcRequest::new(
            "initialize".to_string(),
            Some(serde_json::json!({
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": {
                    "name": "test",
                    "version": "1.0"
                }
            })),
        );

        let json = serde_json::to_string(&request).unwrap();

        assert!(json.contains(r#""jsonrpc":"2.0""#));
        assert!(json.contains(r#""method":"initialize""#));
        assert!(json.contains(r#""params""#));
    }

    /// 🔒 SAFETY: 测试 JSON-RPC 通知序列化喵
    #[test]
    fn test_jsonrpc_notification_serialization() {
        let notification = JsonRpcNotification::new(
            "notifications/initialized".to_string(),
            JsonValue::Null,
        );

        let json = serde_json::to_string(&notification).unwrap();

        assert!(json.contains(r#""jsonrpc":"2.0""#));
        assert!(json.contains(r#""method":"notifications/initialized""#));
        assert!(json.contains(r#""params":null"#));
    }

    /// 🔒 SAFETY: 测试 McpTool 描述转换喵
    #[test]
    fn test_mcp_tool_description() {
        let client = McpClient::new();

        let mcp_tool = McpTool {
            name: "test_tool".to_string(),
            title: Some("Test Tool".to_string()),
            description: "A test tool for testing".to_string(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "message": {
                        "type": "string",
                        "description": "Test message"
                    }
                },
                "required": ["message"]
            }),
            output_schema: None,
        };

        let description = client.tool_to_description(&mcp_tool);

        assert_eq!(description.name, "test_tool");
        assert_eq!(description.description, "A test tool for testing");
        assert_eq!(description.category, Some("mcp".to_string()));
        assert!(!description.dangerous);
    }

    /// 🔒 SAFETY: 测试 McpContentItem 序列化喵
    #[test]
    fn test_mcp_content_item_serialization() {
        // Text content
        let text_item = McpContentItem::Text {
            text: "Hello, world!".to_string(),
        };
        let json = serde_json::to_string(&text_item).unwrap();
        assert!(json.contains(r#""type":"text""#));
        assert!(json.contains("Hello, world!"));

        // Image content
        let image_item = McpContentItem::Image {
            data: "base64data".to_string(),
            mime_type: "image/png".to_string(),
        };
        let json = serde_json::to_string(&image_item).unwrap();
        assert!(json.contains(r#""type":"image""#));
        assert!(json.contains("image/png"));

        // Resource link
        let link_item = McpContentItem::ResourceLink {
            uri: "file:///test.txt".to_string(),
            name: Some("test.txt".to_string()),
            description: Some("Test file".to_string()),
            mime_type: Some("text/plain".to_string()),
        };
        let json = serde_json::to_string(&link_item).unwrap();
        assert!(json.contains(r#""type":"resource_link""#));
        assert!(json.contains("file:///test.txt"));
    }

    /// 🔒 SAFETY: 测试 McpToolResult 格式化喵
    #[test]
    fn test_mcp_tool_result_formatting() {
        let client = McpClient::new();

        let result = McpToolResult {
            content: vec![
                McpContentItem::Text {
                    text: "Result text".to_string(),
                },
                McpContentItem::Image {
                    data: "base64".repeat(10),
                    mime_type: "image/png".to_string(),
                },
            ],
            is_error: Some(false),
            structured_content: Some(serde_json::json!({
                "temperature": 22.5,
                "humidity": 65
            })),
        };

        let formatted = client.format_tool_result(&result);

        assert!(formatted.contains("Result text"));
        assert!(formatted.contains("temperature"));
        assert!(formatted.contains("22.5"));
    }

    /// 🔒 SAFETY: 测试 McpClient 创建喵
    #[test]
    fn test_mcp_client_creation() {
        let client = McpClient::new();
        assert_eq!(client.client_name, "nekoclaw");
        assert_eq!(client.client_version, "0.1.0");

        let custom_client = McpClient::new()
            .with_info("custom".to_string(), "2.0".to_string());
        assert_eq!(custom_client.client_name, "custom");
        assert_eq!(custom_client.client_version, "2.0");
    }

    /// 🔒 SAFETY: 测试 McpClientError 转换喵
    #[test]
    fn test_mcp_client_error_conversions() {
        use McpClientError as E;

        // Transport error
        let io_error = std::io::Error::new(std::io::ErrorKind::NotFound, "test");
        let transport_error = E::from(McpTransportError::Io(io_error));
        assert!(matches!(transport_error, E::Transport(_)));

        // Serialization error
        let ser_error = serde_json::Error::syntax(
            serde_json::error::ErrorCode::ExpectedColon,
            0,
            0,
        );
        let ser_err = E::from(ser_error);
        assert!(matches!(ser_err, E::Serialization(_)));
    }

    /// 🔒 SAFETY: 测试 ListToolsParams 序列化喵
    #[test]
    fn test_list_tools_params_serialization() {
        let params = ListToolsParams {
            cursor: Some("next-page-token".to_string()),
        };

        let json = serde_json::to_string(&params).unwrap();
        assert!(json.contains(r#""cursor":"next-page-token""#));

        let params_no_cursor = ListToolsParams { cursor: None };
        let json = serde_json::to_string(&params_no_cursor).unwrap();
        assert!(!json.contains("cursor"));
    }

    /// 🔒 SAFETY: 测试 CallToolParams 序列化喵
    #[test]
    fn test_call_tool_params_serialization() {
        let params = CallToolParams {
            name: "get_weather".to_string(),
            arguments: serde_json::json!({
                "location": "Tokyo"
            }),
        };

        let json = serde_json::to_string(&params).unwrap();
        assert!(json.contains(r#""name":"get_weather""#));
        assert!(json.contains("Tokyo"));
    }

    /// 🔒 SAFETY: 测试 InitializeParams 序列化喵
    #[test]
    fn test_initialize_params_serialization() {
        let params = InitializeParams {
            protocol_version: "2025-11-25".to_string(),
            capabilities: ServerCapabilities {
                tools: Some(serde_json::json!({
                    "listChanged": false
                })
                .as_object()
                .unwrap()
                .clone()),
                resources: None,
                prompts: None,
            },
            client_info: Some(ClientInfo {
                name: "test".to_string(),
                version: "1.0".to_string(),
            }),
        };

        let json = serde_json::to_string(&params).unwrap();
        assert!(json.contains(r#""protocolVersion":"2025-11-25""#));
        assert!(json.contains(r#""clientInfo""#));
        assert!(json.contains(r#""name":"test""#));
    }

    /// 🔒 SAFETY: 测试 JSON-RPC 响应解析喵
    #[test]
    fn test_jsonrpc_response_parsing() {
        let response_json = r#"{
            "jsonrpc": "2.0",
            "id": "test-id",
            "result": {
                "tools": []
            }
        }"#;

        let response: Result<JsonRpcResponse, _> = serde_json::from_str(response_json);

        assert!(response.is_ok());
        let resp = response.unwrap();
        assert_eq!(resp.jsonrpc, "2.0");
        assert!(resp.result.is_some());
        assert!(resp.error.is_none());
    }

    /// 🔒 SAFETY: 测试 JSON-RPC 错误响应解析喵
    #[test]
    fn test_jsonrpc_error_response_parsing() {
        let error_json = r#"{
            "jsonrpc": "2.0",
            "id": "test-id",
            "error": {
                "code": -32601,
                "message": "Method not found",
                "data": {"details": "initialize"}
            }
        }"#;

        let response: Result<JsonRpcResponse, _> = serde_json::from_str(error_json);

        assert!(response.is_ok());
        let resp = response.unwrap();
        assert!(resp.result.is_none());
        assert!(resp.error.is_some());

        let error = resp.error.unwrap();
        assert_eq!(error.code, -32601);
        assert_eq!(error.message, "Method not found");
        assert!(error.data.is_some());
    }

    /// 🔒 SAFETY: 集成测试标记喵
    ///
    /// 注意：这是一个集成测试，需要真实的 MCP 服务器
    /// 运行前需要启动一个 MCP 服务器
    #[tokio::test]
    #[ignore = "需要手动启动 MCP 服务器"]
    async fn test_mcp_client_integration() {
        // 这个测试被忽略，需要手动运行
        // 1. 启动一个 MCP 服务器（例如 weather server）
        // 2. 使用 cargo test 运行此测试并提供服务器路径

        let server_path = std::env::var("MCP_TEST_SERVER")
            .expect("设置 MCP_TEST_SERVER 环境变量");

        let mut client = McpClient::new();

        // 连接
        client
            .connect_stdio(&server_path, &[])
            .await
            .expect("连接失败");

        // 初始化
        client.initialize().await.expect("初始化失败");

        // 列出工具
        let tools = client.list_tools().await.expect("获取工具失败");
        assert!(!tools.is_empty());

        // 如果有工具，尝试调用
        if let Some(tool) = tools.first() {
            if tool.name == "get_weather" {
                let result = client
                    .call_tool(
                        "get_weather".to_string(),
                        serde_json::json!({"location": "Tokyo"}),
                    )
                    .await;

                assert!(result.is_ok());
            }
        }
    }
}
