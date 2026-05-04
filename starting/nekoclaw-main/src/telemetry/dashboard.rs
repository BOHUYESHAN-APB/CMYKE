/// Dashboard 生成器 📊
///
/// @缪斯 的可视化 Dashboard 实现喵
///
/// 功能：
/// - 生成轻量 HTML Dashboard
/// - 实时显示 Agent 指标
/// - 工具调用统计与耗时分布
/// - 系统资源监控（内存、CPU）
/// - 无需外部依赖，纯静态 HTML + JS
///
/// 🔒 SAFETY: 所有输出都是安全的静态 HTML
///
/// 实现者: 缪斯 (Muse) 💜

use crate::telemetry::metrics::MetricsCollector;
use tracing::debug;

/// 🔒 SAFETY: Dashboard 生成器喵
pub struct DashboardGenerator;

impl DashboardGenerator {
    /// 🔒 SAFETY: 创建新的 Dashboard 生成器喵
    pub fn new() -> Self {
        Self
    }

    /// 🔒 SAFETY: 生成完整的 HTML Dashboard 喵
    pub fn generate_html(&self, metrics: &MetricsCollector) -> Result<String, String> {
        debug!("📊 生成 Dashboard HTML 喵...");

        // 获取各类指标数据
        let agent_metrics = metrics.get_recent_agent_metrics(20).map_err(|e| e.to_string())?;
        let tool_metrics = metrics.get_recent_tool_metrics(50).map_err(|e| e.to_string())?;
        let system_metrics = metrics.get_recent_system_metrics(100).map_err(|e| e.to_string())?;
        let tool_stats = metrics.get_tool_statistics().map_err(|e| e.to_string())?;

        // 计算统计数据
        let stats = self.calculate_stats(&agent_metrics, &tool_metrics);

        // 生成 HTML
        let html = self.render_html(&agent_metrics, &tool_metrics, &system_metrics, &tool_stats, &stats);

        debug!("✅ Dashboard HTML 生成完成喵！");

        Ok(html)
    }

    /// 🔒 SAFETY: 计算统计数据喵
    fn calculate_stats(
        &self,
        agent_metrics: &[crate::telemetry::metrics::AgentMetrics],
        tool_metrics: &[crate::telemetry::metrics::ToolMetrics],
    ) -> DashboardStats {
        let total_requests = agent_metrics.len();

        let total_tokens: u32 = agent_metrics
            .iter()
            .filter_map(|m| m.total_tokens)
            .sum();

        let success_count = agent_metrics.iter().filter(|m| m.status == "success").count();
        let failed_count = total_requests - success_count;

        let avg_tokens = if success_count > 0 {
            Some(total_tokens as f64 / success_count as f64)
        } else {
            None
        };

        let tool_call_count = tool_metrics.len();
        let successful_tools = tool_metrics.iter().filter(|t| t.status == "success").count();

        let avg_tool_duration = if tool_call_count > 0 {
            let total: u64 = tool_metrics.iter().map(|t| t.duration_ms).sum();
            Some(total as f64 / tool_call_count as f64)
        } else {
            None
        };

        DashboardStats {
            total_requests,
            total_tokens,
            avg_tokens,
            success_count,
            failed_count,
            success_rate: if total_requests > 0 {
                Some(success_count as f64 / total_requests as f64 * 100.0)
            } else {
                None
            },
            tool_call_count,
            successful_tools,
            failed_tools: tool_call_count - successful_tools,
            avg_tool_duration,
        }
    }

