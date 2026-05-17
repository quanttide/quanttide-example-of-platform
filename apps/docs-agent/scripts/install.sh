#!/usr/bin/env bash
set -euo pipefail

BUNDLE_DIR="$(dirname "$0")/../build/linux/x64/release/bundle"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/opt/docs-agent}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
APP_DIR="${APP_DIR:-$HOME/.local/share/applications}"

if [ ! -f "$BUNDLE_DIR/docs_agent" ]; then
  echo "错误: 未找到构建产物，请先运行 flutter build linux --release"
  exit 1
fi

mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/data" "$BIN_DIR" "$APP_DIR"

cp "$BUNDLE_DIR/docs_agent" "$INSTALL_DIR/docs_agent"
cp -r "$BUNDLE_DIR/lib/"* "$INSTALL_DIR/lib/"
cp -r "$BUNDLE_DIR/data/"* "$INSTALL_DIR/data/"

ln -sf "$INSTALL_DIR/docs_agent" "$BIN_DIR/docs-agent"

cat > "$APP_DIR/docs-agent.desktop" << EOF
[Desktop Entry]
Type=Application
Name=文档智能体
Comment=Human-AI collaborative document editor
Exec=$INSTALL_DIR/docs_agent
Icon=$INSTALL_DIR/data/flutter_assets
Terminal=false
Categories=Office;TextEditor;
EOF

echo "安装完成: $INSTALL_DIR"
echo "运行: docs-agent"
