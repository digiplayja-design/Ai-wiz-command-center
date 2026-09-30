import test from 'node:test';
import assert from 'node:assert/strict';
import https from 'node:https';
import { EventEmitter } from 'node:events';
import { crawlSite, extractPage, isPublicAddress, normalizeWebsite, parseRobots, requestPinned, robotsAllows } from '../seo_agent/crawler.mjs';

const publicDns = async () => [{ address: '93.184.216.34', family: 4 }];
const html = (extra = '') => `<!doctype html><html><head><title>Example &amp; Company</title><meta name="description" content="An accurate description"><link rel="canonical" href="/"></head><body><h1>Welcome &amp; hello</h1>${extra}</body></html>`;
const response = (body, status = 200, type = 'text/html', headers = {}) => ({ status, body, headers: { 'content-type': type, ...headers }, bytes: Buffer.byteLength(body) });
function fixture(routes, options = {}) {
  const calls = [];
  return { calls, options: { website: 'https://example.com/', resolveHost: publicDns,
    transport: async (url, pin, limits) => {
      calls.push({ url: url.href, pin, limits });
      const item = routes[url.href] ?? routes[url.pathname];
      if (item instanceof Error) throw item;
      if (typeof item === 'function') return item(url, pin, limits);
      return item ?? response('', 404, 'text/plain');
    }, ...options } };
}

test('public IP policy rejects private, reserved, mapped and transition addresses', () => {
  for (const ip of ['0.0.0.0', '10.0.0.1', '127.0.0.1', '100.64.0.1', '169.254.169.254', '172.16.0.1', '192.168.0.1', '192.0.2.1', '192.0.0.10', '198.18.0.1', '198.51.100.10', '203.0.113.1', '224.0.0.1', '255.255.255.255', '::', '::1', '::ffff:8.8.8.8', '::ffff:127.0.0.1', 'fc00::1', 'fe80::1', 'ff00::1', '2001:db8::1', '2001::1', '2002:0808:0808::1', '3fff::1', 'not-an-ip']) assert.equal(isPublicAddress(ip), false, ip);
  for (const ip of ['8.8.8.8', '93.184.216.34', '1.1.1.1', '2606:4700:4700::1111', '2001:4860:4860::8888']) assert.equal(isPublicAddress(ip), true, ip);
});

test('website normalization rejects credential, token, port, scheme and literal-IP forms', () => {
  assert.equal(normalizeWebsite('example.com').href, 'https://example.com/');
  assert.equal(normalizeWebsite('https://example.com/#section').href, 'https://example.com/');
  for (const value of ['http://example.com/', 'https://user:secret@example.com/', 'https://example.com/?token=secret', 'https://example.com:8443/', 'https://127.0.0.1/', 'https://2130706433/', 'https://[::1]/', 'https://localhost/', 'https://service.local/', 'https://example.com./', 'https://example.com\\@127.0.0.1/', 'ftp://example.com/']) assert.throws(() => normalizeWebsite(value), undefined, value);
});

test('DNS rejects mixed public/private answers before making any request', async () => {
  let contacted = false;
  await assert.rejects(crawlSite({ website: 'example.com', resolveHost: async () => [{ address: '8.8.8.8', family: 4 }, { address: '127.0.0.1', family: 4 }], transport: async () => { contacted = true; } }), e => e.code === 'unsafe_address');
  assert.equal(contacted, false);
});

test('DNS is revalidated on every request and the validated address is passed to transport', async () => {
  let resolutions = 0;
  const f = fixture({ '/robots.txt': response('', 404, 'text/plain'), '/': response(html()) }, { resolveHost: async () => ++resolutions === 1 ? [{ address: '8.8.8.8', family: 4 }] : [{ address: '127.0.0.1', family: 4 }] });
  await assert.rejects(crawlSite(f.options), e => e.code === 'unsafe_address');
  assert.equal(f.calls.length, 1);
  assert.deepEqual(f.calls[0].pin, { address: '8.8.8.8', family: 4 });
});

