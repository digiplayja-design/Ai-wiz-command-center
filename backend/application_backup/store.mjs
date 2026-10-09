import {S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand} from '@aws-sdk/client-s3';
import {readBoundedStream} from '../receipt_backup/backblaze.mjs';
import {check, backupError, MAX_PART, PREFIX} from './archive.mjs';

export function createApplicationBackupStore(config, {client, fetchImpl = fetch} = {}) {
  const sdk = client || new S3Client({endpoint: config.endpoint, region: config.region, forcePathStyle: true,
    credentials: {accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey}, maxAttempts: 3,
    requestChecksumCalculation: 'WHEN_REQUIRED', responseChecksumValidation: 'WHEN_REQUIRED'});
  const scoped = key => {
    check(config.prefix === PREFIX && typeof key === 'string' && key.startsWith(PREFIX)
      && key.length <= 800 && /^[a-zA-Z0-9_./-]+$/.test(key) && !key.includes('..') && !key.includes('//'),
    'BACKUP_APP_DESTINATION_SCOPE_INVALID');
    return {Bucket: config.bucket, Key: key};
  };
  const timeout = parent => parent ? AbortSignal.any([parent, AbortSignal.timeout(120000)]) : AbortSignal.timeout(120000);
  async function send(command, signal) {
    try { return await sdk.send(command, {abortSignal: timeout(signal)}); }
    catch (e) {
      if (e?.name === 'NoSuchKey' || e?.$metadata?.httpStatusCode === 404) throw backupError('BACKUP_APP_OBJECT_MISSING');
      if ([401, 403].includes(e?.$metadata?.httpStatusCode)) throw backupError('BACKUP_APP_ACCESS_DENIED');
      throw backupError('BACKUP_APP_PROVIDER_FAILED');
    }
  }
  return {
    async put(key, bytes, signal) {
      check(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= MAX_PART, 'BACKUP_APP_PART_LIMIT');
      const r = await send(new PutObjectCommand({...scoped(key), Body: bytes, ContentLength: bytes.length,
        ContentType: 'application/octet-stream', CacheControl: 'no-store', ServerSideEncryption: 'AES256'}), signal);
      return {versionId: r.VersionId};
    },
    async get(key, signal) {
      let r;
      try { r = await send(new GetObjectCommand(scoped(key)), signal); }
      catch (e) { if (e.code === 'BACKUP_APP_OBJECT_MISSING') return null; throw e; }
      try {
        check(Number.isSafeInteger(r.ContentLength) && r.ContentLength > 0 && r.ContentLength <= MAX_PART,
          'BACKUP_APP_PART_LIMIT');
        const bytes = await readBoundedStream(r.Body, MAX_PART);
        check(bytes.length === r.ContentLength, 'BACKUP_APP_REMOTE_TRUNCATED');
        return bytes;
      } finally { r.Body?.destroy?.(); }
    },
    async assertPrivate(key, signal) {
      scoped(key);
      const r = await fetchImpl(config.endpoint + '/' + config.bucket + '/' + key,
        {redirect: 'error', headers: {Range: 'bytes=0-0'}, cache: 'no-store', signal: timeout(signal)});
      try { check([401, 403].includes(r.status), 'BACKUP_APP_PUBLIC_ACCESS_NOT_DENIED'); }
      finally { await r.body?.cancel(); }
    },
    async deleteProbe(key, versionId, signal) {
      check(/^application\/_probe\/[a-f0-9-]{36}\.enc$/.test(key) && typeof versionId === 'string' && versionId.length > 0,
        'BACKUP_APP_PROBE_DELETE_SCOPE_INVALID');
      await send(new DeleteObjectCommand({...scoped(key), VersionId: versionId}), signal);
    },
    close() { sdk.destroy?.(); },
  };
}
