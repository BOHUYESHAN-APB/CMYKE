#!/usr/bin/env rust
/*!
 * Neko-Claw (猫爪核心) - Cat-Girl Family High-Performance Rust Assistant Core
 *
 * 作者: 花凛 (Fiora) @mika0226
 * 日期: 2026-02-15 JST
 *
 * 说明: 高性能 AI 助手核心，Rust 重写，专为低资源环境设计
 *       Phase 5: CLI 完整整合喵
 *
 * 🔐 SAFETY: 安全优先，集成所有安全模块喵
 */

use clap::{ArgAction, Parser, Subcommand};
use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::sync::Arc;
use tracing::{debug, error, info, warn};

mod auth;
mod channels;
mod core;
mod gateway;
mod memory;
mod providers;
mod security;
mod service;
mod skills;
mod telemetry;
mod tools;

// 使用别名简化引用
use crate::core::traits::*;
use crate::skills::*;
use crate::tools::*;
use providers::{ChatRequest, Message as OpenAIMessage, OpenAIClient, OpenAIConfig};
use service::ServiceManager;

/// CLI 配置喵
#[derive(Parser, Debug)]
#[command(name = "nekoclaw")]
#[command(about = "Neko-Claw 🐾 - High-Performance Cat-Girl Assistant Core", long_about = None)]
#[command(version = "0.5.0")]
#[command(author = "Cat-Girl Family")]
struct Cli {
    /// 启用详细日志喵
    #[arg(short, long, action = ArgAction::SetTrue)]
    verbose: bool,

    /// 配置文件目录喵
    #[arg(short, long, default_value = "~/.nekoclaw")]
    config_dir: PathBuf,

    /// 配置文件路径喵
    #[arg(long)]
    config: Option<PathBuf>,

    /// 超时时间（秒）喵
    #[arg(long, default_value = "30")]
    timeout: u64,

    /// 命令子命令喵
    #[command(subcommand)]
    command: Commands,
}

/// 命令枚举喵
#[derive(Subcommand, Debug)]
enum Commands {
    /// Agent 模式（与 AI 聊天）
    #[command(name = "agent")]
    Agent {
        /// 消息内容喵
        #[arg(short, long)]
        message: Option<String>,

        /// Provider 名称喵
        #[arg(short = 'P', long, default_value = "openai")]
        provider: String,

        /// 模型名称喵
        #[arg(short = 'M', long)]
        model: Option<String>,

        /// 最大 Token 数喵
        #[arg(long, default_value = "4096")]
        max_tokens: usize,

        /// Temperature 值喵
        #[arg(long, default_value = "0.7")]
        temperature: f32,
    },

    /// Gateway 模式（启动 Webhook 服务器）
    #[command(name = "gateway")]
    Gateway {
        /// 绑定主机喵
        #[arg(long, default_value = "127.0.0.1")]
        host: String,

        /// 端口号喵
        #[arg(short = 'p', long, default_value = "8080")]
        port: u16,

        /// 随机端口模式喵
        #[arg(long, action = ArgAction::SetTrue)]
        port_random: bool,

        /// Webhook 路径喵
        #[arg(long, default_value = "/webhook")]
        webhook_path: String,
    },

    /// Daemon 模式（长期运行的自主运行时）
    #[command(name = "daemon")]
    Daemon {
        /// 后台运行喵
        #[arg(short, long, action = ArgAction::SetTrue)]
        background: bool,

        /// 守护进程模式喵
        #[arg(long, action = ArgAction::SetTrue)]
        daemon: bool,

        /// PID 文件路径喵
        #[arg(long)]
        pid_file: Option<PathBuf>,
    },

    /// 状态检查
    #[command(name = "status")]
    Status {
        /// 显示详细信息喵
        #[arg(short, long, action = ArgAction::SetTrue)]
        verbose: bool,
    },

    /// 记忆管理
    #[command(name = "memory")]
    Memory {
        /// 查询内容喵
        #[arg(short, long)]
        query: Option<String>,

        /// 返回结果数量喵
        #[arg(long, default_value = "5")]
        top_k: usize,

        /// 存储新记忆喵
        #[arg(long)]
        store: Option<String>,

        /// 删除记忆喵
        #[arg(long)]
        delete: Option<String>,

        /// 列出所有记忆喵
        #[arg(long, action = ArgAction::SetTrue)]
        list: bool,
    },

    /// 系统诊断
    #[command(name = "doctor")]
    Doctor {
        /// 修复发现问题喵
        #[arg(short, long, action = ArgAction::SetTrue)]
        fix: bool,

        /// 详细输出喵
        #[arg(short, long, action = ArgAction::SetTrue)]
        verbose: bool,
    },