test('real HTTPS transport pins lookup and uses verified TLS without cookies or auth', async () => {
  const original = https.request;
  let options;
  https.request = (value, callback) => {
    options = value;
    const req = new EventEmitter();
    req.destroy = () => {};
    req.end = () => queueMicrotask(() => {
      const res = new EventEmitter();
      res.headers = { 'content-type': 'text/html' }; res.statusCode = 200; res.destroy = () => {};
      callback(res);
      res.emit('data', Buffer.from('hello')); res.emit('end');
    });
    return req;
  };
  try {
    const result = await requestPinned(new URL('https://example.com/page'), { address: '8.8.8.8', family: 4 }, { signal: new AbortController().signal, timeoutMs: 100, maxBytes: 100 });
    assert.equal(result.body, 'hello');
    assert.equal(options.servername, 'example.com');
    assert.equal(options.rejectUnauthorized, true); assert.equal(options.agent, false);
    assert.equal(options.headers.cookie, undefined); assert.equal(options.headers.authorization, undefined);
    await new Promise(resolve => options.lookup('example.com', { all: true }, (err, addresses) => { assert.equal(err, null); assert.deepEqual(addresses, [{ address: '8.8.8.8', family: 4 }]); resolve(); }));
    await new Promise(resolve => options.lookup('example.com', {}, (err, address, family) => { assert.equal(err, null); assert.equal(address, '8.8.8.8'); assert.equal(family, 4); resolve(); }));
  } finally { https.request = original; }
});

test('real transport rejects advertised and streamed excessive response bytes', async () => {
  const original = https.request;
  try {
    for (const advertised of [true, false]) {
      https.request = (_options, callback) => {
        const req = new EventEmitter(); req.destroy = () => {};
        req.end = () => queueMicrotask(() => {
          const res = new EventEmitter(); res.statusCode = 200; res.headers = advertised ? { 'content-length': '1000' } : {}; res.destroy = () => {};
          callback(res); if (!advertised) res.emit('data', Buffer.alloc(1000));
        }); return req;
      };
      await assert.rejects(requestPinned(new URL('https://example.com/'), { address: '8.8.8.8', family: 4 }, { signal: new AbortController().signal, timeoutMs: 100, maxBytes: 50 }), e => e.code === 'response_too_large');
    }
  } finally { https.request = original; }
});

test('robots selects the most specific agent, allow precedence, wildcard and encoded paths', () => {
  const policy = parseRobots('User-agent: *\nDisallow: /\nUser-agent: KorlixSEO\nDisallow: /private\nAllow: /private/public\nDisallow: /*.pdf$\nSitemap: https://example.com/sitemap.xml');
  assert.equal(robotsAllows(policy, new URL('https://example.com/')), true);
  assert.equal(robotsAllows(policy, new URL('https://example.com/private/a')), false);
  assert.equal(robotsAllows(policy, new URL('https://example.com/%70rivate/a')), false);
  assert.equal(robotsAllows(policy, new URL('https://example.com/private/public')), true);
  assert.equal(robotsAllows(policy, new URL('https://example.com/file.pdf')), false);
  assert.equal(robotsAllows(policy, new URL('https://example.com/file.pdf/page')), true);
  assert.deepEqual(policy.sitemaps, ['https://example.com/sitemap.xml']);
  assert.equal(robotsAllows(parseRobots('User-agent: *\nDisallow: /foo*bar$'), new URL('https://example.com/foo*xxbar')), false);
  assert.equal(robotsAllows(parseRobots('User-agent: *\nDisallow: /café'), new URL('https://example.com/caf%C3%A9')), false);
  assert.equal(robotsAllows(parseRobots('User-agent: *\nDisallow: /caf%C3%A9'), new URL('https://example.com/café')), false);
  const adversarial = { rules: [{ path: `/${'*a'.repeat(900)}b$`, allow: false }] };
  assert.equal(robotsAllows(adversarial, new URL(`https://example.com/${'a'.repeat(1900)}`)), true);
});

test('robots disallow and unavailable policies prevent page retrieval', async () => {
  for (const entry of [response('User-agent: *\nDisallow: /', 200, 'text/plain'), response('', 403, 'text/plain'), response('', 503, 'text/plain'), response('<html>login</html>', 200, 'text/html'), response('User-agent: *\nCrawl-delay: 1', 200, 'text/plain')]) {
    const f = fixture({ '/robots.txt': entry, '/': response(html()) });
    await assert.rejects(crawlSite(f.options));
    assert.equal(f.calls.length, 1);
  }
});

