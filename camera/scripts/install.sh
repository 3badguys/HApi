#!/usr/bin/env bash
# ============================================================
# install.sh — Motion (camera motion detection) native install
#
# Usage: sudo bash camera/scripts/install.sh
#
# Prerequisites:
#   - Debian-based Linux (Raspberry Pi OS, Ubuntu, etc.)
#   - A USB or CSI camera connected
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAM_DIR="$(dirname "$SCRIPT_DIR")"
PROJ_DIR="$(dirname "$CAM_DIR")"
CONF_FILE="$CAM_DIR/config/motion.conf"

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

# Extract values for setup
CAM_DEVICE=$(grep -E '^videodevice ' "$CONF_FILE" | awk '{print $2}')
TARGET_DIR=$(grep -E '^target_dir ' "$CONF_FILE" | awk '{print $2}')

info "Installing Motion camera daemon..."

# ---------- Install motion ----------
info "Installing motion package..."
apt-get update -qq
apt-get install -y -qq motion v4l-utils

# ---------- Ensure video device exists ----------
if [[ -e "$CAM_DEVICE" ]]; then
  info "Camera found: $CAM_DEVICE"
  v4l2-ctl --list-formats-ext -d "$CAM_DEVICE" 2>/dev/null | head -10 || true
else
  warn "Camera device $CAM_DEVICE not detected."
  warn "Available video devices:"
  ls -la /dev/video* 2>/dev/null || warn "  (none found)"
  warn "Edit $CONF_FILE and set the correct device, then re-run this script."
fi

# ---------- Ensure recording directory ----------
info "Setting up recording directory: $TARGET_DIR"
mkdir -p "$TARGET_DIR"
chown motion:motion "$TARGET_DIR" 2>/dev/null || chown 109:115 "$TARGET_DIR" 2>/dev/null || true

# ---------- Deploy config ----------
info "Deploying motion config..."
cp "$CONF_FILE" /etc/motion/motion.conf
chmod 640 /etc/motion/motion.conf
chown root:motion /etc/motion/motion.conf 2>/dev/null || true

# Enable motion daemon
sed -i 's/^start_motion_daemon=.*/start_motion_daemon=yes/' /etc/default/motion 2>/dev/null || true

# ---------- Install systemd override ----------
info "Installing systemd service..."
cp "$CAM_DIR/systemd/motion.service" /etc/systemd/system/
sed -i "s|{{PROJ_DIR}}|$PROJ_DIR|g" /etc/systemd/system/motion.service
systemctl daemon-reload
systemctl enable motion.service
systemctl restart motion.service

# ---------- Done ----------
info "Installation complete!"
info ""
info "  Web control:  http://<host-IP>:$(grep webcontrol_port "$CONF_FILE" | awk '{print $2}')"
info "  Live stream:  http://<host-IP>:$(grep stream_port "$CONF_FILE" | awk '{print $2}')"
info "  Recordings:   $TARGET_DIR"
info "  Service:      systemctl status motion"
info "  Logs:         journalctl -u motion -f"
info ""
info "===== Home Assistant Integration ====="
info "Motion publishes events to MQTT. To see them in HA:"
info ""
info "  Option A — MQTT Auto Discovery (if supported by your HA version):"
info "    Motion events should appear automatically in HA."
info ""
info "  Option B — Manual MQTT binary_sensor:"
info "    Add the following to your HA configuration.yaml:"
echo ""
echo "      mqtt:"
echo "        binary_sensor:"
echo "          - name: \"Camera Motion\""
echo "            state_topic: \"motion/<camera-name>/motion\""
echo "            payload_on: \"ON\""
echo "            payload_off: \"OFF\""
echo "            device_class: motion"
echo ""
info "  Option C — motionEye addon (richer UI):"
info "    HA → Settings → Add-ons → motionEye"
info ""
info "  Option D — Generic Camera in HA:"
info "    Settings → Devices & Services → Add Integration → Generic Camera"
info "    Still Image URL: http://<host-IP>:$(grep webcontrol_port "$CONF_FILE" | awk '{print $2}')"
info "    Stream Source URL: http://<host-IP>:$(grep stream_port "$CONF_FILE" | awk '{print $2}')"
