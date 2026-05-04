/*!
 * 测试套件 - 单元测试与基准测试
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 19:30 JST
 *
 * 功能:
 * - 核心模块单元测试
 * - 性能基准测试
 * - 测试覆盖率统计
 */

mod memory_tests;
mod security_tests;
mod config_tests;
mod obfuscate_tests;

pub use memory_tests::*;
pub use security_tests::*;
pub use config_tests::*;
pub use obfuscate_tests::*;

/// 测试覆盖率统计
#[derive(Debug, Clone, Default)]
pub struct CoverageStats {
    pub total_modules: usize,
    pub tested_modules: usize,
    pub total_functions: usize,
    pub tested_functions: usize,
    pub coverage_percentage: f64,
}

impl CoverageStats {
    /// 计算覆盖率
    pub fn calculate(&self) -> f64 {
        if self.total_functions == 0 {
            0.0
        } else {
            (self.tested_functions as f64 / self.total_functions as f64) * 100.0
        }
    }

    /// 生成报告
    pub fn report(&self) -> String {
        format!(
            "📊 **测试覆盖率报告**\n\
             📦 模块覆盖率: {}/{} ({:.1}%)\n\
             🔧 函数覆盖率: {}/{} ({:.1}%)\n",
            self.tested_modules,
            self.total_modules,
            (self.tested_modules as f64 / self.total_modules as f64) * 100.0,
            self.tested_functions,
            self.total_functions,
            self.calculate()
        )
    }
}

/// 基准测试结果
#[derive(Debug, Clone)]
pub struct BenchmarkResult {
    pub name: String,
    pub iterations: usize,
    pub total_ns: u128,
    pub avg_ns: f64,
    pub ops_per_sec: f64,
}

impl BenchmarkResult {
    /// 创建新的基准测试结果
    pub fn new(name: &str, iterations: usize, total_ns: u128) -> Self {
        let avg_ns = total_ns as f64 / iterations as f64;
        let ops_per_sec = 1_000_000_000.0 / avg_ns;

        Self {
            name: name.to_string(),
            iterations,
            total_ns,
            avg_ns,
            ops_per_sec,
        }
    }

    /// 报告格式
    pub fn report(&self) -> String {
        format!(
            "⚡ **{}**\n\
             📊 迭代次数: {}\n\
             ⏱️  平均耗时: {:.2} ns\n\
             🚀 吞吐量: {:.0} ops/sec",
            self.name,
            self.iterations,
            self.avg_ns,
            self.ops_per_sec
        )
    }
}

#[cfg(test)]
mod integration_tests {
    use super::*;

    #[test]
    fn test_coverage_calculation() {
        let stats = CoverageStats {
            total_modules: 10,
            tested_modules: 8,
            total_functions: 100,
            tested_functions: 75,
            coverage_percentage: 0.0,
        };

        let coverage = stats.calculate();
        assert_eq!(coverage, 75.0);
    }

    #[test]
    fn test_benchmark_result_creation() {
        let result = BenchmarkResult::new("test_add", 1000, 1_000_000);
        assert_eq!(result.name, "test_add");
        assert_eq!(result.iterations, 1000);
        assert_eq!(result.total_ns, 1_000_000);
        assert_eq!(result.avg_ns, 1000.0);
    }
}
