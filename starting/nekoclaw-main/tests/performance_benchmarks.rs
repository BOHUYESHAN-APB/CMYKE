/// nekoclaw 性能压力测试套件 🐾
///
/// 本模块包含 nekoclaw 核心的性能基准测试喵！
/// 测试目标：
/// - Discord 响应延迟 < 50ms (P99)
/// - 内存占用稳定 < 20MB
/// - 并发连接数 > 1,000
/// - 吞吐量 > 50 req/s
///
/// 🔒 SECURITY: 测试环境完全隔离，不接触生产数据
///
/// 测试者: 诺诺 (Nono) ⚡
/// 最后更新: 2026-02-15
use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion};
use std::time::Duration;
use tokio::runtime::Runtime;

/// 基础性能测试套件
mod performance;

/// Discord 集成性能测试
mod discord;

/// 内存占用监控测试
mod memory;

/// 🔒 SAFETY: 本测试函数验证基础算术运算性能喵
/// 无外部依赖，纯 CPU 密集型操作
fn fibonacci(n: u64) -> u64 {
    match n {
        0 => 0,
        1 => 1,
        _ => fibonacci(n - 1) + fibonacci(n - 2),
    }
}

/// 🔒 SAFETY: 基准测试入口函数喵
/// 使用 criterion 框架进行精确的性能测量
fn benchmark_fibonacci(c: &mut Criterion) {
    let mut group = c.benchmark_group("fibonacci");
    group.measurement_time(Duration::from_secs(10));
    group.sample_size(1000);

    for i in [20, 21, 22].iter() {
        group.bench_with_input(BenchmarkId::new("recursive", i), i, |b, &i| {
            b.iter(|| fibonacci(black_box(i)))
        });
    }

    group.finish();
}

/// 🔒 SAFETY: 字符串解析性能测试喵
/// 模拟 Discord JSON 消息的解析开销
fn benchmark_json_parsing(c: &mut Criterion) {
    use serde_json;

    let test_message = r#"
    {
        "id": "123456789",
        "content": "Hello Nono!",
        "author": {"id": "987654321", "username": "Nono"},
        "timestamp": "2026-02-15T17:00:00Z"
    }
    "#;

    c.bench_function("json_parse_message", |b| {
        b.iter(|| {
            black_box(serde_json::from_str::<serde_json::Value>(black_box(
                test_message,
            )))
        })
    });
}

/// 🔒 SAFETY: 异步任务生成性能测试喵
/// 模拟高并发环境下的任务调度开销
fn benchmark_async_spawn(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();

    c.bench_function("async_spawn", |b| {
        b.iter(|| {
            rt.block_on(async {
                let handles: Vec<_> = (0..100)
                    .map(|_| {
                        tokio::spawn(async {
                            tokio::time::sleep(Duration::from_micros(1)).await;
                        })
                    })
                    .collect();

                for handle in handles {
                    handle.await.unwrap();
                }
            })
        })
    });
}

/// 🔒 SAFETY: 内存分配压力测试喵
/// 监控连续分配/释放内存时的性能表现
fn benchmark_memory_allocation(c: &mut Criterion) {
    use std::mem;

    c.bench_function("memory_allocation", |b| {
        b.iter(|| {
            let mut vec = Vec::with_capacity(1024);
            for i in 0..1024 {
                vec.push(i);
            }
            black_box(vec.len());
            mem::drop(vec);
        })
    });
}

/// 基准测试组注册
criterion_group!(
    benches,
    benchmark_fibonacci,
    benchmark_json_parsing,
    benchmark_async_spawn,
    benchmark_memory_allocation
);

/// 🔒 SAFETY: 基准测试主入口喵
/// 运行所有性能测试并生成报告
criterion_main!(benches);
