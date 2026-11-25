import { boundedBytes, fail, uuid } from './rules.mjs';
import { send, callback } from './transmissions.mjs';

export function createHandler(svc, origin = 'https://korlix-fax-number.onrender.com') {
  const lineFields = 'id,is_company,preference,state,phone,created_at';
  const docFields =
    'id,direction,sender,recipient,name,status,pages,detail,created_at,updated_at,object_path';
  async function body(req) {
    try {
      return JSON.parse(new TextDecoder().decode(await boundedBytes(req, 8192)));
    } catch (e) {
      if (e.status) throw e;
      fail(400, 'Invalid request.');
    }
  }
  return async (req) => {
    const url = new URL(req.url),
      path = url.pathname.replace(/^.*?\/korlix-fax(?=\/|$)/, '') || '/';
    const headers = {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      Vary: 'Origin',
    };
    const rqOrigin = req.headers.get('origin');
    if (rqOrigin && rqOrigin === origin) headers['Access-Control-Allow-Origin'] = origin;
    headers['Access-Control-Allow-Headers'] =
      'content-type, x-fax-session, x-fax-to, x-filename, x-request-id';
    headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS';
    const json = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers });
    try {
      if (rqOrigin && rqOrigin !== origin)
        fail(403, 'This origin cannot access the fax workspace.');
      if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers });
      if (req.method === 'GET' && path === '/health')
        return json({ app: 'FAX Number by Korlix', carrier: svc.ready ? 'configured' : 'pending' });
      if (req.method === 'POST' && path === '/carrier') {
        await callback(req, svc);
        return json({ received: true });
      }
      if (req.method === 'POST' && path === '/signin')
        return json(await svc.login(await body(req)));
      const user = await svc.identity(req);
      const owner = { user_id: 'eq.' + user.user_id };
      if (req.method === 'POST' && path === '/signout') {
        await svc.db(
          'korlix_fax_sessions',
          { token_hash: 'eq.' + user.hash },
          'DELETE',
          undefined,
          'return=minimal'
        );
        return json({ ok: true });
      }
      if (req.method === 'GET' && path === '/workspace') {
        let line = await svc.lineFor({ ...owner, select: lineFields });
        if (line?.state === 'ordering' && svc.ready) {
          try {
            await svc.sync(await svc.lineFor(owner));
            line = await svc.lineFor({ ...owner, select: lineFields });
          } catch {
            /* Still show the pending order. */
          }
        }
        return json({
          email: user.email,
          operator: user.operator,
          line: line || null,
          carrierReady: svc.ready,
        });
      }
      if (req.method === 'POST' && path === '/line') {
        const { preference } = await body(req);
        if (preference !== 'toll_free' && !/^[2-9]\d{2}$/.test(preference))
          fail(400, 'Choose a US area code or toll-free number.');
        await svc.db(
          'korlix_fax_lines',
          { on_conflict: 'user_id' },
          'POST',
          { user_id: user.user_id, preference },
          'resolution=ignore-duplicates,return=minimal'
        );
        return json({ line: await svc.lineFor({ ...owner, select: lineFields }) });
      }
      if (req.method === 'GET' && path === '/history') {
        const dir = url.searchParams.get('direction');
        if (!['inbound', 'outbound'].includes(dir)) fail(400, 'Choose Inbox or Sent.');
        const offset = Number(url.searchParams.get('offset') || 0);
        if (!Number.isSafeInteger(offset) || offset < 0 || offset > 100000)
          fail(400, 'Invalid page.');
        const rows = await svc.db('korlix_fax_documents', {
          ...owner,
          direction: 'eq.' + dir,
          select: docFields,
          order: 'created_at.desc,id.desc',
          limit: '26',
          offset: String(offset),
        });
        return json({
          items: rows
            .slice(0, 25)
            .map(({ object_path, ...item }) => ({ ...item, hasFile: !!object_path })),
          more: rows.length > 25,
        });
      }
      if (req.method === 'GET' && path.startsWith('/file/')) {
        const id = path.slice(6);
        if (!uuid.test(id)) fail(400, 'Invalid document.');
        const [doc] = await svc.db('korlix_fax_documents', {
          ...owner,
          id: 'eq.' + id,
          select: 'object_path,name',
        });
        if (!doc?.object_path || !doc.object_path.startsWith(user.user_id + '/'))
          fail(404, 'Document unavailable.');
        return json({ url: await svc.signed(doc.object_path, 60), name: doc.name });
      }
      if (req.method === 'POST' && path === '/send') return json(await send(req, user, svc));
      if (path.startsWith('/operator/')) {
        if (!user.operator) fail(403, 'Korlix operator access is required.');
        if (req.method === 'GET' && path === '/operator/requests') {
          const rows = await svc.db('korlix_fax_lines', {
            state: 'in.(requested,ordering)',
            user_id: 'not.is.null',
            select: lineFields,
            order: 'is_company.desc,created_at.asc',
            limit: '100',
          });
          return json({ items: rows });
        }
        const parts = path.match(/^\/operator\/([0-9a-f-]{36})\/(options|order|sync|attach)$/i);
        if (parts && uuid.test(parts[1])) {
          const line = await svc.lineFor({ id: 'eq.' + parts[1], user_id: 'not.is.null' });
          if (!line) fail(404, 'Line request unavailable.');
          if (parts[2] === 'options' && req.method === 'GET')
            return json({ items: (await svc.inventory(line)).slice(0, 12) });
          if (parts[2] === 'sync' && req.method === 'POST')
            return json({ state: (await svc.sync(line)).state });
          if (parts[2] === 'attach' && req.method === 'POST')
            return json({ state: (await svc.attach(line, (await body(req)).phone)).state });
          if (parts[2] === 'order' && req.method === 'POST')
            return json({ state: (await svc.order(line, await body(req))).state });
        }
      }
      return json({ error: 'Page not found.' }, 404);
    } catch (e) {
      return json(
        { error: e.status ? e.message : 'The fax service is temporarily unavailable.' },
        e.status || 503
      );
    }
  };
}
