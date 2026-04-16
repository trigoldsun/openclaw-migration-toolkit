# OpenClaw Migration Toolkit

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](CHANGELOG.md)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-Architecture-green.svg)](https://docs.openclaw.ai)

用于安全迁移 OpenClaw 服务器配置和数据的命令行工具。

## 目录

- [特性](#特性)
- [快速开始](#快速开始)
- [命令参考](#命令参考)
- [使用示例](#使用示例)
- [迁移检查清单](#迁移检查清单)
- [架构说明](#架构说明)
- [安全说明](#安全说明)
- [故障排除](#故障排除)

---

## 特性

### v2.0 新增

- **OpenClaw 架构正确理解** - 理解 Gateway/WS API 架构，正确处理配置迁移
- **discover 命令** - 自动发现本地 OpenClaw 安装和配置状态
- **增量同步** - rsync 支持断点续传，只传输变更部分
- **加密传输** - GPG/OpenSSL 加密备份和传输
- **交互式向导** - 6 步引导式迁移流程
- **Canvas 状态迁移** - 支持迁移 Canvas UI 状态

### 核心功能

- 导出/导入 OpenClaw 配置、数据和状态
- 服务器间迁移
- 增量同步
- 备份验证
- 旧备份清理

---

## 快速开始

### 1. 安装

```bash
# 克隆或下载
git clone https://github.com/trigoldsun/openclaw-migration-toolkit.git
cd openclaw-migration-toolkit

# 设置执行权限
chmod +x migrate.sh
chmod +x install.sh

# 可选: 安装到系统路径
./install.sh
```

### 2. 发现本地 OpenClaw

```bash
./migrate.sh discover
```

输出示例:
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

### 3. 导出数据

```bash
# 导出所有数据
./migrate.sh export

# 加密导出
./migrate.sh export --encrypt --password mysecret

# 仅导出特定组件
./migrate.sh export -c config,skills,memory

# 指定输出目录
./migrate.sh export -o /path/to/backups
```

### 4. 服务器间迁移

```bash
# 基本迁移
./migrate.sh migrate -t user@server.example.com

# 增量同步
./migrate.sh migrate -t user@server.example.com --incremental

# 加密传输
./migrate.sh migrate -t user@server.example.com --encrypt --password mysecret
```

### 5. 交互式向导

```bash
./migrate.sh interactive
```

---

## 命令参考

### discover

发现本地 OpenClaw 安装和配置状态。

```bash
./migrate.sh discover [options]

选项:
  --json       JSON 格式输出
  --verbose    详细输出
```

### export

导出 OpenClaw 数据到备份文件。

```bash
./migrate.sh export [options]

选项:
  -o, --output DIR       输出目录 (默认: ~/.openclaw-migration/backups)
  -c, --components LIST  要导出的组件 (默认: all)
                         可选: config,providers,skills,memory,cron,env,canvas
  --encrypt              加密备份
  --password PASS        加密密码
  --split SIZE           分卷大小 (如: 500M)
  --exclude PATTERN      排除的文件模式
  -v, --verbose          详细输出
  --dry-run              预览不执行
```

**组件说明:**

| 组件 | 说明 | 敏感信息 |
|------|------|----------|
| config | Gateway 配置文件 | 已脱敏 |
| providers | Provider 元数据 | 已跳过 session |
| skills | Skills 目录 | 无 |
| memory | Memory 文件 | 无 |
| sessions | 会话历史 (可选) | 无 |
| cron | Cron 任务 | 无 |
| env | 环境变量模板 | 已脱敏 |
| canvas | Canvas 状态 | 无 |

### import

从备份文件导入数据。

```bash
./migrate.sh import -i <backup-file> [options]

选项:
  -c, --components LIST  要导入的组件
  --overwrite            覆盖已有数据
  --merge                合并模式
  --backup-first         导入前备份当前数据
  --validate             导入后验证
  --decrypt              解密备份
  --password PASS        解密密码
```

### migrate

服务器间迁移。

```bash
./migrate.sh migrate -t <target-host> [options]

选项:
  -t, --target HOST      目标服务器
  -p, --port PORT        SSH 端口 (默认: 22)
  -u, --user USER        SSH 用户 (默认: 当前用户)
  --ssh-key KEY          SSH 密钥
  --method METHOD        传输方式: scp, rsync (默认: rsync)
  --incremental           增量迁移
  --encrypt               传输加密
  --password PASS        加密密码
  --interactive          交互式模式
```

### sync

增量同步到目标服务器。

```bash
./migrate.sh sync -t <target-host> [options]

选项:
  -t, --target HOST      目标服务器
  --components LIST       要同步的组件
  --exclude PATTERN       排除模式
  --bw-limit SPEED        带宽限制 (如: 5M)
```

### status

查看迁移状态。

```bash
./migrate.sh status
```

### validate

验证备份文件完整性。

```bash
./migrate.sh validate [file]

# 如果不指定文件，验证最新的备份
./migrate.sh validate
```

### cleanup

清理旧备份。

```bash
# 清理 30 天前的备份
./migrate.sh cleanup --older-than 30d

# 清理 7 天前的备份
./migrate.sh cleanup --older-than 7d
```

### interactive

交互式迁移向导。

```bash
./migrate.sh interactive
```

---

## 使用示例

### 示例 1: 基本迁移流程

```bash
# 1. 发现本地 OpenClaw
./migrate.sh discover

# 2. 导出数据
./migrate.sh export -o /tmp/backups

# 3. 传输到目标服务器 (手动)
scp /tmp/backups/openclaw-backup-*.tar.gz user@server:/path/to/backups/

# 4. 在目标服务器导入
ssh user@server
cd openclaw-migration-toolkit
./migrate.sh import -i /path/to/backups/openclaw-backup-*.tar.gz
```

### 示例 2: 直接服务器间迁移

```bash
./migrate.sh migrate -t user@server.example.com -p 2222 -u admin
```

### 示例 3: 加密备份和迁移

```bash
# 1. 创建加密备份
./migrate.sh export --encrypt --password mysecret123

# 2. 迁移时也加密传输
./migrate.sh migrate -t user@server.example.com --encrypt --password mysecret123
```

### 示例 4: 仅迁移 Skills

```bash
./migrate.sh export -c skills -o /tmp/skills-backup
./migrate.sh import -i /tmp/skills-backup/openclaw-backup-*.tar.gz -c skills
```

### 示例 5: 增量同步

```bash
# 首次迁移
./migrate.sh migrate -t user@server.example.com

# 后续增量同步
./migrate.sh sync -t user@server.example.com --components config,skills
```

### 示例 6: 使用交互式向导

```bash
./migrate.sh interactive

# 交互式流程:
# [步骤 1/6] 检查本地 OpenClaw
# [步骤 2/6] 选择要迁移的组件
# [步骤 3/6] 输入目标服务器信息
# [步骤 4/6] 选择传输方式
# [步骤 5/6] 加密选项
# [步骤 6/6] 确认并执行
```

### 示例 7: JSON 输出用于脚本

```bash
# 获取 JSON 格式的发现报告
./migrate.sh discover --json > discovery.json

# 解析 JSON
cat discovery.json | jq '.skills.count'
cat discovery.json | jq '.providers | keys'
```

---

## 迁移检查清单

### 迁移前

- [ ] 在源服务器运行 `./migrate.sh discover` 检查 OpenClaw 状态
- [ ] 确认目标服务器已安装 OpenClaw
- [ ] 确认源和目标 OpenClaw 版本兼容
- [ ] 检查网络连通性 (SSH 端口)
- [ ] 确认目标服务器有足够磁盘空间
- [ ] 备份目标服务器现有数据 (如果有)

### 迁移中

- [ ] 创建完整备份: `./migrate.sh export`
- [ ] 验证备份: `./migrate.sh validate`
- [ ] 执行迁移: `./migrate.sh migrate -t <target>`
- [ ] 观察迁移日志

### 迁移后

- [ ] 在目标服务器运行 `./migrate.sh status`
- [ ] 检查 Gateway 状态
- [ ] **重要**: 重新配置 Provider 认证 (WhatsApp/Telegram 等)
- [ ] **重要**: 如果使用 Tailscale 或设备配对，需要重新审批
- [ ] 验证 Skills 和 Memory 数据
- [ ] 测试基本功能

---

## 架构说明

### OpenClaw 核心架构

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

### 重要说明

**OpenClaw 不是普通的文件服务器应用！**

1. **Gateway 是控制平面** - 不是数据存储
2. **每个 Gateway 实例是独立的** - 不能简单文件复制
3. **配置通过认证的 WS API 管理** - 不是配置文件
4. **有设备配对机制** - 新设备需要审批

### 迁移策略

| 数据类型 | 迁移方式 | 原因 |
|----------|----------|------|
| Gateway Config | 脱敏复制 | 需在新服务器重新认证 |
| Provider Session | **不迁移** | 包含敏感认证信息，需重新配置 |
| Skills | 直接复制 | 不包含敏感信息 |
| Memory | 直接复制 | 用户数据，可迁移 |
| Sessions | 可选 | 历史数据，可迁移 |
| Canvas State | 直接复制 | UI 状态 |
| Cron | JSON 导出 | 重新导入 |

---

## 安全说明

### 敏感信息处理

1. **自动脱敏**: 配置中的 secret/token/key/password/auth 字段会被自动替换为 `***REDACTED***`
2. **跳过 Session**: Provider session 文件不会被复制
3. **加密备份**: 使用 GPG AES256 或 OpenSSL AES-256-CBC

### 最佳实践

1. **使用加密**: 生产环境务必使用 `--encrypt`
2. **安全密码**: 使用强密码，不要使用简单密码
3. **迁移后检查**: 确认敏感信息已正确迁移
4. **清理旧备份**: 定期清理包含敏感信息的旧备份

### 已知限制

- Provider 认证信息需要在新服务器手动重新配置
- 设备配对可能需要管理员审批
- 跨版本迁移可能存在兼容性问题

---

## 故障排除

### 常见问题

#### 1. "OpenClaw 命令未找到"

```bash
# 检查 OpenClaw 是否安装
which openclaw

# 如果未安装
curl -fsSL https://get.openclaw.ai | bash
```

#### 2. "无法连接到目标服务器"

```bash
# 检查 SSH 连接
ssh -v -p <port> user@hostname

# 检查端口
ssh user@hostname -p <port> "echo ok"
```

#### 3. "导入后 Provider 无法连接"

这是正常的！Provider session 包含敏感认证信息，不会被迁移。

**解决步骤:**
1. 在目标服务器打开 OpenClaw Gateway UI
2. 进入 Provider 设置
3. 重新配置 WhatsApp/Telegram 等认证

#### 4. "设备配对失败"

**解决步骤:**
1. 在目标服务器的 OpenClaw Gateway UI
2. 进入设备管理
3. 批准新设备配对请求

#### 5. "备份文件损坏"

```bash
# 验证备份
./migrate.sh validate backup-file.tar.gz

# 重新创建备份
./migrate.sh export -o /path/to/new-backups
```

---

## 参考链接

- [OpenClaw 官方文档](https://docs.openclaw.ai)
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [OpenClaw Vision](VISION.md)

---

## 许可证

MIT License

---

*OpenClaw Migration Toolkit v2.0.0*
*Generated by Hermes01 on 2026-04-16*
