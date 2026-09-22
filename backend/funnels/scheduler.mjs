// Durable tasks live in Postgres. This timer only wakes the single-flight runner;
// database versions and NOVA's claim/idempotency protect overlapping instances.
export function createFunnelScheduler({run,logger=console,setTimeoutImpl=setTimeout,clearTimeoutImpl=clearTimeout,intervalMs=60000}={}) {
  let timer=null,stopped=true,running=false;
  async function tick() {
    if(stopped||running)return;
    running=true;
    try {await run();}
    catch {logger.warn('Funnel scheduled follow-up scan unavailable; pending tasks remain stored.');}
    finally {
      running=false;
      if(!stopped){timer=setTimeoutImpl(tick,intervalMs);timer?.unref?.();}
    }
  }
  return {
    start(){if(!stopped)return;stopped=false;logger.info?.('Funnel scheduled follow-up runner started (60-second scan; owner approval required).');timer=setTimeoutImpl(tick,1000);timer?.unref?.();},
    stop(){stopped=true;if(timer)clearTimeoutImpl(timer);timer=null;},
  };
}
