import {backupConfig, safeBackupCode, check} from './config.mjs';
import {createBackblazeStore} from './backblaze.mjs';
import {createReceiptBackupSource} from './source.mjs';
import {runBackblazeProbe, runReceiptBackup} from './runner.mjs';

// Runs inside the existing paid backend. A restart performs catch-up after 15s.
// No customer API route, incoming trigger, or production deletion capability is exposed.
export function startReceiptBackupRuntime({database, env = process.env, logger = console,
  timers = {setTimeout, clearTimeout}, storeFactory = createBackblazeStore, sourceFactory = createReceiptBackupSource}) {
  const controller = new AbortController();
  let timer, store, config, running = false, validated = false;
  const status = {mode: 'off', lastSuccessAt: null, lastFailureAt: null, lastError: null};
  const log = (event, fields, failed = false) => logger[failed ? 'error' : 'info'](JSON.stringify({event, ...fields}));
  try {
    config = backupConfig(env); status.mode = config.mode;
    if (config.mode === 'off') return {stop() {}, getStatus: () => ({...status})};
    if (config.mode === 'enabled') {
      check(new URL(env.SUPABASE_URL).hostname === config.project + '.supabase.co', 'BACKUP_SOURCE_INVALID');
    }
    store = storeFactory(config);
  } catch (error) {
    status.lastError = safeBackupCode(error);
    log('receipt_backup_configuration', {status: 'blocked', code: status.lastError}, true);
    return {stop() {}, getStatus: () => ({...status})};
  }
  async function tick() {
    if (running || controller.signal.aborted) return;
    running = true;
    let failed = false;
    const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(15 * 60 * 1000)]);
    try {
      if (!validated) {
        const probe = await runBackblazeProbe({store, project: config.project, prefix: config.prefix, signal});
        log('receipt_backup_probe', probe); validated = true;
      }
      if (config.mode === 'enabled') {
        const result = await runReceiptBackup({store, source: sourceFactory(database, {project: config.project}), config, signal});
        status.lastSuccessAt = result.completedAt; status.lastError = null;
        log('receipt_backup_run', result);
      }
    } catch (error) {
      failed = true; status.lastFailureAt = new Date().toISOString(); status.lastError = safeBackupCode(error);
      log('receipt_backup_failure', {mode: config.mode, code: status.lastError,
        lastSuccessAt: status.lastSuccessAt, retryMinutes: config.mode === 'enabled' ? 15 : null}, true);
    } finally {
      running = false;
      if (config.mode === 'enabled' && !controller.signal.aborted) {
        timer = timers.setTimeout(tick, (failed ? 15 : 60) * 60 * 1000); timer?.unref?.();
      } else { store.close(); }
    }
  }
  timer = timers.setTimeout(tick, 15000); timer?.unref?.();
  log('receipt_backup_configuration', {mode: config.mode, intervalMinutes: config.mode === 'enabled' ? 60 : null,
    productionBackupsActive: false, state: 'awaiting-verification'});
  return {
    stop() { controller.abort(); timers.clearTimeout(timer); store.close(); config.key?.fill(0); },
    getStatus: () => ({...status}),
  };
}
