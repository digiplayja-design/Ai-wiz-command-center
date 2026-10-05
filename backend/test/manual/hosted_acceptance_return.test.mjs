import test from "node:test";
import assert from "node:assert/strict";
import { runInNewContext } from "node:vm";
import {
  renderHostedAcceptancePage, HOSTED_ACCEPTANCE_RETURN_CSS,
  HOSTED_ACCEPTANCE_RETURN_CSS_PATH, HOSTED_ACCEPTANCE_RETURN_HEADERS,
  renderHostedAcceptanceShell, HOSTED_ACCEPTANCE_RETURN_JS, HOSTED_ACCEPTANCE_RETURN_JS_PATH,
} from "./hosted_acceptance_return.mjs";

function display({ state = "awaiting_payment", paymentState = "unpaid", refundState = "none" } = {}) {
  return {
    booking: {
      state, starts_at: "2026-10-09T12:00:00.000Z", guest_timezone: "UTC",
      snapshot: { title: "Sandbox appointment", host_name: "Isolated sandbox host", duration_minutes: 30 },
    },
    payment: { state: paymentState, amount_cents: 100, currency: "usd", livemode: false, refund_state: refundState },
    refreshPath: "/book/return/private-test-token",
  };
}

test("return page displays separate appointment and payment outcomes without optimistic confirmation", () => {
  const cases = [
    [{}, "Awaiting test payment.", "Unpaid"],
    [{ paymentState: "pending" }, "Payment confirmation pending.", "Payment pending"],
    [{ paymentState: "paid" }, "Confirming your appointment.", "Paid"],
    [{ state: "confirmed", paymentState: "paid" }, "Your test appointment is confirmed.", "Paid"],
    [{ state: "canceled", paymentState: "paid" }, "Appointment canceled.", "Paid"],
    [{ state: "canceled", paymentState: "refunded", refundState: "succeeded" }, "Appointment canceled.", "Refunded"],
    [{ state: "expired" }, "Booking expired.", "Unpaid"],
    [{ state: "confirmed" }, "Payment confirmation pending.", "Unpaid"],
    [{ state: "confirmed", paymentState: "refunded", refundState: "succeeded" }, "Test payment refunded.", "Refunded"],
  ];
  for (const [states, title, paymentLabel] of cases) {
    const html = renderHostedAcceptancePage(display(states));
    assert(html.includes(`<h1 id="booking-title">${title}</h1>`));
    assert(html.includes(`<strong>${paymentLabel}</strong>`));
    assert.match(html, /TEST MODE/);
    assert.match(html, /\$1\.00 USD sandbox test\. No real payment is taken\./);
    assert(!html.includes("saved result") && !html.includes("Saved sandbox"));
    if (states.state !== "confirmed" || states.paymentState !== "paid")
      assert(!html.includes("Your test appointment is confirmed."));
  }
});

test("refresh does not infer success from query-shaped input or serialize private provider fields", () => {
  const input = display();
  input.status = "success";
  input.query = { success: true, paid: true };
  input.booking.id = "private-booking-id";
  input.booking.guest_email = "private@example.test";
  input.booking.manage_token = "private-control-token";
  input.booking.snapshot.location_detail = "https://private-meeting.example.test";
  input.payment.stripe_account_id = "acct_private";
  input.payment.payment_intent_id = "pi_private";
  input.payment.checkout_url = "https://checkout.stripe.com/private-sentinel";
  input.payment.error = "provider-error-with-secret";
  const html = renderHostedAcceptancePage(input);
  assert.match(html, /Awaiting test payment/);
  for (const value of ["private-booking-id", "private@example.test", "private-control-token", "private-meeting", "acct_private", "pi_private", "private-sentinel", "provider-error-with-secret"])
    assert(!html.includes(value), `Must omit ${value}`);
  assert.equal((html.match(/<a\s/g) || []).length, 1);
  assert(html.includes(`href="${input.refreshPath}" rel="noreferrer">Refresh status</a>`));
  assert.match(html, /No booking email was scheduled/);
  assert.match(html, /Calendar integration and appointment changes are unavailable/);
  assert.doesNotMatch(html, /<form\b|<button\b|mailto:|Add to calendar|Continue to.*payment/i);
});

