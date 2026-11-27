import {
  api,
  currentSession,
  openLogin,
  redeem,
  phoneNumber,
  displayNumber,
  checkFileUrl,
  dispatch,
} from "./fax-api.js";
import {
  readPdf,
  pageImage,
  scanPages,
  clearDoc,
  receiptPdf,
} from "./fax-document.js";
import { activityCsv, activityPage, currentMonth, validMonth } from "./fax-activity.js";
const $ = (id) => document.getElementById(id);
const screen = $("screen"),
  sheet = $("sheet"),
  sheetBody = $("sheet-content");
const esc = (v) =>
  String(v ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const icon = (n) => `<i aria-hidden="true" class="ic i-${n}"></i>`;
const btn = (action, txt, cls = "primary", glyph = "", extra = "") =>
  `<button type="button" data-act="${action}" class="${cls}" ${extra}>${glyph ? icon(glyph) : ""}${esc(txt)}</button>`;
const details = (items) =>
  `<dl class="details">${items
    .filter(([, v]) => v !== null && v !== undefined && v !== "")
    .map(
      ([k, v, sub]) =>
        `<div><dt>${esc(k)}</dt><dd>${esc(v)}${sub ? `<small>${esc(sub)}</small>` : ""}</dd></div>`,
    )
    .join("")}</dl>`;
const pageCount = (n) =>
  Number.isInteger(n)
    ? n + (n === 1 ? " page" : " pages")
    : "Page count pending";
const statuses = {
  preparing: "Preparing",
  submitting: "Submitting",
  checking: "Awaiting confirmation",
  queued: "Queued",
  sending: "Sending",
  delivered: "Delivered",
  received: "Received",
  failed: "Failed",
};
const terminal = new Set(["delivered", "received", "failed"]);
const folderState = () => ({
  items: [],
  more: false,
  loaded: false,
  sequence: 0,
});
const folders = { inbound: folderState(), outbound: folderState() };
let report = null, receiptReport = "";
let contacts = [],
  ws = null,
  activeRecord = null,
  folder = "inbound",
  selectedPlan = "solo",
  route = "inbox",
  generation = 0,
  busy = false,
  reading = false,
  background = false,
  fileJob = 0;
let draft = { doc: null, number: "", saveName: "" },
  viewer = null,
  speech = null,
  toastTimer,
  alertText = "";
function clearDraft() {
  fileJob++;
  reading = false;
  clearDoc(draft.doc);
  draft = { doc: null, number: "", saveName: "" };
}
function closeSheet() {
  if (sheet.open) sheet.close();
}
sheet.addEventListener("close", () => {
  if (speech) {
    speech.abort();
    speech = null;
  }
  if (viewer?.owned) clearDoc(viewer.doc);
  viewer = null;
});
function modal(title, body) {
  $("sheet-title").textContent = title;
  sheetBody.innerHTML = body;
  if (!sheet.open) sheet.showModal();
  $("sheet-close").focus({ preventScroll: true });
}
function toast(text) {
  clearTimeout(toastTimer);
  $("toast").textContent = text;
  $("toast").classList.add("show");
  toastTimer = setTimeout(() => $("toast").classList.remove("show"), 3100);
}
function failUI(message) {
  const e = sheet.open ? sheetBody.querySelector("[role=alert]") : null;
  if (e) {
    e.textContent = message;
    return;
  }
  if (sheet.open) {
    const p = document.createElement("p");
    p.className = "err";
    p.setAttribute("role", "alert");
    p.textContent = message;
    sheetBody.append(p);
    return;
  }
  alertText = message;
  const note = $("view-error");
  if (note) {
    note.hidden = false;
    note.textContent = message;
  } else toast(message);
}
function go(path) {
  closeSheet();
  alertText = "";
  if (location.hash.slice(1) === path) {
    navigate();
  } else location.hash = path;
}
function note() {
  return `<p id="view-error" class="err" role="alert" ${alertText ? "" : "hidden"}>${esc(alertText)}</p>`;
}
const arrNumbers = () => new Map(contacts.map((c) => [c.phone, c.name]));
function party(rec) {
  return rec.direction === "inbound" ? rec.sender : rec.recipient;
}
function contactName(phone) {
  return contacts.find((c) => c.phone === phone)?.name || "";
}
function when(iso, options) {
  const d = new Date(iso);
  return Number.isFinite(+d) ? d.toLocaleString(undefined, options) : "";
}
function day(iso) {
  const d = new Date(iso),
    now = new Date(),
    prev = new Date(now);
  prev.setDate(now.getDate() - 1);
  if (d.toDateString() === now.toDateString()) return "Today";
  if (d.toDateString() === prev.toDateString()) return "Yesterday";
  return when(iso, { month: "short", day: "numeric", year: "numeric" });
}
const stamp = (s) => when(s, { dateStyle: "medium", timeStyle: "short" });
function numberCard() {
  const l = ws.line,
    active = l?.state === "active" && l.phone;
  if (!l && ws.customerEnrollmentOpen !== true)
    return '<div class="line-card"><h1 class="line-number no-line">Company workspace</h1><p>No company number is assigned to this account.</p></div>';

  return `<div class="line-card"><div class="stripes" aria-hidden="true"><i></i><i></i><i></i><i></i></div><div class="line-top"><span class="eyebrow">Your fax number</span>${active ? '<span class="line-live"><i class="dot"></i>Active</span>' : ""}</div><h1 class="line-number ${active ? "" : "no-line"}">${active ? esc(displayNumber(l.phone)) : l ? "Activation pending" : "Get a fax number"}</h1><div class="line-tools">${active ? btn("copy", "Copy", "glass-btn", "content-copy") + btn("share", "Share", "glass-btn", "share-variant-outline") : btn("setup", l ? "View request" : "Get my fax number", "glass-btn", "phone-outline")}</div></div>`;
}
function usage() {
  const u = ws.usage;
  if (!u) return "";
  const cap = ws.billing?.active && ws.plans?.[ws.billing.plan]?.pages;
  return `<section class="usage"><div class="row-between"><h2>Monthly pages</h2><span><b>${esc(u.pages)}</b>${cap ? " / " + cap : " used"}</span></div>${cap ? `<progress class="page-meter" aria-label="Monthly pages used" value="${u.pages}" max="${Math.max(cap, u.pages)}"></progress>` : `<p class="usage-detail">${esc(u.inboundPages)} received · ${esc(u.outboundPages)} sent</p>`}${u.pendingReports ? '<p class="usage-detail">Additional page counts are awaiting carrier confirmation.</p>' : ""}${btn("activity", "View monthly activity", "soft-link activity-link", "chevron-right")}</section>`;
}
function activityRow(r) {
  const inbound = r.direction === "inbound";
  const date = when(r.updated_at, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZone: "UTC" });
  const number = displayNumber(party(r));
  return `<button data-act="record" data-id="${esc(r.id)}" class="fax-row">
    <span class="filemark ${inbound ? "" : "out"}">${icon(inbound ? "tray-arrow-down" : "tray-arrow-up")}</span>
    <span class="rtext"><b>${esc(r.name)}</b><small>${inbound ? "Received from" : "Delivered to"} ${esc(number)}</small><small>${esc(date)} UTC</small></span>
    <span class="row-time">${Number.isInteger(r.pages) ? esc(pageCount(r.pages)) : "Count pending"}${icon("chevron-right")}</span>
  </button>`;
}

