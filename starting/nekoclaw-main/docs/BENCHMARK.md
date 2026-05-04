# nekoclaw 性能测试套件文档 📊

**文档作者**: 诺诺 (Nono) ⚡
**更新时间**: 2026-02-15
**版本**: v1.0

---

## 📋 目录

1. [概述](#概述)
2. [测试目标](#测试目标)
3. [测试模块](#测试模块)
4. [快速开始](#快速开始)
5. [测试报告](#测试报告)
6. [性能对比](#性能对比)
7. [常见问题](#常见问题)

---

## 概述

 nekoclaw 性能测试套件是基于 Rust **criterion** 框架构建的高精度基准测试系统喵！

### 设计理念

- 🔒 **安全第一**: 所有测试遵循花凛的安全注释准则
- ⚡ **高精度**: 使用纳秒级计时器
- 📊 **全面覆盖**: 从基础运算到复杂集成
- 🎯 **目标导向**: 所有测试都有明确的性能目标

---

## 测试目标

| 类别 | 指标 | 目标值 | OpenClaw (参考) |
|------|------|--------|----------------|
| **资源占用** | 二进制大小 | < 2.5 MB | 28 MB |
| | 冷启动时间 | < 0.25s | 3.31s |
| | 空载内存 | < 5.5 MB | 1.52 GB |
| **响应性能** | Discord 消息解析 | < 5ms | ~180ms |
| | Discord API 调用 | < 50ms (P99) | ~180ms |
| | WebSocket 心跳 | < 10ms | ~30ms |
| **并发能力** | 并发连接数 | > 1,000 | ~100 |
| | 请求吞吐量 | > 50 req/s | ~5.5 req/s |

---

## 测试模块

### 1. 基础性能测试 (`tests/performance_benchmarks.rs`)

#### 测试列表

| 测试名称 | 描述 | 使用场景 |
|---------|------|---------|
| `benchmark_fibonacci` | 递归性能测试 | 验证基础计算能力 |
| `benchmark_json_parsing` | JSON 解析性能 | Discord 消息解析 |
| `benchmark_async_spawn` | 异步任务生成 | 高并发任务调度 |
| `benchmark_memory_allocation` | 内存分配性能 | 内存管理优化 |

#### 🔒 安全注释示例

```rust
/// 🔒 SAFETY: 异步任务生成性能测试喵
/// 模拟高并发环境下的任务调度开销
///
/// 异常处理: 无，纯性能测试
/// 内存安全: 使用 Arc 安全共享
fn benchmark_async_spawn(c: &mut Criterion) {
    // ...
}
```

---

### 2. Discord 集成测试 (`tests/discord.rs`)

#### 测试列表

| 测试名称 | 描述 | 性能目标 |
|---------|------|---------|
| `bench_discord_message_parse` | Discord 消息解析 | < 5ms |
| `bench_discord_api_request` | Discord API 模拟 | < 50ms |
| `bench_discord_message_throughput` | 消息队列吞吐量 | > 1000 msg/s |
| `bench_discord_websocket_connect` | WebSocket 连接建立 | < 10ms |

#### 测试数据

```rust
let test_messages = vec![
    r#"{"op":0,"s":1,"t":"MESSAGE_CREATE",...}"#, // 标准消息
    r#"{"op":11,"d":null}"#, // 心跳确认
];
```

---

### 3. 内存测试 (`tests/memory.rs`)

#### 测试列表

| 测试名称 | 描述 | 内存目标 |
|---------|------|---------|
| `bench_basic_memory_allocation` | 基础内存分配 | < 1MB 峰值 |
| `bench_zero_copy_string` | 零拷贝字符串操作 | 零额外分配 |
| `bench_buffer_pool` | 内存池复用效率 | 减少 50% 分配 |
| `bench_memory_leak_detection` | 内存泄漏检测 | 无增长 |
| `bench_high_frequency_allocation` | 高频小对象分配 | 稳定 |
| `bench_concurrent_memory_allocation` | 并发内存压力 | 无竞争 |

#### 🔒 内存追踪器

```rust
#[global_allocator]
static TRACKER: MemoryTracker = MemoryTracker;

/// 🔒 SAFETY: 获取当前内存分配量(字节)喵
pub fn get_memory_usage() -> usize {
    ALLOCATED.load(Ordering::Relaxed)
}
```

---

### 4. 性能辅助工具 (`tests/performance.rs`)

#### 工具函数

| 函数 | 描述 | 使用场景 |
|-----|------|---------|
| `PerformanceStats::from_samples` | 统计分析 | 结果汇总 |
| `PerformanceStats::report` | 生成报告 | 输出格式化 |
| `Timer::elapsed_ns` | 计时器 | 代码块计时 |
| `bench_loop!` | 宏简化 | 循环测试 |

---

## 快速开始

### 方法 1: 使用测试脚本（推荐）

```bash
# 在 nekoclaw 根目录
./run_benchmarks.sh
```

### 方法 2: 手动运行

```bash
# 运行所有测试
cargo bench

# 运行特定测试
cargo bench --bench performance_benchmarks
cargo bench --bench discord
cargo bench --bench memory

# 保存基线（用于对比）
cargo bench -- --save-baseline baseline

# 与基线对比
cargo bench -- --baseline baseline
```

### 查看详细报告

```bash
# 打开 HTML 报告
open target/criterion/report/index.html

# 输出文本报告
cargo bench -- --output-format quiet
```

---

## 测试报告

### 报告结构

```
target/criterion/
├── report/                    # HTML 报告入口
│   └── index.html
├── performance_benchmarks/    # 基础测试详细数据
├── discord/                   # Discord 测试详细数据
└── memory/                    # 内存测试详细数据
```

### 报告内容

每项测试都包括：
- ✅ **趋势图**: 性能随时间变化
- 📊 **统计信息**: 平均值、中位数、P99 等
- 🔍 **火焰图**: 性能热点分析（调用 pprof）
- 📈 **对比**: 与历史基线对比

---

## 性能对比

### 与 OpenClaw 对比

| 指标 | OpenClaw | nekoclaw (预期) | 提升幅度 |
|------|----------|----------------|---------|
| 启动时间 | 3.31s | 0.25s | **13.2x** ⚡ |
| 内存占用 | 1.52 GB | 5.5 MB | **276x** 📉 |
| Discord 响应 | 180ms | 50ms | **3.6x** ⚡ |
| 并发连接 | ~100 | >1000 | **10x** 🔥 |

### 与 ZeroClaw 对比

| 指标 | ZeroClaw | nekoclaw (预期) | 说明 |
|------|----------|----------------|------|
| 内存占用 | 7.8 MB | 5.5 MB | 进一步优化 |
| 响应延迟 | 15ms | 10ms | Discord 专注优化 |

---

## 常见问题

### Q1: 测试时内存不足怎么办？

```bash
# 限制并发数
ulimit -n 1024

# 减少测试样本
cargo bench --bench memory -- --sample-size 100
```

### Q2: 如何调试性能问题？

```bash
# 生成火焰图
cargo bench --bench memory -- --profile-time 5

# 查看 target/criterion/memory/ 下的 svg 文件
```

### Q3: 测试结果不稳定怎么办？

```bash
# 增加测量时间
cargo bench -- --measurement-time 30

# 增加样本数
cargo bench -- --sample-size 5000
```

---

## 🔒 安全准则

所有测试遵循花凛的安全注释标准喵：

1. **危险操作必须标注**: 🔒 SAFETY / ⚠️ SAFETY
2. **权限检查点标注**: 🔐 PERMISSION
3. **跨模块调用标注**: 🔄 CALLCHAIN

示例：
```rust
/// 🔒 SAFETY: 此函数执行 Shell 命令，必须经过白名单验证喵
/// 白名单路径: /usr/bin/{git,ls,cat}
fn execute_shell(cmd: &str) -> Result<String> { ... }
```

---

## 📝 更新日志

- **2026-02-15**: 初始版本，完成基础测试框架喵 ⚡

---

**文档维护**: 诺诺 (Nono) ⚡
**安全审查**: 花凛 (Fiora) 🛡️