test("all user display content is escaped and cannot add elements or attributes", () => {
  const input = display();
  input.booking.snapshot.title = `<img src=x onerror="alert('x')"> & </h2><script>alert(1)</script>`;
  input.booking.snapshot.host_name = `'><svg onload="alert(2)">`;
  const html = renderHostedAcceptancePage(input);
  assert(html.includes("&lt;img src=x onerror=&quot;alert(&#39;x&#39;)&quot;&gt; &amp; &lt;/h2&gt;&lt;script&gt;alert(1)&lt;/script&gt;"));
  assert(html.includes("&#39;&gt;&lt;svg onload=&quot;alert(2)&quot;&gt;"));
  assert.doesNotMatch(html, /<img\b|<svg\b|<script\b/i);
  assert.equal((html.match(/<h2\b/g) || []).length, 1);
});

test("refresh accepts canonical local paths and rejects script, external, query and fragment destinations", () => {
  for (const path of ["/book/return/abc-def_123", "/book/return/uuid.token", "/"]) {
    const input = display(); input.refreshPath = path;
    assert.doesNotThrow(() => renderHostedAcceptancePage(input));
  }
  for (const path of [undefined, "", "javascript:alert(1)", "https://evil.example", "//evil.example", "/\\evil.example", "/book/../admin", "/./", "/book//return", "/book?token=secret", "/book#secret", "/book/%2F%2Fevil.example", "/book\r\nLocation:evil", '/book/"onclick="alert(1)', "/" + "a".repeat(2048)]) {
    const input = display(); input.refreshPath = path;
    assert.throws(() => renderHostedAcceptancePage(input), /private refresh path/);
  }
});

test("renderer refuses live or inconsistent payment data and invalid dates without exposing values", () => {
  for (const change of [
    { livemode: true }, { livemode: undefined }, { amount_cents: 200 }, { currency: "eur" },
    { state: "succeeded" }, { state: "refunded", refund_state: "pending" },
    { state: "paid", refund_state: "succeeded" }, { refund_state: "raw-provider-error" },
  ]) {
    const input = display(); Object.assign(input.payment, change);
    assert.throws(() => renderHostedAcceptancePage(input), (error) => error instanceof TypeError && !error.message.includes("raw-provider-error"));
  }
  for (const change of [
    { state: "__proto__" }, { starts_at: "not-a-date" }, { starts_at: "2026-10-09T12:00:00" },
    { guest_timezone: '<script>bad</script>' },
  ]) {
    const input = display(); Object.assign(input.booking, change);
    assert.throws(() => renderHostedAcceptancePage(input), TypeError);
  }
  const input = display(); input.booking.snapshot.duration_minutes = NaN;
  assert.throws(() => renderHostedAcceptancePage(input), /duration/);
});

test("refund messages preserve pending, failed and succeeded distinctions", () => {
  const pending = renderHostedAcceptancePage(display({ state: "canceled", paymentState: "paid", refundState: "pending" }));
  assert.match(pending, /full test refund is pending/);
  assert.doesNotMatch(pending, /refund completed/);
  const failed = renderHostedAcceptancePage(display({ state: "canceled", paymentState: "paid", refundState: "failed" }));
  assert.match(failed, /refund could not be completed/);
  assert.doesNotMatch(failed, /refund completed/);
  const complete = renderHostedAcceptancePage(display({ state: "canceled", paymentState: "refunded", refundState: "succeeded" }));
  assert.match(complete, /Full test refund completed/);
});

test("production terminal and compensation states render accurately without a false confirmation", () => {
  for (const refundState of ["required", "sending", "pending", "uncertain", "failed"]) {
    const html = renderHostedAcceptancePage(display({ state: "payment_failed", paymentState: "paid_unfulfilled", refundState }));
    assert.match(html, /test payment was received, but the appointment could not be confirmed/);
    assert.doesNotMatch(html, /Your test appointment is confirmed|Full test refund completed/);
  }
  const uncertain = renderHostedAcceptancePage(display({ state: "payment_failed", paymentState: "paid_unfulfilled", refundState: "uncertain" }));
  assert.match(uncertain, /refund outcome is not yet confirmed/);
  for (const [states, title] of [
    [{ state: "payment_failed" }, "Appointment not confirmed."],
    [{ state: "completed", paymentState: "paid" }, "Test appointment completed."],
    [{ state: "no_show", paymentState: "paid" }, "Test appointment marked missed."],
    [{ state: "confirmed", paymentState: "disputed" }, "Test payment disputed."],
  ]) {
    const html = renderHostedAcceptancePage(display(states));
    assert(html.includes(`<h1 id="booking-title">${title}</h1>`));
    assert.doesNotMatch(html, /Your test appointment is confirmed/);
  }
});

