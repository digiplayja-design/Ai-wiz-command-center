import https from 'node:https';
import { lookup } from 'node:dns/promises';
import { isIP } from 'node:net';
import { parse } from 'parse5';
import { SeoError } from './core.mjs';

export const CRAWLER_USER_AGENT = 'KorlixSEO/1.0';
const PAGE_LIMIT = 5;
const MAX_BYTES = 1024 * 1024;
const REQUEST_LIMIT = 24;
const TOTAL_MS = 75_000;
const REQUEST_MS = 10_000;
const SKIP_PATH = /(?:^|\/)(?:logout|log-out|signout|sign-out|delete|remove|checkout|cart|admin|wp-admin|login|signin|oauth|callback)(?:\/|$)/i;

function failure(message, code = 'crawl_unavailable', status = 422) {
  const error = new SeoError(message, status);
  error.code = code;
  return error;
}

/** Only globally routable addresses. Conservative exclusions include transition networks. */
export function isPublicAddress(address) {
  const family = isIP(address);
  if (family === 4) {
    const [a, b, c] = address.split('.').map(Number);
    return !(a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) || (a === 192 && b === 0 && (c === 0 || c === 2)) ||
      (a === 192 && b === 88 && c === 99) ||
      (a === 198 && (b === 18 || b === 19 || (b === 51 && c === 100))) ||
      (a === 203 && b === 0 && c === 113));
  }
  if (family !== 6 || address.includes('%')) return false;
  const [first, second] = address.toLowerCase().split(':').map(v => parseInt(v || '0', 16));
  // 2000::/3 global unicast, excluding special protocol, documentation and 6to4 blocks.
  return first >= 0x2000 && first <= 0x3fff &&
    !(first === 0x2001 && (second <= 0x1ff || second === 0xdb8)) &&
    first !== 0x2002 && !(first === 0x3fff && second <= 0x0fff);
}

export function normalizeWebsite(value, base) {
  if (typeof value !== 'string' || value.length > 2048 || /[\u0000-\u0020\\]/.test(value)) {
    throw failure('Enter a public HTTPS website address.', 'invalid_website', 400);
  }
  let url;
  try { url = new URL(base ? value : (/^[a-z][a-z\d+.-]*:/i.test(value) ? value : `https://${value}`), base); }
  catch { throw failure('Enter a valid HTTPS website address.', 'invalid_website', 400); }
  const host = url.hostname.toLowerCase();
  if (url.protocol !== 'https:' || (url.port && url.port !== '443') || url.username || url.password ||
      url.search || isIP(host.replace(/^\[|\]$/g, '')) || !host.includes('.') ||
      host.endsWith('.') || host.endsWith('.localhost') || host.endsWith('.local') ||
      !/^[a-z\d](?:[a-z\d.-]*[a-z\d])?$/.test(host) || host.split('.').some(p => !p || p.length > 63)) {
    throw failure('Use a public HTTPS domain without credentials, query parameters, or a custom port.', 'invalid_website', 400);
  }
  url.hash = '';
  return url;
}

