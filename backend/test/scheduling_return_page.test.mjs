import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { webcrypto } from "node:crypto";
import { runInNewContext } from "node:vm";
import express from "express";
import { registerScheduling } from "../scheduling/routes.mjs";

// Run the shipped browser script, with only its DOM and network boundaries
// replaced. These tests do not claim mobile rendering or real Stripe redirects.
const html = await readFile(new URL("../scheduling/public/index.html", import.meta.url), "utf8");
const script = await readFile(new URL("../scheduling/public/booking.js", import.meta.url), "utf8");
const bookingId = "12345678-1234-4234-8234-123456789abc";
const manageToken = "a".repeat(64);
const fragment = `#${bookingId}.${manageToken}`;
const future = (minutes) => new Date(Date.now() + minutes * 60000).toISOString();
function booking(state = "awaiting_payment", paymentState = "unpaid", refundState = "none") {
  return {
    id: bookingId, state, revision: 1,
    guest_name: "Return page fixture", guest_email: "guest@example.test",
    guest_timezone: "UTC", starts_at: future(1440), cancel_until: future(1440),
    snapshot: { title: "Sandbox appointment", host_name: "Fixture host", duration_minutes: 30,
      refund_policy: "Full refund on request.", questions: [] },
    answers: {}, notifications: [],
    payment: { state: paymentState, refund_state: refundState, amount_cents: 100,
      currency: "usd", livemode: false, checkout_expires_at: future(40) },
  };
}
class Element {
  constructor(tag, hidden = false) {
    this.tagName = tag.toUpperCase(); this.hidden = hidden; this.disabled = false;
    this.children = []; this.value = ""; this._text = "";
    this.classList = { add() {}, remove() {} };
  }
  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() { return this._text + this.children.map((child) => child.textContent).join(""); }
  replaceChildren(...children) { this._text = ""; this.children = children; }
  append(...children) { this.children.push(...children); }
  scrollIntoView() {}
  focus() {}
}
function loadPage({ hash = fragment, reply, search = "" } = {}) {
  const elements = new Map();
  for (const match of html.matchAll(/<([a-z][a-z0-9-]*)\b([^>]*\bid="([^"]+)"[^>]*)>/gi)) {
    elements.set(match[3], new Element(match[1], /\bhidden\b/.test(match[2])));
  }
  const requests = [], intervals = [], historyCalls = [], redirects = [];
  const document = {
    hidden: false,
    getElementById(id) { assert(elements.has(id), `Unknown page element ${id}`); return elements.get(id); },
    createElement: (tag) => new Element(tag),
    querySelectorAll(selector) {
      assert.equal(selector, "button");
      return [...elements.values()].filter((element) => element.tagName === "BUTTON");
    },
  };
  const completion = runInNewContext(script, {
    document, crypto: webcrypto, Intl, Date, URL, AbortController,
    location: { pathname: "/book/manage", hash, search, assign: (url) => redirects.push(url) },
    history: { replaceState: (...args) => historyCalls.push(args) },
    navigator: {},
    setTimeout: () => 1, clearTimeout() {},
    setInterval: (callback, delay) => { intervals.push({ callback, delay }); return 1; },
    fetch: async (path, options) => {
      requests.push({ path, options, body: JSON.parse(options.body) });
      const data = await reply(requests.at(-1));
      return { ok: true, status: 200, json: async () => ({ booking: data }) };
    },
  }, { filename: "booking.js" });
  return { completion, document, requests, intervals, historyCalls, redirects,
    element: (id) => document.getElementById(id) };
}

test("return page waits for the private manage response and never trusts a success query", async () => {
  let resolve;
  const page = loadPage({ search: "?payment_status=paid&success=true", reply: () => new Promise((done) => { resolve = done; }) });
  assert.equal(page.element("receipt").hidden, true, "No confirmation before the API responds");
  assert.equal(page.requests.length, 1);
  assert.equal(page.requests[0].path, "/api/scheduling/manage");
  assert.equal(page.requests[0].options.method, "POST");
  assert.equal(page.requests[0].options.credentials, "same-origin");
  assert.deepEqual(page.requests[0].body, { booking_id: bookingId, manage_token: manageToken });
  resolve(booking());
  await page.completion;
  assert.equal(page.element("receipt-title").textContent, "Complete payment to confirm.");
  assert.equal(page.element("receipt-icon").textContent, "—");
  assert.match(page.element("delivery-status").textContent, /Returning from checkout alone does not confirm/);
  assert.match(page.element("payment-status").textContent, /TEST MODE — no real payment.*unpaid/);
  assert.equal(page.element("checkout").hidden, false);
  assert.equal(page.element("calendar").hidden, true);
  assert.equal(page.historyCalls.at(-1)[2], `/book/manage${fragment}`);
  assert.deepEqual(page.redirects, []);
});

