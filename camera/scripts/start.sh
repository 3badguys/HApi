#!/usr/bin/env bash
# ============================================================
# start.sh — Quick-start Motion for debugging
#
# Usage: bash camera/scripts/start.sh
#
# Runs motion in the foreground with verbose logging.
# Ctrl+C to stop. For production, use systemd instead.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAM_DIR="$(dirname "$SCRIPT_DIR")"
CONF_FILE="$CAM_DIR/config/motion.conf"

if [[ ! -f "$CONF_FILE" ]]; then
  echo "ERROR: Config file not found: $CONF_FILE"
  echo "Run 'npm run generate-config' first."
  exit 1
fi

echo "Starting Motion with config: $CONF_FILE"
echo "  Web control:  http://localhost:$(grep webcontrol_port "$CONF_FILE" | awk '{print $2}')"
echo "  Live stream:  http://localhost:$(grep stream_port "$CONF_FILE" | awk '{print $2}')"
echo "  Press Ctrl+C to stop."
echo ""

# Run motion in foreground (no daemon), log to stdout
exec motion -n -c "$CONF_FILE"
