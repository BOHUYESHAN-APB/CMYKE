# Neko-Claw Quickstart Guide 🐾⚡

> Get started with high-performance Rust AI Assistant framework in 5 minutes

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [First Command](#first-command)
- [Configuration](#configuration)
- [FAQ](#faq)

---

## Prerequisites

- **Rust**: 1.70+ (Recommended 1.93+)
- **OS**: Linux / macOS / Windows (WSL2)
- **Memory**: Minimum 100MB RAM (Target <20MB)

### Check Rust Version

```bash
rustc --version
```

If Rust is not installed, please use [rustup](https://rustup.rs/) to install:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

---

## Installation

### Method 1: Clone Repository (Recommended)

```bash
# Clone the repository
git clone https://github.com/Gengetau/nekoclaw.git
cd nekoclaw

# Build release version
cargo build --release

# Binary file location
./target/release/nekoclaw --help
```

### Method 2: Cargo Installation (Upcoming)

```bash
# Coming soon
cargo install nekoclaw
```

### Build Optimization

To achieve the smallest binary size, use the following optimizations:

```bash
# 1. Create a release build
cargo build --release

# 2. Strip binary (optional, further reduces size)
strip target/release/nekoclaw

# 3. Check binary size
ls -lh target/release/nekoclaw
```

**Expected Size**: <2.5MB

---

## First Command

### 1. View Help

```bash
nekoclaw --help
```

Output:

```
Neko-Claw v0.1.0 - High-performance Rust AI Assistant Framework

USAGE:
    nekoclaw [OPTIONS] <SUBCOMMAND>

OPTIONS:
    -c, --config <CONFIG>    Config file path (Default: ~/.nekoclaw/config.json)
    -v, --verbose           Detailed output
    -h, --help              Show help information

SUBCOMMANDS:
    start       Start Neko-Claw service
    status      Check running status
    stop        Stop service
    restart     Restart service
    config      Config management
    test        Run tests
    version     Show version information
```

### 2. Check Version

```bash
nekoclaw version
```

Output:

```
Neko-Claw v0.1.0
Rust: 1.93.1
```

### 3. Run Tests

```bash
nekoclaw test
```

This will run all unit tests and integration tests.

---

## Configuration

### 1. Config File Location

Default config file: `~/.nekoclaw/config.json`

If it doesn't exist, it will be automatically created on the first start.

### 2. Minimal Configuration Example

Create `~/.nekoclaw/config.json`:

```json
{
  "version": "1.0.0",
  "gateway": {
    "host": "localhost",
    "port": 8080
  },
  "models": {
    "providers": {
      "nvidia": {
        "apiKey": "your-api-key-here"
      }
    }
  },
  "channels": {
    "discord": {
      "accounts": {
        "main_bot": {
          "token": "your-discord-token"
        }
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "nvidia/z-ai/glm4.7"
      }
    }
  }
}
```

### 3. Migrate Config from OpenClaw

If you have an existing OpenClaw configuration, you can copy it directly:

```bash
# Copy OpenClaw configuration
cp ~/.openclaw/openclaw.json ~/.nekoclaw/config.json

# Validate configuration (optional)
nekoclaw config validate
```

For a detailed migration guide, please refer to: [MIGRATION.md](./MIGRATION.md)

---

## Start Service

### Run in Foreground (Development Mode)

```bash
nekoclaw start
```

Output:

```
[INFO] Neko-Claw v0.1.0 starting...
[INFO] Loaded config from ~/.nekoclaw/config.json
[INFO] Initializing providers...
[INFO] Starting gateway server on localhost:8080...
[INFO] Neko-Claw is running! 🚀
```

### Run in Background (Production Mode)

```bash
# Using nohup
nohup nekoclaw start > nekoclaw.log 2>&1 &

# Or use systemd (Recommended)
sudo systemctl enable nekoclaw
sudo systemctl start nekoclaw
```

### Check Running Status

```bash
nekoclaw status
```

Output:

```
Neko-Claw Status:
  Version:    v0.1.0
  Status:     Running
  Uptime:     2h 15m
  Memory:     18.5MB / 20MB
  Services:   5/5 active
```

---

## FAQ

### ❓ Why did the startup fail?

**Possible Cause 1: Missing or malformed config file**

```bash
# Validate config
nekoclaw config validate
```

**Possible Cause 2: Port is already in use**

Change the port in the configuration file:

```json
{
  "gateway": {
    "port": 9000  // Change to another port
  }
}
```

**Possible Cause 3: Invalid API Key**

Check if `models.providers.*.apiKey` is correct.

---

### ❓ How to view detailed logs?

Use the `--verbose` flag:

```bash
nekoclaw start --verbose
```

Or check the log file:

```bash
# Default log location
tail -f ~/.nekoclaw/nekoclaw.log
```

---

### ❓ Memory usage exceeds 20MB?

Check if there are any unclosed sessions:

```bash
nekoclaw config list-sessions
```

Clean up expired sessions:

```bash
nekoclaw config cleanup
```

---

### ❓ How to upgrade to the latest version?

```bash
# Pull latest code
git pull origin main

# Rebuild
cargo build --release

# Restart service
nekoclaw restart
```

---

### ❓ Which Providers are supported?

Currently supported Providers:

- ✅ OpenAI
- ✅ Anthropic (Claude)
- ✅ OpenRouter
- ✅ NVIDIA (Recommended, High-performance)

View the full list: [USAGE.md](./USAGE.md)

---

### ❓ How to contact support?

- 📚 [Documentation Center](https://docs.nekoclaw.ai)
- 💬 [Discord Community](https://discord.gg/nekoclaw)
- 🐛 [GitHub Issues](https://github.com/Gengetau/nekoclaw/issues)

---

## Next Steps

- 📖 Read the full User Guide: [USAGE.md](./USAGE.md)
- 🔧 Config Migration Guide: [MIGRATION.md](./MIGRATION.md)
- 🏗️ Architecture Doc: [../ARCHITECTURE.md](../ARCHITECTURE.md)
- 🔒 Security Doc: [./SECURITY.md](./SECURITY.md)

---

**Happy Using!** 🐾⚡

*Neko-Claw - Zero-overhead Rust AI Assistant Framework*
