import { randomUUID } from 'node:crypto';
import { isIP } from 'node:net';
import { PayrollError, fail, id, text, FLOW_TYPES, configuration, publicConfiguration, seal, unseal, tokenPair, safeFlowUrl, onboardingSummary } from './core.mjs';
import { createGustoProvider } from './provider.mjs';
import { payrollOffer, activationPayload } from './addon.mjs';

export function registerPayroll(app, { database, requireUser, environment = process.env, provider, now = Date.now } = {}) {
  const config = configuration(environment), gusto = provider || createGustoProvider(config);
  const call = async (actor, action, account = null, data = {}) => {
    if (!database) fail('Payroll storage is unavailable.', 503);
    const result = await database.rpc('korlix_payroll_v1', { p_actor: actor, p_action: action, p_account: account, p_data: data });
    if (result.error) {
      const e = result.error, statuses = { P0402: 402, '42501': 403, P0002: 404, '40001': 409, '54000': 429, P0001: 400, '23514': 400, '23502': 400, '22P02': 400 };
      fail(e.code === '42501' ? 'Payroll is available only to active Enterprise business owners.' :
        ['P0402','P0001','P0002','40001','54000'].includes(e.code) ? e.message : 'Payroll storage could not complete this request.',
        statuses[e.code] || 503, e.code === 'P0402' ? 'PAYROLL_ADDON_REQUIRED' : e.code === '42501' ? 'PAYROLL_ENTERPRISE_REQUIRED' : 'PAYROLL_STORAGE_ERROR');
    }
    if (!result.data) fail('Payroll storage is unavailable.', 503);
    return result.data;
  };
  const ready = () => { if (!config.ready) fail('Payroll provider activation is pending.', 503, 'PAYROLL_SETUP_REQUIRED'); };
  const wrap = fn => async (req, res) => {
    res.set({ 'Cache-Control': 'no-store', 'Pragma': 'no-cache', 'Referrer-Policy': 'no-referrer' });
    try {
      let user; try { user = await requireUser(req); } catch { /* handle below */ }
      if (!user?.id || user.is_anonymous || !user.email || !user.email_confirmed_at)
        fail('Sign in with a verified business account to use Payroll.', 401, 'PAYROLL_AUTH_REQUIRED');
      // Every HTTP route and every database command rechecks the authoritative tier.
      await call(user.id, 'list');
      if (req.method !== 'GET' && (!req.body || Array.isArray(req.body) || JSON.stringify(req.body).length > 4096)) fail('Invalid payroll request.');
      await fn(req, res, user);
    } catch (e) {
      res.status(e instanceof PayrollError ? e.status : 503).json({
        error: e instanceof PayrollError ? e.message : 'Payroll is temporarily unavailable. Refresh before retrying.',
        code: e instanceof PayrollError ? e.code : 'PAYROLL_UNAVAILABLE' });
    }
  };
  const context = (account, company) => `korlix-payroll:${account}:${config.mode}:${company}`;
  const expiresAt = seconds => new Date(now() + (seconds - 60) * 1000).toISOString();
  async function session(user, account, work, { termsRequired = true } = {}) {
    await call(user.id, 'check_addon', account);
    ready();
    const lease = randomUUID();
    const record = await call(user.id, 'lease', account, { lease_id: lease, environment: config.mode });
    try {
      const company = id(record.company_id);
      if (termsRequired && !record.terms_accepted) fail('Review and accept the payroll provider terms first.', 409, 'PAYROLL_TERMS_REQUIRED');
      let tokens = unseal(record.sealed_tokens, config.encryptionKey, context(account, company));
      async function refresh() {
        // A persisted marker prevents replaying a possibly consumed refresh token after a crash.
        await call(user.id, 'refresh_started', account, { lease_id: lease });
        const result = await gusto.refresh(tokens.refresh_token);
        const next = tokenPair(result);
        await call(user.id, 'refresh_saved', account, { lease_id: lease,
          sealed_tokens: seal(next, config.encryptionKey, context(account, company)), expires_at: expiresAt(result.expires_in) });
        tokens = next;
      }
      if (!(Date.parse(record.expires_at) > now())) await refresh();
      const api = async action => {
        await call(user.id, 'check_addon', account);
        try { return await action(company, tokens.access_token); }
        catch (e) {
          if (e.providerStatus !== 401) throw e;
          await refresh();
          await call(user.id, 'check_addon', account);
          return action(company, tokens.access_token);
        }
      };
      const result = await work({ api, lease, record });
      // A downgrade or account transfer during an upstream request must not disclose its result.
      await call(user.id, 'check_addon', account);
      return result;
    } finally {
      try { await call(user.id, 'release', account, { lease_id: lease }); } catch { /* bounded lease expires */ }
    }
  }
  const base = '/api/payroll';
  app.get(base + '/workspaces', wrap(async (_q, r, u) => r.json({ ...await call(u.id, 'list'), provider: publicConfiguration(config), offer: payrollOffer() })));
  app.post(base + '/workspaces', wrap(async (q, r, u) => {
    if (q.body.confirmed !== true || q.body.country !== 'US') fail('Confirm this is a US business you are authorized to manage.');
    r.status(201).json(await call(u.id, 'create', null, { business_id: id(q.body.business_id),
      legal_name: text(q.body.legal_name, 160), country: 'US', confirmed: true }));
  }));
  app.get(base + '/workspaces/:id', wrap(async (q, r, u) => r.json({ ...await call(u.id, 'get', id(q.params.id)), provider: publicConfiguration(config), offer: payrollOffer() })));
  app.post(base + '/workspaces/:id/activation-request', wrap(async (q, r, u) => {
    r.json(await call(u.id, 'request_activation', id(q.params.id), activationPayload(q.body)));
  }));
  app.post(base + '/workspaces/:id/activation-request/withdraw', wrap(async (q, r, u) => {
    if (q.body.confirmed !== true) fail('Confirm you want to withdraw this activation request.');
    r.json(await call(u.id, 'withdraw_activation', id(q.params.id), { confirmed: true }));
  }));
  app.post(base + '/workspaces/:id/connect', wrap(async (q, r, u) => {
    const account = id(q.params.id);
    await call(u.id, 'check_addon', account);
    ready();
    if (q.body.confirmed !== true || q.body.new_company !== true) fail('Confirm you want to create a new payroll company. Existing Gusto companies need assisted migration.');
    const firstName = text(q.body.first_name), lastName = text(q.body.last_name), connection = randomUUID();
    const record = await call(u.id, 'begin_connection', account, { environment: config.mode, email: u.email, connection_id: connection });
    try {
      const system = await gusto.systemToken();
      if (typeof system.access_token !== 'string' || system.access_token.length < 8) fail('Provider authorization is unavailable.', 502);
      const result = await gusto.createCompany(system.access_token, { company: { name: record.legal_name },
        user: { first_name: firstName, last_name: lastName, email: u.email } });
      const tokens = tokenPair(result), company = id(result.company_uuid);
      await call(u.id, 'finish_connection', account, { connection_id: connection, company_id: company,
        sealed_tokens: seal(tokens, config.encryptionKey, context(account, company)), expires_at: expiresAt(result.expires_in) });
      r.status(201).json(await call(u.id, 'get', account));
    } catch (error) {
      // Never create a second company after an ambiguous provider response.
      try { await call(u.id, 'connection_failed', account, { connection_id: connection }); } catch { /* original error is safe */ }
      throw error;
    }
  }));
  app.post(base + '/workspaces/:id/terms', wrap(async (q, r, u) => {
    if (q.body.accepted !== true) fail('Review and accept the Gusto Embedded Payroll terms to continue.');
    const account = id(q.params.id);
    const hops = Number(environment.PAYROLL_TRUST_PROXY_HOPS || 0);
    if (!Number.isInteger(hops) || hops < 0 || hops > 5) fail('Payroll network configuration needs attention.', 503);
    const chain = [q.socket.remoteAddress, ...String(q.headers['x-forwarded-for'] || '').split(',').map(s => s.trim()).filter(Boolean).reverse()];
    const address = chain[hops];
    if (!address || !isIP(address)) fail('Payroll could not verify your connection address.', 503);
    await session(u, account, async ({ api, lease, record }) => {
      if (!record.terms_accepted) {
        // Explicit user acceptance only; the primary payroll email is fixed at company creation.
        await api((company, token) => gusto.terms(company, token, { email: record.admin_email, external_user_id: u.id, ip_address: address }));
        await call(u.id, 'terms_accepted', account, { lease_id: lease });
      }
    }, { termsRequired: false });
    r.json(await call(u.id, 'get', account));
  }));
  app.post(base + '/workspaces/:id/refresh', wrap(async (q, r, u) => {
    const account = id(q.params.id);
    const onboarding = await session(u, account, async ({ api }) => onboardingSummary(await api(gusto.onboarding)));
    r.json({ ...await call(u.id, 'get', account), onboarding, checked_at: new Date(now()).toISOString() });
  }));
  app.post(base + '/workspaces/:id/flows', wrap(async (q, r, u) => {
    const account = id(q.params.id), type = q.body.flow_type;
    if (typeof type !== 'string' || !Object.hasOwn(FLOW_TYPES, type)) fail('Choose a supported payroll action.');
    const definition = FLOW_TYPES[type];
    const result = await session(u, account, async ({ api, lease }) => {
      if (definition.onboarded && (await api(gusto.onboarding)).onboarding_completed !== true)
        fail('Complete company onboarding before opening this payroll action.', 409, 'PAYROLL_ONBOARDING_REQUIRED');
      const flow = await api((company, token) => gusto.flow(company, token, { flow_type: type,
        ...(definition.entity ? { entity_type: 'Company', entity_uuid: company } : {}) }));
      const url = safeFlowUrl(flow.url, config);
      await call(u.id, 'flow_opened', account, { lease_id: lease, flow_type: type });
      return { url, title: definition.label, environment: config.mode, expires_at: new Date(now() + 24 * 3600000).toISOString() };
    });
    r.json(result);
  }));
}
