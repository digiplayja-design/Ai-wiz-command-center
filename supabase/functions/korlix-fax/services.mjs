import { bucket, digest, fail, lineNumber, quote, uuid } from './rules.mjs';

export function services(env, http = fetch) {
  const base = env('SUPABASE_URL'),
    serviceKey = env('SUPABASE_SERVICE_ROLE_KEY');
  const carrierKey = env('TELNYX_API_KEY'),
    connection = env('TELNYX_FAX_CONNECTION_ID');
  const publicKey = env('TELNYX_PUBLIC_KEY'),
    ready = Boolean(carrierKey && connection && publicKey);
  const storage = base + '/storage/v1',
    hook = base + '/functions/v1/korlix-fax/carrier';
  async function internal(path, method = 'GET', body, extras = {}) {
    const headers = { apikey: serviceKey, Authorization: 'Bearer ' + serviceKey, ...extras };
    const res = await http(path, { method, headers, body, signal: AbortSignal.timeout(20000) });
    if (!res.ok) {
      const error = Object.assign(new Error('Fax storage could not complete the request.'), {
        status: 503,
      });
      error.remoteStatus = res.status;
      throw error;
    }
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }
  async function db(table, filters = {}, method = 'GET', body, prefer = 'return=representation') {
    const url = new URL(base + '/rest/v1/' + table);
    for (const [key, value] of Object.entries(filters)) url.searchParams.set(key, value);
    return internal(url, method, body === undefined ? undefined : JSON.stringify(body), {
      'Content-Type': 'application/json',
      Prefer: prefer,
    });
  }
  const rpc = (name, body) => db('rpc/korlix_fax_' + name, {}, 'POST', body);
  async function put(path, bytes) {
    await internal(storage + '/object/' + bucket + '/' + path, 'POST', bytes, {
      'Content-Type': 'application/pdf',
      'x-upsert': 'true',
    });
  }
  async function signed(path, seconds) {
    const data = await internal(
      storage + '/object/sign/' + bucket + '/' + path,
      'POST',
      JSON.stringify({ expiresIn: seconds }),
      { 'Content-Type': 'application/json' }
    );
    if (!data.signedURL?.startsWith('/object/sign/')) fail(503, 'A file link could not be issued.');
    return storage + data.signedURL;
  }
  async function carrier(path, method = 'GET', body) {
    if (!ready) fail(503, 'The fax carrier is awaiting setup.');
    const res = await http('https://api.telnyx.com/v2/' + path, {
      method,
      headers: { Authorization: 'Bearer ' + carrierKey, 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(20000),
    });
    if (!res.ok)
      throw Object.assign(new Error('The fax carrier could not complete this request.'), {
        status: 502,
        remoteStatus: res.status,
      });
    return (await res.json()).data;
  }
  async function login(body) {
    if (
      !uuid.test(body.device) ||
      typeof body.email !== 'string' ||
      body.email.length > 254 ||
      typeof body.password !== 'string' ||
      !body.password.length ||
      body.password.length > 2048
    )
      fail(400, 'Enter your Korlix email and password.');
    // Validate using shared Supabase Auth, then close that fresh session locally.
    // Only the separately scoped fax token reaches this app.
    const anon = env('SUPABASE_ANON_KEY');
    const response = await http(base + '/auth/v1/token?grant_type=password', {
      method: 'POST',
      headers: { apikey: anon, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: body.email.trim(), password: body.password }),
    });
    if (!response.ok) {
      if (response.status === 429) fail(429, 'Too many sign-in attempts. Try again later.');
      if (response.status >= 500) fail(503, 'Korlix sign-in is temporarily unavailable.');
      fail(401, 'Check your email and password and confirm your Korlix account.');
    }
    const data = await response.json();
    const revoked = await http(base + '/auth/v1/logout?scope=local', {
      method: 'POST',
      headers: { apikey: anon, Authorization: 'Bearer ' + data.access_token },
    });
    if (!revoked.ok) fail(503, 'Korlix could not finish sign-in. Please try again.');
    if (!data.user?.email_confirmed_at || !uuid.test(data.user.id))
      fail(403, 'Confirm your Korlix email before signing in.');
    const token = [...crypto.getRandomValues(new Uint8Array(32))]
      .map((n) => n.toString(16).padStart(2, '0'))
      .join('');
    const ok = await rpc('open_session', {
      p_user: data.user.id,
      p_device: body.device,
      p_hash: await digest(token),
    });
    if (!ok)
      fail(
        403,
        'Check that your Korlix account is active, or sign out of Fax Number on another device.'
      );
    return { token };
  }
  async function identity(req) {
    const token = req.headers.get('x-fax-session') || '';
    if (!/^[a-f0-9]{64}$/.test(token)) fail(401, 'Sign in to your fax workspace.');
    const hash = await digest(token);
    const [user] = await rpc('identity', { p_hash: hash });
    if (!user) fail(401, 'Your fax session has ended. Sign in again.');
    const result = await internal(base + '/auth/v1/admin/users/' + user.user_id);
    const account = result.user || result;
    if (
      !account.email_confirmed_at ||
      account.deleted_at ||
      Date.parse(account.banned_until) > Date.now()
    )
      fail(403, 'This fax account is unavailable.');
    return { ...user, hash, email: account.email };
  }
  const lineFor = async (filters) => (await db('korlix_fax_lines', { ...filters, limit: '1' }))[0];
  async function inventory(line) {
    const filters = new URLSearchParams({
      'filter[country_code]': 'US',
      'filter[features][]': 'fax',
      'filter[limit]': '80',
      'filter[best_effort]': 'false',
      'filter[phone_number_type]': line.preference === 'toll_free' ? 'toll_free' : 'local',
    });
    if (line.preference === 'toll_free') filters.set('filter[quickship]', 'true');
    else filters.set('filter[national_destination_code]', line.preference);
    const entries = await carrier('available_phone_numbers?' + filters);
    return entries.map((entry) => quote(entry, line.preference)).filter(Boolean);
  }
  async function routedNumber(phone) {
    const items = await carrier(
      'phone_numbers?' + new URLSearchParams({ 'filter[phone_number]': phone })
    );
    if (
      !items.some(
        (x) =>
          x.phone_number === phone &&
          x.status === 'active' &&
          String(x.connection_id) === connection
      )
    )
      return false;
    const app = await carrier('fax_applications/' + encodeURIComponent(connection));
    return (
      app.active === true &&
      app.webhook_event_url === hook &&
      Boolean(app.outbound?.outbound_voice_profile_id) &&
      (!app.inbound?.fax_file_format || app.inbound.fax_file_format === 'pdf')
    );
  }
  async function attach(line, phone) {
    if (line.state === 'active') return line;
    if (
      !lineNumber.test(phone) ||
      (line.preference === 'toll_free'
        ? !/^\+18(00|33|44|55|66|77|88)/.test(phone)
        : phone.slice(2, 5) !== line.preference)
    )
      fail(400, 'Choose an owned fax number that matches the requested prefix.');
    if (line.state === 'ordering' && phone !== line.phone)
      fail(409, 'Complete the outstanding order first.');
    if (!line.is_company && !(await lineFor({ is_company: 'eq.true', state: 'eq.active' })))
      fail(409, 'Activate the Korlix company line first.');
    if (!(await routedNumber(phone)))
      fail(
        409,
        'This number needs an active Korlix fax application, outbound profile, and matching webhook.'
      );
    const [updated] = await db(
      'korlix_fax_lines',
      { id: 'eq.' + line.id, state: 'eq.' + line.state },
      'PATCH',
      { phone, state: 'active' }
    );
    return updated || (await lineFor({ id: 'eq.' + line.id }));
  }
  async function sync(line) {
    if (line.state !== 'ordering') return line;
    const filter = new URLSearchParams({ 'filter[customer_reference]': line.id });
    const orders = line.order_id
      ? [await carrier('number_orders/' + encodeURIComponent(line.order_id))]
      : await carrier('number_orders?' + filter);
    const order = orders.find(
      (x) =>
        x.customer_reference === line.id &&
        x.phone_numbers?.some((n) => n.phone_number === line.phone)
    );
    if (!order) return line; // An ambiguous POST is reconciled, never repeated automatically.
    const where = { id: 'eq.' + line.id, state: 'eq.ordering', phone: 'eq.' + line.phone };
    const requested = order.phone_numbers.find((n) => n.phone_number === line.phone);
    if (order.status === 'failure' || requested.status === 'failure') {
      await db('korlix_fax_lines', where, 'PATCH', {
        state: 'requested',
        phone: null,
        order_id: null,
      });
      return lineFor({ id: 'eq.' + line.id });
    }
    let state = 'ordering';
    if (order.status === 'success' && requested.status === 'success') {
      if (await routedNumber(line.phone)) state = 'active';
    }
    await db('korlix_fax_lines', where, 'PATCH', { order_id: order.id, state });
    return lineFor({ id: 'eq.' + line.id });
  }
  async function order(line, offer) {
    if (line.state !== 'requested') return sync(line);
    if (!line.is_company && !(await lineFor({ is_company: 'eq.true', state: 'eq.active' })))
      fail(409, 'Activate the Korlix company line first.');
    const current = (await inventory(line)).find(
      (x) => x.number === offer.number && x.monthly === offer.monthly && x.upfront === offer.upfront
    );
    if (!current) fail(409, 'This quote has changed. Refresh the available numbers.');
    const [claim] = await db(
      'korlix_fax_lines',
      { id: 'eq.' + line.id, state: 'eq.requested' },
      'PATCH',
      { state: 'ordering', phone: current.number }
    );
    if (!claim) return sync(await lineFor({ id: 'eq.' + line.id }));
    let purchase;
    try {
      purchase = await carrier('number_orders', 'POST', {
        connection_id: connection,
        customer_reference: line.id,
        phone_numbers: [{ phone_number: current.number }],
      });
    } catch (error) {
      // Only explicit business rejections allow a new selection. A timeout may have placed the order.
      if ([400, 401, 402, 403, 404, 422].includes(error.remoteStatus))
        await db('korlix_fax_lines', { id: 'eq.' + line.id, state: 'eq.ordering' }, 'PATCH', {
          state: 'requested',
          phone: null,
        });
      throw error;
    }
    if (!purchase?.id) fail(502, 'The carrier has not confirmed the order. Use Check order.');
    await db('korlix_fax_lines', { id: 'eq.' + line.id, state: 'eq.ordering' }, 'PATCH', {
      order_id: purchase.id,
    });
    return sync({ ...claim, order_id: purchase.id });
  }
  return {
    base,
    db,
    put,
    signed,
    login,
    identity,
    ready,
    carrier,
    publicKey,
    connection,
    hook,
    lineFor,
    inventory,
    sync,
    order,
    attach,
    http,
  };
}
