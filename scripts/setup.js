#!/usr/bin/env node

/**
 * setup.js — HApi project initialization script
 *
 * Usage: node scripts/setup.js
 *
 * What it does:
 *   1. Checks if .env exists; if not, copies from .env.template
 *   2. Creates .env files for homeassistant/ and voice/ sub-projects
 *   3. Creates required directory structure
 *   4. Delegates template rendering to generate-config.js
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { loadEnv, findTemplates, renderTemplate } = require('./generate-config');

const ROOT = path.resolve(__dirname, '..');

// ---------- Utility functions ----------

function copyFile(src, dest) {
  if (!fs.existsSync(src)) {
    console.error(`❌ Source file not found: ${src}`);
    return false;
  }
  fs.copyFileSync(src, dest);
  console.log(`  ✓ ${path.relative(ROOT, dest)}`);
  return true;
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
    console.log(`  ✓ Created directory: ${path.relative(ROOT, dir)}`);
  }
}

// ---------- Main ----------

function main() {
  console.log('\n🔧 HApi Project Initialization\n');

  // Step 1: Ensure .env exists
  const rootEnv = path.join(ROOT, '.env');
  const rootEnvTemplate = path.join(ROOT, '.env.template');

  if (!fs.existsSync(rootEnv)) {
    if (fs.existsSync(rootEnvTemplate)) {
      copyFile(rootEnvTemplate, rootEnv);
      console.log('  ℹ️  .env created from .env.template — edit it with your actual values!\n');
    } else {
      console.error('❌ .env.template not found — cannot create .env');
      process.exit(1);
    }
  }

  // Step 2: Load env vars (via generate-config's shared loader)
  loadEnv();

  // Step 2.5: Persist Zigbee network keys — generate random values for GENERATE placeholders
  console.log('\n🔑 Checking Zigbee network keys...');
  const zigbeeKeys = {
    ZIGBEE_NETWORK_KEY: () => {
      const bytes = crypto.randomBytes(16);
      return '[' + Array.from(bytes).join(', ') + ']';
    },
    ZIGBEE_PAN_ID: () => String(Math.floor(Math.random() * 65534) + 1),
    ZIGBEE_EXT_PAN_ID: () => {
      const bytes = crypto.randomBytes(8);
      return '[' + Array.from(bytes).join(', ') + ']';
    },
  };
  // Old hex-format values also need regeneration (Z2M 2.x requires array format)
  const isHexFormat = (key, val) =>
    (key === 'ZIGBEE_NETWORK_KEY' && /^[0-9a-fA-F]{32}$/.test(val)) ||
    (key === 'ZIGBEE_EXT_PAN_ID' && /^[0-9a-fA-F]{16}$/.test(val));
  let envUpdated = false;
  const envFile = path.join(ROOT, '.env');
  let envContent = fs.readFileSync(envFile, 'utf8');

  for (const [key, generate] of Object.entries(zigbeeKeys)) {
    const currentVal = process.env[key];
    if (!currentVal || currentVal === 'GENERATE' || isHexFormat(key, currentVal)) {
      const val = generate();
      process.env[key] = val;
      const re = new RegExp(`^${key}=.*`, 'm');
      if (re.test(envContent)) {
        envContent = envContent.replace(re, `${key}=${val}`);
      } else {
        envContent += `\n${key}=${val}`;
      }
      const reason = isHexFormat(key, currentVal) ? ' (hex → array)' : '';
      console.log(`  ✓ ${key}=${val}${reason}`);
      envUpdated = true;
    } else {
      console.log(`  ℹ️  ${key} already set — keeping existing value`);
    }
  }

  if (envUpdated) {
    fs.writeFileSync(envFile, envContent, 'utf8');
    console.log('  📝 .env updated with generated keys');
  }

  // Step 3: Create sub-directories
  console.log('📁 Checking directory structure...');
  const dirs = [
    'homeassistant/config',
    'homeassistant/esphome-configs',
    'homeassistant/mosquitto/config',
    'homeassistant/mosquitto/data',
    'homeassistant/mosquitto/log',
    'homeassistant/zigbee2mqtt/data',
    'homeassistant/nodered/data',
    'voice/openwakeword/custom',
    'voice/vosk/data',
    'voice/piper/models',
    'satellite/config',
    'camera/config',
    'camera/recordings',
  ];
  for (const d of dirs) ensureDir(path.join(ROOT, d));

  // Step 4: Create .env for sub-projects
  console.log('\n📝 Creating sub-project .env files...');
  const haEnv = path.join(ROOT, 'homeassistant', '.env');
  fs.copyFileSync(rootEnv, haEnv);
  console.log(`  ✓ homeassistant/.env`);

  const voiceEnv = path.join(ROOT, 'voice', '.env');
  fs.copyFileSync(rootEnv, voiceEnv);
  console.log(`  ✓ voice/.env`);

  // Step 5: Generate config files from templates (delegated to generate-config)
  console.log('\n⚙️  Generating config files...');
  const projDirs = ['homeassistant', 'voice', 'satellite', 'camera'];
  for (const d of projDirs) {
    const base = path.join(ROOT, d);
    const templates = findTemplates(base);
    for (const t of templates) {
      renderTemplate(t);
    }
  }

  // Step 6: Model download hints
  console.log('\n📦 Model download hints:');
  console.log('  • Vosk model: auto-downloaded on first run (language from .env)');
  console.log('    https://alphacephei.com/vosk/models');
  console.log(`    Language: ${process.env.VOSK_LANGUAGE || 'zh'}`);
  console.log('  • Piper model: download .onnx + .json to voice/piper/models/');
  console.log('    https://huggingface.co/rhasspy/piper-voices');
  console.log(`    Recommended: ${process.env.PIPER_VOICE || 'zh_CN-huayan-medium'}`);
  console.log('  • Custom wake words: place .tflite files in voice/openwakeword/custom/\n');

  console.log('✅ Initialization complete! Check your .env file and verify settings.');
  console.log('   Start services: npm run ha:up / npm run voice:up\n');
}

main();