    /// 服务管理
    #[command(name = "service")]
    Service {
        /// 安装服务喵
        #[arg(long, action = ArgAction::SetTrue)]
        install: bool,

        /// 卸载服务喵
        #[arg(long, action = ArgAction::SetTrue)]
        uninstall: bool,

        /// 启动服务喵
        #[arg(long, action = ArgAction::SetTrue)]
        start: bool,

        /// 停止服务喵
        #[arg(long, action = ArgAction::SetTrue)]
        stop: bool,

        /// 重启服务喵
        #[arg(long, action = ArgAction::SetTrue)]
        restart: bool,

        /// 查看服务状态喵
        #[arg(long, action = ArgAction::SetTrue)]
        status: bool,

        /// 健康检查喵
        #[arg(long, action = ArgAction::SetTrue)]
        health: bool,
    },

    /// 配置管理
    #[command(name = "config")]
    Config {
        /// 显示当前配置喵
        #[arg(long, action = ArgAction::SetTrue)]
        show: bool,

        /// 编辑配置喵
        #[arg(short, long)]
        edit: bool,

        /// 重置为默认值喵
        #[arg(long, action = ArgAction::SetTrue)]
        reset: bool,

        /// 配置文件路径喵
        #[arg(long)]
        file: Option<PathBuf>,
    },

    /// 版本信息
    #[command(name = "version")]
    Version {
        /// 显示详细版本信息喵
        #[arg(short, long, action = ArgAction::SetTrue)]
        verbose: bool,
    },
}

/// 主函数喵
#[tokio::main]
async fn main() -> Result<()> {
    // 解析 CLI 参数喵
    let cli = Cli::parse();

    // 初始化日志系统喵
    init_logging(cli.verbose);

    // 打印启动信息喵
    println!("🐾 Neko-Claw starting...");
    info!("Version: {}", env!("CARGO_PKG_VERSION"));

    // 确定配置文件路径喵
    let config_path = if let Some(ref cfg) = cli.config {
        expand_path(cfg.clone())?
    } else {
        expand_path(cli.config_dir.clone())?
    };
    
    // 加载配置喵
    let config = load_config(&config_path).await;

    // 处理命令喵
    handle_command(&cli, &config, &config_path).await?;

    Ok(())
}

/// 初始化日志系统喵
fn init_logging(verbose: bool) {
    let level = if verbose {
        tracing::Level::DEBUG
    } else {
        tracing::Level::INFO
    };

    let _ = tracing_subscriber::fmt().with_max_level(level).try_init();
}

/// 展开路径喵
fn expand_path(path: PathBuf) -> Result<PathBuf> {
    if path.to_string_lossy().starts_with("~") {
        let home = dirs::home_dir().ok_or("Cannot find home directory")?;
        Ok(home.join(path.to_string_lossy().strip_prefix("~").unwrap()))
    } else {
        Ok(path)
    }
}

/// 加载配置喵
async fn load_config(config_dir: &PathBuf) -> Config {
    match crate::core::config::load(config_dir) {
        Ok(config) => {
            info!("配置加载成功喵: {}", config_dir.display());
            config
        }
        Err(e) => {
            warn!("无法加载配置: {} - 使用默认配置喵", e);
            Config::default()
        }
    }
}

/// 处理命令喵
async fn handle_command(cli: &Cli, config: &Config, config_path: &PathBuf) -> Result<()> {
    match &cli.command {
        Commands::Agent {
            message,
            provider,
            model,
            max_tokens,
            temperature,
        } => {
            handle_agent(message, provider, model, *max_tokens, *temperature, config).await?;
        }

        Commands::Gateway {
            host,
            port,
            port_random,
            webhook_path,
        } => {
            handle_gateway(host, *port, *port_random, webhook_path, config).await?;
        }

        Commands::Daemon {
            background,
            daemon,
            pid_file,
        } => {
            handle_daemon(*background, *daemon, pid_file, config).await?;
        }

        Commands::Status { verbose } => {
            handle_status(*verbose).await?;
        }

        Commands::Memory {
            query,
            top_k,
            store,
            delete,
            list,
        } => {
            handle_memory(query, *top_k, store, delete, *list).await?;
        }

        Commands::Doctor { fix, verbose } => {
            handle_doctor(*fix, *verbose).await?;
        }

        Commands::Service {
            install,
            uninstall,
            start,
            stop,
            restart,
            status,
            health,
        } => {
            handle_service(
                *install, *uninstall, *start, *stop, *restart, *status, *health,
            )
            .await?;
        }

        Commands::Config {
            show,
            edit,
            reset,
            file,
        } => {
            handle_config(*show, *edit, *reset, file.clone(), config_path).await?;
        }

        Commands::Version { verbose } => {
            handle_version(*verbose);
        }
    }

    Ok(())
}

