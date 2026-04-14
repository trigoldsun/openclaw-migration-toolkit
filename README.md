# OpenClaw Migration Toolkit

一键迁移OpenClaw服务器配置和数据到新服务器。

## 快速开始

### 方式一：服务器间直接迁移

```bash
# 1. 在源服务器执行导出
./migrate.sh export -o ~/backups

# 2. 传输到目标服务器
scp ~/backups/openclaw-backup-*.tar.gz user@target-server:~/backups/

# 3. 在目标服务器执行导入
ssh user@target-server
./migrate.sh import -i ~/backups/openclaw-backup-*.tar.gz

# 4. 重启服务
openclaw gateway restart
```

### 方式二：一键迁移

```bash
# 在源服务器执行
./migrate.sh migrate -t user@target-server -p 22
```

## 文件清单

```
openclaw-migration-skill/
├── SKILL.md          # OpenClaw技能描述文件
├── migrate.sh        # 迁移脚本
├── README.md         # 本文档
└── install.sh        # 安装脚本（可选）
```

## 迁移内容

| 组件 | 说明 | 必需 |
|------|------|------|
| Gateway配置 | gateway.json等 | ✅ |
| 插件 | plugins/*.js | ✅ |
| 技能 | skills/*.md | ✅ |
| 内存文件 | memory/*.md | ✅ |
| 会话 | sessions/*.jsonl | ⭕ |
| Cron任务 | 定时任务 | ⭕ |
| 环境变量 | .env模板 | ⭕ |

## 系统要求

- **源服务器**: OpenClaw已安装
- **目标服务器**: Ubuntu 20.04+ 或类Debian系统
- **网络**: 两台服务器可SSH互通

## 常见问题

### Q: 迁移中断怎么办？

```bash
# 使用rsync断点续传
rsync -avzP backup.tar.gz user@server:~/
```

### Q: 权限错误？

```bash
# 确保SSH无密码登录
ssh-copy-id user@target-server
```

### Q: 目标服务器OpenClaw版本太旧？

```bash
# 升级OpenClaw
curl -fsSL https://get.openclaw.ai | bash
```

## 许可证

MIT
