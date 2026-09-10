#!/usr/bin/env bash
set -euo pipefail

# Default ECO if not provided
ECO=${ECO:-/root/workspaces/tools/ecosystem.config.js}
export ECO

node <<'NODE'
const cp = require('child_process');
const path = require('path');

const ecoPath = process.env.ECO || '/root/workspaces/tools/ecosystem.config.js';
let declared = [];
try { const conf = require(ecoPath); declared = Array.isArray(conf.apps) ? conf.apps : []; } catch { declared = []; }

let live = [];
try { const out = cp.execSync('pm2 jlist', {stdio:['ignore','pipe','ignore']}).toString(); live = JSON.parse(out); } catch { live = []; }

const byName = new Map();
for (const app of declared) {
  const name = (app && (app.name || app.script)) ? String(app.name || app.script) : '';
  if (!name) continue;
  const baseCwdRaw = app && app.cwd ? String(app.cwd) : path.dirname(ecoPath);
  const baseCwd = path.normalize(path.isAbsolute(baseCwdRaw) ? baseCwdRaw : path.resolve(path.dirname(ecoPath), baseCwdRaw));
  const script = app && app.script ? String(app.script) : '';
  const expectedExecPath = path.normalize(path.isAbsolute(script) ? script : path.resolve(baseCwd, script));
  byName.set(name, { expectedExecPath, declaredCwd: baseCwd });
}

let issues = 0;
const seenLive = new Set();

for (const p of live) {
  const name = String((p && p.name) || (p && p.pm2_env && p.pm2_env.name) || (p && p.pm2_env && p.pm2_env.pm_id) || '');
  if (name) seenLive.add(name);
  const env = (p && p.pm2_env) || {};
  const liveExecPath = env.pm_exec_path ? path.normalize(env.pm_exec_path) : '';
  const liveCwd = env.pm_cwd ? path.normalize(env.pm_cwd) : '';
  const status = String(env.status || '');
  const pid = Number(p && p.pid || 0);

  if (!byName.has(name)) { console.log(`UNDECLARED ${name}`); issues++; }
  if (status === 'online' && (!pid || pid <= 0)) { console.log(`PHANTOM ${name}`); issues++; }

  const decl = byName.get(name);
  if (decl) {
    if (decl.expectedExecPath !== liveExecPath) { console.log(`DIVERGE ${name} script`); issues++; }
    if (decl.declaredCwd !== liveCwd) { console.log(`DIVERGE ${name} cwd`); issues++; }
  }
}

for (const name of byName.keys()) {
  if (!seenLive.has(name)) { console.log(`MISSING ${name}`); issues++; }
}

console.log(`TOTAL ${issues}`);
process.exit(issues === 0 ? 0 : 1);
NODE
