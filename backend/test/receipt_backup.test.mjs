import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash, randomBytes, randomUUID} from 'node:crypto';
import {mkdtemp, readFile, writeFile, mkdir, stat, rm, symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {receiptRecoveryManifest, sealReceiptArchive, openReceiptArchive, extractReceiptArchive, syntheticRecoveryDrill} from '../ops/receipt_backup.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
function fixture({source = 'receipt_wiz', withPreview = true} = {}) {
  const ownerId = randomUUID(), id = randomUUID(), key = randomBytes(32);
  const original = Buffer.from('Synthetic original receipt; no customer content.');
  const preview = withPreview ? Buffer.from('Synthetic preview.') : null;
  const receipt = {id, filename: 'synthetic.jpg', mime_type: 'image/jpeg', byte_size: original.length, sha256: hash(original), preview_size: preview?.length ?? 0, preview_sha256: preview ? hash(preview) : null, pages: 1, state: 'ready', created_at: '2026-10-07T00:00:00Z',
    ...(source === 'receipt_wiz' ? {owner_id: ownerId, details: {merchant: 'Synthetic merchant', total: '12.34'}, reviewed: true, version: 2, updated_at: '2026-10-07T00:00:00Z'} : {business_id: randomUUID(), created_by: ownerId, ready_at: '2026-10-07T00:00:00Z'})};
  const input = {source, ownerId, project: 'synthetic-project', receipt, ...(source === 'bookkeeping' ? {businessOwnerId: ownerId} : {})};
  const manifest = receiptRecoveryManifest(input);
  const archive = sealReceiptArchive({key, manifest, original, preview});
  const expected = {key, archive, expectedOwnerId: ownerId, expectedReceiptId: id, expectedProject: input.project};
  return {input, manifest, key, original, preview, archive, expected};
}

test('Receipt Wiz encrypted round trip preserves originals, preview and reviewed metadata', () => {
  const f = fixture();
  const recovered = openReceiptArchive(f.expected);
  assert.deepEqual(recovered.manifest, f.manifest);
  assert.deepEqual(recovered.original, f.original);
  assert.deepEqual(recovered.preview, f.preview);
  for (const privateText of [f.input.ownerId, f.input.receipt.id, 'Synthetic merchant', 'synthetic.jpg']) assert.equal(f.archive.includes(Buffer.from(privateText)), false);
  assert.notDeepEqual(sealReceiptArchive(f), f.archive, 'Fresh nonces must produce different ciphertext');
});

test('legacy Bookkeeping originals preserve business-bound storage paths', () => {
  const f = fixture({source: 'bookkeeping'});
  const recovered = openReceiptArchive(f.expected);
  assert.equal(recovered.manifest.originalPath, `${f.input.ownerId}/${f.input.receipt.business_id}/${f.input.receipt.id}/original`);
  assert.equal(recovered.manifest.bucket, 'korlix-bookkeeping-receipts');
  assert.throws(() => receiptRecoveryManifest({...f.input, businessOwnerId: randomUUID()}), {code: 'BACKUP_OWNER_MISMATCH'});
});

test('PDF/no-preview recovery does not invent a second object', () => {
  const f = fixture({withPreview: false});
  f.input.receipt.mime_type = 'application/pdf';
  f.input.receipt.filename = 'synthetic.pdf';
  const manifest = receiptRecoveryManifest(f.input);
  const archive = sealReceiptArchive({...f, manifest});
  const recovered = openReceiptArchive({...f.expected, archive});
  assert.equal(recovered.preview, null);
  assert.equal(recovered.manifest.previewPath, null);
});

test('tampered ciphertext and wrong encryption keys fail authentication', () => {
  const f = fixture();
  const archive = Buffer.from(f.archive); archive[archive.length - 2] ^= 1;
  assert.throws(() => openReceiptArchive({...f.expected, archive}), {code: 'BACKUP_AUTHENTICATION_FAILED'});
  assert.throws(() => openReceiptArchive({...f.expected, key: randomBytes(32)}), {code: 'BACKUP_AUTHENTICATION_FAILED'});
});

test('restore requires the independently expected owner, receipt and source project', () => {
  const f = fixture();
  for (const change of [{expectedOwnerId: randomUUID()}, {expectedReceiptId: randomUUID()}, {expectedProject: 'different-project'}]) assert.throws(() => openReceiptArchive({...f.expected, ...change}), {code: 'BACKUP_RESTORE_SCOPE_MISMATCH'});
  assert.throws(() => openReceiptArchive({...f.expected, expectedOwnerId: undefined}), {code: 'BACKUP_EXPECTED_IDENTITY_REQUIRED'});
});

test('cross-owner metadata, traversal identifiers and non-ready rows cannot be archived', () => {
  const f = fixture();
  assert.throws(() => receiptRecoveryManifest({...f.input, ownerId: randomUUID()}), {code: 'BACKUP_OWNER_MISMATCH'});
  assert.throws(() => receiptRecoveryManifest({...f.input, receipt: {...f.input.receipt, id: '../../outside'}}), {code: 'BACKUP_RECEIPT_NOT_READY'});
  for (const state of ['uploading', 'deleting', 'removed']) assert.throws(() => receiptRecoveryManifest({...f.input, receipt: {...f.input.receipt, state}}), {code: 'BACKUP_RECEIPT_NOT_READY'});
  assert.throws(() => receiptRecoveryManifest({...f.input, receipt: {...f.input.receipt, service_role: 'never-accept-credentials'}}), {code: 'BACKUP_METADATA_FIELDS_INVALID'});
});

test('creation verifies both actual files against database hashes and sizes', () => {
  const f = fixture();
  assert.throws(() => sealReceiptArchive({...f, original: Buffer.from('damaged')}), {code: 'BACKUP_ORIGINAL_INTEGRITY'});
  assert.throws(() => sealReceiptArchive({...f, preview: null}), {code: 'BACKUP_PREVIEW_INTEGRITY'});
  assert.throws(() => sealReceiptArchive({...f, preview: Buffer.from('damaged')}), {code: 'BACKUP_PREVIEW_INTEGRITY'});
});

test('bounded metadata and strict key/archive shape fail closed', () => {
  const f = fixture();
  assert.throws(() => receiptRecoveryManifest({...f.input, receipt: {...f.input.receipt, details: {text: 'x'.repeat(17000)}}}), {code: 'BACKUP_METADATA_INVALID'});
  assert.throws(() => sealReceiptArchive({...f, key: Buffer.alloc(31)}), {code: 'BACKUP_KEY_INVALID'});
  assert.throws(() => openReceiptArchive({...f.expected, archive: f.archive.subarray(0, 25)}), {code: 'BACKUP_ARCHIVE_INVALID'});
  assert.throws(() => openReceiptArchive({...f.expected, archive: Buffer.alloc(14 * 1024 * 1024)}), {code: 'BACKUP_ARCHIVE_INVALID'});
});

test('offline extraction creates private files and refuses overwriting a destination', async t => {
  const root = await mkdtemp(join(tmpdir(), 'receipt-recovery-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const f = fixture(); const output = join(root, 'restore');
  assert.deepEqual(await extractReceiptArchive({...f.expected, output}), {verified: true, originalBytes: f.original.length, previewBytes: f.preview.length});
  assert.deepEqual(await readFile(join(output, 'original')), f.original);
  assert.deepEqual(JSON.parse(await readFile(join(output, 'manifest.json'), 'utf8')), f.manifest);
  assert.equal((await stat(output)).mode & 0o777, 0o700);
  assert.equal((await stat(join(output, 'original'))).mode & 0o777, 0o600);
  await assert.rejects(extractReceiptArchive({...f.expected, output}), {code: 'EEXIST'});
  assert.deepEqual(await readFile(join(output, 'original')), f.original);
});

test('wrong-scope extraction creates no output directory', async t => {
  const root = await mkdtemp(join(tmpdir(), 'receipt-recovery-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const f = fixture(); const output = join(root, 'restore');
  await assert.rejects(extractReceiptArchive({...f.expected, expectedOwnerId: randomUUID(), output}), {code: 'BACKUP_RESTORE_SCOPE_MISMATCH'});
  await assert.rejects(stat(output), {code: 'ENOENT'});
});

test('CLI pack/verify/extract use private keys, emit no receipt content and refuse key symlinks', async t => {
  const root = await mkdtemp(join(tmpdir(), 'receipt-recovery-cli-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const f = fixture(); const input = join(root, 'input'); await mkdir(input);
  await writeFile(join(input, 'manifest.json'), JSON.stringify(f.manifest));
  await writeFile(join(input, 'original'), f.original); await writeFile(join(input, 'preview.webp'), f.preview);
  const keyFile = join(root, 'key'); await writeFile(keyFile, f.key, {mode: 0o600});
  const archive = join(root, 'receipt.enc');
  const script = fileURLToPath(new URL('../ops/receipt_backup.mjs', import.meta.url));
  const run = args => spawnSync(process.execPath, [script, ...args], {encoding: 'utf8'});
  const packed = run(['pack', '--input', input, '--archive', archive, '--key-file', keyFile]);
  assert.equal(packed.status, 0, packed.stderr);
  assert.equal((await stat(archive)).mode & 0o777, 0o600);
  const options = ['--archive', archive, '--key-file', keyFile, '--owner', f.input.ownerId, '--receipt', f.input.receipt.id, '--project', f.input.project];
  const verified = run(['verify', ...options]); assert.equal(verified.status, 0, verified.stderr);
  const extracted = run(['extract', ...options, '--output', join(root, 'extracted')]); assert.equal(extracted.status, 0, extracted.stderr);
  for (const result of [packed, verified, extracted]) {
    assert.equal((result.stdout + result.stderr).includes('Synthetic merchant'), false);
    assert.equal((result.stdout + result.stderr).includes(f.input.ownerId), false);
    assert.equal((result.stdout + result.stderr).includes(f.key.toString('hex')), false);
  }
  const link = join(root, 'key-link'); await symlink(keyFile, link);
  const denied = run(['verify', ...options.map(value => value === keyFile ? link : value)]);
  assert.equal(denied.status, 1);
  assert.deepEqual(JSON.parse(denied.stderr), {error: 'BACKUP_OPERATION_FAILED'});
  const publicKey = join(root, 'bad-key'); await writeFile(publicKey, f.key, {mode: 0o644});
  const publicDenied = run(['verify', ...options.map(value => value === keyFile ? publicKey : value)]);
  assert.equal(publicDenied.status, 1);
  assert.deepEqual(JSON.parse(publicDenied.stderr), {error: 'BACKUP_KEY_PERMISSIONS'});
});

test('synthetic recovery drill clearly reports no production activation', () => {
  const result = syntheticRecoveryDrill();
  assert.equal(result.status, 'pass');
  assert.equal(result.originalHashVerified, true);
  assert.equal(result.corruptionRejected, true);
  assert.equal(result.wrongOwnerRejected, true);
  assert.equal(result.networkUsed, false);
  assert.equal(result.productionBackupActivated, false);
});
