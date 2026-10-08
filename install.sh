#!/usr/bin/env bash
set -e

REPO="AnmolKamat/lid-automator"
INSTALL_DIR="/usr/local/bin"

echo "🍎 MacBook Lid Automator Installer"
echo "────────────────────────────────────"

# Ensure macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "❌ Error: lid-automator only supports macOS."
    exit 1
fi

# Ensure Apple Silicon
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "⚠️ Warning: The MacBook Lid Angle Sensor ('las') is primarily available on Apple Silicon (M-series)."
fi

# Determine install target
if [[ ! -w "$INSTALL_DIR" ]]; then
    if command -v sudo >/dev/null 2>&1; then
        USE_SUDO="sudo"
    else
        INSTALL_DIR="$HOME/.local/bin"
        mkdir -p "$INSTALL_DIR"
        USE_SUDO=""
    fi
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "📦 Fetching latest lid-automator..."
cd "$TEMP_DIR"

if git clone --depth 1 "https://github.com/${REPO}.git" . >/dev/null 2>&1; then
    echo "🔨 Compiling with Swift Package Manager..."
    swift build -c release >/dev/null 2>&1
    echo "🚀 Installing binary to ${INSTALL_DIR}/lid-automator..."
    $USE_SUDO cp .build/release/lid-automator "${INSTALL_DIR}/lid-automator"
    $USE_SUDO chmod +x "${INSTALL_DIR}/lid-automator"
else
    echo "❌ Failed to clone repository."
    exit 1
fi

# Initialize default config if not present
mkdir -p "$HOME/.lid-automation"
if [[ ! -f "$HOME/.lid-automation/config" ]]; then
    cat << 'EOF' > "$HOME/.lid-automation/config"
[
  {
    "name": "Lock Screen on Low Angle (< 40°)",
    "angle": "<40",
    "trigger": "enter",
    "notify": true,
    "script": "builtin:lock",
    "enabled": true,
    "rules": {
      "cooldown": 5,
      "rearm": 45
    }
  },
  {
    "name": "Volume 80% & Ping when lid > 100°",
    "angle": ">100",
    "trigger": "enter",
    "notify": true,
    "script": "builtin:volume 80",
    "enabled": true,
    "rules": {
      "cooldown": 2,
      "rearm": 95
    }
  }
]
EOF
fi

echo ""
echo "✅ Installation complete!"
echo "   Binary installed at: ${INSTALL_DIR}/lid-automator"
echo "   Config directory:    $HOME/.lid-automation/config"
echo ""
echo "Quick start:"
echo "  lid-automator status     # Check current lid angle"
echo "  lid-automator list       # List configured automations"
echo "  lid-automator run        # Test live in terminal"
echo "  lid-automator start      # Run in background on login"
echo ""
