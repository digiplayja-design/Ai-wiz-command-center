import {randomUUID} from 'node:crypto';
import {check, hash, opaque, sealPart, openPart, MAX_CATALOG} from './archive.mjs';
import {inventoryDigest} from './postgres.mjs';
import {readBoundedStream} from '../receipt_backup/backblaze.mjs';

export const RECOVERY_ENV_KEYS = ['KORLIX_ZOOM_TOKEN_ENCRYPTION_KEY', 'KORLIX_SCHEDULING_TOKEN_KEY',
  'KORLIX_GOOGLE_ADS_TOKEN_KEY', 'KORLIX_META_TOKEN_KEY', 'PAYROLL_TOKEN_ENCRYPTION_KEY'];
const REPO = 'digiplayja-design/Ai-wiz-command-center';
const FRONTEND_BRANCH = 'release/k135z-frontend-20260919';

export function recoveryConfiguration(env) {
  // Explicit allowlist: no general process.env export, backup credential, master key or service-role key.
  const settings = Object.fromEntries(Object.entries(env).filter(([name, value]) => {
    if (/_URL$|_URI$/.test(name)) {
      try { const url = new URL(value); if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) return false; }
      catch { return false; }
    }
    return /^(KORLIX_|PAYROLL_|GUSTO_|SUPABASE_)/.test(name)
      && !name.startsWith('KORLIX_BACKUP_')
      && /_(ENABLED|MODE|URL|URI|REGION|BUCKET|PREFIX|MODEL|VERSION|FROM_EMAIL|CLIENT_ID|APP_ID|LIMIT|CAP)$/.test(name)
      && !/(SECRET|TOKEN|PASSWORD|KEY|CREDENTIAL|AUTHORIZATION)/.test(name)
      && typeof value === 'string' && value.length <= 4096;
  }));
  return {version: 1, encryptionKeys: Object.fromEntries(RECOVERY_ENV_KEYS.filter(k => env[k]).map(k => [k, env[k]])),
    settings,
    environmentVariableNames: Object.keys(env).filter(k => /^(KORLIX_|LIVE_STUDIO_|PAYROLL_|GUSTO_|SUPABASE_|RECEIPT_BACKUP_)/.test(k)).sort(),
    services: {backend: 'srv-d8csvkkp3tds73emfikg', frontend: 'srv-d8ekf7t7vvec73dpar60'},
    sourceProject: 'uxtjzjbwtppjvnsoiijv', supabaseUrl: env.SUPABASE_URL,
    deployment: {backendCommit: env.RENDER_GIT_COMMIT || null, backendBranch: 'release/k135z-backend-render-20260919', frontendBranch: FRONTEND_BRANCH},
    restoreRequires: ['Keep outbound email, phone, advertising, payments and background automations disabled.',
      'Reconcile provider transactions and completed actions after the database restore point before enabling workers.',
      'Apply deletion requests and revoked access after the restore point before exposing data.',
      'Recreate provider credentials, dashboard auth settings, domains, webhooks and mobile signing credentials from their secure custody locations.',
      'Reauthenticate YouTube; its table data and token encryption key are deliberately excluded.',
      'Revoke restored sessions and recheck roles, ownership and row-level security before customer access.']};
}

