// Pure customer display for the isolated USD 1 sandbox acceptance runtime.
// The caller authenticates the private request and obtains current ledger state.
// This module has no network, database, logging, query-string, or payment logic.

export const HOSTED_ACCEPTANCE_RETURN_CSS_PATH = "/acceptance/assets/return.css";
export const HOSTED_ACCEPTANCE_RETURN_JS_PATH = "/acceptance/assets/return.js";

export const HOSTED_ACCEPTANCE_RETURN_HEADERS = Object.freeze({
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "X-Robots-Tag": "noindex, nofollow, noarchive",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
  "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'none'; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
});

// The fragment never appears in HTTP request URLs. Only the authenticated
// status POST body carries it; no analytics, browser storage, or logging.
export const HOSTED_ACCEPTANCE_RETURN_JS = `
(() => {
  'use strict';
  const shell = document.querySelector('main').cloneNode(true);
  let generation = 0;
  let activeRequest;

  function showMessage(title, message, waiting) {
    const main = shell.cloneNode(true);
    main.setAttribute('aria-busy', String(waiting));
    main.querySelector('#return-heading').textContent = title;
    main.querySelector('#return-message').textContent = message;
    main.querySelector('.status-icon').textContent = waiting ? '…' : '−';
    main.querySelector('#return-feedback').setAttribute('role', waiting ? 'status' : 'alert');
    document.querySelector('main').replaceWith(main);
  }

  async function refreshStatus() {
    const requestGeneration = ++generation;
    if (activeRequest) activeRequest.abort();
    const match = /^#([a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12})\\.([a-f0-9]{64})$/.exec(window.location.hash);
    if (!match) {
      showMessage('Private booking link needed.', 'Open the complete private link for this test appointment.', false);
      return;
    }
    showMessage('Checking your appointment…', 'Please wait while we load your current test appointment status.', true);
    const controller = new AbortController();
    activeRequest = controller;
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch('/acceptance/customer/status', {
        method: 'POST', credentials: 'omit', cache: 'no-store', redirect: 'error',
        referrerPolicy: 'no-referrer', signal: controller.signal,
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({ booking_id: match[1], manage_token: match[2] }),
      });
      if (requestGeneration !== generation) return;
      if (!response.ok) {
        const expired = response.status === 410;
        const unavailable = [401, 403, 404].includes(response.status);
        showMessage(expired ? 'Private link expired.' : 'Status unavailable.',
          expired ? 'This private test link has expired.' : unavailable
            ? 'This test appointment is unavailable. Check your private booking link.'
            : 'Your appointment status is temporarily unavailable. Refresh to try again.', false);
        return;
      }
      const result = await response.json();
      if (requestGeneration !== generation) return;
      if (!result || typeof result.html !== 'string' || result.html.length > 65536) throw new Error('Invalid response');
      const parsed = new DOMParser().parseFromString(result.html, 'text/html');
      const main = parsed.querySelector('main');
      if (!main || main.querySelector('script, iframe, object, embed, form')) throw new Error('Invalid response');
      const replacement = document.importNode(main, true);
      replacement.setAttribute('aria-busy', 'false');
      document.querySelector('main').replaceWith(replacement);
      const heading = replacement.querySelector('h1');
      if (heading) {
        heading.setAttribute('tabindex', '-1');
        heading.focus({ preventScroll: true });
      }
    } catch {
      if (requestGeneration === generation)
        showMessage('Status unavailable.', 'Your appointment status could not be loaded. Refresh to try again.', false);
    } finally {
      clearTimeout(timeout);
      if (activeRequest === controller) activeRequest = undefined;
    }
  }
  document.addEventListener('click', (event) => {
    const target = event.target;
    if (target instanceof Element && target.closest('a.refresh')) {
      event.preventDefault();
      refreshStatus();
    }
  });
  window.addEventListener('hashchange', refreshStatus);
  refreshStatus();
})();
`;

