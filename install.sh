#!/usr/bin/env bash
#===============================================================================
# OpenClaw Migration Toolkit 安装脚本
#===============================================================================

set -e

INSTALL_DIR="${HOME}/.openclaw-migration"
BIN_DIR="${HOME}/bin"

echo "============================================"
echo "  OpenClaw Migration Toolkit 安装"
echo "============================================"

# 创建安装目录
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# 复制文件
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp -r "$SCRIPT_DIR/"* "$INSTALL_DIR/"

# 创建符号链接
ln -sf "$INSTALL_DIR/migrate.sh" "$BIN_DIR/openclaw-migration"
chmod +x "$INSTALL_DIR/migrate.sh"
chmod +x "$BIN_DIR/openclaw-migration"

# 添加到PATH（如果需要）
SHELL_RC="${HOME}/.bashrc"
if [[ -f "$SHELL_RC" ]]; then
    if ! grep -q 'openclaw-migration' "$SHELL_RC"; then
        echo '' >> "$SHELL_RC"
        echo '# OpenClaw Migration Toolkit' >> "$SHELL_RC"
        echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
        echo "已添加到 PATH，请运行: source $SHELL_RC"
    fi
fi

echo ""
echo "安装完成!"
echo ""
echo "使用方式:"
echo "  openclaw-migration export     # 导出数据"
echo "  openclaw-migration import     # 导入数据"
echo "  openclaw-migration migrate    # 服务器间迁移"
echo "  openclaw-migration status     # 查看状态"
echo ""
echo "详细文档: $INSTALL_DIR/README.md"
echo "============================================"
