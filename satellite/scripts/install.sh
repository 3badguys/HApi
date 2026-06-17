#!/usr/bin/env bash
# ============================================================
# install.sh — Wyoming Satellite native install script
#
# Usage: sudo bash satellite/scripts/install.sh
#
# Prerequisites:
#   - Debian-based Linux (Raspberry Pi OS, Ubuntu, etc.)
#   - Python 3.9+
#   - A working microphone & speaker
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAT_DIR="$(dirname "$SCRIPT_DIR")"
PROJ_DIR="$(dirname "$SAT_DIR")"
CONF_FILE="$SAT_DIR/config/satellite.conf"

# ---------- Colour helpers ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------- Check root ----------
if [[ $EUID -ne 0 ]]; then
  err "This script must be run as root (sudo)"
fi

# ---------- Load config ----------
if [[ ! -f "$CONF_FILE" ]]; then
  err "Config file not found: $CONF_FILE — run 'npm run generate-config' first"
fi
set -a; source "$CONF_FILE"; set +a

info "Installing Wyoming Satellite: ${SATELLITE_NAME:-unnamed}"

# ---------- Install system dependencies ----------
info "Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq \
  python3 python3-pip python3-venv \
  alsa-utils portaudio19-dev \
  libatlas-base-dev libopenblas-dev

# ---------- Install wyoming-satellite ----------
info "Installing wyoming-satellite via pip..."
pip3 install --upgrade pip wheel setuptools 2>/dev/null
pip3 install wyoming-satellite 2>/dev/null || {
  warn "pip install from PyPI failed, trying direct GitHub install..."
  pip3 install "wyoming-satellite @ git+https://github.com/rhasspy/wyoming-satellite.git"
}

# ---------- Verify audio devices ----------
info "Checking audio devices..."
echo ""
echo "  Available capture devices (microphones):"
arecord -L 2>/dev/null | grep -E '^(plughw|hw|default|sysdefault)' | head -5 || warn "  No ALSA capture devices found — check your mic connection"
echo ""
echo "  Available playback devices (speakers):"
aplay -L 2>/dev/null | grep -E '^(plughw|hw|default|sysdefault)' | head -5 || warn "  No ALSA playback devices found — check your speaker connection"
echo ""

# ---------- Install systemd service ----------
info "Installing systemd service..."
cp "$SAT_DIR/systemd/wyoming-satellite.service" /etc/systemd/system/
sed -i "s|{{PROJ_DIR}}|$PROJ_DIR|g" /etc/systemd/system/wyoming-satellite.service
systemctl daemon-reload
systemctl enable wyoming-satellite.service
systemctl restart wyoming-satellite.service

# ---------- Done ----------
info "Installation complete!"
info "  Service status: systemctl status wyoming-satellite"
info "  View logs:      journalctl -u wyoming-satellite -f"
info ""
info "  HA integration: Settings → Devices & Services → Add Integration → Wyoming Protocol"
info "                   Host: <satellite-IP>, Port: ${SATELLITE_PORT:-10700}"
