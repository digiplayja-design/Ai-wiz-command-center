'use strict';
// K136S-F5 policy retained. K135Z Gate5 uses a separately pinned integration policy.
// No environment-selectable baseline and no index refresh or Git writes.
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

const INTEGRATION_RELEASE = 'b6df78fbaac28bd6ed694787589acc42b22a0096';
const INTEGRATION_BRANCH = 'build136-k135z-integration-backend-v1-20260917T001330Z';
const INTEGRATION_ALLOWED = new Set([
  "backend/package.json",
  "backend/package-lock.json",
  "supabase/migrations/20260918171654_k135z_workspace_commands_v1.sql",
  "backend/test/k135z_workspace_storage_rpc.test.cjs",
  "backend/k135z_copilot_notes/contract.cjs",
  "backend/k135z_copilot_notes/evidence.cjs",
  "backend/k135z_copilot_notes/minutes_preview.cjs",
  "backend/k135z_copilot_notes/notes_processor.cjs",
  "backend/k135z_copilot_notes/transcript.cjs",
  "backend/k135z_zoom/README.md",
  "backend/k135z_zoom/b1_core.cjs",
  "backend/k135z_zoom/b1_routes.cjs",
  "backend/k135z_zoom/b5b_contract.cjs",
  "backend/k135z_zoom/b5b_repository.cjs",
  "backend/k135z_zoom/config.cjs",
  "backend/k135z_zoom/index.cjs",
  "backend/k135z_zoom/oauth_state.cjs",
  "backend/k135z_zoom/zoom_meeting_discovery.cjs",
  "backend/k135z_zoom/zoom_oauth_service.cjs",
  "backend/k135z_zoom/zoom_routes.cjs",
  "backend/k135z_zoom/zoom_rtms_session_manager.cjs",
  "backend/k135z_zoom/zoom_token_vault.cjs",
  "backend/k135z_zoom/zoom_webhook.cjs",
  "backend/k135z_zoom/zoom_webhook_verifier.cjs",
  "backend/server.js",
  "backend/test/k135z_b5a_zoom_oauth_security.test.cjs",
  "backend/test/k135z_b5b_storage_security.test.cjs",
  "backend/test/k135z_korlixai_minutes.test.cjs",
  "backend/test/k135z_korlixai_notes.test.cjs",
  "backend/test/k135z_korlixai_transcript.test.cjs",
  "backend/test/k135z_scope_guard_regression.test.cjs",
  "backend/test/k135z_shared_server_integration.test.cjs",
  "backend/test/k135z_zoom_b1_core.test.cjs",
  "backend/test/k135z_zoom_b1_routes.test.cjs",
  "backend/test/k135z_zoom_security_foundation.test.cjs",
  "backend/test/k136s_no_conflict_guard.test.cjs",
  "docs/k135z/korlixai/CHECKPOINTS.md",
  "docs/k135z/korlixai/CONTRACT_V1.md",
  "docs/k135z/korlixai/fixtures/contract_v1.json",
  "supabase/migrations/202609040001_k135z_zoom_b1_foundation.sql",
  "supabase/migrations/202609170001_k135z_b5b_storage_v1.sql",
  "backend/test/k135z_b5b_storage_rpc.test.cjs",
  "backend/test/fixtures/k135z_b5b_storage_rpc.sql"
]);