test("page works without scripts or external resources and includes accessible responsive markup", () => {
  const html = renderHostedAcceptancePage(display());
  assert.match(html, /<html lang="en">/);
  assert.match(html, /name="viewport" content="width=device-width, initial-scale=1"/);
  assert.match(html, /name="referrer" content="no-referrer"/);
  assert.match(html, /aria-labelledby="booking-title"/);
  assert.match(html, /<time datetime="2026-10-09T12:00:00\.000Z">Friday, October 9, 2026<\/time>/);
  assert.match(html, /12:00 PM UTC/);
  assert(html.includes(`href="${HOSTED_ACCEPTANCE_RETURN_CSS_PATH}"`));
  assert.doesNotMatch(html, /<script\b|<style\b|\sstyle=|https?:\/\//i);
  assert.doesNotMatch(HOSTED_ACCEPTANCE_RETURN_CSS, /url\(|@import/i);
  assert.match(HOSTED_ACCEPTANCE_RETURN_CSS, /@media \(max-width: 600px\)/);
  assert.match(HOSTED_ACCEPTANCE_RETURN_CSS, /min-height: 48px/);
  assert.match(HOSTED_ACCEPTANCE_RETURN_CSS, /a:focus-visible/);
  assert.equal(HOSTED_ACCEPTANCE_RETURN_HEADERS["Cache-Control"], "no-store");
  assert.equal(HOSTED_ACCEPTANCE_RETURN_HEADERS["Referrer-Policy"], "no-referrer");
  assert.equal(HOSTED_ACCEPTANCE_RETURN_HEADERS["X-Frame-Options"], "DENY");
  for (const directive of ["default-src 'none'", "script-src 'self'", "style-src 'self'", "connect-src 'self'", "form-action 'none'", "frame-ancestors 'none'"])
    assert(HOSTED_ACCEPTANCE_RETURN_HEADERS["Content-Security-Policy"].includes(directive));
});

test("public shell contains only waiting state and static same-origin assets", () => {
  const shell = renderHostedAcceptanceShell();
  assert.match(shell, /Checking your appointment/);
  assert.match(shell, /role="status" aria-live="polite"/);
  assert.match(shell, /<noscript>/);
  assert(shell.includes(`<script src="${HOSTED_ACCEPTANCE_RETURN_JS_PATH}" defer></script>`));
  assert(shell.includes(`<link rel="stylesheet" href="${HOSTED_ACCEPTANCE_RETURN_CSS_PATH}"`));
  assert.doesNotMatch(shell, /confirmed|payment_intent|manage_token|booking_id|https?:\/\//);
  assert.doesNotMatch(HOSTED_ACCEPTANCE_RETURN_JS, /console\.|localStorage|sessionStorage|document\.cookie|location\.search|history\./);
});

// Minimal DOM boundary exercises the shipped browser script's fetch/auth and
// state transitions, without reaching Stripe or an external browser session.
function browserFixture({ hash, fetcher } = {}) {
  const requests = [], handlers = new Map(), location = { hash: hash ?? "", search: "?success=true" };
  let currentMain;
  class Element {
    constructor(html = "", textContent = "") {
      this.html = html; this.textContent = textContent;
      this.attrs = {}; this.fields = new Map();
    }
    cloneNode() {
      const clone = new Element(this.html, this.textContent);
      clone.attrs = { ...this.attrs };
      for (const [key, value] of this.fields) clone.fields.set(key, value.cloneNode());
      return clone;
    }
    querySelector(selector) {
      if (selector === "script, iframe, object, embed, form") return /<(script|iframe|object|embed|form)\b/i.test(this.html) ? new Element() : null;
      return this.fields.get(selector) ?? null;
    }
    setAttribute(key, value) { this.attrs[key] = value; }
    replaceWith(other) { currentMain = other; }
    closest(selector) { return selector === "a.refresh" ? this : null; }
  }
  currentMain = new Element();
  for (const id of ["#return-heading", "#return-message", ".status-icon", "#return-feedback"])
    currentMain.fields.set(id, new Element());
  const document = {
    querySelector: (selector) => selector === "main" ? currentMain : null,
    importNode: (node) => node.cloneNode(),
    addEventListener: (event, handler) => handlers.set(event, handler),
  };
  class DOMParser {
    parseFromString(html) {
      return { querySelector: (selector) => selector === "main" && /<main[\s>]/.test(html) ? new Element(html) : null };
    }
  }
  runInNewContext(HOSTED_ACCEPTANCE_RETURN_JS, {
    window: { location, addEventListener: (event, handler) => handlers.set(event, handler) },
    document, DOMParser, Element, AbortController,
    setTimeout: () => 1, clearTimeout: () => {},
    fetch: async (url, options) => {
      requests.push({ url, options });
      return fetcher ? fetcher(url, options) : { ok: true, status: 200, json: async () => ({ html: renderHostedAcceptancePage(display()) }) };
    },
  });
  return {
    requests, location, get main() { return currentMain; },
    get heading() { return currentMain.querySelector("#return-heading")?.textContent; },
    get message() { return currentMain.querySelector("#return-message")?.textContent; },
    refresh() {
      let prevented = false;
      handlers.get("click")({ target: new Element(), preventDefault: () => { prevented = true; } });
      assert(prevented);
    },
    changeHash(value) { location.hash = value; handlers.get("hashchange")(); },
  };
}
const BOOKING_ID = "12345678-1234-4234-8234-123456789abc";
const TOKEN = "a".repeat(64);
const FRAGMENT = `#${BOOKING_ID}.${TOKEN}`;
const settle = () => new Promise((resolve) => setImmediate(resolve));

test("fragment credential only travels in status POST body and refresh retains the private link", async () => {
  const browser = browserFixture({ hash: FRAGMENT });
  assert.equal(browser.heading, "Checking your appointment…");
  await settle();
  assert.match(browser.main.html, /Awaiting test payment/);
  const request = browser.requests[0];
  assert.equal(request.url, "/acceptance/customer/status");
  assert.equal(request.options.method, "POST");
  assert.equal(request.options.credentials, "omit");
  assert.equal(request.options.cache, "no-store");
  assert.equal(request.options.redirect, "error");
  assert.equal(request.options.referrerPolicy, "no-referrer");
  assert.deepEqual(JSON.parse(request.options.body), { booking_id: BOOKING_ID, manage_token: TOKEN });
  assert(!request.url.includes(TOKEN));
  assert(!JSON.stringify(request.options.headers).includes(TOKEN));
  assert.equal(browser.location.hash, FRAGMENT);
  browser.refresh();
  await settle();
  assert.equal(browser.requests.length, 2);
  assert.equal(browser.location.hash, FRAGMENT);
});

test("missing or malformed fragment never sends credentials or treats success query as payment", async () => {
  for (const hash of ["", "#success", `#${BOOKING_ID}.short`, `${FRAGMENT}&success=true`]) {
    const browser = browserFixture({ hash });
    await settle();
    assert.equal(browser.requests.length, 0);
    assert.equal(browser.heading, "Private booking link needed.");
    assert.equal(browser.main.attrs["aria-busy"], "false");
  }
});

test("HTTP, malformed-response and connection failures show generic recoverable errors", async () => {
  for (const response of [
    { ok: false, status: 404, json: async () => { throw new Error("Must not read provider details"); } },
    { ok: false, status: 503, json: async () => ({ secret: "secret-sentinel" }) },
    { ok: true, status: 200, json: async () => ({ html: "<main><script>secret-sentinel</script></main>" }) },
    { ok: true, status: 200, json: async () => ({ html: "not a page secret-sentinel" }) },
  ]) {
    const browser = browserFixture({ hash: FRAGMENT, fetcher: async () => response });
    await settle();
    assert.equal(browser.heading, "Status unavailable.");
    assert.equal(browser.main.attrs["aria-busy"], "false");
    assert(!browser.message.includes("secret-sentinel"));
  }
  const expired = browserFixture({ hash: FRAGMENT, fetcher: async () => ({ ok: false, status: 410 }) });
  await settle();
  assert.equal(expired.heading, "Private link expired.");
  const disconnected = browserFixture({ hash: FRAGMENT, fetcher: async () => { throw new Error("Network secret-sentinel"); } });
  await settle();
  assert.equal(disconnected.heading, "Status unavailable.");
  assert(!disconnected.message.includes("secret-sentinel"));
});

test("old status responses cannot replace a newer private booking result", async () => {
  const deferred = [];
  const browser = browserFixture({ hash: FRAGMENT, fetcher: () => new Promise((resolve) => deferred.push(resolve)) });
  browser.changeHash(`#${BOOKING_ID}.${"b".repeat(64)}`);
  assert.equal(browser.requests[0].options.signal.aborted, true);
  deferred[1]({ ok: true, status: 200, json: async () => ({ html: renderHostedAcceptancePage(display({ state: "canceled" })) }) });
  await settle();
  assert.match(browser.main.html, /Appointment canceled/);
  deferred[0]({ ok: true, status: 200, json: async () => ({ html: renderHostedAcceptancePage(display({ state: "confirmed", paymentState: "paid" })) }) });
  await settle();
  assert.match(browser.main.html, /Appointment canceled/);
  assert.doesNotMatch(browser.main.html, /Your test appointment is confirmed/);
});
