'use strict';
// Deterministic in-memory fixtures: no repository writes, processes, or network.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, 'k136s_no_conflict_guard.test.cjs'), 'utf8');
const BASE = '63857208d2cec3a635a5a8ef536c89a2711d06c7';
const RELEASE = 'b6df78fbaac28bd6ed694787589acc42b22a0096';
const BRANCH = 'build136-k135z-integration-backend-v1-20260917T001330Z';
const ROOT = '/synthetic-k135z';
const GUARD = 'backend/test/k136s_no_conflict_guard.test.cjs';
const F5 = ['backend/korlix_live_convo_agents.js', 'backend/k136s_learning/http/mount.cjs',
  'backend/test/k136s_mount.test.cjs', 'backend/test/k136s_f5_memory_contract.test.cjs', GUARD];
const stats = paths => paths.map(p => '1\t1\t' + p + '\0').join('');
const patch = line => 'diff --git a/file b/file\n--- a/file\n+++ b/file\n@@ -0,0 +1 @@\n+' + line + '\n';
function fixture(options = {}) {
  const calls = [], registered = [], handles = new Map();
  let nextFd = 10, indexVersion = 0;
  function content(p) {
    if (p.endsWith('/.git/index')) return Buffer.from('index-' + indexVersion);
    const relative = p.slice(ROOT.length + 1);
    return Buffer.from((options.files || {})[relative] ?? 'safe fixture\n');
  }
  function metadata(p) {
    const relative = p.slice(ROOT.length + 1);
    if (relative === options.missing) { const e = new Error('missing source'); e.code = 'ENOENT'; throw e; }
    return {dev:1, ino:2, mode:0o100600, uid:1000, gid:1000, nlink:1,
      size:content(p).length, mtimeMs:123, ctimeMs:456, isFile:() => true};
  }
  const fakeFs = {
    constants:fs.constants,
    realpathSync(p) { return p === ROOT + '/' + options.link ? '/outside-linked-source' : p; },
    openSync(p) { metadata(p); const fd = nextFd++; handles.set(fd,p); return fd; },
    fstatSync(fd) { return metadata(handles.get(fd)); },
    lstatSync:metadata,
    readFileSync(fd) { return content(handles.get(fd)); },
    closeSync(fd) { handles.delete(fd); }
  };
  function exec(command, args) {
    assert.equal(command,'git');
    calls.push(args.slice());
    const a = args.slice(args.indexOf('-C') + 2);
    if (a[0] === 'rev-parse') {
      if (a.includes('--show-toplevel')) return ROOT + '\n';
      if (a.includes('--git-path')) return ROOT + '/.git/index\n';
      if (a.includes(BASE + '^{commit}')) return BASE + '\n';
      if (a.includes(RELEASE + '^{commit}')) return RELEASE + '\n';
      return (options.head || RELEASE) + '\n';
    }
    if (a[0] === 'symbolic-ref') return (options.branch || BRANCH) + '\n';
    if (a[0] === 'merge-base') {
      if (options.badAncestry || (a.includes(RELEASE) && a.includes('HEAD') && options.head && options.head !== RELEASE && !options.descendant)) throw Error('not ancestor');
      return '';
    }
    if (a[0] === 'ls-files') {
      if (a.includes('--unmerged')) return options.unmerged || '';
      return (options.untracked || []).map(p => p + '\0').join('');
    }
    if (a[0] === 'diff') {
      if (options.indexChangedOnDiff) indexVersion = 1;
      const isHistory = a.includes(BASE);
      const label = isHistory ? 'historical' : a.includes('--cached') ? 'staged' :
        a.includes(RELEASE) ? 'committed' : 'unstaged';
      if (a.includes('--numstat')) return (options.numstat || {})[label] ??
        (isHistory ? stats(F5) : '');
      if (a.includes('--name-only')) return '.github/workflows/android-debug-apk.yml\0';
      if (a.includes('--text')) return (options.patches || {})[label] || '';
    }
    throw new Error('unexpected Git invocation');
  }
  const api = vm.runInNewContext(source + '\n({numstatNames,selectPolicy,assertAllowed,inspect,scan,scanPatch,scanCredentials,INTEGRATION_ALLOWED});', {
    __dirname:ROOT + '/backend/test', Buffer, process:{env:{}},
    require(name) {
      if (name === 'node:test') return (name, fn) => registered.push({name, fn});
      if (name === 'node:fs') return fakeFs;
      if (name === 'node:child_process') return {execFileSync:exec};
      if (name === 'node:assert/strict') return assert;
      if (name === 'node:path') return path;
      throw new Error('unapproved fixture import');
    }
  }, {timeout:2000});
  return {api, calls, registered};
}
test('scope guard keeps two independent checkpoint assertions', () => {
  const f=fixture(); assert.equal(f.registered.length,2);
  for (const item of f.registered) item.fn();
});
test('scope guard selects the exact integration branch and release', () => {
  assert.equal(fixture().api.selectPolicy(BRANCH,RELEASE),'integration');
  assert.doesNotThrow(() => fixture({head:'f'.repeat(40),descendant:true}).api.inspect());
});
test('scope guard rejects a wrong integration release', () => {
  assert.throws(() => fixture({head:'f'.repeat(40)}).api.inspect(), /INSPECTION_FAILED/);
});
test('scope guard rejects an unapproved integration branch', () => {
  assert.throws(() => fixture({branch:BRANCH + '-other'}).api.inspect(), /exact branch/);
});
test('scope guard preserves the five-file legacy policy', () => {
  const f=fixture({branch:'historical-f5',head:'e'.repeat(40)}); f.api.inspect();
  assert.throws(() => f.api.assertAllowed('backend/k135z_zoom/zoom_routes.cjs',false), /unapproved F5/);
});
test('scope guard accepts exactly 43 named integration paths', () => {
  const f=fixture(); assert.equal(f.api.INTEGRATION_ALLOWED.size,43);
  for(const p of f.api.INTEGRATION_ALLOWED) f.api.assertAllowed(p,true);
  for(const p of ['backend/k135z_zoom/unapproved.cjs','backend/other.js','lib/main.dart','server.js'])
    assert.throws(() => f.api.assertAllowed(p,true), /unapproved integration/);
});
test('scope guard parses binary and mode-only content-diff entries', () => {
  const a=fixture().api;
  assert.deepEqual(Array.from(a.numstatNames('-\t-\tassets/file.bin\x000\t0\tbackend/tool.cjs\0')),
    ['assets/file.bin','backend/tool.cjs']);
});
test('scope guard rejects malformed or traversing diff records', () => {
  const a=fixture().api;
  for (const s of ['1\t1\tfile','1\t1\t../outside\0','1\t1\t/absolute\0','1\t1\t\0','x\t1\tfile\0'])
    assert.throws(() => a.numstatNames(s));
});
test('scope guard ignores stat-only filename flags by requesting content output', () => {
  const f=fixture(); f.api.inspect();
  assert(f.calls.some(a => a.includes('--numstat')));
  assert(!f.calls.some(a => a.includes('--name-only')));
});
test('scope guard still rejects actually changed unauthorized workflow content', () => {
  const f=fixture({numstat:{unstaged:stats(['.github/workflows/android-debug-apk.yml'])}});
  assert.throws(() => f.api.inspect(), /unapproved integration path/);
});
test('scope guard checks committed and staged changes independently', () => {
  for(const range of ['committed','staged']) {
    const f=fixture({numstat:{[range]:stats(['backend/unapproved.cjs'])}});
    assert.throws(() => f.api.inspect(), /unapproved integration path/);
  }
});
test('scope guard checks new untracked files against the exact list', () => {
  const f=fixture({untracked:['backend/k135z_zoom/unapproved.cjs']});
  assert.throws(() => f.api.inspect(), /unapproved integration path/);
});
test('scope guard retains the historical F5 restriction inside integration', () => {
  const f=fixture({numstat:{historical:stats(['backend/server.js'])}});
  assert.throws(() => f.api.inspect(), /unapproved F5 path/);
});
test('scope guard rejects linked and deleted changed source files', () => {
  const p='backend/server.js';
  assert.throws(() => fixture({numstat:{unstaged:stats([p])},link:p}).api.inspect(), /linked source/);
  assert.throws(() => fixture({numstat:{unstaged:stats([p])},missing:p}).api.inspect(), /missing source/);
});
test('scope guard retains every legacy credential pattern and hides the value', () => {
  const a=fixture().api;
  const values=[['eyJ','a'.repeat(12),'.','b'.repeat(12),'.','c'.repeat(12)].join(''),
    ['s','k-','A'.repeat(20)].join(''),['s','k_live_','A'.repeat(20)].join(''),
    ['A','KIA','B'.repeat(16)].join(''),['gh','p_','C'.repeat(25)].join(''),
    ['-----BEGIN ','RSA PRIVATE KEY','-----'].join(''),
    ['OPENAI_API','_KEY = "','D'.repeat(20),'"'].join('')];
  for (const value of values) {
    assert.throws(() => a.scan(value,'fixture'), e =>
      e.message.includes('value withheld') && !e.message.includes(value));
  }
});
test('scope and credential assertions report independently', () => {
  const f=fixture({numstat:{unstaged:stats(['backend/unapproved.cjs'])}});
  assert.throws(() => f.api.inspect(), /unapproved integration/);
  assert.doesNotThrow(() => f.api.scanCredentials());
});
test('scope guard detects credential-like staged additions', () => {
  const secret=['s','k-','Q'.repeat(20)].join('');
  assert.throws(() => fixture({patches:{staged:patch(secret)}}).api.scanCredentials(), /value withheld/);
});
test('scope guard scans all untracked contents including an unauthorized path', () => {
  const p='backend/unapproved.cjs', secret=['s','k-','Q'.repeat(20)].join('');
  assert.throws(() => fixture({untracked:[p],files:{[p]:secret}}).api.scanCredentials(), /value withheld/);
});
test('scope guard rejects index changes during read-only inspection', () => {
  assert.throws(() => fixture({indexChangedOnDiff:true}).api.inspect(), /index changed/);
});
test('scope guard never requests Git mutations or an index refresh', () => {
  const f=fixture(); f.api.inspect(); f.api.scanCredentials();
  for(const a of f.calls) {
    assert(a.includes('--no-optional-locks'));
    assert(a.includes('diff.autoRefreshIndex=false'));
    assert(a.includes('protocol.allow=never'));
    assert(!a.includes('--refresh'));
    assert(['rev-parse','symbolic-ref','merge-base','ls-files','diff'].includes(a[a.indexOf('-C')+2]));
  }
});
test('scope guard refuses invalid ancestry and unmerged entries', () => {
  assert.throws(() => fixture({badAncestry:true}).api.inspect(), /INSPECTION_FAILED/);
  assert.throws(() => fixture({unmerged:'conflict\0'}).api.inspect(), /unmerged entries/);
});
test('scope guard scans added hunk lines but not removed lines or patch headers', () => {
  const a=fixture().api, secret=['s','k-','Z'.repeat(20)].join('');
  assert.doesNotThrow(() => a.scanPatch('diff --git a/x b/x\n+++ ' + secret + '\n@@ -1 +1 @@\n-' + secret + '\n+safe\n','fixture'));
  assert.throws(() => a.scanPatch(patch(secret),'fixture'), /value withheld/);
});

