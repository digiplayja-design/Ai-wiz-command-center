#!/usr/bin/env node
import {applicationBackupConfig, check} from '../application_backup/archive.mjs';
import {createApplicationBackupStore} from '../application_backup/store.mjs';
import {createPostgresBackupSource} from '../application_backup/postgres.mjs';
import {runApplicationProbe, runApplicationBackup} from '../application_backup/runner.mjs';
import {extractApplicationBackup} from '../application_backup/recovery.mjs';
import {safeBackupCode} from '../receipt_backup/config.mjs';

let store, config;
try {
  const command = process.argv[2], args = process.argv.slice(3);
  check(['probe','run','recover'].includes(command), 'BACKUP_APP_COMMAND_INVALID');
  const environment = command === 'recover' ? {...process.env, KORLIX_BACKUP_MODE:'probe'} : process.env;
  config = applicationBackupConfig(environment);
  check(config.mode !== 'off', 'BACKUP_APP_NOT_ENABLED');
  store = createApplicationBackupStore(config);
  const signal = AbortSignal.timeout(20 * 60 * 1000);
  let result;
  if (command === 'probe') result = await runApplicationProbe({store,config,signal});
  if (command === 'run') {
    check(config.mode === 'enabled' && args.length === 0, 'BACKUP_APP_NOT_ENABLED');
    result = await runApplicationBackup({store,config,source:createPostgresBackupSource(),signal});
  }
  if (command === 'recover') {
    check(args.length === 5 && args[0] === '--catalog' && args[2] === '--output' && args[4] === '--isolated',
      'BACKUP_APP_COMMAND_INVALID');
    result = await extractApplicationBackup({store,config,catalogKey:args[1],output:args[3],signal,
      expectedProject:config.project,acknowledgeIsolatedRecovery:true});
  }
  console.log(JSON.stringify(result));
} catch (error) { console.error(JSON.stringify({status:'failed',code:safeBackupCode(error)})); process.exitCode = 1; }
finally { store?.close(); config?.key?.fill(0); }
