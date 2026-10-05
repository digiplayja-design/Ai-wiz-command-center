// Separate, read-only saved-result display app. Never imported by production.
// No Stripe client, database, acceptance control routes, or payment operations.
import assert from "node:assert/strict";
import { createHash, timingSafeEqual } from "node:crypto";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const MODE = "refunded-sandbox-display-v1";
const DAY = 86400000;
const digest = (value) => createHash("sha256").update(value).digest();
const iso = (value) => typeof value === "string" && Number.isFinite(Date.parse(value)) &&
  new Date(value).toISOString() === value;
const text = (value, limit) => typeof value === "string" && value.length > 0 && value.length <= limit;

export function previewConfig(env = {}, now = Date.now()) {
  assert.equal(env.KORLIX_RETURN_PREVIEW, MODE, "Explicit saved-result display opt-in required.");
  assert(!Object.entries(env).some(([name, value]) => value &&
    (/^(STRIPE_|SUPABASE_|RESEND_|OPENAI_|TWILIO_|VAPI_|DATABASE_URL$)/.test(name) ||
      /^KORLIX_(?!RETURN_PREVIEW(?:_|$))/.test(name))), "Do not attach production or provider configuration.");
  const raw = env.KORLIX_RETURN_PREVIEW_DATA;
  assert(typeof raw === "string" && Buffer.byteLength(raw) <= 32768, "Supply one bounded saved sandbox result.");
  const saved = JSON.parse(raw), b = saved?.booking, p = b?.payment, s = b?.snapshot;
  assert(iso(saved.capturedAt) && Date.parse(saved.capturedAt) <= now + 60000, "Invalid capture time.");
  const expiry = env.KORLIX_RETURN_PREVIEW_EXPIRES_AT;
  assert(iso(expiry) && Date.parse(expiry) > Date.parse(saved.capturedAt) &&
    Date.parse(expiry) <= Date.parse(saved.capturedAt) + 7 * DAY, "Link lifetime must be at most seven days.");
  assert(/^[a-f0-9]{64}$/.test(env.KORLIX_RETURN_PREVIEW_TOKEN_HASH || ""), "Supply only a token hash.");
  const origin = new URL(env.KORLIX_RETURN_PREVIEW_ORIGIN || env.RENDER_EXTERNAL_URL);
  assert(origin.protocol === "https:" && !origin.username && !origin.password &&
    origin.pathname === "/" && !origin.search && !origin.hash, "An HTTPS origin is required.");
  assert(/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(b?.id || ""), "Invalid saved booking.");
  assert(b.state === "canceled" && p?.state === "refunded" && p.refund_state === "succeeded" &&
    p.livemode === false && p.amount_cents === 100 && p.currency === "usd", "Only a fully refunded USD 1 sandbox booking is allowed.");
  assert.equal(b.guest_name, "Synthetic sandbox guest", "Only the known synthetic guest is allowed.");
  assert.equal(b.guest_email, "sandbox-guest@example.test", "Only the synthetic email is allowed.");
  assert.equal(b.guest_timezone, "UTC");
  assert.equal(s?.host_name, "Isolated sandbox host", "Only the synthetic host is allowed.");
  assert.equal(s.duration_minutes, 30);
  assert(text(s.title, 200) && text(s.refund_policy, 1000), "Invalid saved display text.");
  assert(Number.isSafeInteger(b.revision) && b.revision >= 0 && iso(b.starts_at) && iso(b.cancel_until), "Invalid saved booking dates.");
  // Do not copy Checkout URLs, meeting links, provider IDs/errors, or private grants.
  const booking = {
    id: b.id, state: b.state, revision: b.revision,
    guest_name: b.guest_name, guest_email: b.guest_email, guest_timezone: b.guest_timezone,
    starts_at: b.starts_at, cancel_until: b.cancel_until,
    snapshot: { title: s.title, host_name: s.host_name, duration_minutes: s.duration_minutes,
      refund_policy: s.refund_policy, questions: [] },
    answers: {}, notifications: [],
    payment: { state: p.state, refund_state: p.refund_state, amount_cents: p.amount_cents,
      currency: p.currency, livemode: p.livemode },
  };
  return { origin: origin.origin, host: origin.host, expiresAt: Date.parse(expiry),
    capturedAt: saved.capturedAt, tokenHash: Buffer.from(env.KORLIX_RETURN_PREVIEW_TOKEN_HASH, "hex"),
    bookingJson: JSON.stringify({ booking }), bookingId: booking.id };
}

const HEADERS = {
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "X-Robots-Tag": "noindex, nofollow, noarchive",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
  "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' https://www.korlixdeveloper.com; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
};
const PREVIEW_CSS = `
#sandbox-preview-note { max-width: 1000px; margin: 20px auto 0; padding: 16px 20px; border: 1px solid #b7cddd; border-radius: 16px; background: #e5f2fc; color: #142239; }
#sandbox-preview-note p { margin: 5px 0; }
#calendar, #checkout, #cancel, #reschedule, #reschedule-section { display: none !important; }
@media(max-width: 600px) { #sandbox-preview-note { margin: 12px; } }
`;