test("Gate6A accepts only the three explicitly approved storage additions", () => {
  const f=fixture();
  for(const p of ['supabase/migrations/202609170001_k135z_b5b_storage_v1.sql', 'backend/test/k135z_b5b_storage_rpc.test.cjs', 'backend/test/fixtures/k135z_b5b_storage_rpc.sql']) {
    f.api.assertAllowed(p,true);
    assert.throws(()=>f.api.assertAllowed(p,false),/unapproved F5/);
  }
  for(const p of ["supabase/migrations/unapproved.sql","backend/test/fixtures/other.sql",
    "backend/test/k135z_b5b_storage_other.test.cjs"])
    assert.throws(()=>f.api.assertAllowed(p,true),/unapproved integration/);
});

test('Gate6G scope adds only the command migration and its database tests',()=>{
 const f=fixture();
 for(const p of ["supabase/migrations/20260918171654_k135z_workspace_commands_v1.sql", "backend/test/k135z_workspace_storage_rpc.test.cjs"]){
  f.api.assertAllowed(p,true);assert.throws(()=>f.api.assertAllowed(p,false),/unapproved F5/);
 }
 for(const p of ['supabase/migrations/other_workspace.sql','backend/test/k135z_workspace_other.test.cjs'])
  assert.throws(()=>f.api.assertAllowed(p,true),/unapproved integration/);
});

