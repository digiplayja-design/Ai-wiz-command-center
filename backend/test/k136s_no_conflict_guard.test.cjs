'use strict';
// K136S no-conflict guard. Read-only git queries only. Runs in the K136S worktree.
// Fails if the branch diff (base..HEAD, plus uncommitted changes) touches any protected path,
// or if any ADDED line matches a secret pattern. K136S_BASE overrides the base ref.
const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');

const REPO = path.resolve(__dirname, '..', '..');
const BASE = process.env.K136S_BASE || 'b6de854e1ee1967826650116ab0810508166aa3d';

const FORBIDDEN_PREFIXES = [
  'backend/k135z_zoom/', 'lib/meeting_copilot/', 'test/meeting_copilot/', 'assets/meeting_copilot/',
];
const FORBIDDEN_GLOBS = [/^backend\/test\/k135z_zoom_.*\.test\.cjs$/];
const SHARED_FILES = new Set(['lib/main.dart', 'backend/server.js', 'server.js', 'pubspec.yaml', 'backend/package.json']);
const SHARED_PREFIXES = ['supabase/migrations/'];
const ALLOWED_PREFIXES = ['backend/k136s_learning/', 'docs/k136s/'];
const ALLOWED_GLOBS = [/^backend\/test\/k136s_.*\.test\.cjs$/];
const SECRET_PATTERNS = [
  /eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/,
  /\bsk-[A-Za-z0-9_-]{16,}/, /\b(sk|pk|rk)_(live|test)_[A-Za-z0-9]{12,}/, /\bAKIA[A-Z0-9]{16}\b/, /\bgh[pousr]_[A-Za-z0-9]{20,}/,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /(SUPABASE_SERVICE_ROLE_KEY|RESEND_API_KEY|OPENAI_API_KEY)\s*[:=]\s*['"][^'"]{8,}/,
];

function git(args) { return execFileSync('git', ['-C', REPO, ...args], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, env: Object.assign({}, process.env, { GIT_OPTIONAL_LOCKS: '0' }) }); }
function baseRef() { try { return git(['merge-base', BASE, 'HEAD']).trim() || BASE; } catch { return BASE; } }
function changedFiles(from) {
  const committed = git(['diff', '--name-only', `${from}..HEAD`]).split('\n');
  const trackedMods = git(['diff', '--name-only']).split('\n'); // unstaged edits to tracked files
  const staged = git(['diff', '--cached', '--name-only']).split('\n');
  // Untracked files must be listed individually; `git status --porcelain` collapses new files
  // under a directory (e.g. "?? backend/"), which would evade the per-file allow-list.
  const untracked = git(['ls-files', '--others', '--exclude-standard']).split('\n');
  return [...new Set([...committed, ...trackedMods, ...staged, ...untracked])].map((x) => x.trim()).filter(Boolean);
}
const isAllowed = (f) => ALLOWED_PREFIXES.some((p) => f.startsWith(p)) || ALLOWED_GLOBS.some((re) => re.test(f));
const isForbidden = (f) => FORBIDDEN_PREFIXES.some((p) => f.startsWith(p)) || FORBIDDEN_GLOBS.some((re) => re.test(f));
const isShared = (f) => SHARED_FILES.has(f) || SHARED_PREFIXES.some((p) => f.startsWith(p));

test('K136S branch touches only its own allowed paths', () => {
  const from = baseRef();
  const files = changedFiles(from);
  const forbidden = files.filter(isForbidden);
  const shared = files.filter(isShared);
  const foreign = files.filter((f) => !isAllowed(f) && !isForbidden(f) && !isShared(f));
  assert.deepEqual(forbidden, [], `touched K135Z-owned paths: ${forbidden.join(', ')}`);
  assert.deepEqual(shared, [], `touched shared gate files before integration: ${shared.join(', ')}`);
  assert.deepEqual(foreign, [], `touched paths outside the K136S ownership map: ${foreign.join(', ')}`);
});

test('no added line contains a secret-like value', () => {
  const from = baseRef();
  let added = '';
  try { added = git(['diff', '-U0', `${from}..HEAD`]); } catch { added = ''; }
  try { added += '\n' + git(['diff', '-U0']); } catch { /* ignore */ }
  const offenders = added.split('\n').filter((l) => l.startsWith('+') && !l.startsWith('+++')).filter((l) => SECRET_PATTERNS.some((re) => re.test(l)));
  assert.deepEqual(offenders, [], `added lines look secret-bearing:\n${offenders.slice(0, 5).join('\n')}`);
});