export const HOSTED_ACCEPTANCE_RETURN_CSS = `
:root { color-scheme: light; --ink: #142239; --muted: #52647a; --line: #dbe4ee; --paper: #fff; --accent: #145e78; }
* { box-sizing: border-box; }
body { margin: 0; color: var(--ink); background: radial-gradient(ellipse at top right, #dceff2 0, transparent 45%), #f5f7fa; font-family: Arial, Helvetica, sans-serif; font-size: 16px; line-height: 1.6; }
header, footer { max-width: 1120px; margin: auto; padding: 28px; display: flex; align-items: center; justify-content: space-between; gap: 20px; }
.brand { font-size: 24px; font-weight: 800; letter-spacing: 3px; line-height: 1.25; }
.brand span { display: block; margin-top: 5px; color: var(--accent); font-size: 11px; letter-spacing: 4px; }
.header-note, footer { font-size: 14px; color: var(--muted); }
main { max-width: 820px; margin: 22px auto 48px; padding: 0 24px; }
.sandbox-note { margin-bottom: 20px; padding: 16px 22px; border: 1px solid #bed9e7; border-radius: 16px; background: #e9f5fa; }
.sandbox-note strong { display: block; letter-spacing: 1.6px; font-size: 12px; }
.sandbox-note p { margin: 3px 0 0; font-size: 15px; }
.receipt { padding: 40px; background: var(--paper); border: 1px solid var(--line); border-radius: 28px; box-shadow: 0 24px 70px #1422390b; }
.status-icon { display: grid; place-items: center; width: 62px; height: 62px; margin-bottom: 22px; border-radius: 50%; background: #e8f0f8; color: #245770; font-size: 28px; font-weight: 600; }
.status-confirmed .status-icon { background: #e0f3ec; color: #166c50; }
.status-canceled .status-icon, .status-expired .status-icon { background: #edf0f5; color: #52647a; }
.eyebrow { margin: 0; color: var(--accent); font-size: 11px; font-weight: 700; letter-spacing: 1.8px; text-transform: uppercase; }
h1 { margin: 8px 0 12px; font-size: clamp(28px, 4vw, 40px); line-height: 1.16; letter-spacing: -1px; overflow-wrap: anywhere; }
.explanation { color: var(--muted); margin: 0 0 24px; }
h2 { margin: 0 0 18px; font-size: 18px; line-height: 1.5; overflow-wrap: anywhere; }
.meeting { padding: 24px 0; border-top: 1px solid var(--line); border-bottom: 1px solid var(--line); }
dl { margin: 0; }
.detail-row { display: grid; grid-template-columns: 112px minmax(0, 1fr); gap: 12px; margin: 8px 0; }
dt { color: var(--muted); }
dd { margin: 0; overflow-wrap: anywhere; }
.payment { margin: 24px 0; padding: 18px 20px; border-radius: 16px; background: #f0f6fa; }
.payment-line { display: flex; justify-content: space-between; align-items: baseline; flex-wrap: wrap; gap: 8px 20px; }
.payment-line strong { font-size: 18px; }
.payment p { margin: 8px 0 0; font-size: 14px; }
.service-note, .private-note { color: var(--muted); font-size: 14px; }
.service-note { margin: 0 0 24px; }
.refresh { display: inline-flex; min-height: 48px; padding: 12px 22px; align-items: center; justify-content: center; color: #fff; background: var(--accent); border: 2px solid var(--accent); border-radius: 11px; text-decoration: none; font-size: 16px; font-weight: 700; touch-action: manipulation; }
.refresh:hover { background: #104b60; }
a:focus-visible { outline: 3px solid #176782; outline-offset: 4px; }
.private-note { margin: 16px 0 0; }
footer { align-items: flex-start; padding-top: 0; }
footer strong { letter-spacing: 2px; font-size: 12px; }
@media (max-width: 600px) {
  header, footer { padding: 22px 20px; }
  .header-note { display: none; }
  main { margin: 8px auto 24px; padding: 0 14px; }
  .sandbox-note { padding: 14px 18px; }
  .receipt { padding: 26px 20px; border-radius: 22px; }
  .detail-row { grid-template-columns: 1fr; gap: 0; margin: 14px 0; }
  dt { font-size: 13px; }
  .refresh { width: 100%; }
  footer { flex-direction: column; gap: 4px; }
}
@media (prefers-reduced-motion: reduce) { *, *::before, *::after { scroll-behavior: auto; } }
`;

const BOOKING_STATES = new Set(["awaiting_payment", "confirmed", "canceled", "expired", "payment_failed", "completed", "no_show"]);
const PAYMENT_STATES = new Set(["unpaid", "pending", "paid", "paid_unfulfilled", "refunded", "disputed"]);
const REFUND_STATES = new Set(["none", "requested", "required", "sending", "pending", "succeeded", "failed", "uncertain"]);
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (character) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
})[character]);

function requireText(value, maximum) {
  if (typeof value !== "string" || !value.trim() || value.length > maximum)
    throw new TypeError("Invalid sandbox display text.");
  return value;
}

function requirePrivatePath(value) {
  if (typeof value !== "string" || value.length > 2048 || !/^\/[A-Za-z0-9/_.-]*$/.test(value) ||
    value.includes("//") || value.split("/").some((segment) => segment === "." || segment === ".."))
    throw new TypeError("A canonical same-origin private refresh path is required.");
  return value;
}

