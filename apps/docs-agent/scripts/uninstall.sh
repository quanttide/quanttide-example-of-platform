#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/opt/docs-agent}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
APP_DIR="${APP_DIR:-$HOME/.local/share/applications}"

rm -f "$BIN_DIR/docs-agent"
rm -f "$APP_DIR/docs-agent.desktop"
rm -rf "$INSTALL_DIR"

echo "卸载完成"