function aliasOrigin(a, b) {
  return a.protocol === b.protocol && a.port === b.port &&
    a.hostname.replace(/^www\./, '') === b.hostname.replace(/^www\./, '');
}
function assertCharset(value) {
  const declared = /charset\s*=\s*["']?\s*([^;"'\s]+)/i.exec(value)?.[1]?.toLowerCase();
  if (declared && !['utf-8', 'utf8', 'us-ascii', 'ascii'].includes(declared)) {
    throw failure('This audit supports UTF-8 HTML and text responses; this page declares another character encoding.', 'unsupported_charset');
  }
}
function header(headers, name) {
  const value = headers?.[name.toLowerCase()];
  return Array.isArray(value) ? value.join(', ') : String(value ?? '');
}

/** A new TLS socket per request, with DNS pinned to an already validated IP. */
export function requestPinned(url, pin, { signal, timeoutMs, maxBytes }) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      error ? reject(error) : resolve(value);
    };
    const req = https.request({
      protocol: 'https:', hostname: url.hostname, port: 443,
      path: `${url.pathname}${url.search}`, method: 'GET',
      servername: url.hostname, rejectUnauthorized: true, agent: false, signal,
      lookup: (_host, options, callback) => options?.all
        ? callback(null, [{ address: pin.address, family: pin.family }])
        : callback(null, pin.address, pin.family),
      headers: { 'user-agent': CRAWLER_USER_AGENT, accept: 'text/html,application/xhtml+xml,text/plain,application/xml,text/xml;q=0.8', 'accept-encoding': 'identity' },
    }, res => {
      try { assertCharset(header(res.headers, 'content-type')); } catch (error) { res.destroy(); req.destroy(); finish(error); return; }
      const encoding = header(res.headers, 'content-encoding').toLowerCase();
      if (encoding && encoding !== 'identity') {
        res.destroy(); req.destroy();
        finish(failure('Compressed responses are not sampled by this audit.', 'unsupported_encoding'));
        return;
      }
      if (Number(header(res.headers, 'content-length')) > maxBytes) {
        res.destroy(); req.destroy();
        finish(failure('The page exceeds the audit response-size limit.', 'response_too_large'));
        return;
      }
      const chunks = [];
      let bytes = 0;
      res.on('data', chunk => {
        bytes += chunk.length;
        if (bytes > maxBytes) {
          res.destroy(); req.destroy();
          finish(failure('The page exceeds the audit response-size limit.', 'response_too_large'));
        } else chunks.push(chunk);
      });
      res.on('end', () => {
        try {
          const body = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks));
          finish(null, { status: res.statusCode, headers: res.headers, body, bytes });
        } catch { finish(failure('The response is not valid UTF-8 text and was not sampled.', 'unsupported_charset')); }
      });
      res.on('error', () => finish(failure('The website response could not be read.', 'network_error')));
    });
    const timer = setTimeout(() => {
      req.destroy();
      finish(failure('The website did not respond within the audit time limit.', 'request_timeout'));
    }, timeoutMs);
    req.on('error', () => finish(failure('The website could not be reached securely.', signal.aborted ? 'audit_timeout' : 'network_error')));
    req.end();
  });
}

function deadline(promise, signal, timeoutMs, code = 'request_timeout') {
  return new Promise((resolve, reject) => {
    const stop = () => done(failure('The audit time limit was reached.', 'audit_timeout'));
    const timer = setTimeout(() => done(failure('The website did not respond within the audit time limit.', code)), timeoutMs);
    const done = (error, result) => {
      clearTimeout(timer); signal.removeEventListener('abort', stop);
      error ? reject(error) : resolve(result);
    };
    signal.addEventListener('abort', stop, { once: true });
    if (signal.aborted) stop();
    Promise.resolve(promise).then(value => done(null, value), done);
  });
}