export async function createPreviewServer(config, { now = Date.now } = {}) {
  const publicDir = new URL("../../scheduling/public/", import.meta.url);
  const assets = new Map();
  for (const [file, type] of [["booking.js", "text/javascript"], ["booking.css", "text/css"], ["fonts.css", "text/css"]])
    assets.set("/book/assets/" + file, { body: await readFile(new URL(file, publicDir)), type });
  assets.set("/book/assets/return-preview.css", { body: PREVIEW_CSS, type: "text/css" });
  const html = (await readFile(new URL("index.html", publicDir), "utf8"))
    .replace("</head>", '<link rel="stylesheet" href="/book/assets/return-preview.css" /></head>')
    .replace("<main>", `<aside id="sandbox-preview-note" role="note"><strong>Saved sandbox result — read-only display check</strong><p>Captured ${config.capturedAt}. This page shows a refunded test booking. It does not check Stripe again or take payments.</p><p>Calendar downloads and booking changes are unavailable on this test page.</p></aside><main>`)
    .replace("Refresh payment status", "Reload saved result")
    .replace("Anyone with your private link can view and manage this appointment.", "Anyone with this test link can view this saved sandbox result.");
  const send = (res, status, body, type = "application/json") => {
    res.writeHead(status, { ...HEADERS, "Content-Type": type + "; charset=utf-8" });
    res.end(typeof body === "object" && !Buffer.isBuffer(body) ? JSON.stringify(body) : body);
  };
  const missing = (res) => send(res, 404, { error: "This saved sandbox result is unavailable." });
  const server = createServer(async (req, res) => {
    try {
      const url = new URL(req.url, config.origin);
      if (!req.url.startsWith("/") || req.url.startsWith("//") || url.search) return missing(res);
      // Health carries no booking data and also works for Render's internal health requests.
      if (req.method === "GET" && url.pathname === "/health") return send(res, 200, {
        mode: "saved-sandbox-return-display", checkoutEnabled: false, paymentsConnected: false,
        expired: now() >= config.expiresAt,
      });
      if (req.headers.host !== config.host) return missing(res);
      if (req.method === "GET" && url.pathname === "/") {
        res.writeHead(302, { ...HEADERS, Location: "/book/manage" }); return res.end();
      }
      if (req.method === "GET" && url.pathname === "/robots.txt") return send(res, 200, "User-agent: *\nDisallow: /\n", "text/plain");
      if (req.method === "GET" && url.pathname === "/book/manage") return send(res, 200, html, "text/html");
      if (req.method === "GET" && assets.has(url.pathname)) {
        const asset = assets.get(url.pathname); return send(res, 200, asset.body, asset.type);
      }
      if (req.method !== "POST" || url.pathname !== "/api/scheduling/manage") return missing(res);
      if ((req.headers.origin && req.headers.origin !== config.origin) ||
        (req.headers["sec-fetch-site"] && req.headers["sec-fetch-site"] !== "same-origin"))
        return send(res, 403, { error: "Open the private test link directly." });
      if (now() >= config.expiresAt) return send(res, 410, { error: "This sandbox display link has expired." });
      if (!/^application\/json(?:\s*;|$)/i.test(req.headers["content-type"] || ""))
        return send(res, 400, { error: "Use a JSON request." });
      if (Number(req.headers["content-length"]) > 4096) return send(res, 413, { error: "Request too large." });
      const chunks = []; let length = 0;
      for await (const chunk of req) {
        length += chunk.length;
        if (length > 4096) return send(res, 413, { error: "Request too large." });
        chunks.push(chunk);
      }
      let data;
      try { data = JSON.parse(Buffer.concat(chunks).toString("utf8")); }
      catch { return send(res, 400, { error: "Use a valid JSON request." }); }
      if (!data || Array.isArray(data) || Object.keys(data).some(k => !["booking_id", "manage_token"].includes(k)) ||
        data.booking_id !== config.bookingId || typeof data.manage_token !== "string" ||
        !/^[a-f0-9]{64}$/.test(data.manage_token) || !timingSafeEqual(digest(data.manage_token), config.tokenHash))
        return missing(res);
      return send(res, 200, config.bookingJson);
    } catch { if (!res.headersSent) send(res, 400, { error: "This request could not be completed." }); else res.end(); }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const server = await createPreviewServer(previewConfig(process.env));
    const port = Number(process.env.PORT || 10000);
    assert(Number.isInteger(port) && port > 0 && port <= 65535);
    server.listen(port, "0.0.0.0", () => console.log("Saved sandbox return display ready; payment operations unavailable."));
    process.once("SIGTERM", () => { server.close(); server.closeAllConnections(); });
  } catch { console.error("Saved sandbox return display configuration rejected; no values displayed."); process.exitCode = 1; }
}
