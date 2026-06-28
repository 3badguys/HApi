#!/bin/sh
set -e

# ============================================================
# Custom Mosquitto Entrypoint
# Auto-generates password file from MQTT_USERNAME / MQTT_PASSWORD env vars
# ============================================================

if [ -z "$MQTT_USERNAME" ] || [ -z "$MQTT_PASSWORD" ]; then
    echo "❌ MQTT_USERNAME or MQTT_PASSWORD not set — check your .env file"
    exit 1
fi

rm -f /mosquitto/config/passwd
mosquitto_passwd -b -c /mosquitto/config/passwd "$MQTT_USERNAME" "$MQTT_PASSWORD"
chown mosquitto:mosquitto /mosquitto/config/passwd
chmod 0700 /mosquitto/config/passwd
echo "✓ Mosquitto password file generated for user: $MQTT_USERNAME"

# Fix ownership: mosquitto runs as UID 1883, bind mounts may be owned by root
chown -R mosquitto:mosquitto /mosquitto/data /mosquitto/log

# Start mosquitto directly (bypasses original entrypoint chain issues)
exec /usr/sbin/mosquitto -c /mosquitto/config/mosquitto.conf
