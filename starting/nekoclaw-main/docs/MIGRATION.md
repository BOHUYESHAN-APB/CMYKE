# Neko-Claw Migration Guide

## OpenClaw → Neko-Claw Config Migration Manual

> 🔐 This document was written by Karin (Fiora) - 2026-02-15

---

## Table of Contents

1. [Overview](#overview)
2. [Why Migrate?](#why-migrate)
3. [Prerequisites](#prerequisites)
4. [Config File Migration](#config-file-migration)
5. [Identity File Migration](#identity-file-migration)
6. [FAQ](#faq)
7. [Rollback Plan](#rollback-plan)

---

## Overview

This document guides users on how to smoothly migrate their existing OpenClaw configuration to Neko-Claw.

Neko-Claw is a high-performance Rust rewrite of OpenClaw, offering:
- **Lower Resource Usage**: <20MB RAM vs OpenClaw's 1.5GB.
- **Faster Startup**: <100ms startup time.
- **Stronger Security**: Built-in sandbox and encryption modules.

---

## Why Migrate?

### Performance Comparison

| Metrics | OpenClaw | Neko-Claw | Improvement |
|------|----------|-----------|------|
| Memory Usage | ~1500MB | <20MB | **75x** ⬇️ |
| Startup Time | ~5000ms | <100ms | **50x** ⬆️ |
| Binary Size | N/A | <2.5MB | - |
| Response Time | ~1000ms | <10ms | **100x** ⬆️ |

### Feature Comparison

| Feature | OpenClaw | Neko-Claw |
|------|----------|-----------|
| Provider Support | ✅ | ✅ |
| Memory System | ✅ | ✅ (SQLite + Vector) |
| Multi-channel Support | ✅ | ✅ (Discord + Telegram) |
| Agent Integration | ✅ | ✅ |
| OAuth Auth | ✅ | ✅ |
| Security Sandbox | ❌ | ✅ (Whitelist + Injection Protection) |

---

## Prerequisites

### System Requirements

```bash
# Minimum requirements
- Rust 1.70+
- 512MB available RAM
- 100MB disk space
```

### Install Rust (if not installed)

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
rustc --version  # Confirm version >= 1.70
```

### Back up Existing Config

**Important**: Please back up your existing configuration before migration!

```bash
# Back up OpenClaw config directory
cp -r ~/.openclaw ~/.openclaw.backup.$(date +%Y%m%d)

# Back up config file
cp ~/openclaw.json ~/openclaw.json.backup
```

---

## Config File Migration

### OpenClaw Config Structure

OpenClaw uses `openclaw.json` as the main configuration file:

```json
{
  "models": {
    "providers": {
      "nvidia": {
        "apiKey": "YOUR_API_KEY",
        "endpoint": "https://api.nvidia.com",
        "models": ["model-1", "model-2"]
      }
    },
    "defaults": {
      "model": {
        "primary": "nvidia:model-name"
      }
    }
  },
  "channels": {
    "discord": {
      "accounts": {
        "main_bot": {
          "token": "YOUR_DISCORD_TOKEN",
          "permissions": 8
        }
      }
    }
  },
  "agents": {
    "defaults": {
      "thinking": true
    }
  },
  "auth": {
    "profiles": [
      {
        "name": "discord",
        "provider": "discord",
        "enabled": true
      }
    ]
  }
}
```

### Neko-Claw Config Structure

Neko-Claw uses `config.toml` (or `config.json`):

```toml
# Neko-Claw Config Example
app_name = "Neko-Claw"
version = "0.5.0"

[provider.nvidia]
api_key = "YOUR_API_KEY"
endpoint = "https://api.nvidia.com"
models = ["model-1", "model-2"]
default_model = "model-1"

[channel.discord]
token = "YOUR_DISCORD_TOKEN"
enabled = true

[channel.telegram]
token = "YOUR_TELEGRAM_BOT_TOKEN"
enabled = false

[memory]
backend = "sqlite"
vector_backend = "memory"

[security]
enable_sandbox = true
enable_encryption = true

[agent]
thinking_enabled = true
max_tokens = 4096
temperature = 0.7
```

### Manual Migration Steps

#### 1. Create Config Directory

```bash
mkdir -p ~/.nekoclaw
cd ~/.nekoclaw
```

#### 2. Create config.toml

Based on your OpenClaw configuration, create the corresponding `config.toml`:

```bash
# Copy example config
cp /path/to/nekoclaw/config.example.toml ~/.nekoclaw/config.toml

# Edit config
nano ~/.nekoclaw/config.toml
```

#### 3. Migrate Provider Config

**OpenClaw → Neko-Claw Mapping:**

```toml
# OpenClaw: models.providers.nvidia
# Neko-Claw: [provider.nvidia]

[provider.nvidia]
api_key = "YOUR_API_KEY"
endpoint = "https://api.nvidia.com"
models = ["model-1", "model-2"]
default_model = "model-1"
```

#### 4. Migrate Channel Config

**Discord Migration:**

```toml
# OpenClaw: channels.discord.accounts.{bot_name}.token
# Neko-Claw: [channel.discord]

[channel.discord]
token = "YOUR_DISCORD_TOKEN"
enabled = true
```

**Telegram Migration:**

```toml
# Neko-Claw: [channel.telegram]
[channel.telegram]
token = "YOUR_TELEGRAM_BOT_TOKEN"
enabled = false  # Set to true to enable
```

#### 5. Migrate Agent Config

```toml
# OpenClaw: agents.defaults
# Neko-Claw: [agent]

[agent]
thinking_enabled = true
max_tokens = 4096
temperature = 0.7
context_window = 8192
session_timeout = 1800  # 30 minutes
```

#### 6. Migrate Auth Config

```toml
# OpenClaw: auth.profiles
# Neko-Claw: [auth.profiles]

[[auth.profile]]
name = "discord"
provider = "discord"
client_id = "YOUR_CLIENT_ID"
client_secret = "YOUR_CLIENT_SECRET"
enabled = true
```

---

## Identity File Migration

### File Location Comparison

| File | OpenClaw | Neko-Claw |
|------|----------|-----------|
| Identity | `~/.openclaw/IDENTITY.md` | `~/.nekoclaw/IDENTITY.md` |
| Soul | `~/.openclaw/SOUL.md` | `~/.nekoclaw/SOUL.md` |
| Agents | `~/.openclaw/AGENTS.md` | `~/.nekoclaw/AGENTS.md` |

### Migration Steps

```bash
# 1. Copy files
cp ~/.openclaw/IDENTITY.md ~/.nekoclaw/
cp ~/.openclaw/SOUL.md ~/.nekoclaw/
cp ~/.openclaw/AGENTS.md ~/.nekoclaw/

# 2. Verify files
ls -la ~/.nekoclaw/*.md

# 3. Check permissions
chmod 600 ~/.nekoclaw/*.md
```

### Config File Formats

**IDENTITY.md** - Keep unchanged, just copy:

```markdown
# Identity
...

## Personality
- **Name:** Your Name
- **Tone:** Style
```

**SOUL.md** - Keep unchanged, just copy:

```markdown
# Soul
...
```

**AGENTS.md** - Keep unchanged, just copy:

```markdown
# Agents
...
```

---

## Migration Verification

### Run Health Check

After migration, run the health check to verify configuration:

```bash
cd /path/to/nekoclaw
cargo run -- doctor --fix
```

### Verify Project

```bash
# Check config loading
cargo run -- config --show

# Check service status
cargo run -- service --status

# Check all modules
cargo run -- status --verbose
```

### Common Errors

#### 1. Invalid API Key

```error
Error: Invalid API key for provider 'nvidia'
```

**Resolution**: Check if `api_key` in `config.toml` is correct.

#### 2. Invalid Discord Token

```error
Error: Invalid Discord token
```

**Resolution**: 
1. Confirm the Token is a Bot Token (starting with `MTE`).
2. Check if the Token is correctly configured in `config.toml`.

#### 3. Missing Identity Files

```error
Error: IDENTITY.md not found
```

**Resolution**: Copy `IDENTITY.md` to the `~/.nekoclaw/` directory.

---

## FAQ

### Q1: Can I continue using OpenClaw after migration?

**Yes**, but it's recommended to test Neko-Claw first and confirm functionality before switching permanently.

### Q2: What if the config files are incompatible?

Neko-Claw provides a **Config Compatibility Layer** that can read partial OpenClaw configurations:

```bash
# Use OpenClaw config file
nekoclaw --config ~/openclaw.json agent --message "hello"
```

### Q3: How to roll back to OpenClaw?

```bash
# Restore config backup
cp -r ~/.openclaw.backup.* ~/.openclaw

# Delete Neko-Claw config (optional)
rm -rf ~/.nekoclaw
```

### Q4: What if performance doesn't improve?

1. Ensure you are compiling in Release mode:
   ```bash
   cargo build --release
   ```

2. Check system resources:
   ```bash
   cargo run -- doctor --verbose
   ```

### Q5: How to migrate Docker deployment?

```dockerfile
# Use Neko-Claw image
FROM ghcr.io/gengetau/nekoclaw:latest

# Mount config
VOLUME ["/root/.nekoclaw"]

# Run
CMD ["nekoclaw", "daemon", "--background"]
```

---

## Rollback Plan

### Quick Rollback

```bash
# Stop Neko-Claw
nekoclaw service --stop

# Restore OpenClaw config
cp -r ~/.openclaw.backup.* ~/.openclaw

# Delete Neko-Claw config
rm -rf ~/.nekoclaw

# Restart OpenClaw
openclaw start
```

### Config Comparison Table

| Config Item | OpenClaw | Neko-Claw | Compatibility |
|--------|----------|-----------|--------|
| Provider API Key | ✅ | ✅ | Fully Compatible |
| Discord Token | ✅ | ✅ | Fully Compatible |
| Memory Data | ❌ | ✅ | Requires export/import |
| Agent Config | ✅ | ✅ | Fully Compatible |
| Auth Profiles | ✅ | ✅ | Fully Compatible |

---

## Contact Support

If you encounter issues during migration:

1. View logs: `~/.nekoclaw/logs/nekoclaw.log`
2. Run diagnostics: `nekoclaw doctor --verbose`
3. Submit Issue: https://github.com/Gengetau/nekoclaw/issues

---

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-15 | 0.5.0 | Initial version |
| 2026-02-15 | 0.5.1 | Added Docker migration instructions |

---

**🔒 Karin's Security Tips:**

> Always back up your existing configuration during migration! Don't migrate directly in production; verify in a test environment first.
>
> After migration, please remove sensitive information (like API Keys) from `openclaw.json`.

---

*This document was written by the Neko-Claw team - Cat-Girl Family*
