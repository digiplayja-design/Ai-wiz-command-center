import {check, backupError, SOURCE_PROJECT} from './config.mjs';
import {receiptRecoveryManifest} from '../ops/receipt_backup.mjs';

const COMMON = 'id,filename,mime_type,byte_size,sha256,preview_size,preview_sha256,pages,state,created_at';
export const RECEIPT_SOURCES = {
  receipt_wiz: {table: 'korlix_receipt_wiz', columns: COMMON + ',owner_id,details,reviewed,version,updated_at'},
  bookkeeping: {table: 'korlix_bookkeeping_receipts', columns: COMMON + ',business_id,created_by,ready_at'},
};
export function createReceiptBackupSource(database, {project = SOURCE_PROJECT, now = () => new Date()} = {}) {
  check(database && project === SOURCE_PROJECT, 'BACKUP_SOURCE_INVALID');
  async function read(query) {
    const result = await query.abortSignal(AbortSignal.timeout(30000));
    if (result.error) throw backupError('BACKUP_SOURCE_QUERY_FAILED');
    return result.data;
  }
  async function manifest(source, receipt) {
    const ownerId = source === 'receipt_wiz' ? receipt.owner_id : receipt.created_by;
    let businessOwnerId;
    if (source === 'bookkeeping') {
      const business = await read(database.from('korlix_bookkeeping_businesses').select('owner_id').eq('id', receipt.business_id).maybeSingle());
      check(business?.owner_id === ownerId, 'BACKUP_OWNER_MISMATCH');
      businessOwnerId = business.owner_id;
    }
    return receiptRecoveryManifest({source, project, ownerId, receipt, ...(businessOwnerId ? {businessOwnerId} : {}),
      capturedAt: now().toISOString()});
  }
  return {
    async list(maximum = 10000, signal) {
      const records = [];
      for (const [source, spec] of Object.entries(RECEIPT_SOURCES)) {
        let cursor;
        while (true) {
          signal?.throwIfAborted();
          let query = database.from(spec.table).select(spec.columns).eq('state', 'ready').order('id').limit(100);
          if (cursor) query = query.gt('id', cursor);
          const rows = await read(query);
          check(Array.isArray(rows), 'BACKUP_SOURCE_QUERY_FAILED');
          for (const row of rows) {
            signal?.throwIfAborted();
            check(!cursor || row.id > cursor, 'BACKUP_SOURCE_PAGE_INVALID');
            cursor = row.id;
            records.push(await manifest(source, row));
            check(records.length <= maximum, 'BACKUP_RECEIPT_LIMIT');
          }
          if (rows.length < 100) break;
        }
      }
      return records;
    },
    async current(record) {
      const spec = RECEIPT_SOURCES[record.source];
      check(spec, 'BACKUP_SOURCE_INVALID');
      const row = await read(database.from(spec.table).select(spec.columns).eq('id', record.receipt.id).maybeSingle());
      return row?.state === 'ready' ? manifest(record.source, row) : null;
    },
    async download(record, kind, parent) {
      check(kind === 'original' || kind === 'preview', 'BACKUP_SOURCE_INVALID');
      const path = kind === 'original' ? record.originalPath : record.previewPath;
      const size = kind === 'original' ? record.receipt.byte_size : record.receipt.preview_size;
      check(path && size > 0, 'BACKUP_SOURCE_INVALID');
      const result = await database.storage.from(record.bucket).download(path, {}, {cache: 'no-store',
        signal: parent ? AbortSignal.any([parent, AbortSignal.timeout(45000)]) : AbortSignal.timeout(45000)});
      if (result.error || !result.data) throw backupError('BACKUP_SOURCE_DOWNLOAD_FAILED');
      check(result.data.size === size, 'BACKUP_SOURCE_SIZE_MISMATCH');
      return Buffer.from(await result.data.arrayBuffer());
    },
    async ownerActive(ownerId) {
      const profile = await read(database.from('user_profiles').select('id,is_disabled').eq('id', ownerId).maybeSingle());
      return profile?.id === ownerId && profile.is_disabled !== true;
    },
  };
}
