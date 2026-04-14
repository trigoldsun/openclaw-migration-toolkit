---
name: openclaw-migration
description: OpenClaw server migration tool - Complete migration of all OpenClaw configurations, data, and states from one Ubuntu server to another. Supports incremental migration, resume from interruption, and automated verification.
---

# OpenClaw Server Migration Skill

> Complete migration of OpenClaw from source server to target server

## Features

- ✅ **Complete Migration**: Full coverage of config, data, skills, and plugins
- ✅ **Incremental Sync**: Supports incremental updates for migrated data
- ✅ **Resume from Interruption**: Supports resuming after migration interruption
- ✅ **Automated Verification**: Automatic integrity verification after migration
- ✅ **Rollback Mechanism**: Quick rollback if migration fails
- ✅ **Cross-Network Migration**: Supports transfer over the internet

---

## Migration Checklist

| Data Type | Description | Priority |
|----------|------|---------|
| Gateway Config | gateway.json | P0 Required |
| Plugin Config | plugins/*.json | P0 Required |
| Skills Data | skills/ | P0 Required |
| Memory Files | memory/*.md | P0 Required |
| Session Data | sessions/*.jsonl | P1 Recommended |
| Cron Jobs | cron jobs | P1 Recommended |
| Environment Variables | .env | P1 Recommended |
| SSH Keys | ~/.ssh/ | P2 Optional |
| Systemd Service | openclaw.service | P2 Optional |

---

## Prerequisites

### Source Server
- OpenClaw installed and running
- SSH access permissions
- Sufficient disk space (recommended >=1GB)

### Target Server
- Ubuntu 20.04+ or Debian-like system
- OpenClaw installed (or can be installed)
- SSH access permissions

### Network Requirements
- Both servers can SSH to each other
- Or use relay server/cloud storage

---

## Quick Start

### Method 1: Direct Server-to-Server Migration (Recommended)

```bash
# On source server
openclaw migration export --output /tmp/openclaw-backup.tar.gz

# Transfer to target server
scp /tmp/openclaw-backup.tar.gz user@target-server:/tmp/

# On target server
openclaw migration import --input /tmp/openclaw-backup.tar.gz
```

### Method 2: One-Click Remote Migration

```bash
# On source server, specify target server
openclaw migration migrate \
  --target-host user@target-server \
  --target-port 22 \
  --components all
```

---

## Command Reference

### 1. Export Data

```bash
openclaw migration export [options]

Options:
  --output PATH              Export file path (default: openclaw-backup-{date}.tar.gz)
  --components LIST          Components to export (default: all)
                          Optional: config,plugins,skills,memory,sessions,cron,env
  --compress METHOD         Compression method (default: gzip)
                          Optional: gzip, zstd, none
  --exclude PATTERN         Files/directories to exclude
  --encrypt                 Encrypt export file
  --password PASS           Encryption password
  --split-size SIZE         Split size (e.g.: 100M, 1G)
  --dry-run                Preview without executing
  --verbose                Verbose output

Examples:
  # Export all data
  openclaw migration export --output /tmp/backup.tar.gz

  # Export only config and skills
  openclaw migration export --components config,skills,plugins

  # Encrypted export
  openclaw migration export --encrypt --password mysecret

  # Split export (500MB per file)
  openclaw migration export --split-size 500M
```

### 2. Import Data

```bash
openclaw migration import [options]

Options:
  --input PATH              Import file path
  --components LIST          Components to import (default: all)
  --overwrite               Overwrite existing data
  --merge                  Merge with existing data
  --backup-before          Backup current data before import
  --validate               Verify integrity after import
  --dry-run                Preview without executing

Examples:
  # Import all data
  openclaw migration import --input /tmp/backup.tar.gz

  # Import only config and skills
  openclaw migration import --input /tmp/backup.tar.gz --components config,skills

  # Merge mode (don't overwrite existing data)
  openclaw migration import --input /tmp/backup.tar.gz --merge

  # Backup before import
  openclaw migration import --input /tmp/backup.tar.gz --backup-before
```

### 3. Server-to-Server Migration

```bash
openclaw migration migrate [options]

Options:
  --target-host HOST        Target server SSH address
  --target-port PORT        Target server SSH port (default: 22)
  --target-user USER        Target server SSH user (default: current user)
  --target-path PATH        Target server OpenClaw directory (default: ~/openclaw)
  --components LIST          Components to migrate (default: all)
  --method METHOD           Transfer method (default: ssh)
                          Optional: ssh, rsync, s3, webdav
  --bw-limit SPEED          Bandwidth limit (e.g.: 10M)
  -- incremental            Incremental migration (sync only changes)
  --verify                 Verify after migration

Examples:
  # Basic migration
  openclaw migration migrate --target-host 192.168.1.100

  # Specify user and port
  openclaw migration migrate \
    --target-host server.example.com \
    --target-user admin \
    --target-port 2222

  # Use rsync for incremental sync
  openclaw migration migrate \
    --target-host backup-server \
    --method rsync \
    --incremental
```

### 4. Status Check

```bash
# View migration status
openclaw migration status

# Output example:
# Migration Status
# ─────────────────────────────
# Last Backup: 2024-01-15 10:30:00
# Backup Size:  245.6 MB
# Components:  config ✓, plugins ✓, skills ✓, memory ✓
# Sessions:    128 sessions (not migrated)
# Next Backup: in 7 days
```

### 5. Incremental Sync

```bash
# Configure scheduled incremental migration
openclaw migration schedule \
  --source /path/to/source \
  --target user@server:/path/to/target \
  --interval daily

# Manually trigger incremental sync
openclaw migration sync --incremental
```

---

## Migration Process

### Phase 1: Preparation

```bash
# 1. Create backup on source server
openclaw migration export --output /tmp/openclaw-backup.tar.gz

# 2. Verify backup integrity
openclaw migration validate --input /tmp/openclaw-backup.tar.gz

# 3. Prepare directory on target server
ssh user@target-server "mkdir -p ~/openclaw/backups"
```

### Phase 2: Transfer

```bash
# Method A: Direct SCP transfer
scp /tmp/openclaw-backup.tar.gz user@target-server:/tmp/

# Method B: Rsync transfer (supports resume)
rsync -avzP --bwlimit=5M \
  /tmp/openclaw-backup.tar.gz \
  user@target-server:/tmp/

# Method C: Split transfer (for large files)
openclaw migration export --split-size 500M --output /tmp/backup
rsync -avzP /tmp/backup* user@target-server:/tmp/
```

### Phase 3: Import

```bash
# On target server
ssh user@target-server

# Backup current environment before import
openclaw migration import \
  --input /tmp/openclaw-backup.tar.gz \
  --backup-before \
  --validate

# Restart service
openclaw gateway restart
```

### Phase 4: Verification

```bash
# Verify service status
openclaw gateway status

# Verify data integrity
openclaw migration validate

# Check all skills
openclaw skills list

# Check sessions
openclaw sessions list
```

---

## Troubleshooting

### Issue 1: Transfer Interrupted

```bash
# Use rsync resume
rsync -avzP --partial \
  /tmp/openclaw-backup.tar.gz \
  user@target-server:/tmp/
```

### Issue 2: Permission Error

```bash
# Ensure SSH key has no password
ssh-copy-id user@target-server

# Or use ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa
```

### Issue 3: Insufficient Disk Space

```bash
# Clean old backups
openclaw migration cleanup --older-than 30d

# Or split compression
openclaw migration export --split-size 100M
```

### Issue 4: Version Incompatibility

```bash
# Check versions
openclaw version
# Source server: v1.5.2
# Target server: v1.4.1  ← Too old!

# Upgrade target server
curl -fsSL https://get.openclaw.ai | bash

# Or manual upgrade
wget https://releases.openclaw.ai/openclaw_latest_amd64.deb
sudo dpkg -i openclaw_latest_amd64.deb
```

---

## Advanced Usage

### Via Cloud Storage Relay

```bash
# 1. Upload to S3
aws s3 cp /tmp/backup.tar.gz s3://my-bucket/openclaw/

# 2. Download on target server
aws s3 cp s3://my-bucket/openclaw/backup.tar.gz /tmp/

# 3. Import
openclaw migration import --input /tmp/backup.tar.gz
```

### Configure Scheduled Automatic Migration

```bash
# Create cron job
openclaw migration schedule \
  --source /opt/openclaw \
  --target user@backup-server:/backups/openclaw \
  --interval daily \
  --keep-copies 7

# View scheduled tasks
crontab -l
# 0 2 * * * openclaw migration sync --incremental
```

### Migrate Specific Skills Only

```bash
# List all skills
openclaw skills list

# Migrate only specified skills
openclaw migration export \
  --components skills \
  --skill-filter "feishu-*,memory-*,weather-*"
```

---

## Security Considerations

### 1. Encrypt Sensitive Data

```bash
# Use encrypted export
openclaw migration export \
  --encrypt \
  --password "$(cat ~/.migration-key)"

# Or use GPG
gpg --symmetric --cipher-algo AES256 openclaw-backup.tar.gz
```

### 2. Secure Transfer

```bash
# Use scp/ssh (already encrypted)
scp backup.tar.gz server:~/

# Avoid using plaintext protocols like ftp
```

### 3. Verify Before Import

```bash
# Always verify backup
openclaw migration validate --input backup.tar.gz

# Check file hash
sha256sum backup.tar.gz
```

---

## Rollback Operations

```bash
# If migration fails, use backup to rollback
openclaw migration rollback --to 2024-01-15-10-30-00

# Or manual rollback
cd ~/openclaw
rm -rf data.bak
mv data data.failed
mv data.old data
openclaw gateway restart
```

---

## Best Practices

1. **Test Backups Regularly**: Test recovery process once a month
2. **Prefer Incremental**: Use incremental sync daily to reduce downtime
3. **Verify Integrity**: Verify data after each migration
4. **Keep Old Versions**: Keep source server for 7 days after migration before cleanup
5. **Log Changes**: Keep migration logs for audit purposes

---

## Output Examples

### Export Success

```
[✓] OpenClaw Migration Export
──────────────────────────────────────
Started:  2024-01-15 10:30:00
Duration: 45.2 seconds
Output:   /tmp/openclaw-backup-20240115.tar.gz
Size:     245.6 MB

Components:
  [✓] Gateway Config    3 files
  [✓] Plugins           12 files  
  [✓] Skills            28 skills
  [✓] Memory Files      156 files
  [✓] Sessions          0 sessions (excluded)
  [✓] Cron Jobs         5 jobs

Security:
  [✓] Checksum: a1b2c3d4...
  [✓] Compression: gzip (ratio: 3.2:1)

Status: SUCCESS
──────────────────────────────────────
```

### Migration Success

```
[✓] OpenClaw Migration Complete
──────────────────────────────────────
Source:   ubuntu-source (192.168.1.10)
Target:   ubuntu-target (192.168.1.20)
Duration: 2m 35s
Transferred: 245.6 MB

Verification:
  [✓] Config files: 15/15
  [✓] Skills: 28/28
  [✓] Memory: 156/156
  [✓] Plugins: 12/12

Service Status:
  [✓] Gateway: running
  [✓] Web UI: accessible
  [✓] API: responsive

Next: Restart gateway with 'openclaw gateway restart'
──────────────────────────────────────
```

---

*Version: 1.0*
*Last Updated: 2024-01-15*