function git(args) {
  assert.ok(['rev-parse','symbolic-ref','merge-base','ls-files','diff'].includes(args[0]),
    'read-only Git command required');
  try {
    return execFileSync('git', ['--no-optional-locks', '--literal-pathspecs',
      '-c', 'core.fsmonitor=false', '-c', 'diff.autoRefreshIndex=false',
      '-c', 'gc.auto=0', '-c', 'maintenance.auto=false', '-c', 'protocol.allow=never',
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
function validPath(f) {
  assert.ok(typeof f === 'string' && f.length > 0 && !path.isAbsolute(f) &&
    f.split('/').every(x => x !== '' && x !== '.' && x !== '..'), 'invalid source path');
  return f;
}
function numstatNames(text) {
  // --numstat forces content comparison; --no-renames keeps each record single-path.
  // Include binary and mode-only records; do not filter zero-line changes.
  return names(text).map(record => {
    const match = /^(\d+|-)\t(\d+|-)\t([\s\S]+)$/.exec(record);
    assert.ok(match, 'invalid content-diff record');
    return validPath(match[3]);
  });
}
function selectPolicy(branch, head) {
  if (branch === INTEGRATION_BRANCH) {
    assert.ok(/^[0-9a-f]{40}$/.test(head), 'invalid integration HEAD');
    return 'integration';
  }
  assert.ok(!branch.startsWith('build136-k135z-integration-'),
    'integration branch is not the approved exact branch');
  return 'legacy';
}
function assertAllowed(f, integration) {
  validPath(f);
  if (integration) {
    assert.ok(INTEGRATION_ALLOWED.has(f), 'unapproved integration path: ' + JSON.stringify(f));
    return;
  }
  const forbidden = FORBIDDEN_PREFIXES.some(p => f.startsWith(p)) ||
    FORBIDDEN_GLOBS.some(pattern => pattern.test(f));
  const shared = SHARED_FILES.has(f) || SHARED_PREFIXES.some(p => f.startsWith(p));
  assert.ok(!forbidden && !shared && F5_ALLOWED.has(f),
    'unapproved F5 path: ' + JSON.stringify(f));
}
function signature(s) {
  return [s.dev, s.ino, s.mode, s.uid, s.gid, s.nlink, s.size, s.mtimeMs, s.ctimeMs];
}
function stableRead(p, limit) {
  assert.equal(fs.realpathSync(p), p, 'linked source path');
  const fd = fs.openSync(p, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const before = fs.fstatSync(fd);
    assert.ok(before.isFile() && before.nlink === 1 && before.size <= limit,
      'invalid source file');
    const data = fs.readFileSync(fd);
    assert.equal(data.length, before.size, 'source size changed');
    assert.deepEqual(signature(fs.fstatSync(fd)), signature(before), 'source changed during read');
    assert.deepEqual(signature(fs.lstatSync(p)), signature(before), 'source path replaced during read');
    return data;
  } finally { fs.closeSync(fd); }
}
function withIndexUnchanged(fn) {
  const indexPath = git(['rev-parse', '--path-format=absolute', '--git-path', 'index']).trim();
  assert.ok(path.isAbsolute(indexPath), 'index path must be absolute');
  const before = stableRead(indexPath, 32 * 1024 * 1024);
  try { return fn(); }
  finally {
    assert.ok(before.equals(stableRead(indexPath, 32 * 1024 * 1024)),
      'Git index changed during read-only guard');
  }
}
function collectContext() {
  assert.equal(git(['rev-parse', '--show-toplevel']).trim(), REPO);
  assert.equal(git(['rev-parse', '--verify', BASE + '^{commit}']).trim(), BASE);
  git(['merge-base', '--is-ancestor', BASE, 'HEAD']);
  assert.equal(git(['ls-files', '--unmerged', '-z']), '', 'unmerged entries');
  const head = git(['rev-parse', '--verify', 'HEAD']).trim();
  const branch = git(['symbolic-ref', '--quiet', '--short', 'HEAD']).trim();
  const policy = selectPolicy(branch, head);
  const integration = policy === 'integration';
  if (integration) {
    assert.equal(git(['rev-parse', '--verify', INTEGRATION_RELEASE + '^{commit}']).trim(),
      INTEGRATION_RELEASE, 'integration commit unavailable');
    git(['merge-base', '--is-ancestor', BASE, INTEGRATION_RELEASE]);
    git(['merge-base', '--is-ancestor', INTEGRATION_RELEASE, 'HEAD']);
  }
  const ranges = integration ? [
    {label:'historical-F5', args:[BASE, INTEGRATION_RELEASE], integration:false},
    {label:'integration-committed', args:[INTEGRATION_RELEASE, 'HEAD'], integration:true},
    {label:'integration-staged', args:['--cached','HEAD'], integration:true},
    {label:'integration-unstaged', args:[], integration:true}
  ] : [
    {label:'committed',args:[BASE,'HEAD'],integration:false},
    {label:'staged',args:['--cached','HEAD'],integration:false},
    {label:'unstaged',args:[],integration:false}
  ];
  const untracked = names(git(['ls-files', '--others', '--exclude-standard', '-z']));
  return {ranges, untracked, integration};
}
function inspect() {
  return withIndexUnchanged(() => {
    const context = collectContext();
    for (const range of context.ranges) {
      const changed = numstatNames(git(['diff', ...DIFF, '--numstat', '-z', ...range.args, '--']));
      for (const f of changed) {
        assertAllowed(f, range.integration);
        stableRead(path.join(REPO, f), 4 * 1024 * 1024);
      }
    }
    for (const f of context.untracked) {
      assertAllowed(f, context.integration);
      stableRead(path.join(REPO, f), 4 * 1024 * 1024);
    }
    return context;
  });
}
function scan(line, location) {
  assert.ok(!SECRET_PATTERNS.some(pattern => pattern.test(line)),
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
function scanCredentials() {
  // Scope and credential assertions are independent. A scope failure is not a secret finding.
  return withIndexUnchanged(() => {
    const {ranges, untracked} = collectContext();
    for (const range of ranges) {
      scanPatch(git(['diff', ...DIFF, '--text', '-U0', ...range.args, '--']), range.label);
    }
    for (const f of untracked) {
      validPath(f);
      stableRead(path.join(REPO, f), 4 * 1024 * 1024).toString('utf8')
        .split('\n').forEach((line, i) => scan(line, f + ':' + (i + 1)));
    }
  });
}
test('branch changes satisfy pinned F5 or exact approved K135Z integration scope', () => {
  inspect();
});
test('no added line contains a secret-like value', () => {
  scanCredentials();
});
