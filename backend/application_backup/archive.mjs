import {createCipheriv, createDecipheriv, createHmac, hkdfSync, randomBytes} from 'node:crypto';
import {check, backupError, hash, SOURCE_PROJECT} from '../receipt_backup/config.mjs';

export {check, backupError, hash, SOURCE_PROJECT};
export const MAX_PART = 128 * 1024 * 1024;
export const MAX_CATALOG = 16 * 1024 * 1024;
export const PREFIX = 'application/';
const MAGIC = Buffer.from('KORLIXB1');
const KINDS = new Set(['probe', 'object', 'database', 'configuration', 'recovery-controls', 'source', 'catalog']);

export function applicationBackupConfig(env = process.env) {
  const mode = env.KORLIX_BACKUP_MODE || 'off';
  check(['off', 'probe', 'enabled'].includes(mode), 'BACKUP_APP_MODE_INVALID');
  if (mode === 'off') return {mode};
  const accessKeyId = env.KORLIX_BACKUP_B2_KEY_ID || '';
  const secretAccessKey = env.KORLIX_BACKUP_B2_APPLICATION_KEY || '';
  check(/^[a-zA-Z0-9]{10,100}$/.test(accessKeyId) && /^[a-zA-Z0-9_+/=\-]{10,200}$/.test(secretAccessKey),
    'BACKUP_APP_CREDENTIALS_MISSING');
  // A separate key must be restricted to application/. Never evade the receipts/ restriction.
  const encoded = env.RECEIPT_BACKUP_RECOVERY_KEY_BASE64 || '';
  check(/^[A-Za-z0-9+/]{43}=$/.test(encoded), 'BACKUP_APP_RECOVERY_KEY_INVALID');
  const master = Buffer.from(encoded, 'base64');
  try {
    check(master.length === 32 && master.toString('base64') === encoded, 'BACKUP_APP_RECOVERY_KEY_INVALID');
    check(env.RECEIPT_BACKUP_RECOVERY_KEY_ESCROWED === 'true'
      && hash(master).slice(0, 16) === env.RECEIPT_BACKUP_RECOVERY_KEY_FINGERPRINT, 'BACKUP_APP_RECOVERY_CUSTODY_REQUIRED');
    const key = Buffer.from(hkdfSync('sha256', master, SOURCE_PROJECT, 'korlix-application-backup-v1', 32));
    const config = {mode, key, keyFingerprint: hash(key).slice(0, 16), project: SOURCE_PROJECT,
      endpoint: 'https://s3.us-east-005.backblazeb2.com', region: 'us-east-005', bucket: 'korlix-backups',
      prefix: PREFIX, accessKeyId, secretAccessKey};
    if (mode === 'enabled') {
      check(env.KORLIX_BACKUP_RETENTION_CONFIGURED === 'true', 'BACKUP_APP_RETENTION_REQUIRED');
      check(env.KORLIX_BACKUP_PRIVACY_DISCLOSURE_READY === 'true', 'BACKUP_APP_PRIVACY_DISCLOSURE_REQUIRED');
    }
    return config;
  } finally { master.fill(0); }
}

export function opaque(config, identity) {
  return createHmac('sha256', config.key).update(identity).digest('hex');
}

function aad(config, kind, identity) {
  check(config.project === SOURCE_PROJECT && KINDS.has(kind) && typeof identity === 'string'
    && identity.length > 0 && identity.length <= 4096, 'BACKUP_APP_BINDING_INVALID');
  return Buffer.from(JSON.stringify(['korlix-application-v1', config.project, kind, identity]));
}

export function sealPart(config, kind, identity, metadata, bytes) {
  check(Buffer.isBuffer(bytes) && bytes.length <= MAX_PART - 65536, 'BACKUP_APP_PART_LIMIT');
  const header = Buffer.from(JSON.stringify({version: 1, project: config.project, kind, identity,
    metadata, byteSize: bytes.length, sha256: hash(bytes)}));
  check(header.length <= 60000, 'BACKUP_APP_METADATA_LIMIT');
  const length = Buffer.alloc(4); length.writeUInt32BE(header.length);
  const nonce = randomBytes(12), cipher = createCipheriv('aes-256-gcm', config.key, nonce);
  cipher.setAAD(aad(config, kind, identity));
  return Buffer.concat([MAGIC, nonce, cipher.update(length), cipher.update(header), cipher.update(bytes),
    cipher.final(), cipher.getAuthTag()]);
}

export function openPart(config, kind, identity, archive) {
  check(Buffer.isBuffer(archive) && archive.length >= 40 && archive.length <= MAX_PART
    && archive.subarray(0, 8).equals(MAGIC), 'BACKUP_APP_ARCHIVE_INVALID');
  let plaintext;
  try {
    const cipher = createDecipheriv('aes-256-gcm', config.key, archive.subarray(8, 20));
    cipher.setAAD(aad(config, kind, identity)); cipher.setAuthTag(archive.subarray(-16));
    plaintext = Buffer.concat([cipher.update(archive.subarray(20, -16)), cipher.final()]);
    const size = plaintext.readUInt32BE(0);
    check(size <= 60000 && size + 4 <= plaintext.length, 'BACKUP_APP_ARCHIVE_INVALID');
    const header = JSON.parse(plaintext.subarray(4, size + 4).toString('utf8'));
    const bytes = Buffer.from(plaintext.subarray(size + 4));
    check(header.version === 1 && header.project === config.project && header.kind === kind && header.identity === identity
      && header.byteSize === bytes.length && header.sha256 === hash(bytes), 'BACKUP_APP_INTEGRITY_FAILED');
    return {metadata: header.metadata, bytes, sha256: header.sha256};
  } catch { throw backupError('BACKUP_APP_INTEGRITY_FAILED'); }
  finally { plaintext?.fill(0); }
}
