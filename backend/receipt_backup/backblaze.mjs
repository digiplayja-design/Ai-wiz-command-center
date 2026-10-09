import {S3Client, PutObjectCommand, GetObjectCommand, ListObjectsV2Command, DeleteObjectCommand} from '@aws-sdk/client-s3';
import {check, backupError, MAX_ARCHIVE_BYTES} from './config.mjs';

export async function readBoundedStream(body, maximum) {
  const chunks = [];
  let total = 0;
  try {
    for await (const chunk of body) {
      const bytes = Buffer.from(chunk);
      total += bytes.length;
      check(total <= maximum, 'BACKUP_REMOTE_TOO_LARGE');
      chunks.push(bytes);
    }
    return Buffer.concat(chunks, total);
  } finally { body?.destroy?.(); }
}

export function createBackblazeStore(config, {client, fetchImpl = fetch} = {}) {
  const sdk = client || new S3Client({
    endpoint: config.endpoint, region: config.region, forcePathStyle: true,
    credentials: {accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey},
    maxAttempts: 3, requestChecksumCalculation: 'WHEN_REQUIRED', responseChecksumValidation: 'WHEN_REQUIRED',
  });
  function scoped(key) {
    check(typeof key === 'string' && key.startsWith(config.prefix) && key.length <= 800
      && /^[a-zA-Z0-9_./-]+$/.test(key) && !key.includes('..') && !key.includes('//'), 'BACKUP_KEY_SCOPE_INVALID');
    return {Bucket: config.bucket, Key: key};
  }
  function signal(parent) {
    return parent ? AbortSignal.any([parent, AbortSignal.timeout(60000)]) : AbortSignal.timeout(60000);
  }
  async function send(command, parent) {
    try { return await sdk.send(command, {abortSignal: signal(parent)}); }
    catch (error) {
      if (error?.name === 'NoSuchKey') throw backupError('BACKUP_OBJECT_MISSING');
      if (error?.$metadata?.httpStatusCode === 401 || error?.$metadata?.httpStatusCode === 403) throw backupError('BACKUP_ACCESS_DENIED');
      if (error?.$metadata?.httpStatusCode === 404) throw backupError('BACKUP_OBJECT_MISSING');
      throw backupError('BACKUP_PROVIDER_REQUEST_FAILED');
    }
  }
  return {
    async put(key, bytes, parent) {
      check(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= MAX_ARCHIVE_BYTES, 'BACKUP_UPLOAD_SIZE_INVALID');
      const result = await send(new PutObjectCommand({...scoped(key), Body: bytes, ContentLength: bytes.length,
        ContentType: 'application/octet-stream', CacheControl: 'no-store', ServerSideEncryption: 'AES256'}), parent);
      return {versionId: result.VersionId};
    },
    async get(key, maximum = MAX_ARCHIVE_BYTES, parent) {
      let result;
      try { result = await send(new GetObjectCommand(scoped(key)), parent); }
      catch (error) { if (error.code === 'BACKUP_OBJECT_MISSING') return null; throw error; }
      try {
        check(Number.isSafeInteger(result.ContentLength) && result.ContentLength > 0 && result.ContentLength <= maximum,
          'BACKUP_REMOTE_TOO_LARGE');
        const bytes = await readBoundedStream(result.Body, maximum);
        check(bytes.length === result.ContentLength, 'BACKUP_REMOTE_TRUNCATED');
        return bytes;
      } finally { result.Body?.destroy?.(); }
    },
    async list(prefix, parent) {
      scoped(prefix);
      const keys = [];
      let continuation;
      do {
        const result = await send(new ListObjectsV2Command({Bucket: config.bucket, Prefix: prefix,
          MaxKeys: 1000, ...(continuation ? {ContinuationToken: continuation} : {})}), parent);
        for (const item of result.Contents || []) { scoped(item.Key); keys.push(item.Key); }
        check(keys.length <= 20000, 'BACKUP_LIST_LIMIT');
        const next = result.IsTruncated ? result.NextContinuationToken : undefined;
        check(!result.IsTruncated || (typeof next === 'string' && next !== continuation), 'BACKUP_LIST_INCOMPLETE');
        continuation = next;
      } while (continuation);
      return keys;
    },
    async assertPrivate(key, parent) {
      scoped(key);
      let response;
      try {
        response = await fetchImpl(config.endpoint + '/' + config.bucket + '/' + key, {
          method: 'GET', headers: {Range: 'bytes=0-0'}, redirect: 'error', cache: 'no-store', signal: signal(parent),
        });
        // Must actually deny access. A 404/network error is not privacy evidence.
        check(response.status === 401 || response.status === 403, 'BACKUP_PUBLIC_ACCESS_NOT_DENIED');
      } finally { await response?.body?.cancel(); }
    },
    async deleteProbe(key, versionId, parent) {
      check(/^receipts\/_probe\/[a-f0-9-]{36}\.enc$/.test(key) && typeof versionId === 'string' && versionId.length > 0,
        'BACKUP_PROBE_DELETE_SCOPE_INVALID');
      await send(new DeleteObjectCommand({...scoped(key), VersionId: versionId}), parent);
    },
    close() { sdk.destroy?.(); },
  };
}
