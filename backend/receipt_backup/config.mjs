import {createHash} from 'node:crypto';

export function backupError(code) { const error = new Error(code); error.code = code; return error; }
export function check(value, code) { if (!value) throw backupError(code); }
export const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export const MAX_ARCHIVE_BYTES = 13 * 1024 * 1024;
export const MAX_CATALOG_BYTES = 8 * 1024 * 1024;
export const SOURCE_PROJECT = 'uxtjzjbwtppjvnsoiijv';

export function backupConfig(env = process.env) {
  const mode = env.RECEIPT_BACKUP_MODE || 'off';
  check(['off', 'probe', 'enabled'].includes(mode), 'BACKUP_MODE_INVALID');
  if (mode === 'off') return {mode};
  const endpoint = env.RECEIPT_BACKUP_B2_ENDPOINT;
  const region = env.RECEIPT_BACKUP_B2_REGION;
  const bucket = env.RECEIPT_BACKUP_B2_BUCKET;
  const prefix = env.RECEIPT_BACKUP_B2_PREFIX;
  // Pin the destination chosen in the setup. No arbitrary URL receives credentials.
  check(endpoint === 'https://s3.us-east-005.backblazeb2.com' && region === 'us-east-005'
    && bucket === 'korlix-backups' && prefix === 'receipts/', 'BACKUP_DESTINATION_INVALID');
  const accessKeyId = (env.RECEIPT_BACKUP_B2_KEY_ID || '').trim();
  const secretAccessKey = (env.RECEIPT_BACKUP_B2_APPLICATION_KEY || '').trim();
  check(/^[a-zA-Z0-9]{10,100}$/.test(accessKeyId) && /^[a-zA-Z0-9_+\/=\-]{10,200}$/.test(secretAccessKey), 'BACKUP_CREDENTIALS_MISSING');
  const config = {mode, endpoint, region, bucket, prefix, project: SOURCE_PROJECT, accessKeyId, secretAccessKey};
  if (mode === 'enabled') {
    const encoded = env.RECEIPT_BACKUP_RECOVERY_KEY_BASE64 || '';
    check(/^[A-Za-z0-9+/]{43}=$/.test(encoded), 'BACKUP_RECOVERY_KEY_INVALID');
    config.key = Buffer.from(encoded, 'base64');
    check(config.key.length === 32 && config.key.toString('base64') === encoded, 'BACKUP_RECOVERY_KEY_INVALID');
    check(env.RECEIPT_BACKUP_RECOVERY_KEY_ESCROWED === 'true', 'BACKUP_RECOVERY_KEY_CUSTODY_REQUIRED');
    check(env.RECEIPT_BACKUP_RETENTION_CONFIGURED === 'true', 'BACKUP_RETENTION_CONFIGURATION_REQUIRED');
    check(env.RECEIPT_BACKUP_PRIVACY_DISCLOSURE_READY === 'true', 'BACKUP_PRIVACY_DISCLOSURE_REQUIRED');
    config.keyFingerprint = hash(config.key).slice(0, 16);
    check(env.RECEIPT_BACKUP_RECOVERY_KEY_FINGERPRINT === config.keyFingerprint, 'BACKUP_RECOVERY_KEY_CUSTODY_MISMATCH');
  }
  return config;
}

// No provider messages, URLs, filenames, tokens, or customer identifiers in logs.
export function safeBackupCode(error) {
  return typeof error?.code === 'string' && /^BACKUP_[A-Z0-9_]{1,80}$/.test(error.code)
    ? error.code : 'BACKUP_OPERATION_FAILED';
}
