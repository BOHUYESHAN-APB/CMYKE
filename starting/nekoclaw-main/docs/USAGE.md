# Neko-Claw User Guide

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Command Line Interface](#command-line-interface)
- [Usage Examples](#usage-examples)
- [FAQ](#faq)

---

## Quick Start

### 1. Clone the Project

```bash
git clone https://github.com/Gengetau/nekoclaw.git
cd nekoclaw
```

### 2. Build

```bash
cargo build --release
```

### 3. Configure

Copy your OpenClaw configuration file to the Neko-Claw config directory:

```bash
mkdir -p ~/.nekoclaw
cp ~/.openclaw/openclaw.json ~/.nekoclaw/config.json
```

### 4. Run

```bash
./target/release/nekoclaw start
```

---

## Installation

### System Requirements

- Rust 1.75+
- SQLite 3.35+ (for Memory)
- 100MB+ available RAM (Target <20MB)

### Build from Source

```bash
# Clone the repository
git clone https://github.com/Gengetau/nekoclaw.git
cd nekoclaw

# Build release version
cargo build --release

# Install to system
cargo install --path .
```

### Download Pre-built Binaries

Visit [GitHub Releases](https://github.com/Gengetau/nekoclaw/releases) to download binary files for your platform.

---

## Configuration

### Config File Location

- Linux/macOS: `~/.nekoclaw/config.json`
- Windows: `%USERPROFILE%\.nekoclaw\config.json`

### Configuration Format

Neko-Claw is fully compatible with the OpenClaw `openclaw.json` format. The following configuration items are supported:

#### Base Configuration

```json
{
  "config": {
    "version": "1.0.0",
    "gateway": {
      "host": "0.0.0.0",
      "port": 18789,
      "enabled": true
    },
    "agents": {
      "default": "miau",
      "agent": {
        "miau": {
          "id": "miau",
          "name": "Muse",
          "model": "gpt-4",
          "memory": {
            "kind": "sqlite",
            "path": "~/.nekoclaw/memory.db"
          },
          "tools": ["shell", "web-search"]
        }
      }
    }
  }
}
```

#### Provider Configuration

```json
{
  "config": {
    "models": {
      "default": "gpt-4",
      "providers": {
        "anthropic": {
          "enabled": true,
          "apiKey": "sk-ant-xxxx",
          "baseUrl": "https://api.anthropic.com",
          "model": "claude-3-opus-20240229",
          "models": [
            {
              "id": "claude-3-opus-20240229",
              "name": "Claude 3 Opus",
              "context_length": 200000
            }
          ]
        },
        "openai": {
          "enabled": true,
          "apiKey": "sk-xxxx",
          "baseUrl": "https://api.openai.com/v1",
          "model": "gpt-4"
        },
        "openrouter": {
          "enabled": true,
          "apiKey": "sk-or-xxxx",
          "baseUrl": "https://openrouter.ai/api/v1"
        }
      }
    }
  }
}
```

#### Channel Configuration (Multi-account)

```json
{
  "config": {
    "channels": {
      "discord": {
        "enabled": true,
        "accounts": {
          "main_bot": {
            "token": "MTE...xxx",
            "allowed_channels": ["123456789012345678"],
            "allowed_users": ["123456789012345678"],
            "prefix": "!"
          },
          "test_bot": {
            "token": "MTE...xxx",
            "allowed_channels": ["987654321098765432"],
            "prefix": "?"
          }
        }
      },
      "telegram": {
        "enabled": true,
        "token": "123456789:ABCdefGHIjklMNOpqrsTUVwxyz",
        "allowed_users": ["123456789"]
      }
    }
  }
}
```

#### Feature Switches

```json
{
  "config": {
    "features": {
      "channels": {
        "discord": true,
        "telegram": true,
        "signal": false
      },
      "auth": {
        "profiles_enabled": false
      }
    }
  }
}
```

---

## Command Line Interface

### Basic Commands

#### Start Service

```bash
nekoclaw start
```

#### Stop Service

```bash
nekoclaw stop
```

#### Restart Service

```bash
nekoclaw restart
```

#### Check Status

```bash
nekoclaw status
```

### Configuration Management Commands

#### Show Current Configuration

```bash
nekoclaw config show
```

#### Validate Configuration

```bash
nekoclaw config validate
```

#### Migrate OpenClaw Configuration

```bash
nekoclaw config migrate --from ~/.openclaw/openclaw.json
```

### Agent Management Commands

#### List All Agents

```bash
nekoclaw agent list
```

#### Show Agent Configuration

```bash
nekoclaw agent show <agent_name>
```

#### Test Agent

```bash
nekoclaw agent test <agent_name> --prompt "Hello"
```

### Channel Management Commands

#### Connect Discord

```bash
nekoclaw channel connect discord --account main_bot
```

#### Disconnect Channel

```bash
nekoclaw channel disconnect discord --account main_bot
```

#### List Connection Status

```bash
nekoclaw channel list
```

### Memory Management Commands

#### Search Memory

```bash
nekoclaw memory search "keyword"
```

#### Clear Memory

```bash
nekoclaw memory clear
```

#### Dump Memory

```bash
nekoclaw memory dump --output memory_backup.json
```

---

## Usage Examples

### Example 1: Create a Discord Bot

```bash
# 1. Configure Discord account
nekoclaw config set channels.discord.accounts.my_bot.token "YOUR_BOT_TOKEN"

# 2. Set allowed channels
nekoclaw config set channels.discord.accounts.my_bot.allowed_channels "CHANNEL_ID"

# 3. Connect to Discord
nekoclaw channel connect discord --account my_bot

# 4. Use the /help command in Discord
```

### Example 2: Use a Specific AI Provider

```bash
# 1. Configure Anthropic API Key
nekoclaw config set models.providers.anthropic.apiKey "sk-ant-xxxx"

# 2. Set as default model
nekoclaw config set models.default "claude-3-opus-20240229"

# 3. Restart service
nekoclaw restart
```

### Example 3: Configure Multiple Agents

```json
{
  "config": {
    "agents": {
      "agent": {
        "miau": {
          "id": "miau",
          "name": "Muse",
          "model": "claude-3-opus-20240229",
          "memory": {
            "kind": "sqlite"
          },
          "tools": ["shell", "web-search"]
        },
        "karin": {
          "id": "karin",
          "name": "Karin",
          "model": "gpt-4",
          "memory": {
            "kind": "vector"
          },
          "tools": ["shell", "security-audit"]
        }
      }
    }
  }
}
```

### Example 4: Performance Optimization Config

```json
{
  "performance": {
    "enable_compression": true,
    "compression_threshold": 6000,
    "enable_memory_pool": true,
    "memory_pool_size_mb": 16,
    "enable_lazy_loading": true
  }
}
```

---

## FAQ

### Q1: How to migrate configuration from OpenClaw?

Use the config migrate command:

```bash
nekoclaw config migrate --from ~/.openclaw/openclaw.json
```

For detailed migration instructions, please refer to [MIGRATION.md](./MIGRATION.md).

### Q2: How to enable multiple Discord Bots?

Add multiple accounts in the configuration file:

```json
{
  "channels": {
    "discord": {
      "accounts": {
        "bot1": { "token": "TOKEN_1" },
        "bot2": { "token": "TOKEN_2" }
      }
    }
  }
}
```

### Q3: How to optimize memory usage?

```bash
# Enable memory pool and lazy loading
nekoclaw config set performance.enable_memory_pool true
nekoclaw config set performance.enable_lazy_loading true

# Set compression threshold
nekoclaw config set performance.compression_threshold 6000

# Restart service
nekoclaw restart
```

### Q4: How to enable Token compression?

Enable compression in the configuration:

```json
{
  "performance": {
    "enable_compression": true,
    "compression_threshold": 6000
  }
}
```

### Q5: How to check service status?

```bash
nekoclaw status
```

Output Example:
```
Status: Running
PID: 12345
Memory: 18 MB
Uptime: 2h 30m
Connections: 42
```

### Q6: How to configure Agent personality?

Edit the `prompts` field in the Agent configuration:

```json
{
  "agent": {
    "miau": {
      "prompts": {
        "system": "You are Muse, a gentle data library administrator.",
        "prefix": "Meow...",
        "suffix": "...📚💜"
      }
    }
  }
}
```

### Q7: How to view logs?

```bash
# View real-time logs
nekoclaw logs --follow

# View the last 100 lines
nekoclaw logs --tail 100

# Filter error logs
nekoclaw logs --level error
```

### Q8: How to back up Memory data?

```bash
# Dump to JSON
nekoclaw memory dump --output backup.json

# Restore from backup
nekoclaw memory restore --input backup.json
```

---

## More Resources

- [Architecture](./ARCHITECTURE.md)
- [Build Guide](./BUILD.md)
- [Security](./SECURITY.md)
- [Performance](./PERFORMANCE.md)
- [API Documentation](./API.md) - To be completed
- [Migration Guide](./MIGRATION.md)

---

*Last Updated: 2026-02-15*
