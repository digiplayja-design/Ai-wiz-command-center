import {createCipheriv, createDecipheriv, createHmac, randomBytes, randomUUID} from 'node:crypto';
import {receiptRecoveryManifest, sealReceiptArchive, openReceiptArchive} from '../ops/receipt_backup.mjs';
import {check, backupError, hash, MAX_ARCHIVE_BYTES, MAX_CATALOG_BYTES} from './config.mjs';

const CATALOG_MAGIC = Buffer.from('KRCAT001');
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
export function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
  return JSON.stringify(value);
}
export function receiptSignature(manifest) {
  const {capturedAt, ...stable} = receiptRecoveryManifest(manifest);
  return hash(canonical(stable));
}
function catalogueKey(key) { return createHmac('sha256', key).update('korlix-receipt-catalog-v1').digest(); }
export function sealCatalog(catalog, key) {
  check(Buffer.isBuffer(key) && key.length === 32, 'BACKUP_KEY_INVALID');
  const bytes = Buffer.from(JSON.stringify(catalog));
  const derived = catalogueKey(key);
  try {
    check(bytes.length <= MAX_CATALOG_BYTES - 36, 'BACKUP_CATALOG_TOO_LARGE');
    const nonce = randomBytes(12), cipher = createCipheriv('aes-256-gcm', derived, nonce);
    cipher.setAAD(CATALOG_MAGIC);
    const encrypted = Buffer.concat([cipher.update(bytes), cipher.final()]);
    return Buffer.concat([CATALOG_MAGIC, nonce, cipher.getAuthTag(), encrypted]);
  } finally { bytes.fill(0); derived.fill(0); }
}
export function openCatalog(archive, key, project) {
  check(Buffer.isBuffer(key) && key.length === 32 && Buffer.isBuffer(archive) && archive.length > 36
    && archive.length <= MAX_CATALOG_BYTES && archive.subarray(0, 8).equals(CATALOG_MAGIC), 'BACKUP_CATALOG_INVALID');
  const derived = catalogueKey(key);
  let decoded;
  try {
    const decipher = createDecipheriv('aes-256-gcm', derived, archive.subarray(8, 20));
    decipher.setAAD(CATALOG_MAGIC); decipher.setAuthTag(archive.subarray(20, 36));
    const bytes = Buffer.concat([decipher.update(archive.subarray(36)), decipher.final()]);
    try { decoded = JSON.parse(bytes.toString('utf8')); } finally { bytes.fill(0); }
  } catch { throw backupError('BACKUP_CATALOG_AUTHENTICATION_FAILED'); }
  finally { derived.fill(0); }
  check(decoded?.format === 1 && decoded.project === project && Array.isArray(decoded.entries)
    && decoded.entries.length <= 10000 && Number.isFinite(Date.parse(decoded.startedAt))
    && Number.isFinite(Date.parse(decoded.completedAt)) && decoded.keyFingerprint === hash(key).slice(0, 16), 'BACKUP_CATALOG_INVALID');
  const seen = new Set();
  for (const item of decoded.entries) {
    check(['receipt_wiz', 'bookkeeping'].includes(item.source) && UUID.test(item.ownerId) && UUID.test(item.receiptId)
      && /^[a-f0-9]{64}$/.test(item.signature) && typeof item.archiveKey === 'string'
      && new RegExp('^receipts/v1/' + project + '/daily/[0-9]{4}-[0-9]{2}-[0-9]{2}/' + item.source
        + '/[a-f0-9]{64}/' + item.signature + '\\.enc$').test(item.archiveKey), 'BACKUP_CATALOG_INVALID');
    const identity = item.source + '/' + item.receiptId;
    check(!seen.has(identity), 'BACKUP_CATALOG_INVALID'); seen.add(identity);
  }
  return decoded;
}
function verifyArchive(bytes, key, manifest) {
  check(bytes, 'BACKUP_UPLOAD_NOT_VERIFIED');
  const result = openReceiptArchive({key, archive: bytes, expectedOwnerId: manifest.ownerId,
    expectedReceiptId: manifest.receipt.id, expectedProject: manifest.project});
  try { check(receiptSignature(result.manifest) === receiptSignature(manifest), 'BACKUP_SNAPSHOT_MISMATCH'); }
  finally { result.original.fill(0); result.preview?.fill(0); }
}
function signatures(records) { return records.map(receiptSignature).sort().join('\n'); }