function activityView() {
  const { month, summary, items, next, loading, exporting, error } = report;
  const picker = `<label class="field-label" for="activity-month">Report month</label>
    <input type="month" class="control" id="activity-month" value="${esc(month)}" max="${currentMonth()}" placeholder="YYYY-MM" required>`;
  let body = "";
  if (summary) {
    const counts = [["Total pages", summary.pages], ["Sent", summary.outboundPages], ["Received", summary.inboundPages]];
    body = `<dl class="activity-totals">${counts.map(([label, value]) => `<div><dt>${esc(label)}</dt><dd>${esc(value)}</dd></div>`).join("")}</dl>`;
    if (summary.pendingReports) body += `<p class="usage-detail">${esc(summary.pendingReports)} ${summary.pendingReports === 1 ? "fax is" : "faxes are"} awaiting a carrier page count.</p>`;
    if (items.length) {
      body += `<div class="activity-list-head"><h2 class="small-title">Completed faxes</h2>
        ${btn("activity-csv", exporting ? "Preparing CSV…" : "Download CSV", "soft-link", "download-outline", exporting ? "disabled" : "")}</div>
        <div class="list-box">${items.map(activityRow).join("")}</div>`;
      if (next) body += btn("activity-more", loading ? "Loading…" : "Load older faxes", "soft-link full", "", loading ? "disabled" : "");
    } else body += '<div class="empty-folder"><h3>No completed faxes this month</h3></div>';
  } else if (loading) body = '<p class="lead block" role="status">Loading activity…</p>';
  if (error) body += `<p class="err" role="alert">${esc(error)}</p>${btn("activity-retry", "Try again", "soft-link")}`;
  return `<div class="flow"><div class="flow-nav">${btn("leave-activity", "Back", "back", "chevron-left")}
    ${summary ? btn("activity-refresh", "Refresh", "soft-link", "restart", loading ? "disabled" : "") : ""}</div>
    <h1 class="title">Monthly fax activity</h1><p class="lead">Pages are grouped by completion date in UTC.</p>
    <div class="block">${picker}</div>${body}</div>`;
}

async function loadActivity(more = false) {
  const state = report;
  if (state.loading || (more && !state.next)) return;
  state.loading = true;
  state.error = "";
  render();
  try {
    const page = await activityPage(state.month, more ? state.next : null);
    state.items = more ? [...state.items, ...page.items] : page.items;
    if (!more) state.summary = page.summary;
    state.next = page.next;
  } catch (err) {
    state.error = err.message;
    state.retryMore = more;
  } finally {
    state.loading = false;
    if (report === state && route === "activity/" + state.month) render();
  }
}

