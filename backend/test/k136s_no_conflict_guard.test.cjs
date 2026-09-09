'use strict';
// K136S-F5: exact approved scope; read-only Git inspection; no baseline override.
const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const REPO = path.resolve(__dirname, '..', '..');
const BASE = '63857208d2cec3a635a5a8ef536c89a2711d06c7';
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

const F5_ALLOWED = new Set(["backend/korlix_live_convo_agents.js", "backend/k136s_learning/http/mount.cjs", "backend/test/k136s_mount.test.cjs", "backend/test/k136s_f5_memory_contract.test.cjs", "backend/test/k136s_no_conflict_guard.test.cjs"]);

function git(args) {
  try {
    return execFileSync('git', ['--no-optional-locks', '--literal-pathspecs',
      '-c', 'core.fsmonitor=false', '-c', 'diff.autoRefreshIndex=false',
      '-C', REPO, ...args], {
      encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: 30000,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: Object.assign({}, process.env, {
        GIT_OPTIONAL_LOCKS: '0', GIT_NO_LAZY_FETCH: '1',
        GIT_NO_REPLACE_OBJECTS: '1', GIT_TERMINAL_PROMPT: '0'
      })
    });
  } catch {
    throw new Error('F5_GUARD_INSPECTION_FAILED:' + args[0]);
  }
}
const DIFF = ['--no-ext-diff', '--no-textconv', '--no-renames', '--no-relative',
  '--ignore-submodules=none', '--no-color'];
function names(text) {
  assert.ok(text === '' || text.endsWith('\0'), 'invalid Git filename response');
  return text === '' ? [] : text.slice(0, -1).split('\0');
}
function inspect() {
  assert.equal(git(['rev-parse', '--show-toplevel']).trim(), REPO);
  assert.equal(git(['rev-parse', '--verify', BASE + '^{commit}']).trim(), BASE);
  git(['merge-base', '--is-ancestor', BASE, 'HEAD']);
  assert.equal(git(['ls-files', '--unmerged', '-z']), '', 'unmerged entries');
  const ranges = [[BASE, 'HEAD'], ['--cached', 'HEAD'], []];
  const untracked = names(git(['ls-files', '--others', '--exclude-standard', '-z']));
  const changed = [...new Set([...ranges.flatMap((r) =>
    names(git(['diff', ...DIFF, '--name-only', '-z', ...r, '--']))), ...untracked])];
  for (const f of changed) {
    const forbidden = FORBIDDEN_PREFIXES.some((p) => f.startsWith(p)) ||
      FORBIDDEN_GLOBS.some((pattern) => pattern.test(f));
    const shared = SHARED_FILES.has(f) || SHARED_PREFIXES.some((p) => f.startsWith(p));
    assert.ok(!forbidden && !shared && F5_ALLOWED.has(f),
      'unapproved F5 path: ' + JSON.stringify(f));
    const p = path.join(REPO, f);
    assert.equal(fs.realpathSync(p), p, 'linked source path');
    assert.ok(fs.lstatSync(p).isFile(), 'source must remain a regular file');
  }
  return { ranges, untracked };
}
function scan(line, location) {
  assert.ok(!SECRET_PATTERNS.some((pattern) => pattern.test(line)),
    'credential-like added source at ' + location + '; value withheld');
}
function scanPatch(patch, label) {
  let inHunk = false;
  const lines = patch.split('\n');
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (line.startsWith('diff --git ')) inHunk = false;
    else if (line.startsWith('@@ ')) inHunk = true;
    else if (inHunk && line.startsWith('+')) scan(line.slice(1), label + ':' + (i + 1));
  }
}
function readNew(f) {
  const p = path.join(REPO, f);
  assert.equal(fs.realpathSync(p), p, 'linked untracked path');
  const fd = fs.openSync(p, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const before = fs.fstatSync(fd);
    assert.ok(before.isFile() && before.size <= 4 * 1024 * 1024, 'invalid untracked source');
    const data = fs.readFileSync(fd);
    const after = fs.fstatSync(fd);
    assert.equal(data.length, before.size, 'untracked size changed');
    assert.equal(after.mtimeMs, before.mtimeMs, 'untracked source changed');
    assert.equal(after.ctimeMs, before.ctimeMs, 'untracked metadata changed');
    return data.toString('utf8');
  } finally { fs.closeSync(fd); }
}
test('K136S-F5 branch touches only the five approved backend paths', () => {
  inspect();
});
test('no added line contains a secret-like value', () => {
  const { ranges, untracked } = inspect();
  for (let i = 0; i < ranges.length; i += 1)
    scanPatch(git(['diff', ...DIFF, '--text', '-U0', ...ranges[i], '--']),
      ['committed', 'staged', 'unstaged'][i]);
  for (const f of untracked)
    readNew(f).split('\n').forEach((line, i) => scan(line, f + ':' + (i + 1)));
});