export async function runReceiptBackup({source, store, config, signal, now = () => new Date(), maximumReceipts = 10000,
  maximumSourceBytes = 512 * 1024 * 1024}) {
  check(config.mode === 'enabled' && config.key?.length === 32, 'BACKUP_NOT_ENABLED');
  const startedAt = now().toISOString(), day = startedAt.slice(0, 10);
  const records = await source.list(maximumReceipts, signal);
  check(records.length <= maximumReceipts, 'BACKUP_RECEIPT_LIMIT');
  const totalBytes = records.reduce((n, r) => n + r.receipt.byte_size + r.receipt.preview_size, 0);
  check(totalBytes <= maximumSourceBytes, 'BACKUP_RUN_BYTE_LIMIT');
  const entries = [];
  let uploaded = 0, verified = 0;
  for (const record of records) {
    signal?.throwIfAborted();
    check(record.project === config.project, 'BACKUP_SOURCE_INVALID');
    const signature = receiptSignature(record);
    const identity = createHmac('sha256', config.key).update(record.source + '/' + record.ownerId + '/' + record.receipt.id).digest('hex');
    const archiveKey = config.prefix + 'v1/' + config.project + '/daily/' + day + '/' + record.source + '/' + identity + '/' + signature + '.enc';
    const existing = await store.get(archiveKey, MAX_ARCHIVE_BYTES, signal);
    if (existing) verifyArchive(existing, config.key, record);
    else {
      let original, preview;
      try {
        original = await source.download(record, 'original', signal);
        preview = record.previewPath ? await source.download(record, 'preview', signal) : null;
        const current = await source.current(record);
        check(current && receiptSignature(current) === signature, 'BACKUP_SOURCE_CHANGED');
        const archive = sealReceiptArchive({key: config.key, manifest: record, original, preview});
        await store.put(archiveKey, archive, signal);
        verifyArchive(await store.get(archiveKey, MAX_ARCHIVE_BYTES, signal), config.key, record);
        uploaded++;
      } finally { original?.fill(0); preview?.fill(0); }
    }
    verified++;
    entries.push({source: record.source, ownerId: record.ownerId, receiptId: record.receipt.id, signature, archiveKey});
  }
  signal?.throwIfAborted();
  // Never publish a complete inventory after a concurrent edit/deletion or failed query.
  const after = await source.list(maximumReceipts, signal);
  check(signatures(records) === signatures(after), 'BACKUP_SOURCE_CHANGED');
  const completedAt = now().toISOString();
  const catalog = {format: 1, project: config.project, startedAt, completedAt,
    keyFingerprint: hash(config.key).slice(0, 16), entries};
  const name = config.prefix + 'v1/' + config.project + '/catalogs/' + startedAt.replace(/[:.]/g, '-') + '-' + randomUUID() + '.enc';
  await store.put(name, sealCatalog(catalog, config.key), signal);
  const downloaded = await store.get(name, MAX_CATALOG_BYTES, signal);
  check(canonical(openCatalog(downloaded, config.key, config.project)) === canonical(catalog), 'BACKUP_CATALOG_READBACK_FAILED');
  return {status: 'complete', startedAt, completedAt, receipts: records.length, sourceBytes: totalBytes, uploaded, verified,
    catalogVerified: true, encryption: 'AES-256-GCM', keyFingerprint: catalog.keyFingerprint};
}