test('Gate6V package scope names only the two backend manifests',()=>{
 const f=fixture();
 for(const p of ['backend/package.json','backend/package-lock.json']) {
  f.api.assertAllowed(p,true);
  assert.throws(()=>f.api.assertAllowed(p,false),/unapproved F5/);
 }
 for(const p of ['package.json','package-lock.json','backend/npm-shrinkwrap.json',
  'backend/.npmrc','backend/submodule/package.json','backend/package.json.bak'])
  assert.throws(()=>f.api.assertAllowed(p,true),/unapproved integration/);
});

test('Gate6V package changes remain limited to the exact integration policy',()=>{
 const paths=['backend/package.json','backend/package-lock.json'];
 for(const range of ['committed','staged','unstaged'])
  assert.doesNotThrow(()=>fixture({numstat:{[range]:stats(paths)}}).api.inspect());
 assert.doesNotThrow(()=>fixture({untracked:paths}).api.inspect());
 assert.throws(()=>fixture({numstat:{historical:stats(paths)}}).api.inspect(),/unapproved F5/);
 assert.throws(()=>fixture({branch:BRANCH+'-other',untracked:paths}).api.inspect(),/exact branch/);
 for(const p of paths) {
  assert.throws(()=>fixture({numstat:{unstaged:stats([p])},link:p}).api.inspect(),/linked source/);
  assert.throws(()=>fixture({numstat:{unstaged:stats([p])},missing:p}).api.inspect(),/missing source/);
 }
});

test('Gate6V allowed package changes still undergo credential scanning',()=>{
 const p='backend/package.json',secret=['s','k-','Q'.repeat(20)].join('');
 const text=JSON.stringify({note:secret});
 const staged=fixture({numstat:{staged:stats([p])},patches:{staged:patch(text)}});
 assert.doesNotThrow(()=>staged.api.inspect());
 assert.throws(()=>staged.api.scanCredentials(),/value withheld/);
 const untracked=fixture({untracked:[p],files:{[p]:text}});
 assert.doesNotThrow(()=>untracked.api.inspect());
 assert.throws(()=>untracked.api.scanCredentials(),/value withheld/);
});
