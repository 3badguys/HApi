#!/usr/bin/env bash
# ============================================================
# start.sh — Quick-start Wyoming Satellite for debugging
#
# Usage: bash satellite/scripts/start.sh
#
# Runs wyoming-satellite in the foreground.
# Ctrl+C to stop. For production, use systemd instead.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAT_DIR="$(dirname "$SCRIPT_DIR")"
CONF_FILE="$SAT_DIR/config/satellite.conf"

if [[ ! -f "$CONF_FILE" ]]; then
  echo "ERROR: Config file not found: $CONF_FILE"
  echo "Run 'npm run generate-config' first."
  exit 1
fi

set -a; source "$CONF_FILE"; set +a

echo "Starting Wyoming Satellite: ${SATELLITE_NAME:-unnamed}"
echo "  URI:       ${SATELLITE_URI:-tcp://0.0.0.0:10700}"
echo "  Mic:       ${MIC_DEVICE:-default}"
echo "  Speaker:   ${SPEAKER_DEVICE:-default}"
echo "  Wake URI:  ${WAKE_URI:-tcp://127.0.0.1:10400}"
echo "  STT URI:   ${STT_URI:-tcp://127.0.0.1:10300}"
echo "  TTS URI:   ${TTS_URI:-tcp://127.0.0.1:10200}"
echo ""

exec wyoming-satellite \
  --name "${SATELLITE_NAME:-Wyoming Satellite}" \
  --uri "${SATELLITE_URI:-tcp://0.0.0.0:10700}" \
  --mic-command "${MIC_COMMAND:-arecord -D default -r 16000 -c 1 -f S16_LE -t raw}" \
  --snd-command "${SND_COMMAND:-aplay -D default -r 22050 -c 1 -f S16_LE -t raw}" \
  --wake-uri "${WAKE_URI:-tcp://127.0.0.1:10400}" \
  --stt-uri "${STT_URI:-tcp://127.0.0.1:10300}" \
  --tts-uri "${TTS_URI:-tcp://127.0.0.1:10200}" \
  ${WAKE_WORD_NAME:+--wake-word-name "$WAKE_WORD_NAME"} \
  --volume-multiplier "${VOLUME_MULTIPLIER:-1.0}" \
  $([[ "${NOISE_SUPPRESSION:-1}" == "1" ]] && echo "--noise-suppression" || echo "") \
  $([[ "${AUTO_GAIN:-1}" == "1" ]] && echo "--auto-gain" || echo "") \
  $([[ "${DEBUG:-0}" == "1" ]] && echo "--debug" || echo "")