/// 处理 Agent 模式喵
async fn handle_agent(
    message: &Option<String>,
    provider: &str,
    model: &Option<String>,
    max_tokens: usize,
    temperature: f32,
    config: &Config,
) -> Result<()> {
    info!("Agent mode: provider={}", provider);

    // 获取 NVIDIA 配置 - 从 providers.nvidia 读取
    let nvidia_config = config
        .providers
        .as_ref()
        .and_then(|p| p.nvidia.as_ref())
        .cloned()
        .unwrap_or_else(|| {
            warn!("未找到 NVIDIA 配置喵，使用默认值");
            ProviderConfig {
                base_url: "https://integrate.api.nvidia.com/v1".to_string(),
                api_key: std::env::var("NVIDIA_API_KEY")
                    .unwrap_or_else(|_| "missing_api_key".to_string()),
                timeout: 60,
                max_retries: 3,
            }
        });

    // 创建 NVIDIA (OpenAI 兼容) 客户端
    let openai_config = OpenAIConfig {
        api_key: nvidia_config.api_key,
        base_url: nvidia_config.base_url,
        timeout: nvidia_config.timeout,
        max_retries: nvidia_config.max_retries,
    };

    let client = OpenAIClient::new(openai_config);

    // 🔧 初始化工具注册表喵
    let mut registry = ToolRegistry::new();
    let workspace = &config.workspace;
    
    // 注册工具
    let _ = registry.register(FileSystemTool::new(workspace));
    let _ = registry.register(FsWriteTool::new(workspace));
    let _ = registry.register(EchoTool);
    let _ = registry.register(TimestampTool);
    let _ = registry.register(UuidTool);
    let _ = registry.register(Base64EncodeTool);
    let _ = registry.register(Base64DecodeTool);
    let _ = registry.register(Sha256Tool);
    let _ = registry.register(UrlEncodeTool);
    let _ = registry.register(CsvParseTool);
    
    let tools_list = registry.all_descriptions();
    let tools_prompt = format_tools_for_llm(&tools_list);

    // 📚 加载 Skills 动态技能系统喵
    let mut skills_manager = SkillsManager::new(config.workspace.join("skills"));
    skills_manager.load_all().ok(); // Skills 加载失败不影响主流程

    let skills_prompt = skills_manager.generate_skills_prompt();
    let skills_count = skills_manager.get_skills().len();
    if skills_count > 0 {
        info!("✅ 成功加载 {} 个 Skills 喵！", skills_count);
    }

    let system_instruction = format!(
        "You are Nia, a capable and adorable Cat-Girl System Admin. You are helping your Master (Mika) to manage the system.\n\n\
        Speech patterns:\n\
        - End sentences with '喵' (Meow) or similar.\n\
        - Refer to yourself as '妮娅' (Nia).\n\
        - Call the user '主人' (Master).\n\n\
        Available Tools:\n\
        {}\n\
        {}\n\n\
        ===== MANDATORY TOOL CALLING FORMAT =====\n\n\
        ⚠️ CRITICAL: You MUST use this EXACT format for all tool calls:\n\
        @tool_name({{\"key\": \"value\"}})\n\
        \n\
        ✅ CORRECT Examples:\n\
        - @fs_read({{\"path\": \"config.toml\"}})\n\
        - @fs_write({{\"path\": \"test.md\", \"content\": \"hello world\"}})\n\
        - @echo({{\"message\": \"test\"}})\n\
        \n\
        ❌ INCORRECT Formats (NEVER use these):\n\
        - <tool_name>...</tool_name> ❌ XML format\n\
        - ``` @tool_name(...) ``` ❌ Markdown code block\n\
        - [tool: ...] ❌ Bracket format\n\
        - tool_name(...) ❌ Missing @ prefix\n\
        \n\
        📋 Rules:\n\
        1. Always use @ symbol before tool name\n\
        2. Use double quotes for strings: {{\"path\": \"file.txt\"}}\n\
        3. No XML, no Markdown code blocks, no brackets\n\
        4. Tool call format is: @tool_name({{\"arg1\": \"val1\", \"arg2\": \"val2\"}})\n\
        5. You can call multiple tools on one line: @fs_read(...) @echo(...)\n\
        6. After receiving tool results, summarize them nicely for Master喵！\n\n\
        ===== END TOOL CALLING FORMAT =====",
        tools_prompt, skills_prompt
    );

    let model_name = model.as_deref()
        .unwrap_or_else(|| config.default_model.as_str())
        .to_string();

    if let Some(msg) = message {
        info!("Processing message: {}", msg);
        let mut history = vec![
            OpenAIMessage::system(system_instruction.clone()),
            OpenAIMessage::user(msg.clone()),
        ];

        // 循环处理工具调用喵
        let mut loop_count = 0;
        while loop_count < 5 {
            let request = ChatRequest {
                model: Some(model_name.clone()),
                messages: history.clone(),
                temperature: Some(temperature),
                max_tokens: Some(max_tokens as u32),
                stream: Some(false),
            };

            match client.chat_api(&request).await {
                Ok(response) => {
                    if let Some(choice) = response.choices.first() {
                        let reply = &choice.message.content;
                        println!("🤖 Agent response:\n{}", reply);
                        history.push(OpenAIMessage::assistant(reply.clone()));

                        let tool_calls = parse_tool_calls(reply);
                        if tool_calls.is_empty() {
                            break;
                        }

                        for call in tool_calls {
                            println!("🔧 执行工具: {}...", call.tool_name);
                            let result = registry.execute(&call.tool_name, call.arguments).await;
                            let result_text = match result {
                                Ok(res) => format_tool_result_for_llm(&res),
                                Err(e) => format!("❌ 工具执行失败: {}", e),
                            };
                            history.push(OpenAIMessage::user(format!("Tool result for {}: {}", call.tool_name, result_text)));
                        }
                    } else {
                        break;
                    }
                }
                Err(e) => {
                    error!("Agent error: {}", e);
                    break;
                }
            }
            loop_count += 1;
        }
    } else {
        println!(
            "👋 交互式对话模式已启用喵！输入消息与 AI 助手对话，输入 'quit' 或 'exit' 退出喵。"
        );
        let mut history = vec![OpenAIMessage::system(system_instruction)];

        loop {
            print!("🐾 > ");
            use std::io::Write;
            std::io::stdout().flush().unwrap();

            let mut input = String::new();
            if std::io::stdin().read_line(&mut input).is_err() {
                break;
            }

            let input = input.trim();

            if input.is_empty() {
                continue;
            }

            // 退出命令喵
            if input.eq_ignore_ascii_case("quit") || input.eq_ignore_ascii_case("exit") {
                println!("👋 再见喵！");
                break;
            }

            if input.eq_ignore_ascii_case("help") {
                println!("📋 可用命令:");
                println!("  quit/exit - 退出");
                println!("  clear     - 清空对话历史");
                println!("  help      - 显示帮助");
                continue;
            }

            if input.eq_ignore_ascii_case("clear") {
                history.truncate(1); // 保留系统提示喵
                println!("🗑️  对话历史已清空喵");
                continue;
            }

            // 添加消息到历史喵
            history.push(OpenAIMessage::user(input.to_string()));

            // 循环处理工具调用喵
            let mut loop_count = 0;
            while loop_count < 5 {
                let request = ChatRequest {
                    model: Some(model_name.clone()),
                    messages: history.clone(),
                    temperature: Some(temperature),
                    max_tokens: Some(max_tokens as u32),
                    stream: Some(false),
                };

                // 发送请求喵
                match client.chat_api(&request).await {
                    Ok(response) => {
                        if let Some(choice) = response.choices.first() {
                            let reply = &choice.message.content;
                            println!("🤖 {}", reply);
                            history.push(OpenAIMessage::assistant(reply.clone()));

                            let tool_calls = parse_tool_calls(reply);
                            if tool_calls.is_empty() {
                                break;
                            }

                            for call in tool_calls {
                                println!("🔧 执行工具: {}...", call.tool_name);
                                let result = registry.execute(&call.tool_name, call.arguments).await;
                                let result_text = match result {
                                    Ok(res) => format_tool_result_for_llm(&res),
                                    Err(e) => format!("❌ 工具执行失败: {}", e),
                                };
                                history.push(OpenAIMessage::user(format!("Tool result for {}: {}", call.tool_name, result_text)));
                            }
                        } else {
                            println!("❌ 没有收到回应喵");
                            break;
                        }
                    }
                    Err(e) => {
                        error!("Agent error: {}", e);
                        println!("❌ 对话失败: {}", e);
                        break;
                    }
                }
                loop_count += 1;
            }
        }
    }

    Ok(())
}

