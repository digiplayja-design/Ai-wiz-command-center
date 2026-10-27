import {autoEmailAppRouteAllowed} from './auto_email_app.mjs';
// Receipt Wiz and Messenger companion allowances are tied to the provider's verified login, not to a
// client-controlled header. Keep revoked bindings: deleting one would let an
// old companion JWT fall back to the hub's legacy session behavior.
const TABLE = 'korlix_receipt_app_sessions';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const fail = (message, statusCode = 401, code = 'invalid_session') => {
  throw Object.assign(new Error(message), {statusCode, code});
};
const unavailable = () => fail('Account access could not be verified. Please retry.', 503, 'session_storage_unavailable');

// Legacy export name retained for existing hub/Receipt Wiz integrations.
export function requestsReceiptApp(req) {
  return ['receipt_wiz', 'korlix_messenger', 'auto_email'].includes(req?.body?.client_app)
    || ['receipt_wiz', 'korlix_messenger', 'auto_email'].includes(req?.headers?.['x-korlix-app']);
}

export function messengerAppRouteAllowed(req) {
  const method = String(req?.method || '').toUpperCase();
  const path = String(req?.originalUrl || req?.url || req?.path || '').split('?')[0];
  if (['GET', 'HEAD', 'POST'].includes(method)
      && /^\/api\/social\/[a-zA-Z0-9_/-]+$/.test(path)) return true;
  return method === 'POST' && [
    '/api/messenger/auth/refresh', '/api/messenger/auth/signout',
    '/api/messenger/account/delete-request',
  ].includes(path.replace(/\/$/, ''));
}


// Call only after getUser() or a successful provider sign-in/refresh. This
// parser does not verify JWTs and is never an authentication substitute.
export function verifiedLoginId(accessToken, userId) {
  try {
    const parts = String(accessToken || '').split('.');
    if (parts.length !== 3 || parts[1].length > 16384) return null;
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return claims.sub === userId && UUID.test(claims.session_id || '')
      ? claims.session_id.toLowerCase() : null;
  } catch { return null; }
}

export function receiptAppRouteAllowed(req) {
  const method = String(req?.method || '').toUpperCase();
  const path = String(req?.originalUrl || req?.url || req?.path || '').split('?')[0];
  if (['GET', 'HEAD', 'POST'].includes(method) && /^\/api\/receipt-wiz\/?$/.test(path)) return true;
  if (['GET', 'HEAD'].includes(method) && /^\/api\/receipt-wiz\/export\/?$/.test(path)) return true;
  const match = path.match(/^\/api\/receipt-wiz\/([0-9a-f-]{36})(?:\/(file|preview|scan))?\/?$/i);
  if (match && UUID.test(match[1])) {
    if (!match[2]) return ['GET', 'HEAD', 'PUT', 'DELETE'].includes(method);
    return match[2] === 'scan' ? method === 'POST' : ['GET', 'HEAD'].includes(method);
  }
  return method === 'POST' && [
    '/api/auth/refresh', '/api/auth/signout', '/api/account/delete-request',
  ].includes(path.replace(/\/$/, ''));
}

export function createReceiptAppSessions({database}) {
  async function register({userId, session, deviceInfo}) {
    const sessionId = verifiedLoginId(session?.access_token, userId);
    const app = ['korlix_messenger', 'auto_email'].includes(deviceInfo?.clientApp) ? deviceInfo.clientApp : 'receipt_wiz';
    const label = {korlix_messenger:'Messenger', auto_email:'Auto-Email', receipt_wiz:'Receipt Wiz'}[app];
    if (!sessionId) fail(`Please sign in again to start a ${label} session.`);
    if (!deviceInfo?.explicitDeviceId || !deviceInfo.deviceId || deviceInfo.deviceId.length > 200) {
      fail(`A valid installation ID is required for ${label}.`, 400, app === 'auto_email' ? 'auto_email_device_required' : app === 'korlix_messenger' ? 'messenger_device_required' : 'receipt_device_required');
    }
    if (!database) unavailable();
    const {data, error} = await database.rpc(app === 'auto_email' ? 'korlix_register_auto_email_app_session' : app === 'korlix_messenger' ? 'korlix_register_messenger_app_session' : 'korlix_register_receipt_app_session', {
      p_user_id: userId, p_session_id: sessionId, p_device_id: deviceInfo.deviceId,
      p_device_label: String(deviceInfo.deviceLabel || '').slice(0, 160),
      p_platform: String(deviceInfo.platform || 'unknown').slice(0, 40),
    });
    if (['receipt_device_limit', 'messenger_device_limit', 'auto_email_device_limit'].includes(error?.message)) {
      fail(`${label} device limit reached. Sign out of ${label} on another device, then try again. Your KORLIX AI session can stay signed in.`, 403, app === 'auto_email' ? 'auto_email_device_limit' : app === 'korlix_messenger' ? 'messenger_device_limit' : 'receipt_device_limit');
    }
    if (error?.code === '42501') fail('This device is not authorized for this account. Please sign in again.', 403);
    if (error || !data) unavailable();
    return data;
  }

  async function authorize({userId, accessToken, deviceInfo, req}) {
    const sessionId = verifiedLoginId(accessToken, userId);
    if (!sessionId) {
      if (requestsReceiptApp(req)) fail('Please sign in again to start this companion app session.');
      return null; // Preserve older hub sessions; never grants a companion slot.
    }
    if (!database) unavailable();
    const {data: row, error} = await database.from(TABLE).select('*')
      .eq('session_id', sessionId).maybeSingle();
    if (error) unavailable();
    if (!row) {
      if (requestsReceiptApp(req)) fail('Please sign in again to start this companion app session.');
      return null;
    }
    if (row.user_id !== userId || row.status !== 'active'
        || !deviceInfo?.explicitDeviceId || row.device_id !== deviceInfo.deviceId) {
      fail('This device is not authorized for this account. Please sign in again.', 403);
    }
    const allowed = row.client_app === 'auto_email' ? autoEmailAppRouteAllowed(req) : (row.client_app ?? 'receipt_wiz') === 'korlix_messenger'
      ? messengerAppRouteAllowed(req) : receiptAppRouteAllowed(req);
    if (!allowed) {
      fail('Open KORLIX AI and sign in there to use this feature.', 403, row.client_app === 'auto_email' ? 'auto_email_app_scope' : (row.client_app ?? 'receipt_wiz') === 'korlix_messenger' ? 'messenger_app_scope' : 'receipt_app_scope');
    }
    const {data: active, error: touchError} = await database.from(TABLE)
      .update({last_seen_at: new Date().toISOString()})
      .eq('session_id', sessionId).eq('user_id', userId).eq('status', 'active')
      .select('*').maybeSingle();
    if (touchError) unavailable();
    if (!active) fail('This device is no longer authorized. Please sign in again.', 403);
    req.korlixReceiptAppSession = active;
    return active;
  }

  async function revoke(row) {
    if (!database || !row?.session_id || !row?.user_id) unavailable();
    const {error} = await database.from(TABLE).update({
      status: 'revoked', revoked_at: new Date().toISOString(), last_seen_at: new Date().toISOString(),
    }).eq('session_id', row.session_id).eq('user_id', row.user_id);
    if (error) unavailable();
  }
  return {register, authorize, revoke};
}
