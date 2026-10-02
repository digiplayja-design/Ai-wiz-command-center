// Optional relay credentials remain server-side until an authenticated Social
// member opens calling. Prefer short-lived credentials issued by your TURN host.
export function socialCallConfig(env = process.env) {
  const iceServers = [{ urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] }];
  try {
    const configured = JSON.parse(env.SOCIAL_ICE_SERVERS || '[]');
    if (Array.isArray(configured)) for (const server of configured.slice(0, 8)) {
      const urls = (Array.isArray(server?.urls) ? server.urls : [server?.urls]).filter(x => typeof x === 'string' && /^(stun|stuns|turn|turns):[^\s]+$/.test(x));
      if (!urls.length) continue;
      iceServers.push({ urls, ...(typeof server.username === 'string' ? { username: server.username } : {}), ...(typeof server.credential === 'string' ? { credential: server.credential } : {}) });
    }
  } catch { /* Direct connectivity remains available if optional config is invalid. */ }
  return { enabled: env.SOCIAL_CALLS_ENABLED !== 'false', iceServers, relay: iceServers.some(s => s.urls.some(u => /^turns?:/.test(u)) && s.username && s.credential) === true, ringSeconds: 45 };
}

export function socialRelayReadiness(env = process.env) {
  const staticRelay = socialCallConfig(env).relay;
  const twilio = /^AC[a-f0-9]{32}$/i.test(env.TWILIO_ACCOUNT_SID || '') &&
    !!(env.TWILIO_AUTH_TOKEN || env.TWILIO_API_KEY && env.TWILIO_API_SECRET);
  return {mode: staticRelay ? 'configured' : twilio && env.SOCIAL_TURN_PROVIDER !== 'disabled' ? 'twilio' : 'direct-only'};
}

// Only ephemeral TURN credentials reach authenticated Social members. Existing
// Twilio account credentials stay on the server; this does not create a service.
export function createSocialCallConfig({env=process.env,fetchImpl=fetch,logger=console}={}) {
  const cache=new Map();
  return async actor => {
    const config=socialCallConfig(env);
    if(!config.enabled || config.relay || socialRelayReadiness(env).mode!=='twilio')return {...config,relayStatus:config.relay?'ready':'not-configured'};
    const existing=cache.get(actor);
    if(existing && existing.until>Date.now())return existing.result;
    const result=(async()=>{
      try {
        const account=env.TWILIO_ACCOUNT_SID;
        const username=env.TWILIO_API_KEY || account;
        const password=env.TWILIO_API_KEY ? env.TWILIO_API_SECRET : env.TWILIO_AUTH_TOKEN;
        const response=await fetchImpl(`https://api.twilio.com/2010-04-01/Accounts/${account}/Tokens.json`,{
          method:'POST',signal:AbortSignal.timeout(8000),headers:{Authorization:`Basic ${Buffer.from(`${username}:${password}`).toString('base64')}`,'Content-Type':'application/x-www-form-urlencoded'},
          body:new URLSearchParams({Ttl:'14400'}).toString(),
        });
        if(!response.ok)throw Error('TURN credentials unavailable');
        const token=await response.json();
        const resolved=socialCallConfig({...env,SOCIAL_ICE_SERVERS:JSON.stringify(token.ice_servers)});
        if(!resolved.relay)throw Error('No relay returned');
        return {...resolved,relayStatus:'ready'};
      } catch {
        cache.delete(actor);
        logger.warn('Social calling relay credentials unavailable');
        return {...config,relayStatus:'unavailable'};
      }
    })();
    cache.set(actor,{result,until:Date.now()+300000});
    while(cache.size>1000)cache.delete(cache.keys().next().value);
    return result;
  };
}
