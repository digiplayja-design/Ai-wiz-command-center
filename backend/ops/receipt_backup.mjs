// Offline recovery building block. No network, database writes or scheduled job.
import {createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID} from 'node:crypto';
import {constants} from 'node:fs';
import {open, mkdir, rm, writeFile} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {pathToFileURL} from 'node:url';

const MAGIC = Buffer.from('KRCPB001');
const MAX_ARCHIVE = 13 * 1024 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const PROJECT = /^[a-z0-9-]{3,63}$/;
const MIME = new Set(['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);
const COMMON = ['id', 'filename', 'mime_type', 'byte_size', 'sha256', 'preview_size', 'preview_sha256', 'pages', 'state', 'created_at'];
const FIELDS = {
  receipt_wiz: [...COMMON, 'owner_id', 'details', 'reviewed', 'version', 'updated_at'],
  bookkeeping: [...COMMON, 'business_id', 'created_by', 'ready_at'],
};
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
function fail(code) { const error = new Error(code); error.code = code; throw error; }
function requireThat(ok, code) { if (!ok) fail(code); }
function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function validTime(value) { return typeof value === 'string' && value.length <= 40 && Number.isFinite(Date.parse(value)); }
function keyCheck(key) { requireThat(Buffer.isBuffer(key) && key.length === 32, 'BACKUP_KEY_INVALID'); }

// Pass only a ready row plus a separately checked business-owner binding.
// Unrelated table rows, API credentials and upload leases are not accepted.
export function receiptRecoveryManifest({source, project, ownerId, receipt, businessOwnerId, capturedAt = new Date().toISOString()}) {
  requireThat(Object.hasOwn(FIELDS, source) && PROJECT.test(project ?? '') && UUID.test(ownerId ?? '') && object(receipt), 'BACKUP_IDENTITY_INVALID');
  requireThat(Object.keys(receipt).every(name => FIELDS[source].includes(name)), 'BACKUP_METADATA_FIELDS_INVALID');
  requireThat(UUID.test(receipt.id ?? '') && receipt.state === 'ready', 'BACKUP_RECEIPT_NOT_READY');
  requireThat(typeof receipt.filename === 'string' && receipt.filename.length >= 1 && receipt.filename.length <= 160, 'BACKUP_METADATA_INVALID');
  requireThat(MIME.has(receipt.mime_type) && Number.isInteger(receipt.pages) && receipt.pages >= 1 && receipt.pages <= 10, 'BACKUP_METADATA_INVALID');
  requireThat(Number.isInteger(receipt.byte_size) && receipt.byte_size >= 1 && receipt.byte_size <= 8388608 && HASH.test(receipt.sha256 ?? ''), 'BACKUP_METADATA_INVALID');
  requireThat(Number.isInteger(receipt.preview_size) && receipt.preview_size >= 0 && receipt.preview_size <= 1048576, 'BACKUP_METADATA_INVALID');
  requireThat(receipt.preview_size === 0 ? receipt.preview_sha256 === null : HASH.test(receipt.preview_sha256 ?? ''), 'BACKUP_METADATA_INVALID');
  requireThat(validTime(receipt.created_at) && validTime(capturedAt), 'BACKUP_METADATA_INVALID');
  if (source === 'receipt_wiz') {
    requireThat(receipt.owner_id === ownerId && businessOwnerId === undefined, 'BACKUP_OWNER_MISMATCH');
    requireThat(object(receipt.details) && Buffer.byteLength(JSON.stringify(receipt.details)) <= 16000 && typeof receipt.reviewed === 'boolean' && Number.isInteger(receipt.version) && receipt.version >= 1 && validTime(receipt.updated_at), 'BACKUP_METADATA_INVALID');
  } else {
    requireThat(UUID.test(receipt.business_id ?? '') && receipt.created_by === ownerId && businessOwnerId === ownerId, 'BACKUP_OWNER_MISMATCH');
    requireThat(validTime(receipt.ready_at), 'BACKUP_METADATA_INVALID');
  }
  const bucket = source === 'receipt_wiz' ? 'korlix-receipt-wiz' : 'korlix-bookkeeping-receipts';
  const prefix = [ownerId, ...(source === 'bookkeeping' ? [receipt.business_id] : []), receipt.id].join('/');
  return {format: 1, source, project, ownerId, ...(businessOwnerId ? {businessOwnerId} : {}), capturedAt, receipt: structuredClone(receipt), bucket,
    originalPath: `${prefix}/original`, previewPath: receipt.preview_size ? `${prefix}/preview.webp` : null};
}

function checkedBytes(manifest, original, preview) {
  const r = manifest.receipt;
  requireThat(Buffer.isBuffer(original) && original.length === r.byte_size && sha(original) === r.sha256, 'BACKUP_ORIGINAL_INTEGRITY');
  requireThat(r.preview_size === 0 ? preview === null : Buffer.isBuffer(preview) && preview.length === r.preview_size && sha(preview) === r.preview_sha256, 'BACKUP_PREVIEW_INTEGRITY');
}

export function sealReceiptArchive({key, manifest, original, preview = null}) {
  keyCheck(key);
  const checked = receiptRecoveryManifest(manifest);
  checkedBytes(checked, original, preview);
  const payload = Buffer.from(JSON.stringify({manifest: checked, original: original.toString('base64'), preview: preview?.toString('base64') ?? null}));
  requireThat(payload.length <= MAX_ARCHIVE - 36, 'BACKUP_TOO_LARGE');
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(MAGIC);
  try {
    const ciphertext = Buffer.concat([cipher.update(payload), cipher.final()]);
    return Buffer.concat([MAGIC, nonce, cipher.getAuthTag(), ciphertext]);
  } finally { payload.fill(0); }
}

export function openReceiptArchive({key, archive, expectedOwnerId, expectedReceiptId, expectedProject}) {
  keyCheck(key);
  requireThat(UUID.test(expectedOwnerId ?? '') && UUID.test(expectedReceiptId ?? '') && PROJECT.test(expectedProject ?? ''), 'BACKUP_EXPECTED_IDENTITY_REQUIRED');
  requireThat(Buffer.isBuffer(archive) && archive.length > 36 && archive.length <= MAX_ARCHIVE && archive.subarray(0, 8).equals(MAGIC), 'BACKUP_ARCHIVE_INVALID');
  let payload;
  try {
    const decipher = createDecipheriv('aes-256-gcm', key, archive.subarray(8, 20));
    decipher.setAAD(MAGIC);
    decipher.setAuthTag(archive.subarray(20, 36));
    payload = Buffer.concat([decipher.update(archive.subarray(36)), decipher.final()]);
  } catch { fail('BACKUP_AUTHENTICATION_FAILED'); }
  let decoded;
  try { decoded = JSON.parse(payload.toString('utf8')); } catch { fail('BACKUP_PAYLOAD_INVALID'); } finally { payload.fill(0); }
  requireThat(object(decoded) && object(decoded.manifest) && decoded.manifest.format === 1, 'BACKUP_PAYLOAD_INVALID');
  const manifest = receiptRecoveryManifest(decoded.manifest);
  requireThat(manifest.ownerId === expectedOwnerId && manifest.receipt.id === expectedReceiptId && manifest.project === expectedProject, 'BACKUP_RESTORE_SCOPE_MISMATCH');
  requireThat(decoded.manifest.bucket === manifest.bucket && decoded.manifest.originalPath === manifest.originalPath && decoded.manifest.previewPath === manifest.previewPath, 'BACKUP_PATH_MISMATCH');
  requireThat(typeof decoded.original === 'string' && (decoded.preview === null || typeof decoded.preview === 'string'), 'BACKUP_PAYLOAD_INVALID');
  const original = Buffer.from(decoded.original, 'base64');
  const preview = decoded.preview === null ? null : Buffer.from(decoded.preview, 'base64');
  checkedBytes(manifest, original, preview);
  return {manifest, original, preview};
}

async function boundedFile(path, max, {privateFile = false} = {}) {
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await handle.stat();
    requireThat(stat.isFile() && stat.size <= max, 'BACKUP_INPUT_INVALID');
    requireThat(!privateFile || (stat.mode & 0o077) === 0, 'BACKUP_KEY_PERMISSIONS');
    const bytes = Buffer.alloc(stat.size + 1);
    let size = 0;
    while (size < bytes.length) {
      const result = await handle.read(bytes, size, bytes.length - size, null);
      if (!result.bytesRead) break;
      size += result.bytesRead;
    }
    requireThat(size === stat.size, 'BACKUP_INPUT_CHANGED');
    return bytes.subarray(0, size);
  } finally { await handle.close(); }
}

// Extract only to a NEW private local directory. Never overwrite existing files,
// upload to a bucket, execute receipt content, or write database records.
export async function extractReceiptArchive(options) {
  const recovered = openReceiptArchive(options);
  const output = resolve(options.output);
  await mkdir(output, {mode: 0o700});
  try {
    await writeFile(join(output, 'manifest.json'), JSON.stringify(recovered.manifest, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
    await writeFile(join(output, 'original'), recovered.original, {mode: 0o600, flag: 'wx'});
    if (recovered.preview) await writeFile(join(output, 'preview.webp'), recovered.preview, {mode: 0o600, flag: 'wx'});
  } catch (error) { await rm(output, {recursive: true, force: true}); throw error; }
  return {verified: true, originalBytes: recovered.original.length, previewBytes: recovered.preview?.length ?? 0};
}

export function syntheticRecoveryDrill() {
  const key = randomBytes(32);
  const ownerId = randomUUID(), id = randomUUID();
  const original = Buffer.from('%PDF-1.7\nSynthetic recovery fixture only.\n');
  const receipt = {id, owner_id: ownerId, filename: 'synthetic.pdf', mime_type: 'application/pdf', byte_size: original.length, sha256: sha(original), preview_size: 0, preview_sha256: null, pages: 1, state: 'ready', details: {merchant: 'Synthetic test'}, reviewed: true, version: 1, created_at: '2026-10-07T00:00:00.000Z', updated_at: '2026-10-07T00:00:00.000Z'};
  try {
    const manifest = receiptRecoveryManifest({source: 'receipt_wiz', project: 'synthetic-project', ownerId, receipt});
    const archive = sealReceiptArchive({key, manifest, original});
    const expected = {key, archive, expectedOwnerId: ownerId, expectedReceiptId: id, expectedProject: 'synthetic-project'};
    const recovered = openReceiptArchive(expected);
    requireThat(recovered.original.equals(original), 'BACKUP_DRILL_FAILED');
    const damaged = Buffer.from(archive); damaged[damaged.length - 1] ^= 1;
    let corruptionRejected = false;
    try { openReceiptArchive({...expected, archive: damaged}); } catch (error) { corruptionRejected = error.code === 'BACKUP_AUTHENTICATION_FAILED'; }
    let wrongOwnerRejected = false;
    try { openReceiptArchive({...expected, expectedOwnerId: randomUUID()}); } catch (error) { wrongOwnerRejected = error.code === 'BACKUP_RESTORE_SCOPE_MISMATCH'; }
    requireThat(corruptionRejected && wrongOwnerRejected, 'BACKUP_DRILL_FAILED');
    return {status: 'pass', syntheticOnly: true, encryption: 'AES-256-GCM', originalHashVerified: true, corruptionRejected, wrongOwnerRejected, networkUsed: false, productionBackupActivated: false};
  } finally { key.fill(0); }
}

async function cli(args) {
  const [command, ...rest] = args;
  if (command === 'drill' && rest.length === 0) return syntheticRecoveryDrill();
  const allowed = new Set(['pack', 'verify', 'extract']);
  requireThat(allowed.has(command) && rest.length % 2 === 0, 'BACKUP_USAGE');
  const flags = {};
  for (let i = 0; i < rest.length; i += 2) {
    const name = rest[i];
    requireThat(['--input', '--archive', '--key-file', '--owner', '--receipt', '--project', '--output'].includes(name) && !Object.hasOwn(flags, name) && rest[i + 1], 'BACKUP_USAGE');
    flags[name] = rest[i + 1];
  }
  const needed = command === 'pack' ? ['--input', '--archive', '--key-file'] : ['--archive', '--key-file', '--owner', '--receipt', '--project', ...(command === 'extract' ? ['--output'] : [])];
  requireThat(needed.every(name => flags[name]) && Object.keys(flags).every(name => needed.includes(name)), 'BACKUP_USAGE');
  const key = await boundedFile(flags['--key-file'], 32, {privateFile: true});
  keyCheck(key);
  try {
    if (command === 'pack') {
      const dir = resolve(flags['--input']);
      const manifest = receiptRecoveryManifest(JSON.parse((await boundedFile(join(dir, 'manifest.json'), 32768)).toString('utf8')));
      const original = await boundedFile(join(dir, 'original'), 8388608);
      const preview = manifest.receipt.preview_size ? await boundedFile(join(dir, 'preview.webp'), 1048576) : null;
      const archive = sealReceiptArchive({key, manifest, original, preview});
      await writeFile(resolve(flags['--archive']), archive, {mode: 0o600, flag: 'wx'});
      return {encrypted: true, archiveBytes: archive.length, productionBackupActivated: false};
    }
    const options = {key, archive: await boundedFile(flags['--archive'], MAX_ARCHIVE), expectedOwnerId: flags['--owner'], expectedReceiptId: flags['--receipt'], expectedProject: flags['--project']};
    if (command === 'extract') return extractReceiptArchive({...options, output: flags['--output']});
    const recovered = openReceiptArchive(options);
    return {verified: true, originalBytes: recovered.original.length, previewBytes: recovered.preview?.length ?? 0};
  } finally { key.fill(0); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { console.log(JSON.stringify(await cli(process.argv.slice(2)))); }
  catch (error) { console.error(JSON.stringify({error: typeof error.code === 'string' && error.code.startsWith('BACKUP_') ? error.code : 'BACKUP_OPERATION_FAILED'})); process.exitCode = 1; }
}