test('robots is applied before discovered pages, and sitemap is bounded and same-origin', async () => {
  const f = fixture({ '/robots.txt': response('User-agent: KorlixSEO\nDisallow: /private\nSitemap: https://elsewhere.com/sitemap.xml', 200, 'text/plain'), '/': response(html('<a href="/%70rivate">private</a><a href="/public">public</a>')), '/public': response(html()), '/sitemap.xml': response('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"></urlset>', 200, 'application/xml') });
  const audit = await crawlSite(f.options);
  assert.equal(audit.pages.length, 2); assert.equal(audit.coverage.robotsExcluded, 1);
  assert.equal(f.calls.some(c => c.url.includes('private') || c.url.includes('%70rivate') || c.url.includes('elsewhere')), false);
  assert.equal(audit.sitemap.available, true); assert.equal(audit.sitemap.fullValidation, false);
});

test('apex to www redirect checks the destination robots and public DNS', async () => {
  const f = fixture({ 'https://example.com/robots.txt': response('', 404, 'text/plain'), 'https://example.com/': response('', 301, 'text/plain', { location: 'https://www.example.com/' }), 'https://www.example.com/robots.txt': response('', 404, 'text/plain'), 'https://www.example.com/': response(html()) });
  const audit = await crawlSite(f.options);
  assert.equal(audit.siteUrl, 'https://www.example.com/');
  assert.deepEqual(f.calls.slice(0, 4).map(c => c.url), ['https://example.com/robots.txt', 'https://example.com/', 'https://www.example.com/robots.txt', 'https://www.example.com/']);
});

test('external, private, nonstandard and token-bearing redirect targets are rejected', async () => {
  for (const location of ['https://evil.example.org/', 'https://127.0.0.1/', 'https://example.com:8443/', 'https://example.com/?access_token=secret']) {
    const f = fixture({ '/robots.txt': response('', 404, 'text/plain'), '/': response('', 302, 'text/plain', { location }) });
    await assert.rejects(crawlSite(f.options));
    assert.equal(f.calls.length, 2);
  }
});

test('subpage redirects cannot change origin, even to the www alias', async () => {
  const f = fixture({ '/robots.txt': response('', 404, 'text/plain'), '/': response(html('<a href="/other">next</a>')), '/other': response('', 302, 'text/plain', { location: 'https://www.example.com/other' }) });
  const audit = await crawlSite(f.options);
  assert.equal(audit.pages.length, 1);
  assert.equal(f.calls.some(c => c.url.startsWith('https://www.')), false);
  assert.equal(audit.limitations.some(s => s.includes('external_redirect')), true);
});

test('parser decodes entities and extracts metadata without executing or fetching assets', () => {
  const page = extractPage('<!doctype html><title>A &amp; B</title><meta content="Description &amp; more" name="description"><meta name="robots" content="noindex,follow"><link href="/preferred" rel="canonical"><h1>One <span>heading</span></h1><img src="https://elsewhere/image" alt=""><img src="x"><script>secretScript()</script><a href="/yes#anchor">next</a><a href="/query?token=secret">skip</a><a href="//outside.com/">outside</a><a href="/logout">logout</a>', 'https://example.com/', { headers: { 'x-robots-tag': 'noarchive' } });
  assert.equal(page.title, 'A & B'); assert.equal(page.description, 'Description & more');
  assert.deepEqual(page.h1s, ['One heading']); assert.equal(page.canonical, 'https://example.com/preferred');
  assert.equal(page.noindex, true); assert.equal(page.images, 2); assert.equal(page.missingAlt, 1); assert.equal(page.emptyAlt, 1);
  assert.equal(page.textExcerpt.includes('secretScript'), false);
  assert.deepEqual(page.links, ['https://example.com/yes']);
});

