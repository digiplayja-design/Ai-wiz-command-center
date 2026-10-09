import {applicationBackupConfig} from './archive.mjs';
import {createApplicationBackupStore} from './store.mjs';
import {createPostgresBackupSource} from './postgres.mjs';
import {runApplicationProbe, runApplicationBackup} from './runner.mjs';
import {safeBackupCode} from '../receipt_backup/config.mjs';
import {createReceiptBackupAlerts} from '../receipt_backup/alerts.mjs';

export function startApplicationBackupRuntime({env = process.env, logger = console, timers = {setTimeout, clearTimeout},
  storeFactory = createApplicationBackupStore, sourceFactory = createPostgresBackupSource,
  alertsFactory = createReceiptBackupAlerts, probe = runApplicationProbe, run = runApplicationBackup,
  now = () => new Date()} = {}) {
  const controller = new AbortController();
  const status = {mode: env.KORLIX_BACKUP_MODE || 'off', lastSuccessAt: null, lastDatabaseAt: null, lastError: null};
  const log = (event, fields, failed = false) => logger[failed ? 'error' : 'info'](JSON.stringify({event, ...fields}));
  let timer, store, config, alerts, running = false, validated = false, databaseDay = null;
  try {
    config = applicationBackupConfig(env);
    if (config.mode === 'off') {
      log('application_backup_configuration', {mode:'off', productionBackupsActive:false, state:'awaiting-configuration'});
      return {stop() {}, getStatus: () => ({...status})};
    }
    alerts = alertsFactory({env, logger, signal: controller.signal, scope: 'application'});
    store = storeFactory(config);
  } catch (error) {
    status.lastError = safeBackupCode(error); log('application_backup_configuration', {status: 'blocked', code: status.lastError}, true);
    return {stop() { controller.abort(); config?.key?.fill(0); }, getStatus: () => ({...status})};
  }
  async function tick() {
    if (running || controller.signal.aborted) return;
    running = true; let failed = false;
    const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(20 * 60 * 1000)]);
    try {
      if (!validated) { log('application_backup_probe', await probe({store, config, signal})); validated = true; }
      if (config.mode === 'enabled') {
        const day = now().toISOString().slice(0, 10), includeDatabase = databaseDay !== day;
        const result = await run({source: sourceFactory({env}), store, config, env, includeDatabase, signal, now});
        status.lastSuccessAt = result.completedAt; status.lastError = null;
        if (includeDatabase) { databaseDay = day; status.lastDatabaseAt = result.completedAt; }
        log('application_backup_run', result);
      }
    } catch (error) {
      failed = true; status.lastError = safeBackupCode(error);
      log('application_backup_failure', {code: status.lastError, lastSuccessAt: status.lastSuccessAt,
        lastDatabaseAt: status.lastDatabaseAt, retryMinutes: 15}, true);
      if (config.mode === 'enabled' && !controller.signal.aborted) {
        try { await alerts.failure(error); } catch { log('application_backup_alert', {status: 'failed'}, true); }
      }
    } finally {
      running = false;
      if (config.mode === 'enabled' && !controller.signal.aborted) {
        timer = timers.setTimeout(tick, (failed ? 15 : 60) * 60 * 1000); timer?.unref?.();
      } else { store.close(); }
    }
  }
  timer = timers.setTimeout(tick, 60000); timer?.unref?.();
  log('application_backup_configuration', {mode: config.mode, state: 'awaiting-verification', intervalMinutes: 60,
    databaseSchedule: 'daily-and-after-restart', externalOutageMonitoring: false});
  return {getStatus: () => ({...status}), stop() {
    controller.abort(); timers.clearTimeout(timer); store.close(); config.key?.fill(0);
  }};
}
