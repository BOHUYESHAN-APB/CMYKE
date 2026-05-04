/// 通用性能测试辅助模块 📊
///
/// @诺诺 的性能测试工具箱喵
///
/// 功能：
/// - 统计数据分析
/// - 性能报告生成
/// - 基准对比
///
/// 🔒 SECURITY: 纯计算，无外部依赖
///
/// 测试者: 诺诺 (Nono) ⚡
use std::time::{Duration, Instant};

/// 🔒 SAFETY: 性能统计结构体喵
/// 收集并分析测试结果
#[derive(Debug, Clone)]
pub struct PerformanceStats {
    /// 样本数量
    pub sample_count: usize,
    /// 平均值（纳秒）
    pub mean_ns: u64,
    /// 中位数（纳秒）
    pub median_ns: u64,
    /// P99 分位数（纳秒）
    pub p99_ns: u64,
    /// 最小值（纳秒）
    pub min_ns: u64,
    /// 最大值（纳秒）
    pub max_ns: u64,
    /// 标准差（纳秒）
    pub std_dev_ns: u64,
}

impl PerformanceStats {
    /// 🔒 SAFETY: 计算性能统计喵
    /// 输入：一组纳秒级时间戳
    /// 输出：完整的统计信息
    pub fn from_samples(samples: &[u64]) -> Self {
        let count = samples.len();
        if count == 0 {
            return Self {
                sample_count: 0,
                mean_ns: 0,
                median_ns: 0,
                p99_ns: 0,
                min_ns: 0,
                max_ns: 0,
                std_dev_ns: 0,
            };
        }

        let mut sorted = samples.to_vec();
        sorted.sort_unstable();

        let sum: u64 = sorted.iter().sum();
        let mean = sum / count as u64;

        let median = sorted[count / 2];
        let p99 = sorted[(count as f64 * 0.99) as usize];

        let min = sorted[0];
        let max = sorted[count - 1];

        // 计算标准差
        let variance: u64 = sorted
            .iter()
            .map(|&x| {
                let diff = x as i64 - mean as i64;
                (diff * diff) as u64
            })
            .sum::<u64>()
            / count as u64;
        let std_dev = (variance as f64).sqrt() as u64;

        Self {
            sample_count: count,
            mean_ns: mean,
            median_ns: median,
            p99_ns: p99,
            min_ns: min,
            max_ns: max,
            std_dev_ns: std_dev,
        }
    }

    /// 🔒 SAFETY: 格式化为人类可读的时间字符串喵
    pub fn format_duration(&self, ns: u64) -> String {
        if ns < 1_000 {
            format!("{}ns", ns)
        } else if ns < 1_000_000 {
            format!("{:.2}μs", ns as f64 / 1_000.0)
        } else if ns < 1_000_000_000 {
            format!("{:.2}ms", ns as f64 / 1_000_000.0)
        } else {
            format!("{:.2}s", ns as f64 / 1_000_000_000.0)
        }
    }

    /// 🔒 SAFETY: 生成性能报告喵
    /// 返回 Markdown 格式报告
    pub fn report(&self, benchmark_name: &str) -> String {
        format!(
            r#"## Performance Report: {}

| Metric | Value |
|--------|-------|
| Sample Count | {} |
| Mean | {} |
| Median | {} |
| P99 | {} |
| Min | {} |
| Max | {} |
| Std Dev | {} |

**Performance Target Assessment:**
- Mean < 50ms: {}
- P99 < 100ms: {}
"#,
            benchmark_name,
            self.sample_count,
            self.format_duration(self.mean_ns),
            self.format_duration(self.median_ns),
            self.format_duration(self.p99_ns),
            self.format_duration(self.min_ns),
            self.format_duration(self.max_ns),
            self.format_duration(self.std_dev_ns),
            if self.mean_ns < 50_000_000 {
                "✅ PASS"
            } else {
                "❌ FAIL"
            },
            if self.p99_ns < 100_000_000 {
                "✅ PASS"
            } else {
                "❌ FAIL"
            }
        )
    }
}

/// 🔒 SAFETY: 计时器辅助结构喵
/// 精确测量代码块执行时间
pub struct Timer {
    start: Instant,
}

impl Timer {
    /// 创建新的计时器喵
    pub fn new() -> Self {
        Self {
            start: Instant::now(),
        }
    }

    /// 获取经过的时间（纳秒）喵
    pub fn elapsed_ns(&self) -> u64 {
        self.start.elapsed().as_nanos() as u64
    }

    /// 重置计时器喵
    pub fn reset(&mut self) {
        self.start = Instant::now();
    }
}

impl Default for Timer {
    fn default() -> Self {
        Self::new()
    }
}

/// 🔒 SAFETY: 基准测试助手宏喵
/// 简化常见的性能测试代码
#[macro_export]
macro_rules! bench_loop {
    ($iterations:expr, $code:block) => {{
        let timer = crate::tests::performance::Timer::new();
        for _ in 0..$iterations {
            $code
        }
        timer.elapsed_ns()
    }};
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_performance_stats_basic() {
        let samples = vec![1000, 2000, 1500, 3000, 2500];
        let stats = PerformanceStats::from_samples(&samples);

        assert_eq!(stats.sample_count, 5);
        assert!(stats.mean_ns > 0);
        assert!(stats.median_ns > 0);
    }

    #[test]
    fn test_timer() {
        let mut timer = Timer::new();
        let elapsed = timer.elapsed_ns();
        assert!(elapsed < 1_000_000); // 应该很快

        // 重置后应该从零开始
        timer.reset();
        let elapsed2 = timer.elapsed_ns();
        assert!(elapsed2 < elapsed);
    }

    #[test]
    fn test_format_duration() {
        assert!(PerformanceStats::format_duration(500).contains("ns"));
        assert!(PerformanceStats::format_duration(50_000).contains("μs"));
        assert!(PerformanceStats::format_duration(50_000_000).contains("ms"));
        assert!(PerformanceStats::format_duration(5_000_000_000).contains("s"));
    }
}