export function parseRobots(text) {
  const groups = [];
  const sitemaps = [];
  let group = null;
  for (const raw of text.split(/\r?\n/).slice(0, 10_000)) {
    const line = raw.replace(/#.*$/, '').trim();
    const match = /^([\w-]+)\s*:\s*(.*)$/.exec(line);
    if (!match) continue;
    const name = match[1].toLowerCase();
    const value = match[2].trim();
    if (name === 'sitemap') { if (sitemaps.length < 8) sitemaps.push(value.slice(0, 2048)); continue; }
    if (name === 'user-agent') {
      if (!group || group.hasRules) { group = { agents: [], rules: [], delay: 0, hasRules: false }; groups.push(group); }
      group.agents.push(value.toLowerCase());
    } else if (group && ['allow', 'disallow', 'crawl-delay'].includes(name)) {
      group.hasRules = true;
      if (name === 'crawl-delay') group.delay = Math.max(group.delay, Number(value) || 0);
      else if (value.startsWith('/') && value.length <= 2048) group.rules.push({ path: value, allow: name === 'allow' });
    }
  }
  const agent = CRAWLER_USER_AGENT.toLowerCase();
  const strength = group => Math.max(-1, ...group.agents.map(v => v === '*' ? 0 : agent.startsWith(v) ? v.length : -1));
  const best = Math.max(-1, ...groups.map(strength));
  const selected = groups.filter(g => best >= 0 && strength(g) === best);
  return { rules: selected.flatMap(g => g.rules), delay: Math.max(0, ...selected.map(g => g.delay)), sitemaps };
}

function robotPath(value) {
  return value.replace(/[^\x00-\x7f]+/gu, part => encodeURIComponent(part.toWellFormed())).replace(/%([0-9a-f]{2})/gi, (part, hex) => {
    const character = String.fromCharCode(parseInt(hex, 16));
    return /[a-z\d._~-]/i.test(character) ? character : part.toUpperCase();
  });
}
function wildcardMatches(pattern, value) {
  let p = 0, v = 0, star = -1, resume = 0;
  while (v < value.length) {
    if (pattern[p] === '*') { star = p++; resume = v; }
    else if (pattern[p] === value[v]) { p++; v++; }
    else if (star >= 0) { p = star + 1; v = ++resume; }
    else return false;
  }
  while (pattern[p] === '*') p++;
  return p === pattern.length;
}
export function robotsAllows(policy, url) {
  let best = -1;
  let allowed = true;
  const path = robotPath(`${url.pathname}${url.search}`);
  for (const rule of policy.rules ?? []) {
    const anchor = rule.path.endsWith('$');
    const pattern = robotPath(anchor ? rule.path.slice(0, -1) : `${rule.path}*`);
    if (wildcardMatches(pattern, path)) {
      const size = pattern.replace(/[*$]/g, '').length;
      if (size > best || (size === best && rule.allow)) { best = size; allowed = rule.allow; }
    }
  }
  return allowed;
}

const clean = (value, length = 1000) => String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, length);
const attr = (node, name) => node.attrs?.find(a => a.name === name)?.value ?? '';
function nodeText(node, max = 1500) {
  const parts = []; const stack = [node]; let length = 0;
  while (stack.length && length < max) {
    const item = stack.pop();
    if (item.nodeName === '#text') { parts.push(item.value); length += item.value.length; }
    else if (!['script', 'style', 'template'].includes(item.tagName)) {
      for (let i = (item.childNodes?.length ?? 0) - 1; i >= 0; i--) stack.push(item.childNodes[i]);
    }
  }
  return clean(parts.join(' '), max);
}

export function extractPage(html, url, response = {}) {
  const document = parse(html);
  const stack = [document];
  let nodes = 0, images = 0, missingAlt = 0, emptyAlt = 0, title = '', description = '', canonical = '', base = url;
  const h1s = [], robots = [], hrefs = [], text = [];
  let textLength = 0;
  while (stack.length) {
    const node = stack.pop();
    if (++nodes > 150_000) throw failure('The page structure exceeds the audit parsing limit.', 'page_too_complex');
    const tag = node.tagName;
    if (tag === 'title' && !title) title = nodeText(node, 500);
    if (tag === 'h1' && h1s.length < 20) h1s.push(nodeText(node, 500));
    if (tag === 'meta') {
      if (attr(node, 'charset')) assertCharset(`charset=${attr(node, 'charset')}`);
      if (attr(node, 'http-equiv').toLowerCase() === 'content-type') assertCharset(attr(node, 'content'));
      const name = attr(node, 'name').toLowerCase();
      if (name === 'description' && !description) description = clean(attr(node, 'content'), 1500);
      if (['robots', 'googlebot', 'korlixseo'].includes(name)) robots.push(`${name}: ${clean(attr(node, 'content'), 500)}`);
    }
    if (tag === 'link' && attr(node, 'rel').toLowerCase().split(/\s+/).includes('canonical') && !canonical) {
      try { canonical = new URL(attr(node, 'href'), url).href.slice(0, 2048); } catch {}
    }
    if (tag === 'base' && base === url) { try { base = new URL(attr(node, 'href'), url).href; } catch {} }
    if (tag === 'img') {
      images++;
      if (!node.attrs?.some(a => a.name === 'alt')) missingAlt++;
      else if (!attr(node, 'alt').trim()) emptyAlt++;
    }
    if (tag === 'a' && hrefs.length < 200) hrefs.push(attr(node, 'href'));
    if (node.nodeName === '#text' && textLength < 8000) { text.push(node.value); textLength += node.value.length; }
    if (!['script', 'style', 'template', 'noscript', 'head'].includes(tag)) {
      for (let i = (node.childNodes?.length ?? 0) - 1; i >= 0; i--) stack.push(node.childNodes[i]);
    } else if (tag === 'head') {
      // Inspect metadata without including scripts or stylesheet content in the evidence excerpt.
      for (let i = (node.childNodes?.length ?? 0) - 1; i >= 0; i--) {
        const child = node.childNodes[i];
        if (['title', 'meta', 'link', 'base'].includes(child.tagName)) stack.push(child);
      }
    }
  }
  const links = [];
  for (const href of hrefs) {
    try {
      const link = normalizeWebsite(href, base);
      let path; try { path = decodeURIComponent(link.pathname); } catch { continue; }
      if (link.origin === new URL(url).origin && !SKIP_PATH.test(path) &&
          !/\.(?:pdf|jpe?g|png|gif|webp|svg|ico|zip|gz|mp[34]|woff2?|css|js|xml|json|txt)$/i.test(link.pathname) &&
          !links.includes(link.href)) links.push(link.href);
    } catch {}
    if (links.length === 50) break;
  }
  const xRobots = header(response.headers, 'x-robots-tag');
  if (xRobots) robots.push(`X-Robots-Tag: ${clean(xRobots, 500)}`);
  return { url, status: response.status ?? 200, title, description, h1s, canonical, robots,
    images, missingAlt, emptyAlt, textExcerpt: clean(text.join(' '), 5000), links,
    responseBytes: response.bytes ?? Buffer.byteLength(html),
    noindex: robots.some(v => /(?:^|[\s,:])(?:noindex|none)(?:$|[\s,;])/i.test(v)) };
}