test("a verified paid response renders the confirmed appointment and hides checkout", async () => {
  const page = loadPage({ reply: () => booking("confirmed", "paid") });
  await page.completion;
  assert.equal(page.element("receipt-title").textContent, "You’re booked.");
  assert.equal(page.element("receipt-icon").textContent, "✓");
  assert.match(page.element("payment-status").textContent, /TEST MODE — no real payment.*paid/);
  assert.equal(page.element("checkout").hidden, true);
  assert.equal(page.element("calendar").hidden, false);
  assert.equal(page.element("reschedule").hidden, false);
  assert.equal(page.element("cancel").hidden, false);
});

test("a refunded return response displays cancellation and succeeded full refund", async () => {
  const page = loadPage({ reply: () => booking("canceled", "refunded", "succeeded") });
  await page.completion;
  assert.equal(page.element("receipt-title").textContent, "Appointment canceled.");
  assert.equal(page.element("receipt-icon").textContent, "—");
  assert.match(page.element("payment-status").textContent, /refunded.*Full refund: succeeded/);
  assert.equal(page.element("checkout").hidden, true);
  assert.equal(page.element("reschedule").hidden, true);
  assert.equal(page.element("cancel").hidden, true);
  assert.equal(page.element("calendar").textContent, "Download calendar update");
});

test("incomplete or malformed private return fragments make no API call", async () => {
  for (const hash of ["", `#${bookingId}`, `#${bookingId}.${manageToken.slice(1)}`, `${fragment}&payment_status=paid`]) {
    const page = loadPage({ hash, reply: () => assert.fail("Invalid link must not fetch") });
    await page.completion;
    assert.equal(page.requests.length, 0);
    assert.equal(page.element("receipt").hidden, true);
    assert.equal(page.element("error").hidden, false);
    assert.match(page.element("error").textContent, /Open the complete private link/);
    assert.equal(page.historyCalls.length, 0);
  }
});

test("pending return polls while visible, shows the verified update, and stops once paid", async () => {
  let current = booking();
  const page = loadPage({ reply: () => current });
  await page.completion;
  assert.equal(page.intervals.length, 1);
  assert.equal(page.intervals[0].delay, 15000);
  page.document.hidden = true;
  await page.intervals[0].callback();
  assert.equal(page.requests.length, 1);
  page.document.hidden = false;
  current = booking("confirmed", "paid");
  await page.intervals[0].callback();
  assert.equal(page.requests.length, 2);
  assert.equal(page.element("receipt-title").textContent, "You’re booked.");
  await page.intervals[0].callback();
  assert.equal(page.requests.length, 2, "Settled payment must not keep polling");
  current = booking("canceled", "refunded", "succeeded");
  await page.element("payment-refresh").onclick();
  assert.equal(page.requests.length, 3);
  assert.equal(page.element("receipt-title").textContent, "Appointment canceled.");
  assert.match(page.element("payment-status").textContent, /Full refund: succeeded/);
});

test("real return route serves its page and assets with private-page security headers", async () => {
  const app = express();
  const unavailable = () => assert.fail("Static return page must not call any provider or database");
  const service = registerScheduling(app, {
    environment: { NODE_ENV: "test", KORLIX_SCHEDULING_PUBLIC_URL: "https://booking.example.test" },
    database: { rpc: unavailable }, requireUser: unavailable, fetcher: unavailable,
    autoStartWorker: false,
  });
  const server = app.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  const root = `http://127.0.0.1:${server.address().port}`;
  try {
    const response = await fetch(root + "/book/manage");
    assert.equal(response.status, 200);
    assert.match(response.headers.get("content-type"), /text\/html/);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.equal(response.headers.get("referrer-policy"), "no-referrer");
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    const csp = response.headers.get("content-security-policy");
    assert.match(csp, /script-src 'self'/);
    assert.match(csp, /connect-src 'self'/);
    assert.match(csp, /object-src 'none'/);
    assert.equal(await response.text(), html);
    for (const asset of ["booking.js", "booking.css", "fonts.css"]) {
      const result = await fetch(root + "/book/assets/" + asset);
      assert.equal(result.status, 200, asset);
      assert.equal(result.headers.get("referrer-policy"), "no-referrer");
      assert.equal(result.headers.get("x-content-type-options"), "nosniff");
      const content = await result.text();
      assert(content.length > 0);
      if (asset === "booking.js") assert.equal(content, script);
    }
  } finally {
    service.connected.stop(); service.notifications.stop();
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});