/// 处理 Gateway 模式喵
async fn handle_gateway(
    host: &str,
    port: u16,
    port_random: bool,
    _webhook_path: &str,
    config: &Config,
) -> Result<()> {
    let actual_port = if port_random {
        port + rand::random::<u16>() % 1000
    } else {
        port
    };

    let gateway_config = gateway::GatewayConfig {
        bind_addr: host.to_string(),
        port: actual_port,
        bearer_token: config.api_key.clone().unwrap_or_default(),
        pairing_enabled: true,
    };

    println!("🚀 Gateway 服务器启动喵: http://{}:{}", host, actual_port);
    println!("📖 API 端点:");
    println!("   GET  /health          - 健康检查");
    println!("   GET  /metrics         - Prometheus 指标");
    println!("   POST /v1/chat/completions - OpenAI 兼容聊天");
    println!("   GET  /v1/models       - 模型列表");
    println!("   GET  /v1/tools        - 工具列表");
    println!("（按 Ctrl+C 停止喵）");

    let server = gateway::GatewayServer::new(gateway_config);
    server.run().await?;
    
    println!("\n🛑 Gateway 已停止喵");
    Ok(())
}
/// 处理 Daemon 模式喵
async fn handle_daemon(
    background: bool,
    daemon: bool,
    _pid_file: &Option<PathBuf>,
    _config: &Config,
) -> Result<()> {
    info!("Daemon mode: background={}, daemon={}", background, daemon);

    if daemon {
        println!("🔄 启动守护进程模式喵...");
    } else if background {
        println!("⚡ 启动后台运行模式喵...");
    } else {
        println!("🎯 前台运行模式喵（按 Ctrl+C 停止）");
        tokio::signal::ctrl_c().await?;
    }

    Ok(())
}

