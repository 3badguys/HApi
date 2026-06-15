#!/usr/bin/env node

/**
 * generate-config.js — Generate actual config files from .template files
 *
 * Usage:
 *   node scripts/generate-config.js [ha|voice|all]    # CLI
 *   const { loadEnv, findTemplates, renderTemplate } = require('./generate-config');  # module
 *
 * What it does:
 *   Scans homeassistant/ and voice/ for .template files,
 *   replaces {{VAR_NAME}} placeholders with values from .env,
 *   and writes the result without the .template suffix.
 *
 * Convention: every .template file sits alongside its target;
 *             stripping .template yields the output path.
 *   e.g. mosquitto/config/mosquitto.conf.template → mosquitto/config/mosquitto.conf
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

// ---------- Load .env ----------

function loadEnv() {
  /** Parse root .env into process.env (does not override existing vars). */
  const envFile = path.join(ROOT, '.env');
  if (!fs.existsSync(envFile)) {
    console.error('❌ .env file not found — run "node scripts/setup.js" first');
    process.exit(1);
  }
  const content = fs.readFileSync(envFile, 'utf8');
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx === -1) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    const val = trimmed.slice(eqIdx + 1).trim();
    if (!process.env[key]) {
      process.env[key] = val;
    }
  }
}

// ---------- Find & render templates ----------

function findTemplates(baseDir) {
  /** Recursively collect all .template file paths under baseDir. */
  const results = [];
  function walk(dir) {
    if (!fs.existsSync(dir)) return;
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (['node_modules', '.git', '.esphome'].includes(e.name)) continue;
        walk(full);
      } else if (e.name.endsWith('.template')) {
        results.push(full);
      }
    }
  }
  walk(baseDir);
  return results;
}

function renderTemplate(templatePath) {
  /**
   * Read a .template file, replace {{VAR_NAME}} with process.env values,
   * write the output next to the template (without .template suffix).
   * Creates the target directory if needed.
   */
  let content = fs.readFileSync(templatePath, 'utf8');
  content = content.replace(/\{\{(\w+)\}\}/g, (_, name) => {
    const val = process.env[name];
    if (val === undefined) {
      console.warn(`  ⚠ Placeholder {{${name}}} not found in .env — left empty`);
      return '';
    }
    return val;
  });

  const outPath = templatePath.replace(/\.template$/, '');
  const outDir = path.dirname(outPath);
  if (!fs.existsSync(outDir)) {
    fs.mkdirSync(outDir, { recursive: true });
  }
  fs.writeFileSync(outPath, content, 'utf8');
  console.log(`  ✓ ${path.relative(ROOT, outPath)}`);
}

// ---------- CLI entry ----------

function main() {
  loadEnv();

  const target = process.argv[2] || 'all';
  const dirs = [];
  if (target === 'ha' || target === 'all') dirs.push('homeassistant');
  if (target === 'voice' || target === 'all') dirs.push('voice');

  if (dirs.length === 0) {
    console.log('Usage: node scripts/generate-config.js [ha|voice|all]');
    process.exit(0);
  }

  console.log(`\n⚙️  Generating configs from templates (target: ${target})\n`);

  for (const d of dirs) {
    const base = path.join(ROOT, d);
    const templates = findTemplates(base);
    if (templates.length === 0) {
      console.log(`  ℹ️  No .template files found under ${d}/`);
      continue;
    }
    for (const t of templates) {
      renderTemplate(t);
    }
  }

  console.log('\n✅ Config generation complete!\n');
}

// ---------- Exports (for use by setup.js) ----------

module.exports = { loadEnv, findTemplates, renderTemplate };

// Run CLI when invoked directly
if (require.main === module) {
  main();
}
