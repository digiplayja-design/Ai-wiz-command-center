import {loadAutomatedSupportConfig} from './config.mjs';
import {createAutomatedSupportStore} from './store.mjs';
import {createAutomatedSupportService} from './service.mjs';
import {registerAutomatedSupportRoutes} from './routes.mjs';
import {createAutomatedSupportResendProvider} from './provider.mjs';
import {registerAutomatedSupportInbound} from './inbound.mjs';

export function createAutomatedSupportRuntime({
  app, database, requireUser, environment = process.env, fetcher = globalThis.fetch,
  now = Date.now, intervalMilliseconds = 30000, autostart = true,
  store: injectedStore, provider: injectedProvider, resolveReporter: injectedResolver,
  onError = () => console.error('[KORLIX_AUTOMATED_SUPPORT_UNAVAILABLE]'),
} = {}) {
  let config;
  try {config = loadAutomatedSupportConfig(environment);}
  catch {
    // An enrollment typo must not take down voice, reporting or the rest of the app.
    app.use('/api/automated-support', (_req,res) => res.status(503)
      .set('Cache-Control','no-store').json({ok:false,error:'Automated support setup needs attention.'}));
    onError();
    return {wake:async()=>{},close:()=>{},configured:false};
  }
  const store = injectedStore || createAutomatedSupportStore(database);
  const provider = injectedProvider || createAutomatedSupportResendProvider({environment,fetcher});
  const service = createAutomatedSupportService({store,profiles:config.profiles,deliver:provider.send,now,environment});
  // Inbound events are authenticated by their provider signature. Register this
  // exact endpoint before the authenticated owner API's namespace middleware.
  registerAutomatedSupportInbound(app,{service,provider,profiles:config.profiles,environment,now});
  registerAutomatedSupportRoutes(app,{requireUser,service});

  const resolveReporter = injectedResolver || (async report => {
    if (!database?.auth?.admin?.getUserById) throw new Error('Reporter lookup unavailable');
    const {data,error} = await database.auth.admin.getUserById(report.userId);
    // Missing/deleted accounts can be recorded for review, while a provider
    // outage retains the durable intake for a later attempt.
    if (error) {
      if (error.status === 404 || error.code === 'user_not_found') return null;
      throw new Error('Reporter lookup unavailable');
    }
    const user = data?.user;
    return user ? {
      id:user.id,email:user.email,
      emailConfirmed:Boolean(user.email_confirmed_at),
    } : null;
  });
  let running = null, closed = false, timer = null, reportedFailure = false;
  async function run() {
    if (closed || !config.profiles.length) return;
    if (running) return running;
    running = (async () => {
      try {
        await service.drainIntake({resolveReporter,limit:20});
        await service.processPending({limit:20});
        reportedFailure = false;
      } catch {
        if (!reportedFailure) onError();
        reportedFailure = true;
      }
    })();
    try {await running;} finally {running = null;}
  }
  if (autostart && (database || injectedStore) && config.profiles.length) {
    void run();
    timer = setInterval(() => {void run();},Math.max(1000,intervalMilliseconds));
    timer.unref?.();
  }
  return {service,configured:config.profiles.length>0,wake:run,close:()=>{closed=true;clearInterval(timer);}};
}
