import {createClient} from '@supabase/supabase-js';
import {backupConfig, check, safeBackupCode, MAX_CATALOG_BYTES} from '../receipt_backup/config.mjs';
import {createBackblazeStore} from '../receipt_backup/backblaze.mjs';
import {createReceiptBackupSource} from '../receipt_backup/source.mjs';
import {runBackblazeProbe, runReceiptBackup, verifyRecoverableReceipt} from '../receipt_backup/runner.mjs';
import {extractReceiptArchive} from './receipt_backup.mjs';

// Server/operator-only commands. All credentials arrive through private environment variables.
// No application keys or recovery keys are accepted in command-line arguments.
async function main(args) {
  const [command, ...rest] = args;
  check(['probe', 'run', 'list-catalogs', 'recover'].includes(command), 'BACKUP_USAGE');
  const flags = {};
  if (command === 'recover') {
    check(rest.length === 10, 'BACKUP_USAGE');
    for (let i = 0; i < rest.length; i += 2) {
      const name = rest[i];
      check(['--catalog', '--owner', '--receipt', '--source', '--output'].includes(name) && !Object.hasOwn(flags, name)
        && typeof rest[i + 1] === 'string' && rest[i + 1].length > 0, 'BACKUP_USAGE');
      flags[name] = rest[i + 1];
    }
  } else check(rest.length === 0, 'BACKUP_USAGE');
  const config = backupConfig(process.env);
  check(config.mode === 'enabled' || (config.mode === 'probe' && command === 'probe'), 'BACKUP_NOT_ENABLED');
  const signal = AbortSignal.timeout(15 * 60 * 1000), store = createBackblazeStore(config);
  try {
    if (command === 'probe') return await runBackblazeProbe({store, project: config.project, signal});
    const prefix = config.prefix + 'v1/' + config.project + '/catalogs/';
    if (command === 'list-catalogs') return {catalogs: (await store.list(prefix, signal)).sort().reverse()};
    check(new URL(process.env.SUPABASE_URL).hostname === config.project + '.supabase.co'
      && Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY), 'BACKUP_SOURCE_INVALID');
    const database = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY,
      {auth: {persistSession: false, autoRefreshToken: false}});
    const source = createReceiptBackupSource(database, {project: config.project});
    if (command === 'run') return await runReceiptBackup({source, store, config, signal});
    check(flags['--catalog'].startsWith(prefix), 'BACKUP_RESTORE_SCOPE_MISMATCH');
    const catalogBytes = await store.get(flags['--catalog'], MAX_CATALOG_BYTES, signal);
    const archive = await verifyRecoverableReceipt({catalogBytes, source, store, config, signal,
      ownerId: flags['--owner'], receiptId: flags['--receipt'], sourceName: flags['--source']});
    const result = await extractReceiptArchive({key: config.key, archive, expectedOwnerId: flags['--owner'],
      expectedReceiptId: flags['--receipt'], expectedProject: config.project, output: flags['--output']});
    return {...result, productionRestorePerformed: false};
  } finally { config.key?.fill(0); store.close(); }
}

try { console.log(JSON.stringify(await main(process.argv.slice(2)))); }
catch (error) { console.error(JSON.stringify({error: safeBackupCode(error)})); process.exitCode = 1; }