function findingsFor(pages) {
  const findings = [];
  const add = (page, priority, kind, title, detail, evidence) => findings.push({ id: `${kind}-${findings.length + 1}`, priority, title, detail, url: page.url, evidence: clean(evidence, 700) });
  const titles = new Map();
  for (const page of pages) {
    if (page.status >= 400) { add(page, 'high', 'http', `Sampled page returned HTTP ${page.status}`, 'Review this sampled URL and its incoming internal link. Access restrictions can also cause this response.', `HTTP ${page.status}`); continue; }
    if (!page.title) add(page, 'high', 'title', 'Page title is missing', 'Add a descriptive title that accurately represents this page.', '<title> was absent or empty in the fetched HTML.');
    else {
      const key = page.title.toLowerCase();
      if (titles.has(key)) add(page, 'medium', 'duplicate-title', 'Duplicate title among sampled pages', 'Review whether these pages should have distinct, accurate titles.', `${page.title}; also seen at ${titles.get(key)}`);
      else titles.set(key, page.url);
    }
    if (!page.description) add(page, 'medium', 'description', 'Meta description is missing', 'Consider a useful summary of this page for its description metadata.', 'No non-empty meta name="description" was found.');
    if (!page.h1s.length) add(page, 'medium', 'h1', 'No H1 found in the sampled HTML', 'Review the main visible heading and page structure.', 'No H1 element was found in the server-returned HTML.');
    if (!page.canonical) add(page, 'low', 'canonical', 'No canonical link found', 'Review whether this URL needs an explicit canonical hint, especially if duplicate URLs exist.', 'No link rel="canonical" was found.');
    if (page.noindex) add(page, 'high', 'noindex', 'Noindex directive is present', 'Confirm whether exclusion from indexing is intentional before changing this directive.', page.robots.join('; '));
    if (page.missingAlt) add(page, 'medium', 'alt', 'Images lack an alt attribute', 'Review informative images and provide useful alternatives. Decorative images may use an empty alt attribute.', `${page.missingAlt} of ${page.images} image elements have no alt attribute.`);
  }
  return findings;
}