function bookingMessage(bookingState, paymentState) {
  if (paymentState === "disputed") return {
    title: "Test payment disputed.",
    detail: "A dispute is recorded for this test payment. Check the payment status for updates.",
    icon: "−", appearance: "pending",
  };
  if (bookingState === "canceled") return {
    title: "Appointment canceled.",
    detail: "This test appointment is canceled. Check the payment status below for any refund update.",
    icon: "−", appearance: "canceled",
  };
  if (bookingState === "expired") return {
    title: "Booking expired.",
    detail: "This test appointment is no longer reserved. Check the payment status below for any payment or refund update.",
    icon: "−", appearance: "expired",
  };
  if (paymentState === "refunded") return {
    title: "Test payment refunded.",
    detail: "The test payment has been refunded. Refresh to check the appointment status.",
    icon: "−", appearance: "pending",
  };
  if (paymentState === "paid_unfulfilled") return {
    title: "Appointment not confirmed.",
    detail: "The test payment was received, but the appointment could not be confirmed. Check the refund status below for updates.",
    icon: "−", appearance: "pending",
  };
  if (bookingState === "payment_failed") return {
    title: "Appointment not confirmed.",
    detail: "This test appointment could not be confirmed. Check the payment status below for updates.",
    icon: "−", appearance: "pending",
  };
  if (bookingState === "completed") return {
    title: "Test appointment completed.",
    detail: "This sandbox appointment is marked completed. Payment status is shown below.",
    icon: "−", appearance: "pending",
  };
  if (bookingState === "no_show") return {
    title: "Test appointment marked missed.",
    detail: "This sandbox appointment is marked as missed. Payment status is shown below.",
    icon: "−", appearance: "pending",
  };
  if (bookingState === "confirmed" && paymentState === "paid") return {
    title: "Your test appointment is confirmed.",
    detail: "The test payment is complete and your sandbox appointment is confirmed.",
    icon: "✓", appearance: "confirmed",
  };
  if (paymentState === "paid") return {
    title: "Confirming your appointment.",
    detail: "The test payment is complete. Your appointment is still awaiting confirmation. Refresh to check for an update.",
    icon: "…", appearance: "pending",
  };
  if (paymentState === "pending" || bookingState === "confirmed") return {
    title: "Payment confirmation pending.",
    detail: "Your test payment has not been confirmed. Refresh to check for an update.",
    icon: "…", appearance: "pending",
  };
  return {
    title: "Awaiting test payment.",
    detail: "Your test appointment is not confirmed. Refresh after completing test checkout to check the result.",
    icon: "…", appearance: "pending",
  };
}

/**
 * Render a current, authenticated sandbox display DTO supplied by the server.
 *
 * booking: {state, starts_at, guest_timezone?, snapshot:{title,host_name,duration_minutes}}
 * payment: {state, amount_cents:100, currency:'usd', livemode:false, refund_state?}
 * refreshPath: canonical same-origin private path, without query or fragment.
 *
 * No Stripe IDs, booking IDs, emails, raw objects, URLs from payment data, or
 * arbitrary messages are serialized. The only link is the validated refresh
 * path; the server must redact private paths from logs and send the exported
 * security headers. Serve exported CSS at HOSTED_ACCEPTANCE_RETURN_CSS_PATH.
 */
