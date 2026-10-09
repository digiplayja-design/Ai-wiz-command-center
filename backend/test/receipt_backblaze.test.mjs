import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes, randomUUID} from 'node:crypto';
import {Readable} from 'node:stream';
import {backupConfig, hash, safeBackupCode, SOURCE_PROJECT} from '../receipt_backup/config.mjs';
import {createBackblazeStore, readBoundedStream} from '../receipt_backup/backblaze.mjs';
import {receiptRecoveryManifest, openReceiptArchive} from '../ops/receipt_backup.mjs';
import {runBackblazeProbe, runReceiptBackup, openCatalog, sealCatalog, receiptSignature, verifyRecoverableReceipt} from '../receipt_backup/runner.mjs';
import {startReceiptBackupRuntime} from '../receipt_backup/runtime.mjs';
import {createReceiptBackupSource} from '../receipt_backup/source.mjs';

const TIME = '2026-10-09T05:00:00.000Z';
function environment(mode = 'probe') {
  return {RECEIPT_BACKUP_MODE: mode, RECEIPT_BACKUP_B2_ENDPOINT: 'https://s3.us-east-005.backblazeb2.com',
    RECEIPT_BACKUP_B2_REGION: 'us-east-005', RECEIPT_BACKUP_B2_BUCKET: 'korlix-backups', RECEIPT_BACKUP_B2_PREFIX: 'receipts/',
    RECEIPT_BACKUP_B2_KEY_ID: 'syntheticKeyId', RECEIPT_BACKUP_B2_APPLICATION_KEY: 'syntheticApplicationKey'};
}
function fixture(source = 'receipt_wiz') {
  const ownerId = randomUUID(), id = randomUUID(), original = Buffer.from('Original synthetic receipt bytes');
  const preview = Buffer.from('Synthetic preview bytes');
  const receipt = {id, filename: 'synthetic.png', mime_type: 'image/png', byte_size: original.length, sha256: hash(original),
    preview_size: preview.length, preview_sha256: hash(preview), pages: 1, state: 'ready', created_at: TIME,
    ...(source === 'receipt_wiz' ? {owner_id: ownerId, details: {merchant: 'Synthetic merchant'}, reviewed: true, version: 1, updated_at: TIME}
      : {created_by: ownerId, business_id: randomUUID(), ready_at: TIME})};
  return {original, preview, manifest: receiptRecoveryManifest({source, project: SOURCE_PROJECT, ownerId, receipt,
    capturedAt: TIME, ...(source === 'bookkeeping' ? {businessOwnerId: ownerId} : {})})};
}
function memoryStore() {
  const objects = new Map(), puts = [];
  return {objects, puts, closed: false,
    async put(name, bytes) { objects.set(name, Buffer.from(bytes)); puts.push(name); return {versionId: 'synthetic-version'}; },
    async get(name) { return objects.has(name) ? Buffer.from(objects.get(name)) : null; },
    async list(prefix) { return [...objects.keys()].filter(k => k.startsWith(prefix)); },
    async assertPrivate() {},
    async deleteProbe(name) { assert.match(name, /^receipts\/_probe\//); objects.delete(name); },
    close() { this.closed = true; },
  };
}
function setup() {
  const files = [fixture(), fixture('bookkeeping')], store = memoryStore(), key = randomBytes(32);
  const config = {...backupConfig(environment()), mode: 'enabled', key};
  const source = {
    async list() { return files.map(f => structuredClone(f.manifest)); },
    async current(m) { return structuredClone(files.find(f => f.manifest.source === m.source && f.manifest.receipt.id === m.receipt.id)?.manifest || null); },
    async download(m, kind) { return Buffer.from(files.find(f => f.manifest.receipt.id === m.receipt.id)[kind]); },
    async ownerActive() { return true; },
  };
  return {files, store, key, config, source, now: () => new Date(TIME)};
}
const catalogs = store => [...store.objects.keys()].filter(k => k.includes('/catalogs/'));

test('configuration defaults off and cannot silently enable without recovery custody, retention, and disclosure', () => {
  assert.deepEqual(backupConfig({}), {mode: 'off'});
  const env = environment('enabled'), key = randomBytes(32);
  assert.throws(() => backupConfig(env), /RECOVERY_KEY_INVALID/);
  env.RECEIPT_BACKUP_RECOVERY_KEY_BASE64 = key.toString('base64');
  assert.throws(() => backupConfig(env), /CUSTODY_REQUIRED/);
  env.RECEIPT_BACKUP_RECOVERY_KEY_ESCROWED = 'true';
  assert.throws(() => backupConfig(env), /RETENTION_CONFIGURATION_REQUIRED/);
  env.RECEIPT_BACKUP_RETENTION_CONFIGURED = 'true';
  assert.throws(() => backupConfig(env), /PRIVACY_DISCLOSURE_REQUIRED/);
  env.RECEIPT_BACKUP_PRIVACY_DISCLOSURE_READY = 'true';
  assert.throws(() => backupConfig(env), /CUSTODY_MISMATCH/);
  env.RECEIPT_BACKUP_RECOVERY_KEY_FINGERPRINT = hash(key).slice(0, 16);
  assert.equal(backupConfig(env).keyFingerprint, hash(key).slice(0, 16));
});

test('destination pinning rejects arbitrary endpoints, buckets, prefixes, and whitespace credential substitutions', () => {
  for (const [name, value] of [['RECEIPT_BACKUP_B2_ENDPOINT', 'https://attacker.invalid'], ['RECEIPT_BACKUP_B2_BUCKET', 'other'],
    ['RECEIPT_BACKUP_B2_PREFIX', ''], ['RECEIPT_BACKUP_B2_REGION', 'us-west-004']]) {
    assert.throws(() => backupConfig({...environment(), [name]: value}), /DESTINATION_INVALID/);
  }
  assert.throws(() => backupConfig({...environment(), RECEIPT_BACKUP_B2_APPLICATION_KEY: ''}), /CREDENTIALS_MISSING/);
  assert.equal(safeBackupCode(new Error('customer or credential here')), 'BACKUP_OPERATION_FAILED');
});

test('synthetic provider probe checks ciphertext recovery, ownership, tampering, privacy, listing, and cleanup', async () => {
  const store = memoryStore();
  const result = await runBackblazeProbe({store, project: SOURCE_PROJECT});
  assert.equal(result.status, 'pass'); assert.equal(result.syntheticOnly, true);
  assert.equal(result.wrongOwnerRejected, true); assert.equal(result.corruptionRejected, true);
  assert.equal(result.productionBackupsActive, false); assert.equal(store.objects.size, 0);
});

test('full run covers both sources and previews with encrypted verified catalog and exact round-trip bytes', async () => {
  const ctx = setup(); const result = await runReceiptBackup(ctx);
  assert.equal(result.uploaded, 2); assert.equal(result.verified, 2); assert.equal(result.catalogVerified, true);
  const catalogBytes = ctx.store.objects.get(catalogs(ctx.store)[0]);
  const cat = openCatalog(catalogBytes, ctx.key, SOURCE_PROJECT);
  assert.equal(cat.entries.length, 2);
  for (const file of ctx.files) {
    assert.equal(catalogBytes.includes(Buffer.from(file.manifest.ownerId)), false);
    const entry = cat.entries.find(e => e.receiptId === file.manifest.receipt.id);
    const encrypted = ctx.store.objects.get(entry.archiveKey);
    assert.equal(encrypted.includes(file.original), false);
    assert.equal(entry.archiveKey.includes(file.manifest.ownerId), false);
    const recovered = openReceiptArchive({key: ctx.key, archive: encrypted, expectedProject: SOURCE_PROJECT,
      expectedOwnerId: entry.ownerId, expectedReceiptId: entry.receiptId});
    assert.deepEqual(recovered.original, file.original); assert.deepEqual(recovered.preview, file.preview);
  }
});

test('same-day reconciliation reuses immutable receipt bytes; next day creates a fresh baseline', async () => {
  const ctx = setup(); await runReceiptBackup(ctx);
  assert.equal((await runReceiptBackup(ctx)).uploaded, 0);
  assert.equal((await runReceiptBackup({...ctx, now: () => new Date('2026-10-10T05:00:00Z')})).uploaded, 2);
  assert.equal(catalogs(ctx.store).length, 3);
});

test('review edits produce new versions and retain previous encrypted copies', async () => {
  const ctx = setup(); await runReceiptBackup(ctx);
  ctx.files[0].manifest.receipt.details = {merchant: 'Corrected synthetic merchant'};
  ctx.files[0].manifest.receipt.version = 2;
  assert.equal((await runReceiptBackup(ctx)).uploaded, 1);
  assert.equal([...ctx.store.objects.keys()].filter(k => k.includes('/daily/')).length, 3);
});

test('changing source during download never commits a complete catalog', async () => {
  const ctx = setup();
  ctx.source.current = async m => ({...m, receipt: {...m.receipt, filename: 'changed.png'}});
  await assert.rejects(runReceiptBackup(ctx), /SOURCE_CHANGED/);
  assert.equal(catalogs(ctx.store).length, 0);
});

test('source deletion at reconciliation never publishes stale complete inventory', async () => {
  const ctx = setup(); let calls = 0;
  ctx.source.list = async () => ++calls === 1 ? ctx.files.map(f => structuredClone(f.manifest)) : [];
  await assert.rejects(runReceiptBackup(ctx), /SOURCE_CHANGED/);
  assert.equal(catalogs(ctx.store).length, 0);
});

test('corrupt source and corrupt remote bytes cannot be marked backed up', async () => {
  let ctx = setup(); ctx.source.download = async () => Buffer.from('wrong bytes');
  await assert.rejects(runReceiptBackup(ctx), /ORIGINAL_INTEGRITY/);
  assert.equal(catalogs(ctx.store).length, 0);
  ctx = setup(); const put = ctx.store.put;
  ctx.store.put = async (name, bytes) => { const changed = Buffer.from(bytes); changed[changed.length - 1] ^= 1; return put(name, changed); };
  await assert.rejects(runReceiptBackup(ctx), /AUTHENTICATION_FAILED/);
  assert.equal(catalogs(ctx.store).length, 0);
});

test('limits fail before copying a corpus outside the configured budget', async () => {
  const ctx = setup();
  await assert.rejects(runReceiptBackup({...ctx, maximumSourceBytes: 1}), /RUN_BYTE_LIMIT/);
  await assert.rejects(runReceiptBackup({...ctx, maximumReceipts: 1}), /RECEIPT_LIMIT/);
  assert.equal(ctx.store.puts.length, 0);
});

test('recovery verifies current owner and denies deleted, disabled, mismatched, or stale receipts', async () => {
  const ctx = setup(); await runReceiptBackup(ctx);
  const m = ctx.files[0].manifest;
  const args = {...ctx, catalogBytes: ctx.store.objects.get(catalogs(ctx.store)[0]), ownerId: m.ownerId,
    receiptId: m.receipt.id, sourceName: m.source};
  assert(Buffer.isBuffer(await verifyRecoverableReceipt(args)));
  await assert.rejects(verifyRecoverableReceipt({...args, ownerId: randomUUID()}), /NOT_IN_CATALOG/);
  ctx.source.ownerActive = async () => false;
  await assert.rejects(verifyRecoverableReceipt(args), /OWNER_INACTIVE/);
  ctx.source.ownerActive = async () => true; ctx.source.current = async () => null;
  await assert.rejects(verifyRecoverableReceipt(args), /SOURCE_CHANGED/);
});

test('catalogs reject tampering, wrong project, wrong recovery key, and untrusted object paths', async () => {
  const ctx = setup(); await runReceiptBackup(ctx);
  const bytes = ctx.store.objects.get(catalogs(ctx.store)[0]);
  assert.throws(() => openCatalog(bytes, randomBytes(32), SOURCE_PROJECT), /AUTHENTICATION_FAILED/);
  assert.throws(() => openCatalog(bytes, ctx.key, 'another-project'), /CATALOG_INVALID/);
  const cat = openCatalog(bytes, ctx.key, SOURCE_PROJECT); cat.entries[0].archiveKey = 'receipts/../other';
  assert.throws(() => openCatalog(sealCatalog(cat, ctx.key), ctx.key, SOURCE_PROJECT), /CATALOG_INVALID/);
});

test('bounded remote streaming rejects oversized data and closes the stream', async () => {
  const stream = Readable.from([Buffer.alloc(4), Buffer.alloc(4)]);
  await assert.rejects(readBoundedStream(stream, 5), /REMOTE_TOO_LARGE/);
  assert.equal(stream.destroyed, true);
});

test('adapter scopes every operation and never deletes a production key', async () => {
  const calls = [], config = backupConfig(environment());
  const client = {async send(command) { calls.push(command); return {VersionId: 'v1'}; }};
  const store = createBackblazeStore(config, {client});
  await assert.rejects(store.put('another/key', Buffer.from('x')), /KEY_SCOPE/);
  await assert.rejects(store.get('receipts/../secret'), /KEY_SCOPE/);
  await assert.rejects(store.deleteProbe('receipts/v1/customer.enc', 'v1'), /DELETE_SCOPE/);
  await store.put('receipts/_probe/test.enc', Buffer.from('synthetic'));
  assert.equal(calls.length, 1); assert.equal(calls[0].input.ServerSideEncryption, 'AES256');
  assert.equal(calls[0].input.Bucket, 'korlix-backups');
});

test('adapter sanitizes provider errors and does not treat access denied as missing', async () => {
  const store = createBackblazeStore(backupConfig(environment()), {client: {async send() {
    throw Object.assign(new Error('secret-token-and-customer-path'), {$metadata: {httpStatusCode: 403}});
  }}});
  await assert.rejects(store.get('receipts/test.enc'), {code: 'BACKUP_ACCESS_DENIED', message: 'BACKUP_ACCESS_DENIED'});
});

test('privacy probe rejects public success, missing objects, redirects, and server errors', async () => {
  for (const status of [200, 206, 302, 404, 500]) {
    const store = createBackblazeStore(backupConfig(environment()), {client: {}, fetchImpl: async () => new Response('', {status})});
    await assert.rejects(store.assertPrivate('receipts/test.enc'), /PUBLIC_ACCESS_NOT_DENIED/);
  }
  const store = createBackblazeStore(backupConfig(environment()), {client: {}, fetchImpl: async () => new Response('', {status: 403})});
  await store.assertPrivate('receipts/test.enc');
});

test('probe runtime never reads source data, reports no production activation, and stops scheduling', async () => {
  const logs = [], jobs = [], store = memoryStore();
  const runtime = startReceiptBackupRuntime({database: null, env: environment(), logger: {info: v => logs.push(v), error: v => logs.push(v)},
    timers: {setTimeout: callback => {jobs.push(callback); return 1;}, clearTimeout() {}}, storeFactory: () => store,
    sourceFactory() { throw new Error('must not read customer data'); }});
  assert.equal(jobs.length, 1); await jobs[0](); assert.equal(jobs.length, 1);
  assert.equal(runtime.getStatus().mode, 'probe'); assert.equal(runtime.getStatus().lastSuccessAt, null);
  assert(logs.some(v => JSON.parse(v).event === 'receipt_backup_probe'));
  assert(!logs.join('').includes('syntheticApplicationKey')); assert.equal(store.closed, true);
});

test('configuration failures do not crash the application or log submitted secrets', () => {
  const logs = [];
  const runtime = startReceiptBackupRuntime({env: {...environment(), RECEIPT_BACKUP_B2_ENDPOINT: 'https://secret.example'},
    logger: {info: v => logs.push(v), error: v => logs.push(v)}, storeFactory() { throw new Error('must not construct'); }});
  assert.equal(runtime.getStatus().lastError, 'BACKUP_DESTINATION_INVALID');
  assert(!logs.join('').includes('secret.example')); assert(!logs.join('').includes('syntheticApplicationKey'));
});

test('source uses keyset pagination, explicit metadata fields, and verifies legacy business ownership', async () => {
  const items = Array.from({length: 101}, () => fixture().manifest.receipt).sort((a, b) => a.id.localeCompare(b.id));
  const legacy = fixture('bookkeeping'), observed = [];
  const database = {from(table) {
    const query = {filters: {}, select(columns) {observed.push({table, columns}); return this;},
      eq(k, v) {this.filters[k] = v; return this;}, gt(k, v) {this.cursor = v; return this;}, order() {return this;},
      limit(v) {this.limitValue = v; return this;}, maybeSingle() {this.single = true; return this;},
      async abortSignal() {
        if (table === 'korlix_bookkeeping_businesses') return {data: {owner_id: legacy.manifest.ownerId}};
        const rows = (table === 'korlix_receipt_wiz' ? items : [legacy.manifest.receipt])
          .filter(r => (!this.cursor || r.id > this.cursor) && (!this.filters.id || r.id === this.filters.id));
        return {data: this.single ? rows[0] || null : rows.slice(0, this.limitValue)};
      }};
    return query;
  }};
  const source = createReceiptBackupSource(database, {now: () => new Date(TIME)});
  const all = await source.list(); assert.equal(all.length, 102);
  assert.equal(all[101].businessOwnerId, legacy.manifest.ownerId);
  assert(observed.every(row => !row.columns.includes('*') && !row.columns.includes('upload_token') && !row.columns.includes('request_key')));
  assert.equal(receiptSignature(await source.current(all[0])), receiptSignature(all[0]));
});