function faxRow(r) {
  const whom = party(r),
    name = contactName(whom) || displayNumber(whom);
  const sub =
    r.direction === "inbound"
      ? r.status === "failed"
        ? "Failed"
        : r.name
      : statuses[r.status] || "Pending";
  return `<button class="fax-row" data-act="record" data-id="${esc(r.id)}"><span class="filemark ${r.direction === "outbound" ? "out" : ""}">${icon("file-document-outline")}</span><span class="rtext"><b>${esc(name || "Unknown sender")}</b><small>${esc(sub)}${Number.isInteger(r.pages) ? " · " + pageCount(r.pages) : ""}</small></span><span class="row-time">${esc(when(r.created_at, { hour: "numeric", minute: "2-digit" }))}${icon("chevron-right")}</span></button>`;
}
function home() {
  const f = folders[folder],
    groups = new Map();
  for (const r of f.items) {
    const group = day(r.created_at);
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group).push(r);
  }
  return `<div class="home-grid"><div class="overview">${numberCard()}<div class="action-row">${btn("compose", "Send a Fax", "primary", "send-outline")}${btn("rici", "Rici", "secondary", "waveform", 'aria-label="Ask Rici"')}</div></div><section class="mail"><h2 class="section-title">Mailbox</h2><div class="segment" role="group" aria-label="Mailbox folder">${["inbound", "outbound"].map((v, i) => `<button data-act="folder" data-id="${v}" class="${folder === v ? "selected" : ""}" aria-pressed="${folder === v}">${icon(i ? "tray-arrow-up" : "tray-arrow-down")}${i ? "Sent" : "Inbox"}${v === folder && f.items.length ? `<span class="seg-total">${f.items.length}${f.more ? "+" : ""}</span>` : ""}</button>`).join("")}</div>${!f.loaded ? '<p class="lead">Loading faxes…</p>' : !f.items.length ? `<div class="empty-folder">${icon("tray-arrow-" + (folder === "inbound" ? "down" : "up"))}<h3>${folder === "inbound" ? "Your inbox is ready" : "No sent faxes yet"}</h3><p>${folder === "outbound" ? "Delivery updates appear here after you send a fax." : ws.line?.state === "active" ? "Share your number to receive your first fax." : "Incoming faxes appear here once your line is active."}</p></div>` : ""}${[...groups].map(([name, items]) => `<h3 class="group-title">${esc(name)}</h3><div class="list-box">${items.map(faxRow).join("")}</div>`).join("")}${f.more ? btn("older", "Load older faxes", "soft-link") : ""}</section>${usage()}</div>`;
}
function step(n, title, back, sub = "") {
  return `<div class="flow-nav">${btn(back, "Back", "back", "chevron-left")}<span class="step-text">Step ${n} of 3</span></div><div class="stepper" aria-hidden="true">${[1, 2, 3].map((i) => `<span class="${i <= n ? "on" : ""}"></span>`).join("")}</div><h1 class="title">${esc(title)}</h1>${sub ? `<p class="lead">${esc(sub)}</p>` : ""}`;
}
function choice(action, glyph, title, sub) {
  return `<button class="source-choice" data-act="${action}">${icon(glyph)}<span><b>${esc(title)}</b><small>${esc(sub)}</small></span>${icon("chevron-right")}</button>`;
}
function filePanel(doc) {
  return `<div class="paper-card"><button class="paper-stage" data-act="view-draft" aria-label="Preview document"><img src="${esc(doc.images.get(0))}" alt=""><span class="pagebadge">1 of ${doc.pages}</span></button><div class="doc-title">${icon("file-document-outline")}<span><b>${esc(doc.name)}</b><small>${pageCount(doc.pages)} · PDF</small></span>${btn("view-draft", "", "edit", "arrow-expand-all", 'aria-label="Expand document"')}</div></div>`;
}
function add() {
  const recent = folders.outbound.items.find((r) => r.hasFile);
  return `<div class="flow">${step(1, "Add a document", "home", "Scan paper or choose a PDF up to 8 MB.")}<div class="block source-list">${choice("camera", "camera-outline", draft.doc?.scanPages ? "Scan another page" : "Scan pages", "Use your camera")}${choice("upload", "folder-open-outline", "Choose a PDF", "Browse files")}</div><input id="camera-file" type="file" accept="image/*" capture="environment" multiple hidden><input id="upload-file" type="file" accept="application/pdf,.pdf" hidden><p id="file-status" class="lead" role="status">${reading ? "Preparing document…" : ""}</p>${draft.doc ? `<section class="block"><div class="row-between"><h2 class="small-title">Your document</h2>${btn("remove", "Remove", "edit")}</div>${filePanel(draft.doc)}</section><div class="btn-stack">${btn("after-doc", draft.number ? "Review fax" : "Choose recipient", "primary full", "", reading ? "disabled" : "")}</div>` : recent ? `<section class="block"><h2 class="small-title">Recent document</h2><div class="list-box"><button class="fax-row" data-act="recent" data-id="${esc(recent.id)}"><span class="filemark">${icon("file-document-outline")}</span><span class="rtext"><b>${esc(recent.name)}</b><small>${pageCount(recent.pages)} · PDF</small></span>${icon("chevron-right")}</button></div></section>` : ""}</div>`;
}
function recipientOptions() {
  const options = arrNumbers();
  for (const r of [...folders.outbound.items, ...folders.inbound.items]) {
    const p = phoneNumber(party(r));
    if (p && !options.has(p)) options.set(p, "");
  }
  return [...options];
}
function contactRows(filter = "") {
  const list = recipientOptions().filter(
    ([n, name]) =>
      !filter ||
      n.includes(filter) ||
      name.toLowerCase().includes(filter.toLowerCase()),
  );
  return list
    .slice(0, 30)
    .map(
      ([n, name]) =>
        `<button class="contact" data-act="contact" data-num="${esc(n)}" aria-pressed="${phoneNumber(draft.number) === n}"><span class="contact-avatar">${
          name
            ? esc(
                name
                  .split(/\s+/)
                  .slice(0, 2)
                  .map((w) => w[0])
                  .join("")
                  .toUpperCase(),
              )
            : icon("phone-outline")
        }</span><span><b>${esc(name || displayNumber(n))}</b><small>${esc(name ? displayNumber(n) : "Recent fax number")}</small></span>${icon(phoneNumber(draft.number) === n ? "check-circle-outline" : "chevron-right")}</button>`,
    )
    .join("");
}
function recipient() {
  return `<div class="flow">${step(2, "Choose a recipient", "add")}<label class="field-label" for="fax-to">Recipient’s fax number</label><input class="control" id="fax-to" type="tel" inputmode="tel" autocomplete="off" value="${esc(draft.number)}" placeholder="10-digit U.S. fax number"><label class="field-label" for="contact-name">Save as a contact <span class="optional">(optional)</span></label><input class="control" id="contact-name" maxlength="80" value="${esc(draft.saveName)}" placeholder="Person or business"><section class="block">${recipientOptions().length ? `<h2 class="small-title">Recent contacts</h2><div class="list-box" id="contacts-list">${contactRows()}</div>` : ""}</section><div class="btn-stack">${btn("review", "Review fax", "primary full", "", phoneNumber(draft.number) ? "" : "disabled")}</div></div>`;
}
function review() {
  const to = phoneNumber(draft.number),
    who = draft.saveName || contactName(to);
  return `<div class="flow">${step(3, "Review your fax", "recipient", "Confirm the document and recipient.")}<div class="block">${filePanel(draft.doc)}</div><div class="review-info"><div class="row-between"><h2 class="small-title">Fax details</h2>${btn("recipient", "Edit recipient", "edit")}</div>${details(
    [
      ["To", who || displayNumber(to), who ? displayNumber(to) : ""],
      ["From", displayNumber(ws.line.phone)],
      ["Pages", String(draft.doc.pages)],
    ],
  )}</div><div class="btn-stack review-actions">${btn("send", busy ? "Submitting…" : "Send " + pageCount(draft.doc.pages), "primary full", "send-outline", busy ? "disabled" : "")}</div></div>`;
}
function receipt(r) {
  const inbound = r.direction === "inbound",
    failed = r.status === "failed",
    done = terminal.has(r.status),
    other = party(r),
    who = contactName(other),
    label = statuses[r.status] || "Pending";
  const title = failed
    ? "Delivery failed"
    : r.status === "delivered"
      ? "Fax delivered"
      : r.status === "received"
        ? "Fax received"
        : label;
  const meta = [
    [
      inbound ? "From" : "Recipient",
      who || displayNumber(other),
      who ? displayNumber(other) : "",
    ],
    [inbound ? "To" : "From", displayNumber(inbound ? r.recipient : r.sender)],
    ["Document", r.name],
    [
      r.status === "delivered"
        ? "Pages delivered"
        : r.status === "received"
          ? "Pages received"
          : "Pages reported",
      Number.isInteger(r.pages) ? String(r.pages) : "Awaiting page count",
    ],
    ["Fax reference", r.id],
    ["Details", r.detail],
  ];
  return `<div class="flow receipt"><div class="flow-nav">${btn(receiptReport ? "receipt-report" : inbound ? "home" : "sent", "Back", "back", "chevron-left")}</div><div class="receipt-hero"><div class="seal ${failed ? "failed" : ""}">${icon(failed ? "information-outline" : r.status === "received" ? "tray-arrow-down" : done ? "check" : "progress-clock")}</div><h1 class="title">${esc(title)}</h1><p class="lead">${esc(stamp(r.updated_at || r.created_at))}</p></div><div class="receipt-card"><div class="receipt-head">${icon("file-check-outline")}${inbound ? "Received fax" : done ? "Delivery receipt" : "Delivery status"}</div>${details(meta)}</div><div class="btn-stack">${inbound && r.hasFile ? btn("view-record", "Open document", "primary full", "file-document-outline") : failed && r.hasFile && !inbound ? btn("retry", "Try again", "primary full", "restart") : btn("sent", inbound ? "View inbox" : "View sent faxes", "primary full", inbound ? "tray-arrow-down" : "tray-arrow-up", inbound ? 'data-folder="inbound"' : "")}${r.hasFile ? (inbound ? btn("save-record", "Save PDF", "soft-link", "download-outline") : btn("view-record", "View document", "soft-link", "file-document-outline")) : ""}${done ? btn("save-receipt", "Save receipt PDF", "soft-link", "file-check-outline") : btn("refresh", "Refresh status", "soft-link", "restart")}</div></div>`;
}
function setup() {
  const line = ws.line,
    active = line?.state === "active";
  if (!line && ws.customerEnrollmentOpen !== true)
    return `<div class="flow"><div class="flow-nav">${btn("home", "Back", "back", "chevron-left")}</div><h1 class="title">Company workspace</h1><p class="lead">No company number is assigned to this account.</p></div>`;
  if (line)
    return `<div class="flow"><div class="flow-nav">${btn("home", "Back", "back", "chevron-left")}</div><section class="block"><h1 class="title">${active ? "Your fax number" : "Activation pending"}</h1><p class="lead">${active ? "Use this number to send and receive faxes." : "Korlix has your request. Your number will appear here when activation is complete."}</p></section><div class="block">${details(
      [
        [
          "Status",
          active
            ? "Active"
            : line.state === "ordering"
              ? "Carrier processing"
              : "Requested",
        ],
        ["Number", active ? displayNumber(line.phone) : null],
        [
          "Preference",
          line.preference === "toll_free"
            ? "U.S. toll-free"
            : "Area code " + line.preference,
        ],
        ["Requested plan", ws.plans?.[line.requested_plan]?.name],
      ],
    )}</div><div class="btn-stack">${btn("refresh", "Refresh", "outline-btn", "restart")}${ws.sample ? (active
      ? btn("sample-request", "Try requesting a number", "soft-link")
      : btn("sample-activate", "Activate sample line", "primary full")) : ""}</div></div>`;
  return `<div class="flow"><div class="flow-nav">${btn("home", "Back", "back", "chevron-left")}</div><div class="block"><h1 class="title">Get my fax number</h1><p class="lead">Choose a plan to request your own U.S. fax number.</p></div><div class="block plan-list">${Object.entries(ws.plans || {})
    .map(
      ([id, p]) =>
        `<button class="plan ${id === selectedPlan ? "selected" : ""}" data-act="plan" data-id="${id}" aria-pressed="${id === selectedPlan}"><span><b>${p.name}</b><small>${p.pages} pages per month</small></span><span class="price">$${p.price}<small> / mo</small></span></button>`,
    )
    .join(
      "",
    )}</div><label class="field-label" for="prefix">Number preference</label><select class="control" id="prefix"><option value="toll_free">U.S. toll-free</option><option value="local">Local U.S. area code</option></select><input id="area" class="control area" inputmode="numeric" maxlength="3" aria-label="Three-digit area code" placeholder="Three-digit area code" hidden><div class="btn-stack">${btn("request", "Request my fax number", "primary full", "phone-outline")}</div><p class="small-note block">${ws.sample ? "This example stays on your device. No number is ordered or billed." : "Submitting a request is free. Pricing applies when you activate a paid plan."}</p></div>`;
}
function render() {
  if (!ws) return;
  let html;
  if (route === "add") html = add();
  else if (route === "recipient") html = recipient();
  else if (route === "review") html = review();
  else if (route === "setup") html = setup();
  else if (route.startsWith("activity/")) html = activityView();
  else if (route.startsWith("record/"))
    html =
      activeRecord?.id === route.slice(7)
        ? receipt(activeRecord)
        : '<p class="lead" role="status">Opening fax…</p>';
  else html = home();
  screen.innerHTML = note() + html;
}
async function getFolder(dir, more = false) {
  const f = folders[dir],
    offset = more ? f.items.length : 0,
    tag = ++f.sequence;
  const data = await api("/history?direction=" + dir + "&offset=" + offset);
  if (f.sequence !== tag) return;
  if (!more && f.loaded && f.items.length > 25) {
    const freshIds = new Set(data.items.map((r) => r.id));
    const last = data.items.at(-1);
    f.items = [
      ...data.items,
      ...(last
        ? f.items.filter(
            (r) =>
              !freshIds.has(r.id) &&
              (r.created_at < last.created_at ||
                (r.created_at === last.created_at && r.id < last.id)),
          )
        : []),
    ];
  } else
    f.items = more
      ? [...new Map([...f.items, ...data.items].map((r) => [r.id, r])).values()]
      : data.items;
  if (more || f.items.length <= 25) f.more = data.more;
  f.loaded = true;
}
function locate(id) {
  return [...folders.inbound.items, ...folders.outbound.items].find(
    (x) => x.id === id,
  );
}
async function navigate() {
  if (!ws) return;
  const tick = ++generation;
  let target = location.hash.slice(1) || "inbox";
  if (target === "activity") {
    target = "activity/" + currentMonth();
    history.replaceState(null, "", "#" + target);
  }
  const activityRoute = target.startsWith("activity/") && validMonth(target.slice(9));
  if (
    !activityRoute &&
    !/^record\/[a-f0-9-]{36}$/i.test(target) &&
    !["inbox", "sent", "setup", "add", "recipient", "review"].includes(target)
  )
    target = "inbox";
  if (
    ["add", "recipient", "review"].includes(target) &&
    ws.line?.state !== "active"
  )
    target = "setup";
  if (["recipient", "review"].includes(target) && !draft.doc) target = "add";
  if (target === "review" && !phoneNumber(draft.number)) target = "recipient";
  if (target === "inbox" || target === "sent")
    folder = target === "sent" ? "outbound" : "inbound";
  if (target.startsWith("record/") && target !== route)
    receiptReport = route.startsWith("activity/") ? route : "";
  if (activityRoute && (report?.month !== target.slice(9) || !route.startsWith("record/"))) {
    report = { month: target.slice(9), summary: null, items: [], next: null, loading: false, exporting: false, error: "" };
  }
  route = target;
  alertText = "";
  if (route.startsWith("record/"))
    activeRecord = locate(route.slice(7)) || null;
  render();
  window.scrollTo(0, 0);
  screen.focus({ preventScroll: true });
  if (activityRoute) {
    if (!report.summary) await loadActivity();
    return;
  }
  if (route.startsWith("record/")) {
    try {
      const r = await api("/document/" + target.slice(7));
      if (tick === generation) {
        activeRecord = r;
        render();
      }
    } catch (e) {
      if (tick === generation) failUI(e.message);
    }
  }
}
async function refresh(force = false) {
  if (!ws || background) return;
  const current = route;
  if (
    !force &&
    (document.hidden ||
      sheet.open ||
      (!["sent", "inbox", "setup"].includes(route) &&
        !route.startsWith("record/")))
  )
    return;
  background = true;
  try {
    const prev = folders.inbound.items[0]?.id,
      wasLoaded = folders.inbound.loaded;
    const jobs = [
      api("/workspace").then((r) => {
        ws = r;
      }),
    ];
    if (current.startsWith("record/"))
      jobs.push(
        api("/document/" + current.slice(7)).then((r) => {
          if (route === current) activeRecord = r;
        }),
      );
    else if (current === "sent" || current === "inbox")
      jobs.push(getFolder(folder));
    await Promise.all(jobs);
    if (
      route === current &&
      !sheet.open &&
      !(current === "setup" && !ws.line && ws.customerEnrollmentOpen === true)
    ) {
      alertText = "";
      render();
    }
    if (
      prev &&
      wasLoaded &&
      folder === "inbound" &&
      route === "inbox" &&
      prev !== folders.inbound.items[0]?.id
    )
      toast("New fax received");
  } catch (e) {
    if (force || route === current) failUI(e.message);
  } finally {
    background = false;
  }
}
async function start() {
  let code = new URLSearchParams(location.hash.slice(1)).get("handoff");
  if (code) {
    history.replaceState(null, "", location.pathname + location.search);
    sessionStorage.removeItem("korlixFaxSession");
    try {
      await redeem(code);
    } catch (e) {
      openLogin(e.message);
      return;
    }
    code = null;
  }
  if (!currentSession()) {
    openLogin();
    return;
  }
  try {
    ws = await api("/workspace");
    $("app-header").hidden = false;
    if (ws.sample) {
      const banner = document.createElement("p");
      banner.className = "sample-notice";
      banner.textContent = "Sample workspace · Faxes stay on this device";
      $("app-header").after(banner);
    }
    await navigate();
    const results = await Promise.allSettled([
      getFolder("inbound"),
      getFolder("outbound"),
      api("/contacts").then((data) => {
        contacts = data.items;
      }),
    ]);
    if (
      route === "inbox" ||
      route === "sent" ||
      route === "add" ||
      route === "recipient"
    )
      render();
    const err = results.find((x) => x.status === "rejected");
    if (err) failUI(err.reason.message);
  } catch (e) {
    if (e.status === 401) return;
    screen.innerHTML = `<div class="flow"><h1 class="title">Workspace unavailable</h1><p class="lead">${esc(e.message)}</p><div class="btn-stack">${btn("reload", "Try again", "primary full")}${btn("signout", "Sign out", "soft-link")}</div></div>`;
  }
}
async function storedDoc(r, forViewing = false) {
  if (ws.sample) {
    const selected = window.KorlixFaxNative.sample.file(r.id);
    const sample = selected || await receiptPdf("Sample document", [
      ["Document", r.name], ["Workspace", "Harbor Studio"], ["Purpose", "Explore how to preview and send a fax."]
    ], r.id);
    return readPdf(new File([sample], r.name, {type: "application/pdf"}), forViewing);
  }
  const data = await api("/file/" + r.id);
  const url = checkFileUrl(data.url);
  const response = await fetch(url, {
    credentials: "omit",
    redirect: "error",
    referrerPolicy: "no-referrer",
    cache: "no-store",
    signal: AbortSignal.timeout(45000),
  });
  if (!response.ok)
    throw Error("The document could not be opened. Refresh and try again.");
  const blob = await response.blob();
  return readPdf(
    new File([blob], data.name || r.name, { type: "application/pdf" }),
    forViewing,
  );
}
async function loadIntoDraft(loader) {
  const job = ++fileJob;
  reading = true;
  const indicator = $("file-status");
  if (indicator) indicator.textContent = "Preparing document…";
  let doc;
  try {
    doc = await loader();
    if (
      job !== fileJob ||
      (!["add", "inbox", "sent", "review"].includes(route) &&
        !route.startsWith("record/"))
    ) {
      clearDoc(doc);
      return;
    }
    const old = draft.doc;
    draft.doc = doc;
    clearDoc(old);
    if (route === "add") render();
  } finally {
    if (job === fileJob) {
      reading = false;
      if (route === "add") render();
    }
  }
}
async function openViewer(doc, owned = false) {
  viewer = { doc, owned, index: 0 };
  modal(doc.name, '<p class="lead">Opening document…</p>');
  await showPage();
}
async function showPage() {
  const current = viewer;
  if (!current) return;
  const { index, doc } = current;
  sheetBody.innerHTML = `<div class="viewer-tools">${btn("prev", "Previous", "chip", "", index === 0 ? "disabled" : "")}<span>Page ${index + 1} of ${doc.pages}</span>${btn("next", "Next", "chip", "", index >= doc.pages - 1 ? "disabled" : "")}</div><img id="page-img" class="viewer-image" alt="Page ${index + 1}"><div class="btn-stack">${btn("save-view", "Save PDF", "soft-link", "download-outline")}</div>`;
  const img = $("page-img");
  img.src = await pageImage(doc, index);
}
async function download(doc) {
  if (window.KorlixFaxNative) {
    await window.KorlixFaxNative.saveFile(doc.file, doc.name);
    return;
  }
  const a = document.createElement("a");
  const url = doc.url || URL.createObjectURL(doc.file);
  a.href = url;
  a.download = doc.name;
  document.body.append(a);
  a.click();
  a.remove();
  if (!doc.url) setTimeout(() => URL.revokeObjectURL(url), 60000);
}
function account() {
  const b = ws.billing;
  modal(
    "Your account",
    details([
      ["Email", ws.email],
      [
        "Fax number",
        ws.line?.phone ? displayNumber(ws.line.phone) : "Awaiting activation",
      ],
      [
        "Plan",
        ws.line?.is_company
          ? "Korlix company line"
          : b?.active
            ? ws.plans?.[b.plan]?.name
            : ws.plans?.[ws.line?.requested_plan]?.name &&
              ws.plans?.[ws.line.requested_plan].name + " requested",
      ],
    ]) +
      `<div class="sheet-actions">${btn("setup", "My number", "outline-btn", "phone-outline")}${ws.operator ? btn("manage", "Line requests", "outline-btn", "account-multiple-outline") : ""}${window.KorlixFaxNative ? btn("delete-account", "Request account deletion", "soft-link") : ""}${btn("signout", ws.sample ? "Leave sample workspace" : "Sign out", "soft-link")}</div>`,
  );
}
async function copyNumber() {
  try {
    await navigator.clipboard.writeText(ws.line.phone);
    toast("Fax number copied");
  } catch {
    modal(
      "Copy your fax number",
      `<input id="copy-field" class="control" readonly value="${esc(ws.line.phone)}">`,
    );
    $("copy-field").select();
  }
}
function rici() {
  const recent = folders.outbound.items.find((r) => r.hasFile),
    known = recipientOptions().find(([, name]) => name);
  const speechOK = window.SpeechRecognition || window.webkitSpeechRecognition;
  modal(
    "Ask Rici",
    `<label class="small-title" for="rici-request">What would you like to fax?</label><input id="rici-request" class="control" placeholder="Document and recipient"><p class="small-note block">Enter a saved contact or fax number. You’ll review the document before sending.</p>${speechOK ? btn("dictate", "Dictate request", "soft-link", "microphone-outline") : ""}${recent && known ? `<div class="block"><h3 class="small-title">Recent document</h3>${btn("rici-last", "Fax " + recent.name + " to " + known[1], "chip", "waveform")}</div>` : ""}<p role="alert" class="err"></p><div class="btn-stack">${btn("prepare", "Prepare fax", "primary")}</div>`,
  );
}
function listen() {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SR) return;
  if (speech) speech.abort();
  speech = new SR();
  speech.lang = navigator.language || "en-US";
  speech.interimResults = false;
  speech.onresult = (e) => {
    if ($("rici-request")) $("rici-request").value = e.results[0][0].transcript;
  };
  speech.onerror = () => {
    if (sheet.open) failUI("You can type your request here.");
  };
  speech.start();
}
async function prepareRici(explicit = false) {
  const q = $("rici-request").value.trim().toLowerCase();
  const options = recipientOptions();
  const names = options.filter(
    ([, name]) => name && q.includes(name.toLowerCase()),
  );
  const numbers =
    q.match(/\+?1?[\s.(\-]*[2-9]\d{2}[\s.)\-]*[2-9]\d{2}[\s.\-]*\d{4}/g) || [];
  const phone = explicit
    ? options.find(([, name]) => name)?.[0]
    : numbers.length === 1
      ? phoneNumber(numbers[0])
      : !numbers.length && names.length === 1
        ? names[0][0]
        : "";
  if (!phone)
    throw Error("Enter one recipient’s saved contact name or full fax number.");
  const docs = folders.outbound.items.filter((r) => r.hasFile);
  const matches = docs.filter((x) =>
    q.includes(x.name.toLowerCase().replace(/\.pdf$/, "")),
  );
  const rec = explicit ? docs[0] : matches[0];
  if (rec) {
    const doc = await storedDoc(rec);
    clearDraft();
    draft.doc = doc;
  }
  draft.number = displayNumber(phone);
  draft.saveName = contactName(phone);
  go(draft.doc ? "review" : "add");
}
const actions = {
  activity: () => go("activity/" + currentMonth()),
  "leave-activity": () => go(folder === "outbound" ? "sent" : "inbox"),
  "receipt-report": () => go(receiptReport),
  "activity-more": () => loadActivity(true),
  "activity-refresh": () => loadActivity(),
  "activity-retry": () => loadActivity(report.retryMore),
  "activity-csv": async () => {
    const state = report;
    if (state.exporting) return;
    alertText = "";
    state.exporting = true;
    render();
    try {
      const data = await activityCsv(state.month);
      if (state !== report || route !== "activity/" + state.month) return;
      await download({ file: data, name: "Fax-by-Korlix-" + state.month + ".csv" });
    } catch (err) {
      if (state === report && route === "activity/" + state.month) failUI(err.message);
    } finally {
      state.exporting = false;
      if (state === report && route === "activity/" + state.month) render();
    }
  },
  home: () => go("inbox"),
  sent: (b) => go(b?.dataset.folder === "inbound" ? "inbox" : "sent"),
  reload: () => location.reload(),
  folder: (b) => go(b.dataset.id === "outbound" ? "sent" : "inbox"),
  older: async () => {
    await getFolder(folder, true);
    render();
  },
  compose: () => {
    clearDraft();
    go(ws.line?.state === "active" ? "add" : "setup");
  },
  setup: () => go("setup"),
  add: () => go("add"),
  recipient: () => go("recipient"),
  record: (b) => go("record/" + b.dataset.id),
  copy: copyNumber,
  share: async () => {
    if (window.KorlixFaxNative)
      return window.KorlixFaxNative.shareNumber(displayNumber(ws.line.phone));
    if (navigator.share)
      try {
        await navigator.share({
          title: "Fax number",
          text: displayNumber(ws.line.phone),
        });
      } catch (e) {
        if (e.name !== "AbortError") throw e;
      }
    else
      modal(
        "Share your fax number",
        `<p class="lead">${esc(displayNumber(ws.line.phone))}</p><div class="btn-stack">${btn("copy", "Copy number", "primary", "content-copy")}</div>`,
      );
  },
  camera: async () => {
    if (!window.KorlixFaxNative) return $("camera-file").click();
    const files = await window.KorlixFaxNative.scan();
    if (files) await loadIntoDraft(() => scanPages(files, draft.doc));
  },
  upload: () => $("upload-file").click(),
  remove: () => {
    clearDraft();
    render();
  },
  recent: async (b) => {
    const rec = locate(b.dataset.id);
    await loadIntoDraft(() => storedDoc(rec));
    if (route === "add" && draft.doc) go(draft.number ? "review" : "recipient");
  },
  "after-doc": () => {
    if (!reading && draft.doc)
      go(phoneNumber(draft.number) ? "review" : "recipient");
  },
  contact: (b) => {
    draft.number = displayNumber(b.dataset.num);
    draft.saveName = contactName(b.dataset.num);
    render();
  },
  review: async () => {
    const number = phoneNumber(draft.number);
    if (!number) throw Error("Enter a valid U.S. fax number.");
    const name = draft.saveName.trim();
    if (name && name !== contactName(number)) {
      const saved = await api("/contacts", {
        method: "POST",
        body: { name, phone: number },
      });
      contacts = [saved, ...contacts.filter((c) => c.phone !== number)];
    }
    go("review");
  },
  send: async () => {
    if (busy || !draft.doc) return;
    busy = true;
    render();
    try {
      const r = await dispatch(draft.doc, phoneNumber(draft.number), ws.email);
      clearDraft();
      go("record/" + r.id);
      await getFolder("outbound");
    } finally {
      busy = false;
      if (route === "review" && draft.doc) render();
    }
  },
  retry: async () => {
    const rec = activeRecord;
    if (rec.status !== "failed" || rec.direction !== "outbound" || !rec.hasFile)
      return;
    const doc = await storedDoc(rec);
    clearDraft();
    draft.doc = doc;
    draft.number = displayNumber(rec.recipient);
    go("review");
  },
  "view-draft": () => openViewer(draft.doc),
  "view-record": async () =>
    openViewer(await storedDoc(activeRecord, true), true),
  "save-receipt": async () => {
    const r = activeRecord;
    if (!r || !terminal.has(r.status)) return;
    const time = new Date(r.updated_at || r.created_at);
    const outcome =
      r.status === "failed"
        ? "Failed fax report"
        : r.direction === "inbound"
          ? "Received fax receipt"
          : "Fax delivery receipt";
    const fields = [
      ["Status", statuses[r.status]],
      [
        "Status updated",
        new Intl.DateTimeFormat("en-US", {
          dateStyle: "long",
          timeStyle: "long",
          timeZone: "UTC",
        }).format(time),
      ],
      ["From", displayNumber(r.sender)],
      ["To", displayNumber(r.recipient)],
      ["Document", r.name],
      [
        "Pages reported",
        Number.isInteger(r.pages) ? r.pages : "Awaiting page count",
      ],
      ["Fax reference", r.id],
      ["Details", r.detail],
    ];
    const file = await receiptPdf(outcome, fields, r.id);
    await download({ file, name: file.name });
  },
  "save-record": async () => {
    const d = await storedDoc(activeRecord, true);
    try {
      await download(d);
    } finally {
      setTimeout(() => clearDoc(d), 60000);
    }
  },
  "save-view": () => download(viewer.doc),
  prev: () => {
    if (viewer.index > 0) {
      viewer.index--;
      return showPage();
    }
  },
  next: () => {
    if (viewer.index < viewer.doc.pages - 1) {
      viewer.index++;
      return showPage();
    }
  },
  refresh: () => refresh(true),
  "sample-request": async () => {
    if (!ws.sample) return;
    window.KorlixFaxNative.sample.previewLineRequest();
    ws = await api("/workspace");
    render();
  },
  "sample-activate": async () => {
    if (!ws.sample) return;
    window.KorlixFaxNative.sample.activateRequestedLine();
    ws = await api("/workspace");
    render();
  },
  plan: (b) => {
    if (ws.customerEnrollmentOpen !== true) return;
    selectedPlan = b.dataset.id;
    const pref = $("prefix")?.value,
      area = $("area")?.value;
    render();
    if (pref === "local") {
      $("prefix").value = pref;
      $("area").hidden = false;
      $("area").value = area;
    }
  },
  request: async () => {
    if (ws.customerEnrollmentOpen !== true) return;
    const preference =
      $("prefix").value === "local" ? $("area").value.trim() : "toll_free";
    if (preference !== "toll_free" && !/^[2-9]\d{2}$/.test(preference))
      throw Error("Enter a valid three-digit U.S. area code.");
    const result = await api("/line", {
      method: "POST",
      body: { preference, plan: selectedPlan },
    });
    ws.line = result.line;
    render();
    toast("Your fax number request was saved");
  },
  "delete-account": () => modal("Delete your Korlix account?", '<p>This requests deletion of your Korlix account and associated data, including your fax mailbox. Other Korlix apps using this account are affected.</p><div class="btn-stack">' + btn("cancel-delete", "Keep my account", "primary full") + btn("confirm-delete", "Request deletion", "soft-link") + "</div>"),
  "cancel-delete": closeSheet,
  "confirm-delete": async () => {
    await api("/account/delete-request", { method: "POST", body: { confirm: true } });
    if (ws.sample) modal("Sample deletion request", "<p>You completed the deletion flow in the sample workspace. Your real Korlix account is unaffected.</p>");
    else modal("Deletion requested", "<p>Korlix received your request. Contact support@korlixdeveloper.com for help with your request.</p>");
  },
  manage: () => location.assign("account.html"),
  signout: async () => {
    await api("/signout", { method: "POST" });
    clearDraft();
    openLogin();
  },
  rici: () => {
    if (ws.line?.state !== "active") go("setup");
    else rici();
  },
  dictate: listen,
  prepare: () => prepareRici(false),
  "rici-last": () => prepareRici(true),
};
document.addEventListener("click", async (e) => {
  const b = e.target.closest("button[data-act]");
  if (!b || !actions[b.dataset.act] || b.disabled) return;
  b.disabled = true;
  try {
    await actions[b.dataset.act](b);
  } catch (err) {
    failUI(err.message);
  } finally {
    if (b.isConnected) b.disabled = false;
  }
});
document.addEventListener("input", (e) => {
  if (e.target.id === "fax-to") {
    draft.number = e.target.value;
    draft.saveName = contactName(phoneNumber(draft.number));
    $("contact-name").value = draft.saveName;
    screen.querySelector('[data-act="review"]').disabled = !phoneNumber(
      draft.number,
    );
    const lst = $("contacts-list");
    if (lst) lst.innerHTML = contactRows();
  } else if (e.target.id === "contact-name") draft.saveName = e.target.value;
});
document.addEventListener("change", async (e) => {
  const field = e.target;
  if (field.id === "activity-month") {
    if (validMonth(field.value)) go("activity/" + field.value);
    else {
      field.value = report.month;
      failUI("Choose the current month or an earlier month.");
    }
    return;
  }
  if (field.id === "prefix") {
    $("area").hidden = field.value !== "local";
    return;
  }
  if (!["camera-file", "upload-file"].includes(field.id) || !field.files.length)
    return;
  const files = [...field.files];
  try {
    await loadIntoDraft(() =>
      field.id === "camera-file"
        ? scanPages(files, draft.doc)
        : readPdf(files[0]),
    );
  } catch (err) {
    failUI(err.message);
  }
});
$("brand-home").onclick = () => go("inbox");
$("account").onclick = account;
$("sheet-close").onclick = closeSheet;
window.addEventListener("hashchange", () => {
  if (ws) {
    closeSheet();
    navigate();
  }
});
window.addEventListener("pageshow", (e) => {
  if (e.persisted) {
    if (!currentSession()) openLogin();
    else refresh(true);
  }
});
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) refresh();
});
setInterval(() => refresh(), 10000);
start();