export function renderHostedAcceptancePage({ booking, payment, refreshPath } = {}) {
  if (!BOOKING_STATES.has(booking?.state) || !PAYMENT_STATES.has(payment?.state))
    throw new TypeError("Invalid sandbox display status.");
  if (payment.livemode !== false || payment.amount_cents !== 100 || payment.currency !== "usd")
    throw new TypeError("Only a USD 1 test payment can be displayed.");
  const refundState = payment.refund_state ?? "none";
  if (!REFUND_STATES.has(refundState) ||
    (payment.state === "refunded" && refundState !== "succeeded") ||
    (refundState === "succeeded" && payment.state !== "refunded"))
    throw new TypeError("Invalid sandbox refund status.");
  const title = requireText(booking.snapshot?.title, 200);
  const host = requireText(booking.snapshot?.host_name, 100);
  const zone = requireText(booking.guest_timezone ?? "UTC", 80);
  const start = requireText(booking.starts_at, 30);
  if (!Number.isFinite(Date.parse(start)) || new Date(start).toISOString() !== start)
    throw new TypeError("Invalid sandbox appointment time.");
  const duration = booking.snapshot?.duration_minutes;
  if (!Number.isSafeInteger(duration) || duration < 1 || duration > 1440)
    throw new TypeError("Invalid sandbox appointment duration.");
  const path = requirePrivatePath(refreshPath);
  let date, time;
  try {
    date = new Intl.DateTimeFormat("en-US", { timeZone: zone, weekday: "long", month: "long", day: "numeric", year: "numeric" }).format(new Date(start));
    time = new Intl.DateTimeFormat("en-US", { timeZone: zone, hour: "numeric", minute: "2-digit", timeZoneName: "short" }).format(new Date(start));
  } catch { throw new TypeError("Invalid sandbox appointment time zone."); }
  const message = bookingMessage(booking.state, payment.state);
  const paymentLabel = { unpaid: "Unpaid", pending: "Payment pending", paid: "Paid", paid_unfulfilled: "Paid · Appointment not confirmed", refunded: "Refunded", disputed: "Payment disputed" }[payment.state];
  const refundLine = {
    none: "", requested: "A full test refund has been requested.", required: "A full test refund is required and has not completed.",
    sending: "The full test refund is being submitted.", pending: "The full test refund is pending.",
    succeeded: "Full test refund completed.", failed: "The test refund could not be completed. Check again for an update.",
    uncertain: "The test refund outcome is not yet confirmed. Check again for an update.",
  }[refundState];
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="robots" content="noindex, nofollow, noarchive" />
  <meta name="referrer" content="no-referrer" />
  <meta name="theme-color" content="#142239" />
  <title>Appointment status · KORLIX 2MEETU</title>
  <link rel="stylesheet" href="${HOSTED_ACCEPTANCE_RETURN_CSS_PATH}" />
</head>
<body>
  <header>
    <div class="brand" aria-label="KORLIX 2MEETU">KORLIX<span>2MEETU</span></div>
    <span class="header-note">Make time for what matters.</span>
  </header>
  <main>
    <aside class="sandbox-note" aria-label="Test mode">
      <strong>TEST MODE</strong>
      <p>This is a $1.00 USD sandbox test. No real payment is taken.</p>
    </aside>
    <section class="receipt status-${message.appearance}" aria-labelledby="booking-title">
      <div class="status-icon" aria-hidden="true">${message.icon}</div>
      <p class="eyebrow">Appointment status</p>
      <h1 id="booking-title">${message.title}</h1>
      <p class="explanation">${message.detail}</p>
      <section class="meeting" aria-labelledby="meeting-title">
        <h2 id="meeting-title">${escapeHtml(title)}</h2>
        <dl>
          <div class="detail-row"><dt>Date</dt><dd><time datetime="${escapeHtml(start)}">${escapeHtml(date)}</time></dd></div>
          <div class="detail-row"><dt>Time</dt><dd>${escapeHtml(time)}</dd></div>
          <div class="detail-row"><dt>Duration</dt><dd>${duration} minutes</dd></div>
          <div class="detail-row"><dt>Host</dt><dd>${escapeHtml(host)}</dd></div>
        </dl>
      </section>
      <section class="payment" aria-label="Test payment status">
        <div class="payment-line"><strong>${paymentLabel}</strong><span>$1.00 USD · Test payment</span></div>
        ${refundLine ? `<p>${refundLine}</p>` : ""}
      </section>
      <p class="service-note">No booking email was scheduled. Calendar integration and appointment changes are unavailable in this sandbox.</p>
      <a class="refresh" href="${escapeHtml(path)}" rel="noreferrer">Refresh status</a>
      <p class="private-note">Keep this private booking link. Anyone with the link can view this test appointment.</p>
    </section>
  </main>
  <footer><strong>KORLIX</strong><span>More than a meeting. A connection.</span></footer>
</body>
</html>`;
}

/** Public shell; all booking data is fetched after fragment authentication. */
export function renderHostedAcceptanceShell() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="robots" content="noindex, nofollow, noarchive" />
  <meta name="referrer" content="no-referrer" />
  <meta name="theme-color" content="#142239" />
  <title>Appointment status · KORLIX 2MEETU</title>
  <link rel="stylesheet" href="${HOSTED_ACCEPTANCE_RETURN_CSS_PATH}" />
  <script src="${HOSTED_ACCEPTANCE_RETURN_JS_PATH}" defer></script>
</head>
<body>
  <header>
    <div class="brand" aria-label="KORLIX 2MEETU">KORLIX<span>2MEETU</span></div>
    <span class="header-note">Make time for what matters.</span>
  </header>
  <main aria-busy="true">
    <aside class="sandbox-note" aria-label="Test mode"><strong>TEST MODE</strong><p>This is a $1.00 USD sandbox test. No real payment is taken.</p></aside>
    <section class="receipt" aria-labelledby="return-heading">
      <div class="status-icon" aria-hidden="true">…</div>
      <p class="eyebrow">Appointment status</p>
      <div id="return-feedback" role="status" aria-live="polite">
        <h1 id="return-heading">Checking your appointment…</h1>
        <p id="return-message" class="explanation">Please wait while we load your current test appointment status.</p>
      </div>
      <noscript><p>Enable JavaScript to view your private test appointment status.</p></noscript>
      <a class="refresh" href="/book/manage" rel="noreferrer">Refresh status</a>
      <p class="private-note">Keep this private booking link. Anyone with the link can view this test appointment.</p>
    </section>
  </main>
  <footer><strong>KORLIX</strong><span>More than a meeting. A connection.</span></footer>
</body>
</html>`;
}