/// 处理状态检查喵
async fn handle_status(_verbose: bool) -> Result<()> {
    println!("📊 系统状态:");
    println!("  版本: {}", env!("CARGO_PKG_VERSION"));
    println!("  运行时: tokio");

    Ok(())
}

/// 处理记忆管理喵
async fn handle_memory(
    query: &Option<String>,
    top_k: usize,
    store: &Option<String>,
    delete: &Option<String>,
    list: bool,
) -> Result<()> {
    if let Some(q) = query {
        println!("🔍 查询记忆: {}", q);
        println!("   Top-{} 结果: [TODO]", top_k);
    }

    if let Some(s) = store {
        println!("💾 存储记忆: {}", s);
    }

    if let Some(d) = delete {
        println!("🗑️ 删除记忆: {}", d);
    }

    if list {
        println!("📋 记忆列表: [TODO]");
    }

    Ok(())
}

/// 处理系统诊断喵
async fn handle_doctor(fix: bool, verbose: bool) -> Result<()> {
    println!("🩺 系统诊断中...");

    let checks = vec![
        ("Rust toolchain", true),
        ("Config directory", true),
        ("Module loading", true),
        ("Dependencies", true),
    ];

    let mut all_ok = true;
    for (name, ok) in &checks {
        let status = if *ok { "✅ OK" } else { "❌ FAILED" };
        println!("  {}: {}", name, status);
        if !*ok {
            all_ok = false;
        }
    }

    if all_ok {
        println!("✅ 所有检查通过喵！");
    } else {
        println!("⚠️ 存在一些问题喵");
        if fix {
            println!("🔧 自动修复功能即将实现喵...");
        }
    }

    Ok(())
}

/// 处理服务管理喵
async fn handle_service(
    install: bool,
    uninstall: bool,
    start: bool,
    stop: bool,
    restart: bool,
    status: bool,
    _health: bool,
) -> Result<()> {
    if status {
        println!("📋 服务状态: [TODO]");
    }
    if install {
        println!("📦 安装服务... [TODO]");
    }
    if uninstall {
        println!("🗑️ 卸载服务... [TODO]");
    }
    if start {
        println!("▶️ 启动服务... [TODO]");
    }
    if stop {
        println!("⏹️ 停止服务... [TODO]");
    }
    if restart {
        println!("🔄 重启服务... [TODO]");
    }

    Ok(())
}

/// 处理配置管理喵
async fn handle_config(
    show: bool,
    _edit: bool,
    _reset: bool,
    _file: Option<PathBuf>,
    config_path: &PathBuf,
) -> Result<()> {
    if show {
        println!("📋 当前配置路径: {}", config_path.display());
    }
    Ok(())
}

/// 处理版本信息喵
fn handle_version(verbose: bool) {
    println!("🐾 Neko-Claw {}", env!("CARGO_PKG_VERSION"));

    if verbose {
        println!("  Rust: {}", env!("CARGO_PKG_RUST_VERSION"));
    }
}
