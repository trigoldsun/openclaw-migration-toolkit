---
name: openclaw-migration
description: OpenClaw服务器迁移工具 - 将一台Ubuntu服务器的OpenClaw所有配置、数据和状态完整迁移到另一台服务器。支持增量迁移、断点续传、自动化验证。
---

# OpenClaw 服务器迁移技能

> 将OpenClaw从源服务器完整迁移到目标服务器

## 功能特性

- ✅ **完整迁移**: 配置、数据、技能、插件全覆盖
- ✅ **增量同步**: 支持已迁移数据的增量更新
- ✅ **断点续传**: 支持迁移中断后继续
- ✅ **自动化验证**: 迁移后自动校验完整性
- ✅ **回滚机制**: 迁移失败可快速回滚
- ✅ **跨网络迁移**: 支持通过互联网传输

---

## 迁移清单

| 数据类型 | 说明 | 优先级 |
|----------|------|---------|
| Gateway配置 | gateway.json | P0 必须 |
| 插件配置 | plugins/*.json | P0 必须 |
| 技能数据 | skills/ | P0 必须 |
| 内存文件 | memory/*.md | P0 必须 |
| 会话数据 | sessions/*.jsonl | P1 推荐 |
| 定时任务 | cron jobs | P1 推荐 |
| 环境变量 | .env | P1 推荐 |
| SSH密钥 | ~/.ssh/ | P2 可选 |
| Systemd服务 | openclaw.service | P2 可选 |

---

## 使用前提

### 源服务器
- OpenClaw已安装并运行
- SSH访问权限
- 磁盘空间足够（建议>=1GB）

### 目标服务器
- Ubuntu 20.04+ 或类Debian系统
- OpenClaw已安装（或可安装）
- SSH访问权限

### 网络要求
- 两台服务器可互相SSH访问
- 或使用中转服务器/云存储

---

## 快速开始

### 方式一：服务器间直接迁移（推荐）

```bash
# 在源服务器执行
openclaw migration export --output /tmp/openclaw-backup.tar.gz

# 传输到目标服务器
scp /tmp/openclaw-backup.tar.gz user@target-server:/tmp/

# 在目标服务器执行
openclaw migration import --input /tmp/openclaw-backup.tar.gz
```

### 方式二：一键远程迁移

```bash
# 在源服务器执行，指定目标服务器
openclaw migration migrate \
  --target-host user@target-server \
  --target-port 22 \
  --components all
```

---

## 命令详解

### 1. 导出数据

```bash
openclaw migration export [选项]

选项:
  --output PATH              导出文件路径 (默认: openclaw-backup-{date}.tar.gz)
  --components LIST          要导出的组件 (默认: all)
                          可选: config,plugins,skills,memory,sessions,cron,env
  --compress METHOD         压缩方式 (默认: gzip)
                          可选: gzip, zstd, none
  --exclude PATTERN         排除的文件/目录
  --encrypt                 加密导出文件
  --password PASS           加密密码
  --split-size SIZE        分卷大小 (如: 100M, 1G)
  --dry-run                预览不执行
  --verbose                详细输出

示例:
  # 导出所有数据
  openclaw migration export --output /tmp/backup.tar.gz

  # 只导出配置和技能
  openclaw migration export --components config,skills,plugins

  # 加密导出
  openclaw migration export --encrypt --password mysecret

  # 分卷导出（每500MB一个文件）
  openclaw migration export --split-size 500M
```

### 2. 导入数据

```bash
openclaw migration import [选项]

选项:
  --input PATH              导入文件路径
  --components LIST          要导入的组件 (默认: all)
  --overwrite               覆盖已有数据
  --merge                  合并到已有数据
  --backup-before          导入前备份当前数据
  --validate               导入后验证完整性
  --dry-run                预览不执行

示例:
  # 导入所有数据
  openclaw migration import --input /tmp/backup.tar.gz

  # 只导入配置和技能
  openclaw migration import --input /tmp/backup.tar.gz --components config,skills

  # 合并模式（不覆盖已有数据）
  openclaw migration import --input /tmp/backup.tar.gz --merge

  # 导入前先备份
  openclaw migration import --input /tmp/backup.tar.gz --backup-before
```

### 3. 服务器间迁移

```bash
openclaw migration migrate [选项]

选项:
  --target-host HOST        目标服务器SSH地址
  --target-port PORT        目标服务器SSH端口 (默认: 22)
  --target-user USER        目标服务器SSH用户 (默认: 当前用户)
  --target-path PATH        目标服务器OpenClaw目录 (默认: ~/openclaw)
  --components LIST          要迁移的组件 (默认: all)
  --method METHOD           传输方式 (默认: ssh)
                          可选: ssh, rsync, s3, webdav
  --bw-limit SPEED          带宽限制 (如: 10M)
  -- incremental            增量迁移（只同步变更）
  --verify                 迁移后验证

示例:
  # 基本迁移
  openclaw migration migrate --target-host 192.168.1.100

  # 指定用户和端口
  openclaw migration migrate \
    --target-host server.example.com \
    --target-user admin \
    --target-port 2222

  # 使用rsync增量同步
  openclaw migration migrate \
    --target-host backup-server \
    --method rsync \
    --incremental
```

### 4. 状态检查

```bash
# 查看迁移状态
openclaw migration status

# 输出示例:
# Migration Status
# ─────────────────────────────
# Last Backup: 2024-01-15 10:30:00
# Backup Size:  245.6 MB
# Components:  config ✓, plugins ✓, skills ✓, memory ✓
# Sessions:    128 sessions (not migrated)
# Next Backup: in 7 days
```

### 5. 增量同步

```bash
# 配置定时增量迁移
openclaw migration schedule \
  --source /path/to/source \
  --target user@server:/path/to/target \
  --interval daily

# 手动触发增量
openclaw migration sync --incremental
```

---

## 迁移流程

### 阶段1：准备

```bash
# 1. 在源服务器创建备份
openclaw migration export --output /tmp/openclaw-backup.tar.gz

# 2. 验证备份完整性
openclaw migration validate --input /tmp/openclaw-backup.tar.gz

# 3. 在目标服务器准备目录
ssh user@target-server "mkdir -p ~/openclaw/backups"
```

### 阶段2：传输

```bash
# 方式A: SCP直接传输
scp /tmp/openclaw-backup.tar.gz user@target-server:/tmp/

# 方式B: Rsync传输（支持断点续传）
rsync -avzP --bwlimit=5M \
  /tmp/openclaw-backup.tar.gz \
  user@target-server:/tmp/

# 方式C: 分卷传输（适合大文件）
openclaw migration export --split-size 500M --output /tmp/backup
rsync -avzP /tmp/backup* user@target-server:/tmp/
```

### 阶段3：导入

```bash
# 在目标服务器执行
ssh user@target-server

# 导入前备份当前环境
openclaw migration import \
  --input /tmp/openclaw-backup.tar.gz \
  --backup-before \
  --validate

# 重启服务
openclaw gateway restart
```

### 阶段4：验证

```bash
# 验证服务状态
openclaw gateway status

# 验证数据完整性
openclaw migration validate

# 检查所有技能
openclaw skills list

# 检查会话
openclaw sessions list
```

---

## 故障排查

### 问题1：传输中断

```bash
# 使用rsync断点续传
rsync -avzP --partial \
  /tmp/openclaw-backup.tar.gz \
  user@target-server:/tmp/
```

### 问题2：权限错误

```bash
# 确保SSH密钥无密码
ssh-copy-id user@target-server

# 或使用ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa
```

### 问题3：磁盘空间不足

```bash
# 清理旧备份
openclaw migration cleanup --older-than 30d

# 或分卷压缩
openclaw migration export --split-size 100M
```

### 问题4：版本不兼容

```bash
# 检查版本
openclaw version
# 源服务器: v1.5.2
# 目标服务器: v1.4.1  ← 太旧!

# 升级目标服务器
curl -fsSL https://get.openclaw.ai | bash

# 或手动升级
wget https://releases.openclaw.ai/openclaw_latest_amd64.deb
sudo dpkg -i openclaw_latest_amd64.deb
```

---

## 高级用法

### 通过云存储中转

```bash
# 1. 上传到S3
aws s3 cp /tmp/backup.tar.gz s3://my-bucket/openclaw/

# 2. 在目标服务器下载
aws s3 cp s3://my-bucket/openclaw/backup.tar.gz /tmp/

# 3. 导入
openclaw migration import --input /tmp/backup.tar.gz
```

### 配置定时自动迁移

```bash
# 创建cron任务
openclaw migration schedule \
  --source /opt/openclaw \
  --target user@backup-server:/backups/openclaw \
  --interval daily \
  --keep-copies 7

# 查看定时任务
crontab -l
# 0 2 * * * openclaw migration sync --incremental
```

### 只迁移特定技能

```bash
# 列出所有技能
openclaw skills list

# 只迁移指定技能
openclaw migration export \
  --components skills \
  --skill-filter "feishu-*,memory-*,weather-*"
```

---

## 安全考虑

### 1. 加密敏感数据

```bash
# 使用加密导出
openclaw migration export \
  --encrypt \
  --password "$(cat ~/.migration-key)"

# 或使用GPG
gpg --symmetric --cipher-algo AES256 openclaw-backup.tar.gz
```

### 2. 安全传输

```bash
# 使用scp/ssh（已加密）
scp backup.tar.gz server:~/

# 避免使用ftp等明文协议
```

### 3. 导入前验证

```bash
# 始终验证备份
openclaw migration validate --input backup.tar.gz

# 检查文件哈希
sha256sum backup.tar.gz
```

---

## 回滚操作

```bash
# 如果迁移失败，使用备份回滚
openclaw migration rollback --to 2024-01-15-10-30-00

# 或手动回滚
cd ~/openclaw
rm -rf data.bak
mv data data.failed
mv data.old data
openclaw gateway restart
```

---

## 最佳实践

1. **定期测试备份**: 每月测试一次恢复流程
2. **增量优先**: 日常使用增量同步，减少停机时间
3. **验证完整性**: 每次迁移后验证数据
4. **保留旧版本**: 迁移后保留源服务器7天再清理
5. **记录变更**: 记录迁移日志，便于审计

---

## 输出示例

### 导出成功

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

### 迁移成功

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

*版本: 1.0*
*最后更新: 2024-01-15*
