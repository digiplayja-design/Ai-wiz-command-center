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
  return { enabled: env.SOCIAL_CALLS_ENABLED !== 'false', iceServers, relay: iceServers.some(s => s.urls.some(u => /^turns?:/.test(u))), ringSeconds: 45 };
}