// Returns only a verified archive for an existing, active owner's CURRENT receipt.
// Disaster recovery of a deleted/missing database requires the separate recovery runbook.
// This helper never writes into Supabase or restores customer data automatically.
export async function verifyRecoverableReceipt({catalogBytes, source, store, config, ownerId, receiptId, sourceName, signal}) {
  check(UUID.test(ownerId) && UUID.test(receiptId), 'BACKUP_EXPECTED_IDENTITY_REQUIRED');
  const catalog = openCatalog(catalogBytes, config.key, config.project);
  const entry = catalog.entries.find(e => e.ownerId === ownerId && e.receiptId === receiptId && e.source === sourceName);
  check(entry, 'BACKUP_RESTORE_NOT_IN_CATALOG');
  check(await source.ownerActive(ownerId), 'BACKUP_RESTORE_OWNER_INACTIVE');
  const current = await source.current({source: sourceName, receipt: {id: receiptId}});
  check(current && current.ownerId === ownerId && receiptSignature(current) === entry.signature, 'BACKUP_RESTORE_SOURCE_CHANGED');
  const archive = await store.get(entry.archiveKey, MAX_ARCHIVE_BYTES, signal);
  verifyArchive(archive, config.key, current);
  return archive;
}

export async function runBackblazeProbe({store, project, prefix = 'receipts/', signal}) {
  const key = randomBytes(32), ownerId = randomUUID(), id = randomUUID();
  const original = Buffer.from('%PDF-1.7\nKORLIX synthetic backup connectivity test. No customer data.\n');
  const name = prefix + '_probe/' + randomUUID() + '.enc';
  const receipt = {id, owner_id: ownerId, filename: 'synthetic-backup-test.pdf', mime_type: 'application/pdf',
    byte_size: original.length, sha256: hash(original), preview_size: 0, preview_sha256: null, pages: 1,
    state: 'ready', details: {merchant: 'Synthetic backup test'}, reviewed: true, version: 1,
    created_at: new Date().toISOString(), updated_at: new Date().toISOString()};
  let versionId;
  try {
    const manifest = receiptRecoveryManifest({source: 'receipt_wiz', project, ownerId, receipt});
    const archive = sealReceiptArchive({key, manifest, original});
    ({versionId} = await store.put(name, archive, signal));
    const recovered = await store.get(name, MAX_ARCHIVE_BYTES, signal);
    verifyArchive(recovered, key, manifest);
    let wrongOwnerRejected = false, corruptionRejected = false;
    try { openReceiptArchive({key, archive: recovered, expectedOwnerId: randomUUID(), expectedReceiptId: id, expectedProject: project}); }
    catch (error) { wrongOwnerRejected = error.code === 'BACKUP_RESTORE_SCOPE_MISMATCH'; }
    const damaged = Buffer.from(recovered); damaged[damaged.length - 1] ^= 1;
    try { openReceiptArchive({key, archive: damaged, expectedOwnerId: ownerId, expectedReceiptId: id, expectedProject: project}); }
    catch (error) { corruptionRejected = error.code === 'BACKUP_AUTHENTICATION_FAILED'; }
    check(wrongOwnerRejected && corruptionRejected, 'BACKUP_PROBE_RECOVERY_FAILED');
    await store.assertPrivate(name, signal);
    check((await store.list(prefix + '_probe/', signal)).includes(name), 'BACKUP_PROBE_LIST_FAILED');
    await store.deleteProbe(name, versionId, signal);
    versionId = undefined;
    check((await store.get(name, MAX_ARCHIVE_BYTES, signal)) === null, 'BACKUP_PROBE_CLEANUP_FAILED');
    return {status: 'pass', syntheticOnly: true, uploadVerified: true, downloadVerified: true, recoveryVerified: true,
      wrongOwnerRejected, corruptionRejected, anonymousAccessDenied: true, probeRemoved: true, productionBackupsActive: false};
  } finally {
    key.fill(0); original.fill(0);
    if (versionId) { try { await store.deleteProbe(name, versionId, signal); } catch { /* Preserve original failure; never delete any customer object. */ } }
  }
}