test('sample never exceeds five pages and findings rely on fetched evidence', async () => {
  const links = Array.from({ length: 10 }, (_, i) => `<a href="/page${i}">${i}</a>`).join('');
  const f = fixture({ '/robots.txt': response('', 404, 'text/plain'), '/': response(html(links)), ...Object.fromEntries(Array.from({ length: 10 }, (_, i) => [`/page${i}`, i === 0 ? response('missing', 404, 'text/plain') : response(html('<img src="x">'))])) });
  const audit = await crawlSite(f.options);
  assert.equal(audit.pages.length, 5); assert.equal(audit.coverage.pageLimit, 5);
  assert.equal(audit.findings.some(f => f.title.includes('HTTP 404')), true);
  assert.equal(audit.findings.some(f => f.title.includes('Duplicate title')), true);
  assert.equal(audit.findings.some(f => f.title.includes('alt attribute')), true);
  assert.ok(audit.score >= 0 && audit.score <= 100);
  assert.equal(audit.limitations.some(s => s.includes('does not verify Google indexing')), true);
  assert.equal(f.calls.some(c => c.url.includes('/page9')), false);
});

test('response type, encoding and byte cap are enforced', async () => {
  for (const entry of [response('{}', 200, 'application/json'), response('a'.repeat(101), 200), response(html(), 200, 'text/html', { 'content-encoding': 'gzip' })]) {
    const f = fixture({ '/robots.txt': response('', 404, 'text/plain'), '/': entry }, { maxBytes: 100 });
    await assert.rejects(crawlSite(f.options));
  }
});

test('hung DNS and requests are bounded, and cancellation aborts before work', async () => {
  await assert.rejects(crawlSite({ website: 'example.com', resolveHost: () => new Promise(() => {}), requestMs: 15, totalMs: 30 }), e => ['dns_timeout', 'audit_timeout'].includes(e.code));
  await assert.rejects(crawlSite({ website: 'example.com', resolveHost: publicDns, transport: () => new Promise(() => {}), requestMs: 15, totalMs: 30 }), e => ['request_timeout', 'audit_timeout'].includes(e.code));
  const controller = new AbortController(); controller.abort();
  let contacted = false;
  await assert.rejects(crawlSite({ website: 'example.com', signal: controller.signal, resolveHost: async () => { contacted = true; return publicDns(); } }), e => e.code === 'audit_timeout');
  assert.equal(contacted, false);
});

test('active external cancellation is forwarded into the transport signal', async () => {
  const controller = new AbortController();
  let innerSignal;
  const pending = crawlSite({ website: 'example.com', signal: controller.signal, resolveHost: publicDns, transport: (_url, _pin, { signal }) => { innerSignal = signal; return new Promise(() => {}); } });
  await new Promise(resolve => setTimeout(resolve, 5)); controller.abort();
  await assert.rejects(pending, e => e.code === 'audit_timeout');
  assert.equal(innerSignal.aborted, true);
});


test('declared non-UTF8 response and HTML metadata encodings are rejected', async () => {
  const f = fixture({ '/robots.txt': response('', 404, 'text/plain'), '/': response(html(), 200, 'text/html; charset=iso-8859-1') });
  await assert.rejects(crawlSite(f.options), e => e.code === 'unsupported_charset');
  assert.throws(() => extractPage('<meta charset=windows-1252><h1>Hello</h1>', 'https://example.com/'), e => e.code === 'unsupported_charset');
  assert.throws(() => extractPage('<meta http-equiv=Content-Type content="text/html; charset=UTF-16"><h1>Hello</h1>', 'https://example.com/'), e => e.code === 'unsupported_charset');
  assert.equal(extractPage('<meta charset=UTF-8><h1>Hello</h1>', 'https://example.com/').h1s[0], 'Hello');
});

test('real transport rejects invalid UTF-8 bytes instead of producing misleading text', async () => {
  const original = https.request;
  https.request = (_options, callback) => {
    const req = new EventEmitter(); req.destroy = () => {};
    req.end = () => queueMicrotask(() => {
      const res = new EventEmitter(); res.statusCode = 200; res.headers = {}; res.destroy = () => {};
      callback(res); res.emit('data', Buffer.from([0xff, 0xfe, 0x00, 0x61])); res.emit('end');
    }); return req;
  };
  try {
    await assert.rejects(requestPinned(new URL('https://example.com/'), { address: '8.8.8.8', family: 4 }, { signal: new AbortController().signal, timeoutMs: 100, maxBytes: 50 }), e => e.code === 'unsupported_charset');
  } finally { https.request = original; }
});
