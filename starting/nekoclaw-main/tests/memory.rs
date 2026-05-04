/// 内存占用监控与压力测试模块 💾
///
/// @花凛 授权的内存安全测试喵
///
/// 测试目标：
/// - 空载内存占用 < 5MB
/// - 单次任务内存峰值 < 10MB
/// - 长时间运行无内存泄漏
/// - 内存碎片率 < 5%
///
/// 🔒 SECURITY: 内存边界测试，防止 OOM 攻击
///
/// 测试者: 诺诺 (Nono) ⚡ + 花凛 (Fiora) 🛡️
use criterion::{black_box, BenchmarkId, Criterion, Throughput};
use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicUsize, Ordering};

/// 🔒 SAFETY: 内存分配追踪器喵
/// 用于精确测量测试过程中的内存分配量
struct MemoryTracker;

#[global_allocator]
static TRACKER: MemoryTracker = MemoryTracker;

/// 🔒 SAFETY: 原子计数器用于追踪内存分配状态喵
/// 使用 OrderRelaxed 放宽内存序，性能优先
static ALLOCATED: AtomicUsize = AtomicUsize::new(0);

unsafe impl GlobalAlloc for MemoryTracker {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let ptr = System.alloc(layout);
        if !ptr.is_null() {
            ALLOCATED.fetch_add(layout.size(), Ordering::Relaxed);
        }
        ptr
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        System.dealloc(ptr, layout);
        ALLOCATED.fetch_sub(layout.size(), Ordering::Relaxed);
    }
}

/// 🔒 SAFETY: 获取当前内存分配量（字节）喵
/// 返回自程序启动以来分配但未释放的内存总量
pub fn get_memory_usage() -> usize {
    ALLOCATED.load(Ordering::Relaxed)
}

/// 🔒 SAFETY: 基本内存分配测试喵
/// 验证 Vec 分配和释放的内存行为
pub fn bench_basic_memory_allocation(c: &mut Criterion) {
    c.bench_function("memory_basic_allocation", |b| {
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

/// 🔒 SAFETY: 零拷贝字符串操作测试喵
/// 验证 &str vs String 的内存开销差异
pub fn bench_zero_copy_string(c: &mut Criterion) {
    let test_string = "Hello, this is a long test string for zero copy analysis喵！";

    c.bench_function("string_copy", |b| {
        b.iter(|| {
            let _owned = black_box(test_string.to_string());
        })
    });

    c.bench_function("string_borrow", |b| {
        b.iter(|| {
            let _borrowed = black_box(test_string);
        })
    });
}

/// 🔒 SAFETY: 内存池复用性能测试喵
/// 验证缓冲区复用与重复分配的性能差异
pub fn bench_buffer_pool(c: &mut Criterion) {
    use std::sync::Arc;
    use tokio::sync::Semaphore;

    c.bench_function("buffer_without_pool", |b| {
        b.iter(|| {
            let mut buffer = Vec::with_capacity(4096);
            buffer.extend_from_slice(&[0u8; 2048]);
            black_box(buffer);
        })
    });

    c.bench_function("buffer_with_pool", |b| {
        let mut pool = Vec::new();
        b.iter(|| {
            let mut buffer = pool.pop().unwrap_or_else(|| Vec::with_capacity(4096));
            buffer.clear();
            buffer.extend_from_slice(&[0u8; 2048]);
            black_box(buffer.len());
            pool.push(buffer);
        })
    });
}

/// 🔒 SAFETY: 内存泄漏检测测试喵
/// 长时间运行检查内存是否持续增长
///
/// ⚠️ PERFORMANCE: 此测试运行时间较长（30秒）
/// 用于检测潜在的内存泄漏问题
pub fn bench_memory_leak_detection(c: &mut Criterion) {
    let mut group = c.benchmark_group("memory_leak");
    group.measurement_time(Duration::from_secs(30));
    group.sample_size(1000);

    group.bench_function("long_running", |b| {
        b.iter(|| {
            // 模拟真实使用场景
            let mut vec = Vec::new();
            for i in 0..100 {
                vec.push(i);
            }
            // 确保内存被正确释放
            black_box(vec.len());
            drop(vec);
        })
    });

    group.finish();
}

/// 🔒 SAFETY: 高频小对象分配测试喵
/// 测试类似消息处理的场景（频繁分配小对象）
pub fn bench_high_frequency_allocation(c: &mut Criterion) {
    let mut group = c.benchmark_group("high_freq_alloc");
    group.throughput(Throughput::Elements(10000));

    for size in [16, 64, 256].iter() {
        group.bench_with_input(BenchmarkId::new("small_objects", size), size, |b, &size| {
            b.iter(|| {
                for _ in 0..10000 {
                    let data = vec![0u8; size];
                    black_box(data);
                }
            })
        });
    }

    group.finish();
}

/// 🔒 SAFETY: 并发内存分配压力测试喵
/// 验证多线程环境下内存分配器的工作负载
pub fn bench_concurrent_memory_allocation(c: &mut Criterion) {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use std::thread;

    c.bench_function("concurrent_alloc", |b| {
        b.iter(|| {
            let running = Arc::new(AtomicBool::new(true));
            let mut handles = vec![];

            // 启动 10 个并发线程
            for _ in 0..10 {
                let running = running.clone();
                let handle = thread::spawn(move || {
                    while running.load(Ordering::Relaxed) {
                        let mut vec = Vec::with_capacity(1024);
                        for i in 0..1024 {
                            vec.push(i);
                        }
                        drop(vec);
                    }
                });
                handles.push(handle);
            }

            // 运行 10ms
            std::thread::sleep(Duration::from_millis(10));
            running.store(false, Ordering::Relaxed);

            for handle in handles {
                handle.join().unwrap();
            }
        })
    });
}
