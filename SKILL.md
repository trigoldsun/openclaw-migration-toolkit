---
name: openclaw-migration
description: OpenClaw server migration tool v2.0 - Complete migration of all OpenClaw configurations, data, and states from one Ubuntu server to another. Supports incremental migration, resume from interruption, and automated verification. Based on OpenClaw Gateway architecture.
---

# OpenClaw Server Migration Skill

> Complete migration of OpenClaw from source server to target server

## Features

- ✅ **Complete Migration**: Full coverage of config, data, skills, and plugins
- ✅ **Incremental Sync**: Supports incremental updates for migrated data (rsync)
- ✅ **Resume from Interruption**: Supports resuming after migration interruption
- ✅ **Automated Verification**: Automatic integrity verification after migration
- ✅ **Encrypted Transfer**: GPG/OpenSSL encryption for backup and transfer
- ✅ **Interactive Wizard**: 6-step guided migration process
- ✅ **OpenClaw Architecture**: Correctly understands Gateway/WS API architecture

---

## Migration Checklist

| Data Type | Description | Sensitivity | Migration Strategy |
|-----------|-------------|-------------|-------------------|
| Gateway Config | gateway.json | Medium | Export with redaction, re-auth on target |
| Provider Metadata | providers/*.json | Low | Migrate, re-authenticate sessions |
| Skills | skills/ | None | Direct copy |
| Memory Files | memory/*.md | None | Direct copy |
| Session Data | sessions/*.jsonl | None | Optional migration |
| Canvas State | canvas/ | None | Direct copy |
| Cron Jobs | cron list | None | JSON export + restore script |
| Environment Variables | .env | **High** | Template only (redacted) |

### What NOT to Migrate (Security Reasons)

| Data Type | Reason | Solution |
|-----------|--------|----------|
| Provider Sessions | Contains auth tokens/secrets | Re-authenticate on target |
| Device Pairing | Device IDs conflict | Re-pair devices |
| Auth Secrets | Security risk | Re-configure on target |

---

## Prerequisites

### Source Server
- OpenClaw installed and running (`openclaw version` should work)
- SSH access to target server
- Sufficient disk space (recommended >=1GB for full backup)

### Target Server
- Ubuntu 20.04+ or Debian-like system
- OpenClaw installed (or can be installed via `curl -fsSL https://get.openclaw.ai | bash`)
- SSH access from source server

### Network Requirements
- SSH connectivity between servers
- Target server port 22 (or custom SSH port)

---

## Quick Start

### Step 1: Discover Local OpenClaw

```bash
./migrate.sh discover
```

This will show:
- OpenClaw version and installation path
- Gateway status and port
- Provider connection status
- Skills and Memory statistics
- Cron jobs

### Step 2: Export Data

```bash
# Export all data (recommended)
./migrate.sh export

# Encrypted export
./migrate.sh export --encrypt --password mysecret

# Export specific components
./migrate.sh export -c config,skills,memory
```

### Step 3: Migrate to Target Server

```bash
# Direct server-to-server migration
./migrate.sh migrate -t user@target-server

# Incremental migration (faster for subsequent syncs)
./migrate.sh migrate -t user@target-server --incremental

# Encrypted transfer
./migrate.sh migrate -t user@target-server --encrypt --password mysecret
```

### Alternative: Interactive Wizard

```bash
./migrate.sh interactive
```

This provides a 6-step guided migration:
1. Check local OpenClaw
2. Select components to migrate
3. Enter target server info
4. Choose transfer method
5. Configure encryption
6. Confirm and execute

---

## Command Reference

### 1. Discover (`discover`)

Discover local OpenClaw installation and configuration.

```bash
./migrate.sh discover [options]

Options:
  --json       JSON format output (for scripting)
  --verbose    Detailed output

Examples:
  ./migrate.sh discover
  ./migrate.sh discover --json
```

### 2. Export (`export`)

Export OpenClaw data to backup file.

```bash
./migrate.sh export [options]

Options:
  -o, --output DIR       Output directory (default: ~/.openclaw-migration/backups)
  -c, --components      Components to export (default: all)
                        Optional: config,providers,skills,memory,sessions,cron,env,canvas
  --encrypt             Encrypt backup
  --password PASS       Encryption password
  --split SIZE          Split size (e.g.: 500M)
  --exclude PATTERN     Exclude file pattern
  -v, --verbose         Verbose output
  --dry-run             Preview without executing

Examples:
  ./migrate.sh export
  ./migrate.sh export -o /tmp/backups
  ./migrate.sh export -c config,skills --encrypt --password mysecret
```

### 3. Import (`import`)

Import data from backup file.

```bash
./migrate.sh import -i <backup-file> [options]

Options:
  -c, --components      Components to import
  --overwrite           Overwrite existing data
  --merge               Merge with existing data
  --backup-first        Backup current data before import
  --validate            Verify after import
  --decrypt             Decrypt backup
  --password PASS       Decryption password

Examples:
  ./migrate.sh import -i backup.tar.gz
  ./migrate.sh import -i backup.tar.gz --backup-first --validate
```

### 4. Migrate (`migrate`)

Server-to-server migration.

```bash
./migrate.sh migrate -t <target-host> [options]

Options:
  -t, --target HOST     Target server
  -p, --port PORT       SSH port (default: 22)
  -u, --user USER       SSH user (default: current user)
  --ssh-key KEY         SSH private key
  --method METHOD       Transfer method: scp, rsync (default: rsync)
  --incremental          Incremental migration
  --encrypt             Encrypt transfer
  --password PASS       Encryption password
  --interactive         Interactive wizard mode

Examples:
  ./migrate.sh migrate -t user@server.example.com
  ./migrate.sh migrate -t user@server -p 2222 -u admin --incremental
```

### 5. Sync (`sync`)

Incremental sync to target server.

```bash
./migrate.sh sync -t <target-host> [options]

Options:
  -t, --target HOST     Target server
  -c, --components      Components to sync
  --exclude PATTERN      Exclude pattern
  --bw-limit SPEED       Bandwidth limit (e.g.: 5M)

Examples:
  ./migrate.sh sync -t user@server
  ./migrate.sh sync -t user@server -c config,skills --bw-limit 10M
```

### 6. Status (`status`)

View migration status.

```bash
./migrate.sh status
```

### 7. Validate (`validate`)

Verify backup integrity.

```bash
./migrate.sh validate [file]

# Validate latest backup
./migrate.sh validate
```

### 8. Cleanup (`cleanup`)

Clean up old backups.

```bash
./migrate.sh cleanup --older-than 30d
```

---

## Migration Process

### Phase 1: Pre-Migration Check

```bash
# 1. Discover local OpenClaw
./migrate.sh discover

# 2. Verify OpenClaw is running
openclaw gateway status

# 3. Check target server connectivity
ssh -v user@target-server "echo ok"

# 4. Verify target has OpenClaw installed
ssh user@target-server "openclaw version"
```

### Phase 2: Export

```bash
# 1. Create backup
./migrate.sh export -o /tmp/backups

# 2. Validate backup
./migrate.sh validate /tmp/backups/openclaw-backup-*.tar.gz

# 3. Check backup size
ls -lh /tmp/backups/openclaw-backup-*.tar.gz
```

### Phase 3: Transfer

```bash
# Method A: Direct migration (recommended)
./migrate.sh migrate -t user@target-server --incremental

# Method B: Manual transfer
scp /tmp/backups/openclaw-backup-*.tar.gz user@target-server:/tmp/

# Method C: Rsync for large files
rsync -avzP --bwlimit=5M /tmp/backups/ user@target-server:/tmp/backups/
```

### Phase 4: Import

```bash
# On target server
./migrate.sh import -i /tmp/openclaw-backup-*.tar.gz --validate

# Restart Gateway
openclaw gateway restart
```

### Phase 5: Post-Migration

```bash
# 1. Verify status
./migrate.sh status
openclaw gateway status

# 2. Re-authenticate providers (REQUIRED!)
#    - WhatsApp: Open Gateway UI -> Providers -> WhatsApp -> Scan QR
#    - Telegram: Open Gateway UI -> Providers -> Telegram -> Re-bot

# 3. Re-pair devices if needed
#    - Gateway UI -> Devices -> Approve pending devices

# 4. Verify skills and memory
./migrate.sh discover --json | jq '.skills, .memory'
```

---

## OpenClaw Architecture (Important)

```
┌─────────────────────────────────────────────────────────────┐
│                      OpenClaw Gateway                       │
│                   (127.0.0.1:18789)                        │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  Control    │  │   Node      │  │   Provider          │ │
│  │  Plane      │  │   Role      │  │   Connections        │ │
│  │  Clients    │  │             │  │   (WhatsApp, etc.)  │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│                                                              │
│              ┌───────────────────────┐                       │
│              │   WebSocket API       │                       │
│              │   (Typed Protocol)    │                       │
│              └───────────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

**Key Points:**

1. **Gateway is Control Plane** - Not a data store
2. **WS API manages configuration** - Not simple config files
3. **Provider sessions are independent** - Cannot simply copy
4. **Device pairing mechanism** - New devices need approval

---

## Troubleshooting

### Issue 1: "OpenClaw command not found"

```bash
# Check if OpenClaw is installed
which openclaw
command -v openclaw

# If not installed
curl -fsSL https://get.openclaw.ai | bash

# Or check common paths
ls -la /usr/local/bin/openclaw
ls -la ~/.local/bin/openclaw
```

### Issue 2: "Cannot connect to target server"

```bash
# Test SSH connection
ssh -v -p <port> user@hostname

# Check if SSH daemon is running (on target)
ssh user@hostname "systemctl status sshd"

# Check firewall (on target)
ssh user@hostname "sudo ufw status"
```

### Issue 3: "Provider not connecting after migration"

**This is NORMAL!** Provider sessions contain sensitive auth tokens and cannot be migrated for security reasons.

```bash
# Re-authenticate provider:
# 1. Open Gateway UI (http://target-server:18789)
# 2. Go to Settings -> Providers
# 3. Select provider (WhatsApp/Telegram/etc.)
# 4. Re-authenticate (scan QR or re-bot)
```

### Issue 4: "Device pairing failed"

```bash
# On target server Gateway UI:
# 1. Go to Settings -> Devices
# 2. Find pending device approval
# 3. Click "Approve"
```

### Issue 5: "Backup file corrupted"

```bash
# Verify backup
./migrate.sh validate backup-file.tar.gz

# Recreate backup
./migrate.sh export -o /path/to/new-backups

# Check checksum
sha256sum backup-file.tar.gz
cat backup-file.tar.gz.sha256
```

---

## Security Best Practices

1. **Always use encryption**: `--encrypt --password <secret>`
2. **Use strong passwords**: Avoid simple passwords
3. **Verify backups**: Always validate before migration
4. **Re-authenticate providers**: Don't copy provider sessions
5. **Clean old backups**: Regularly clean old backups with sensitive data
6. **Check target server security**: Ensure target server is secure

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2026-04-16 | Major rewrite with OpenClaw architecture understanding, discover command, incremental sync, encrypted transfer, interactive wizard |
| 1.0.0 | 2024-01-15 | Initial release |

---

## Output Examples

### Discover Command

```
========================================
    OpenClaw Discovery Report
========================================

[1/6] OpenClaw 命令发现
----------------------------------------
  ✓ 命令: /usr/local/bin/openclaw
  ✓ 版本: v1.5.2

[2/6] Gateway 配置
----------------------------------------
  ✓ Gateway进程: 运行中
  ✓ 端口 18789: 已监听
  ✓ gateway.json: 存在

[3/6] Provider 连接
----------------------------------------
  ✓ whatsapp: 已连接
  ✓ telegram: 已连接

[4/6] Skills
----------------------------------------
  ✓ Skills数量: 28
  ✓ Skills大小: 15M

[5/6] Memory 和 Sessions
----------------------------------------
  ✓ Memory文件: 156 (23M)
  ✓ Sessions: 12 (8.2G)

[6/6] Cron 任务
----------------------------------------
  ✓ Cron任务: 5 个
```

### Export Success

```
[INFO] 开始导出OpenClaw数据...
[INFO] 版本: v2.0.0
[INFO] 输出: /home/user/.openclaw-migration/backups/openclaw-backup-20260416_143022.tar.gz
[✓] 配置: gateway.json
[✓] 配置: channels.json
[✓] Providers: 2 个 (元数据)
[WARN] 认证信息需要在新服务器重新配置
[✓] Skills: 28 个 (15M)
[✓] Memory: 156 文件 (23M)
[✓] Cron任务: 5 个任务
[✓] 环境变量: 已导出模板(已脱敏)
[✓] Canvas: 2.3M
[INFO] 正在打包...
[SUCCESS] 导出完成!

================================
导出成功!
================================
文件: /home/user/.openclaw-migration/backups/openclaw-backup-20260416_143022.tar.gz
大小: 45.2M
校验: a1b2c3d4e5f6...
================================
```

### Migration Success

```
================================
OpenClaw Migration v2.0.0
================================
源服务器: ubuntu-source
目标服务器: user@ubuntu-target
传输方式: rsync
模式: 增量迁移
================================
[INFO] 预检查...
[✓] SSH连接: OK
[INFO] 目标可用空间: 50G
[✓] OpenClaw: 已安装
[INFO] [1/3] 导出数据...
[SUCCESS] 导出完成
[INFO] [2/3] 传输数据...
[SUCCESS] 传输完成
[INFO] [3/3] 在目标服务器导入...
[SUCCESS] 导入完成!
================================
迁移成功!
================================
目标服务器: user@ubuntu-target
请在目标服务器验证Gateway状态
Provider需要重新认证
================================
```

---

## References

- [OpenClaw Official Docs](https://docs.openclaw.ai)
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [Migration Toolkit GitHub](https://github.com/trigoldsun/openclaw-migration-toolkit)

---

*Version: 2.0*
*Last Updated: 2026-04-16*
*Generated by Hermes01*