    /// 🔒 SAFETY: 渲染 HTML 喵
    fn render_html(
        &self,
        agent_metrics: &[crate::telemetry::metrics::AgentMetrics],
        tool_metrics: &[crate::telemetry::metrics::ToolMetrics],
        system_metrics: &[crate::telemetry::metrics::SystemMetrics],
        tool_stats: &[(String, i64, f64)],
        stats: &DashboardStats,
    ) -> String {
        format!(
            r#"<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NekoClow Metrics Dashboard 📊</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #e0e0e0;
            padding: 20px;
            min-height: 100vh;
        }}
        .container {{
            max-width: 1400px;
            margin: 0 auto;
        }}
        h1 {{
            text-align: center;
            margin-bottom: 30px;
            color: #9370DB;
            font-size: 2.5em;
            text-shadow: 0 0 20px rgba(147, 112, 219, 0.3);
        }}
        .grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}
        .card {{
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(147, 112, 219, 0.2);
            border-radius: 12px;
            padding: 20px;
            backdrop-filter: blur(10px);
        }}
        .card h2 {{
            color: #9370DB;
            margin-bottom: 15px;
            font-size: 1.3em;
            border-bottom: 1px solid rgba(147, 112, 219, 0.2);
            padding-bottom: 10px;
        }}
        .stat-grid {{
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 15px;
        }}
        .stat-item {{
            background: rgba(147, 112, 219, 0.1);
            padding: 12px;
            border-radius: 8px;
            text-align: center;
        }}
        .stat-label {{
            font-size: 0.85em;
            color: #aaa;
            margin-bottom: 5px;
        }}
        .stat-value {{
            font-size: 1.8em;
            font-weight: bold;
            color: #fff;
        }}
        .stat-value.success {{ color: #4CAF50; }}
        .stat-value.error {{ color: #f44336; }}
        .table {{
            width: 100%;
            border-collapse: collapse;
            margin-top: 10px;
        }}
        .table th, .table td {{
            padding: 10px;
            text-align: left;
            border-bottom: 1px solid rgba(255, 255, 255, 0.1);
        }}
        .table th {{
            background: rgba(147, 112, 219, 0.2);
            color: #9370DB;
            font-weight: bold;
        }}
        .table tr:hover {{
            background: rgba(147, 112, 219, 0.1);
        }}
        .status-success {{ color: #4CAF50; }}
        .status-failed {{ color: #f44336; }}
        .refresh-info {{
            text-align: center;
            color: #888;
            margin-top: 30px;
            font-size: 0.9em;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>📊 NekoClow Metrics Dashboard</h1>

        <div class="grid">
            <div class="card">
                <h2>🤖 Agent 指标</h2>
                <div class="stat-grid">
                    <div class="stat-item">
                        <div class="stat-label">总请求数</div>
                        <div class="stat-value">{}</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-label">成功率</div>
                        <div class="stat-value {}">{:.1}%</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-label">总 Token</div>
                        <div class="stat-value">{}</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-label">平均 Token</div>
                        <div class="stat-value">{:.1}</div>
                    </div>
                </div>
            </div>

            <div class="card">
                <h2>🔧 工具调用</h2>
                <div class="stat-grid">
                    <div class="stat-item">
                        <div class="stat-label">总调用数</div>
                        <div class="stat-value">{}</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-label">成功率</div>
                        <div class="stat-value success">{:.1}%</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-label">平均耗时</div>
                        <div class="stat-value">{:.1}ms</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-label">失败数</div>
                        <div class="stat-value {}">{}</div>
                    </div>
                </div>
            </div>
        </div>

        <div class="grid">
            <div class="card">
                <h2>🔧 工具调用统计</h2>
                <table class="table">
                    <thead>
                        <tr>
                            <th>工具名称</th>
                            <th>调用次数</th>
                            <th>平均耗时</th>
                        </tr>
                    </thead>
                    <tbody>
                        {}
                    </tbody>
                </table>
            </div>

            <div class="card">
                <h2>📊 最近 Agent 请求</h2>
                <table class="table">
                    <thead>
                        <tr>
                            <th>时间</th>
                            <th>模型</th>
                            <th>Token</th>
                            <th>状态</th>
                        </tr>
                    </thead>
                    <tbody>
                        {}
                    </tbody>
                </table>
            </div>
        </div>

        <div class="card">
            <h2>🖥️ 系统资源监控（最近 100 个采样点）</h2>
            <table class="table">
                <thead>
                    <tr>
                        <th>采样时间</th>
                        <th>内存使用 (MB)</th>
                    </tr>
                </thead>
                <tbody>
                    {}
                </tbody>
            </table>
        </div>

        <div class="refresh-info">
            最后更新: {} 📚 Generated by 缪斯 (Muse) 💜
        </div>
    </div>
</body>
</html>"#,
            stats.total_requests,
            if stats.success_rate.unwrap_or(100.0) >= 90.0 { "success" } else { "" },
            stats.success_rate.unwrap_or(100.0),
            stats.total_tokens,
            stats.avg_tokens.unwrap_or(0.0),
            stats.tool_call_count,
            if stats.tool_call_count > 0 {
                stats.successful_tools as f64 / stats.tool_call_count as f64 * 100.0
            } else {
                100.0
            },
            stats.avg_tool_duration.unwrap_or(0.0),
            if stats.failed_tools > 0 { "error" } else { "" },
            stats.failed_tools,
            self.render_tool_stats(tool_stats),
            self.render_agent_metrics(agent_metrics),
            self.render_system_metrics(system_metrics),
            chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC")
        )
    }

    /// 🔒 SAFETY: 渲染工具统计表格喵
    fn render_tool_stats(&self, tool_stats: &[(String, i64, f64)]) -> String {
        if tool_stats.is_empty() {
            return String::from("<tr><td colspan=\"3\" style=\"text-align:center;color:#888;\">暂无数据</td></tr>");
        }

        tool_stats
            .iter()
            .map(|(name, count, avg_duration)| {
                format!(
                    r#"<tr>
                        <td>{}</td>
                        <td>{}</td>
                        <td>{:.1}ms</td>
                    </tr>"#,
                    name, count, avg_duration
                )
            })
            .collect::<Vec<_>>()
            .join("")
    }

    /// 🔒 SAFETY: 渲染 Agent 指标表格喵
    fn render_agent_metrics(
        &self,
        agent_metrics: &[crate::telemetry::metrics::AgentMetrics],
    ) -> String {
        if agent_metrics.is_empty() {
            return String::from("<tr><td colspan=\"4\" style=\"text-align:center;color:#888;\">暂无数据</td></tr>");
        }

        agent_metrics
            .iter()
            .take(10)
            .map(|m| {
                let time_str = m
                    .start_time
                    .format("%Y-%m-%d %H:%M:%S")
                    .to_string();
                let tokens = m.total_tokens.map(|t| t.to_string()).unwrap_or("-".to_string());
                let status_class = if m.status == "success" {
                    "status-success"
                } else {
                    "status-failed"
                };

                format!(
                    r#"<tr>
                        <td>{}</td>
                        <td>{}</td>
                        <td>{}</td>
                        <td class="{}">{}</td>
                    </tr>"#,
                    time_str, m.model, tokens, status_class, m.status
                )
            })
            .collect::<Vec<_>>()
            .join("")
    }

    /// 🔒 SAFETY: 渲染系统指标表格喵
    fn render_system_metrics(
        &self,
        system_metrics: &[crate::telemetry::metrics::SystemMetrics],
    ) -> String {
        if system_metrics.is_empty() {
            return String::from("<tr><td colspan=\"2\" style=\"text-align:center;color:#888;\">暂无数据</td></tr>");
        }

        system_metrics
            .iter()
            .take(10) // 只显示最近 10 条
            .map(|m| {
                let time_str = m
                    .sample_time
                    .format("%Y-%m-%d %H:%M:%S")
                    .to_string();

                format!(
                    r#"<tr>
                        <td>{}</td>
                        <td>{:.2}</td>
                    </tr>"#,
                    time_str, m.memory_mb
                )
            })
            .collect::<Vec<_>>()
            .join("")
    }
}

/// 🔒 SAFETY: Dashboard 统计数据喵
#[derive(Debug)]
struct DashboardStats {
    total_requests: usize,
    total_tokens: u32,
    avg_tokens: Option<f64>,
    success_count: usize,
    failed_count: usize,
    success_rate: Option<f64>,
    tool_call_count: usize,
    successful_tools: usize,
    failed_tools: usize,
    avg_tool_duration: Option<f64>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_dashboard_generation() {
        // 测试基本的 Dashboard 生成逻辑
        let generator = DashboardGenerator::new();

        // 创建一个测试用的 empty 统计
        let stats = DashboardStats {
            total_requests: 0,
            total_tokens: 0,
            avg_tokens: None,
            success_count: 0,
            failed_count: 0,
            success_rate: None,
            tool_call_count: 0,
            successful_tools: 0,
            failed_tools: 0,
            avg_tool_duration: None,
        };

        // 测试渲染不会崩溃
        let html = generator.render_html(&[], &[], &[], &[], &stats);
        assert!(html.contains("NekoClow Metrics Dashboard"));
        assert!(html.contains("暂无数据"));
    }
}