/** Bounded public-HTML audit; resolver/transport injections are for deterministic tests. */
export async function crawlSite({ website, onPhase, resolveHost = (host) => lookup(host, { all: true, verbatim: true }), transport = requestPinned, now = () => Date.now(), signal, totalMs = TOTAL_MS, requestMs = REQUEST_MS, maxBytes = MAX_BYTES } = {}) {
  const started = now();
  const initial = normalizeWebsite(website);
  const controller = new AbortController();
  const abort = () => controller.abort();
  signal?.addEventListener('abort', abort, { once: true });
  if (signal?.aborted) abort();
  const hardTotal = Math.min(TOTAL_MS, Math.max(1, totalMs));
  const timer = setTimeout(() => controller.abort(), hardTotal);
  const limits = { requestMs: Math.min(REQUEST_MS, Math.max(1, requestMs)), maxBytes: Math.min(MAX_BYTES, Math.max(1, maxBytes)) };
  const limitations = [
    'This is a sample of up to five public HTML pages, not a complete site crawl.',
    'JavaScript is not executed. Content rendered only in the browser may be absent.',
    'This audit does not verify Google indexing, search rankings, traffic, Core Web Vitals, or ranking improvements.',
    'Query-string URLs, non-HTTPS URLs, private networks, authenticated pages, and external resources are excluded.',
  ];
  let requests = 0, blocked = 0;
  const robotCache = new Map();
  const check = () => { if (controller.signal.aborted || now() - started >= hardTotal) throw failure('The audit time limit was reached.', 'audit_timeout'); };
  const phase = async value => { check(); if (onPhase) await deadline(Promise.resolve(onPhase(value)), controller.signal, limits.requestMs); };
  async function raw(url, bytes = limits.maxBytes) {
    check();
    if (++requests > REQUEST_LIMIT) throw failure('The audit request limit was reached.', 'request_limit');
    const timeout = Math.min(limits.requestMs, hardTotal - (now() - started));
    const records = await deadline(resolveHost(url.hostname), controller.signal, timeout, 'dns_timeout');
    if (!Array.isArray(records) || !records.length || records.some(r => !isPublicAddress(r.address) || isIP(r.address) !== Number(r.family))) {
      throw failure('The website must resolve only to public network addresses.', 'unsafe_address', 400);
    }
    const response = await deadline(transport(url, records[0], { signal: controller.signal, timeoutMs: timeout, maxBytes: bytes }), controller.signal, timeout);
    if (!response || !Number.isInteger(response.status) || response.status < 100 || response.status > 599 || typeof response.body !== 'string') throw failure('The website returned an invalid response.', 'invalid_response');
    if (Buffer.byteLength(response.body) > bytes || response.bytes > bytes) throw failure('The page exceeds the audit response-size limit.', 'response_too_large');
    assertCharset(header(response.headers, 'content-type'));
    const encoding = header(response.headers, 'content-encoding').toLowerCase();
    if (encoding && encoding !== 'identity') throw failure('Compressed responses are not sampled by this audit.', 'unsupported_encoding');
    return response;
  }
  async function robotsFor(origin) {
    if (robotCache.has(origin)) return robotCache.get(origin);
    let target = new URL('/robots.txt', origin);
    let response;
    for (let hops = 0; hops < 4; hops++) {
      response = await raw(target, Math.min(limits.maxBytes, 128 * 1024));
      if (![301, 302, 303, 307, 308].includes(response.status)) break;
      if (hops === 3 || !header(response.headers, 'location')) throw failure('The robots.txt redirect could not be safely resolved.', 'robots_unavailable');
      const next = normalizeWebsite(header(response.headers, 'location'), target);
      if (!aliasOrigin(new URL(origin), next)) throw failure('The robots.txt redirect leaves this website.', 'robots_unavailable');
      target = next;
    }
    let policy;
    if ([404, 410].includes(response.status)) policy = { rules: [], delay: 0, sitemaps: [], status: response.status, available: false };
    else if (response.status >= 200 && response.status < 300) {
      const type = header(response.headers, 'content-type');
      if (!/^(?:text\/plain|text\/x-robots)(?:;|$)/i.test(type) && type) throw failure('robots.txt did not return plain text; the audit stopped conservatively.', 'robots_unavailable');
      policy = { ...parseRobots(response.body), status: response.status, available: true };
    } else throw failure('robots.txt could not be checked; the audit stopped conservatively.', 'robots_unavailable');
    policy.url = new URL('/robots.txt', origin).href;
    robotCache.set(origin, policy);
    return policy;
  }
  async function permitted(url) {
    const policy = await robotsFor(url.origin);
    if (policy.delay > 0) throw failure('This website requests a crawl delay. The audit stopped rather than ignore that preference.', 'robots_crawl_delay');
    if (!robotsAllows(policy, url)) { blocked++; return false; }
    return true;
  }
  async function pageRequest(url, root = false) {
    const source = url;
    for (let hops = 0; hops < 4; hops++) {
      if (!(await permitted(url))) return null;
      const response = await raw(url);
      if (![301, 302, 303, 307, 308].includes(response.status)) return { url, response };
      if (hops === 3 || !header(response.headers, 'location')) throw failure('The page has too many or invalid redirects.', 'redirect_limit');
      const next = normalizeWebsite(header(response.headers, 'location'), url);
      if (root ? !aliasOrigin(source, next) : next.origin !== source.origin) throw failure('A page redirects outside the allowed website.', 'external_redirect');
      url = next;
    }
  }
  try {
    await phase('checking_website');
    const result = await pageRequest(initial, true);
    if (!result) throw failure('The website disallows this page for KorlixSEO in robots.txt.', 'robots_disallowed');
    const site = result.url;
    const pages = [], visited = new Set(), queue = [site.href];
    let first = result;
    await phase('sampling_pages');
    while (queue.length && pages.length < PAGE_LIMIT) {
      check();
      const link = queue.shift();
      if (visited.has(link)) continue;
      visited.add(link);
      let item;
      try { item = first ?? await pageRequest(new URL(link)); first = null; }
      catch (error) {
        if (error.code === 'audit_timeout') { limitations.push('The audit time limit ended the sample early.'); break; }
        limitations.push(`A discovered page was not sampled (${error.code ?? 'unavailable'}): ${link}`);
        continue;
      }
      if (!item) continue;
      const { url, response } = item;
      if (pages.some(p => p.url === url.href)) continue;
      visited.add(url.href);
      if (response.status >= 400) {
        pages.push({ url: url.href, status: response.status, title: '', description: '', h1s: [], canonical: '', robots: [], images: 0, missingAlt: 0, emptyAlt: 0, textExcerpt: '', links: [], responseBytes: response.bytes ?? Buffer.byteLength(response.body), noindex: false });
        continue;
      }
      if (response.status < 200 || response.status >= 300 || !/^text\/html(?:;|$)|^application\/xhtml\+xml(?:;|$)/i.test(header(response.headers, 'content-type'))) {
        if (!pages.length) throw failure('The website did not return a successful HTML page.', 'not_html');
        limitations.push(`A discovered URL did not return HTML and was excluded: ${url.href}`);
        continue;
      }
      const page = extractPage(response.body, url.href, response);
      pages.push(page);
      for (const next of page.links) if (!visited.has(next) && !queue.includes(next) && queue.length < 30) queue.push(next);
    }
    const robots = await robotsFor(site.origin);
    const sitemap = { referenced: robots.sitemaps, checkedUrl: null, status: null, available: false, fullValidation: false };
    if (!controller.signal.aborted && now() - started < hardTotal - 1000) {
      let target;
      for (const ref of [...robots.sitemaps, new URL('/sitemap.xml', site).href]) {
        try { const candidate = normalizeWebsite(ref); if (candidate.origin === site.origin) { target = candidate; break; } } catch {}
      }
      if (target && robotsAllows(robots, target)) {
        sitemap.checkedUrl = target.href;
        try {
          const response = await raw(target, Math.min(limits.maxBytes, 256 * 1024));
          sitemap.status = response.status;
          sitemap.available = response.status === 200 && /<(?:[\w.-]+:)?(?:urlset|sitemapindex)(?:\s|>)/i.test(response.body);
        } catch { limitations.push('Sitemap availability could not be checked within this audit.'); }
      }
    }
    limitations.push('Sitemap checking only detects a bounded response with a sitemap root element; URLs and XML correctness are not fully validated.');
    if (blocked) limitations.push(`${blocked} discovered page(s) were excluded by robots.txt.`);
    const findings = findingsFor(pages);
    const deduction = findings.reduce((n, f) => n + ({ high: 12, medium: 6, low: 2 }[f.priority]), 0);
    return { scannedAt: new Date(now()).toISOString(), siteUrl: site.href, pages, findings,
      score: Math.max(0, 100 - deduction), scoreLabel: 'Sampled on-page checks score (not a ranking score)',
      coverage: { pagesScanned: pages.length, pageLimit: PAGE_LIMIT, requests, robotsExcluded: blocked, discoveredLinks: visited.size + queue.length, elapsedMs: Math.max(0, now() - started) },
      limitations: [...new Set(limitations)].slice(0, 40),
      robots: { url: robots.url, status: robots.status, available: robots.available, respected: true }, sitemap };
  } finally { clearTimeout(timer); signal?.removeEventListener('abort', abort); controller.abort(); }
}
