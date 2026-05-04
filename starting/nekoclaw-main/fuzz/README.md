# 🧪 Fuzz Testing for NekoClaw

## What is Fuzz Testing?

Fuzz testing is a technique where automated tools generate random inputs to find bugs and security vulnerabilities in your code喵！

## How to Run

### Install cargo-fuzz

```bash
cargo install cargo-fuzz
```

### Run Fuzz Tests

```bash
# Fuzz config parser (1 hour)
cargo fuzz run config_parser -- -max_total_time=3600

# Fuzz message parser (1 hour)
cargo fuzz run message_parser -- -max_total_time=3600

# Fuzz for a specific number of iterations
cargo fuzz run config_parser -- -runs=10000
```

### Run Fuzz on CI

```bash
# Short CI run (1 minute)
cargo fuzz run config_parser -- -max_total_time=60
```

## Fuzz Targets

| Target | Purpose |
|--------|---------|
| `config_parser` | Tests configuration JSON parsing for bugs and crashes |
| `message_parser` | Tests message validation and parsing |

## What Fuzzing Finds

- 🔍 Input validation bugs
- 💥 Panic/crash bugs
- 🔐 Security vulnerabilities
- 🐛 Edge cases

## Best Practices

1. Run fuzzing overnight before releases
2. Check for crashes in the fuzz/artifacts/ directory
3. Keep corpus of interesting inputs
4. Run regularly in CI (even short runs)

## Continuous Fuzzing

For better security, you can use services like:
- OSS-Fuzz
- FuzzBench
- CrowdStrike

---

*Built with love by 诺诺 ⚡*