export async function releaseSources(env, signal, fetchImpl = fetch) {
  check(/^[a-f0-9]{40}$/.test(env.RENDER_GIT_COMMIT || ''), 'BACKUP_APP_RELEASE_COMMIT_REQUIRED');
  const response = await fetchImpl(`https://api.github.com/repos/${REPO}/git/ref/heads/${encodeURIComponent(FRONTEND_BRANCH)}`,
    {redirect: 'error', signal, headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Korlix-Recovery-Backup'}});
  check(response.ok, 'BACKUP_APP_SOURCE_CODE_FETCH_FAILED');
  const ref = JSON.parse((await readBoundedStream(response.body, 65536)).toString('utf8'));
  check(ref.ref === 'refs/heads/' + FRONTEND_BRANCH && /^[a-f0-9]{40}$/.test(ref.object?.sha || ''), 'BACKUP_APP_SOURCE_CODE_REF_INVALID');
  const result = [];
  for (const [component, commit] of [['backend', env.RENDER_GIT_COMMIT], ['frontend-release', ref.object.sha]]) {
    const r = await fetchImpl(`https://codeload.github.com/${REPO}/tar.gz/${commit}`, {redirect: 'error', signal});
    check(r.ok, 'BACKUP_APP_SOURCE_CODE_FETCH_FAILED');
    const bytes = await readBoundedStream(r.body, 64 * 1024 * 1024);
    check(bytes[0] === 0x1f && bytes[1] === 0x8b, 'BACKUP_APP_SOURCE_CODE_ARCHIVE_INVALID');
    result.push({component, commit, bytes});
  }
  return result;
}

export async function runApplicationProbe({store, config, signal}) {
  const id = randomUUID(), key = `${config.prefix}_probe/${id}.enc`;
  const plaintext = Buffer.from('KORLIX synthetic application-backup probe');
  const archive = sealPart(config, 'probe', id, {synthetic: true}, plaintext);
  let versionId;
  try {
    ({versionId} = await store.put(key, archive, signal));
    const remote = await store.get(key, signal);
    const opened = openPart(config, 'probe', id, remote);
    check(opened.bytes.equals(plaintext), 'BACKUP_APP_PROBE_FAILED'); opened.bytes.fill(0);
    await store.assertPrivate(key, signal);
    let rejected = false;
    try { openPart(config, 'probe', 'wrong-binding', remote); } catch { rejected = true; }
    check(rejected, 'BACKUP_APP_PROBE_FAILED');
    const damaged = Buffer.from(remote); damaged[damaged.length - 1] ^= 1; rejected = false;
    try { openPart(config, 'probe', id, damaged); } catch { rejected = true; }
    check(rejected, 'BACKUP_APP_PROBE_FAILED');
    return {status: 'passed', uploadReadback: true, encryptionVerified: true, privateAccess: true,
      tamperRejected: true, wrongBindingRejected: true};
  } finally { if (versionId) await store.deleteProbe(key, versionId, signal); }
}

export async function runApplicationBackup({source, store, config, env = process.env, includeDatabase = true,
  signal, now = () => new Date(), sourceCodeProvider = releaseSources}) {
  const runId = randomUUID(), startedAt = now().toISOString(), day = startedAt.slice(0, 10);
  const root = `${config.prefix}v1/${config.project}/daily/${day}`;
  let uploaded = 0, reused = 0, verified = 0;
  const parts = [];
  async function save(kind, identity, metadata, bytes, key) {
    signal?.throwIfAborted();
    const part = sealPart(config, kind, identity, metadata, bytes);
    await store.put(key, part, signal); uploaded++;
    const remote = await store.get(key, signal);
    const opened = openPart(config, kind, identity, remote);
    check(opened.sha256 === hash(bytes) && JSON.stringify(opened.metadata) === JSON.stringify(metadata), 'BACKUP_APP_READBACK_FAILED');
    opened.bytes.fill(0); verified++;
    const entry = {key, kind, identity, metadata, sha256: hash(bytes), byteSize: bytes.length};
    parts.push(entry); return entry;
  }
  try {
    const snapshot = await source.begin(signal);
    for (const object of snapshot.inventory.objects) {
      const identity = `${object.bucket_id}/${object.id}/${object.name}`;
      const fingerprint = hash(Buffer.from(JSON.stringify(object)));
      const key = `${root}/objects/${opaque(config, identity)}/${fingerprint}.enc`;
      const previous = await store.get(key, signal);
      if (previous) {
        const opened = openPart(config, 'object', identity, previous);
        check(JSON.stringify(opened.metadata) === JSON.stringify(object)
          && opened.bytes.length === Number(object.metadata.size), 'BACKUP_APP_OBJECT_METADATA_MISMATCH');
        parts.push({key, kind: 'object', identity, metadata: object, sha256: opened.sha256, byteSize: opened.bytes.length});
        opened.bytes.fill(0); reused++; verified++;
      } else {
        const bytes = await source.download(object, signal);
        try { await save('object', identity, object, bytes, key); }
        finally { bytes.fill(0); }
      }
    }
    check(snapshot.recoveryControls && typeof snapshot.recoveryControls === 'object', 'BACKUP_APP_RECOVERY_CONTROLS_REQUIRED');
    const controls = Buffer.from(JSON.stringify(snapshot.recoveryControls));
    try { await save('recovery-controls', runId, {capturedAt: snapshot.capturedAt}, controls, `${root}/recovery-controls/${runId}.enc`); }
    finally { controls.fill(0); }
    if (includeDatabase) {
      const bytes = await source.dump(signal);
      try { await save('database', runId, snapshot.databaseMetadata, bytes, `${root}/database/${runId}.enc`); }
      finally { bytes.fill(0); }
      const settings = Buffer.from(JSON.stringify(recoveryConfiguration(env)));
      try { await save('configuration', runId, {capturedAt: snapshot.capturedAt}, settings, `${root}/configuration/${runId}.enc`); }
      finally { settings.fill(0); }
      const releases = await sourceCodeProvider(env, signal);
      for (const release of releases) {
        try { await save('source', `${release.component}/${release.commit}`, {component: release.component, commit: release.commit},
          release.bytes, `${root}/source/${release.component}-${release.commit}-${runId}.enc`); }
        finally { release.bytes.fill(0); }
      }
    }
    check(await source.unchanged(snapshot.inventory, signal), 'BACKUP_APP_SOURCE_CHANGED_RETRY');
    const completedAt = now().toISOString();
    const catalog = {version: 1, project: config.project, runId, kind: includeDatabase ? 'database-and-files' : 'files',
      startedAt, capturedAt: snapshot.capturedAt, completedAt, databaseIncluded: includeDatabase,
      inventoryDigest: inventoryDigest(snapshot.inventory), buckets: snapshot.inventory.buckets, parts,
      exclusions: ['YouTube Live Studio table data', 'Supabase-managed platform schemas and dashboard settings',
        'Provider API credentials and mobile signing credentials', 'External-provider-only files and device-only files'],
      recoveryPolicy: 'Offline isolated recovery only. Apply subsequent deletion/revocation records and reconcile provider actions before re-enabling access or workers.'};
    const bytes = Buffer.from(JSON.stringify(catalog));
    check(bytes.length <= MAX_CATALOG, 'BACKUP_APP_CATALOG_LIMIT');
    const catalogKey = `${root}/catalogs/${runId}.enc`;
    try { await save('catalog', runId, {kind: catalog.kind}, bytes, catalogKey); }
    finally { bytes.fill(0); }
    return {status: 'complete', startedAt, completedAt, capturedAt: snapshot.capturedAt, databaseIncluded: includeDatabase,
      objectCount: snapshot.inventory.objects.length, sourceBytes: snapshot.inventory.sourceBytes, uploaded, reused, verified,
      catalogVerified: true, recoveryControlsIncluded: true, catalogKey, keyFingerprint: config.keyFingerprint, fullApplicationRestoreTested: false};
  } finally { await source.close(); }
}
