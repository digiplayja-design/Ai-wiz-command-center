import {mkdir, chmod, writeFile, rm} from 'node:fs/promises';
import {isAbsolute, join} from 'node:path';
import {check, hash, openPart, MAX_CATALOG} from './archive.mjs';

// Offline extraction only: no Supabase client, SQL executor, production write or customer-serving endpoint.
// Outputs use generated names; archived customer paths can never select local filesystem paths.
export async function extractApplicationBackup({store, config, catalogKey, output, signal,
  expectedProject, acknowledgeIsolatedRecovery = false}) {
  check(expectedProject === config.project && acknowledgeIsolatedRecovery === true, 'BACKUP_APP_RECOVERY_ACK_REQUIRED');
  const match = catalogKey.match(/^application\/v1\/([a-z0-9]+)\/daily\/([0-9]{4}-[0-9]{2}-[0-9]{2})\/catalogs\/([a-f0-9-]{36})\.enc$/);
  check(match && match[1] === expectedProject && isAbsolute(output), 'BACKUP_APP_CATALOG_SCOPE_INVALID');
  const raw = await store.get(catalogKey, signal);
  const opened = openPart(config, 'catalog', match[3], raw);
  check(opened.bytes.length <= MAX_CATALOG, 'BACKUP_APP_CATALOG_LIMIT');
  let catalog;
  try { catalog = JSON.parse(opened.bytes.toString('utf8')); } finally { opened.bytes.fill(0); }
  check(catalog.version === 1 && catalog.project === expectedProject && catalog.runId === match[3]
    && Array.isArray(catalog.parts) && catalog.parts.length <= 10010, 'BACKUP_APP_CATALOG_INVALID');
  const root = `application/v1/${expectedProject}/daily/${match[2]}/`;
  const unique = new Set(); let total = 0;
  for (const part of catalog.parts) {
    check(part.key.startsWith(root) && /^[a-zA-Z0-9_./-]+$/.test(part.key) && !part.key.includes('..')
      && !unique.has(part.key) && ['object','database','configuration','recovery-controls','source'].includes(part.kind)
      && /^[a-f0-9]{64}$/.test(part.sha256) && Number.isSafeInteger(part.byteSize) && part.byteSize >= 0,
    'BACKUP_APP_CATALOG_INVALID');
    unique.add(part.key); total += part.byteSize;
  }
  check(total <= 2 * 1024 * 1024 * 1024, 'BACKUP_APP_RECOVERY_SIZE_LIMIT');
  await mkdir(output, {mode: 0o700}); await chmod(output, 0o700);
  const files = [];
  try {
    for (const [index, part] of catalog.parts.entries()) {
      signal?.throwIfAborted();
      const archive = await store.get(part.key, signal);
      const restored = openPart(config, part.kind, part.identity, archive);
      try {
        check(hash(restored.bytes) === part.sha256 && restored.bytes.length === part.byteSize
          && JSON.stringify(restored.metadata) === JSON.stringify(part.metadata), 'BACKUP_APP_RECOVERY_INTEGRITY_FAILED');
        const ext = {database:'dump', configuration:'json', 'recovery-controls':'json', source:'tar.gz', object:'bin'}[part.kind];
        const filename = `${String(index).padStart(5, '0')}-${part.kind}.${ext}`;
        await writeFile(join(output, filename), restored.bytes, {flag:'wx', mode:0o600});
        files.push({...part, filename});
      } finally { restored.bytes.fill(0); }
    }
    await writeFile(join(output, 'recovery-manifest.json'), JSON.stringify({...catalog, parts:files}, null, 2), {flag:'wx',mode:0o600});
    await writeFile(join(output, 'RECOVERY-BLOCKED.txt'),
      'ISOLATED RECOVERY ONLY. Do not import directly into production. Reconcile subsequent deletion/revocation records, provider payments and sent actions. Keep all external actions and customer access disabled until authorization, RLS, ownership and recovery checks pass. This extraction is not a completed application restore.\n',
      {flag:'wx',mode:0o600});
    return {verifiedParts:files.length, bytes:total, databaseIncluded:catalog.databaseIncluded,
      productionModified:false, fullApplicationRestoreTested:false};
  } catch (error) {
    await rm(output, {recursive:true, force:true}); throw error;
  }
}
