#!/usr/bin/env bash
#===============================================================================
# OpenClaw Migration Toolkit Installation Script
#===============================================================================

set -e

INSTALL_DIR="${HOME}/.openclaw-migration"
BIN_DIR="${HOME}/bin"

echo "============================================"
echo "  OpenClaw Migration Toolkit Installation"
echo "============================================"

# Create installation directory
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# Copy files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp -r "$SCRIPT_DIR/"* "$INSTALL_DIR/"

# Create symbolic link
ln -sf "$INSTALL_DIR/migrate.sh" "$BIN_DIR/openclaw-migration"
chmod +x "$INSTALL_DIR/migrate.sh"
chmod +x "$BIN_DIR/openclaw-migration"

# Add to PATH (if needed)
SHELL_RC="${HOME}/.bashrc"
if [[ -f "$SHELL_RC" ]]; then
    if ! grep -q 'openclaw-migration' "$SHELL_RC"; then
        echo '' >> "$SHELL_RC"
        echo '# OpenClaw Migration Toolkit' >> "$SHELL_RC"
        echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
        echo "Added to PATH, please run: source $SHELL_RC"
    fi
fi

echo ""
echo "Installation complete!"
echo ""
echo "Usage:"
echo "  openclaw-migration export     # Export data"
echo "  openclaw-migration import     # Import data"
echo "  openclaw-migration migrate    # Server-to-server migration"
echo "  openclaw-migration status     # View status"
echo ""
echo "For detailed documentation: $INSTALL_DIR/README.md"
echo "============================================"
