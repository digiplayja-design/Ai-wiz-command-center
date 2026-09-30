"use strict";
const $ = (id) => document.getElementById(id),
  show = (id, on = true) => ($(id).hidden = !on);
let event,
  contextToken,
  week,
  firstWeek,
  slots = [],
  selected,
  selectedDay,
  bookingRecord,
  manageToken,
  requestId = crypto.randomUUID(),
  pendingBody,
  busy = false,
  manageEvent;
const slug = location.pathname.split("/").filter(Boolean).at(-1),
  isManage = slug === "manage";
const randomToken = () =>
  Array.from(crypto.getRandomValues(new Uint8Array(32)), (x) =>
    x.toString(16).padStart(2, "0"),
  ).join("");
let guestZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
const format = (value, options = {}) =>
  new Intl.DateTimeFormat(undefined, {
    timeZone: guestZone,
    ...options,
  }).format(new Date(value));
const dayKey = (value) =>
  new Intl.DateTimeFormat("en-CA", {
    timeZone: guestZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(value));
const dayAdd = (value, n) =>
  new Date(Date.parse(value + "T12:00:00Z") + n * 86400000)
    .toISOString()
    .slice(0, 10);
const meetingTime = (s) =>
  format(s, {
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZoneName: "short",
  });
function message(value) {
  $("error").textContent = value || "";
  show("error", !!value);
  if (value) $("error").scrollIntoView({ block: "nearest", behavior: "auto" });
}
function node(tag, content, className) {
  const n = document.createElement(tag);
  if (content !== undefined) n.textContent = content;
  if (className) n.className = className;
  return n;
}
async function api(path, body) {
  const controller = new AbortController(),
    timer = setTimeout(() => controller.abort(), 70000);
  try {
    const r = await fetch("/api/scheduling/" + path, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    let result;
    try {
      result = await r.json();
    } catch {
      throw new Error(
        "The response could not be confirmed. Please retry the same request.",
      );
    }
    if (!r.ok) {
      const error = new Error(
        result.error || "This request could not be completed.",
      );
      error.status = r.status;
      throw error;
    }
    return result;
  } finally {
    clearTimeout(timer);
  }
}
async function run(action) {
  if (busy) return;
  busy = true;
  message("");
  document.querySelectorAll("button").forEach((b) => (b.disabled = true));
  try {
    await action();
  } catch (e) {
    message(
      e.name === "AbortError"
        ? "The request took too long. Retry the same request before starting another booking."
        : e.message,
    );
  } finally {
    busy = false;
    document.querySelectorAll("button").forEach((b) => (b.disabled = false));
    if (!isManage && !bookingRecord && slots.length) renderDays();
  }
}
const money = (c) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(
    (c || 0) / 100,
  ) + " USD";
function setEvent(e) {
  event = e;
  $("host").textContent = e.host_name;
  $("avatar").textContent = e.host_name
    .trim()
    .split(/\s+/)
    .map((x) => x[0])
    .slice(0, 2)
    .join("");
  $("title").textContent = e.title;
  $("description").textContent = e.description;
  $("duration").textContent = `◷ ${e.duration_minutes} minutes`;
  $("location").textContent = {
    video: "Video meeting",
    phone: "Phone call",
    in_person: "In person",
    custom: "Meeting details after booking",
  }[e.location_kind];
  $("capacity").textContent =
    e.kind === "group"
      ? `Group session · up to ${e.capacity} guests`
      : "One-to-one appointment";
  $("price").textContent =
    e.price_cents > 0
      ? money(e.price_cents) +
        (e.payment_live === false ? " · TEST MODE — no real payment" : "")
      : "Free booking";
  $("refund-policy").textContent =
    e.price_cents > 0
      ? "Refund policy: " +
        e.refund_policy +
        " Canceling an appointment does not automatically issue a refund. If payment succeeds but your appointment cannot be confirmed, a full refund is requested automatically."
      : "";
  $("calendar-policy").textContent = e.calendar_sync
    ? "Your host’s enabled calendars are checked for conflicts."
    : "Your host’s KORLIX bookings and blocked times are checked for conflicts.";
  if (e.routing_mode === "round_robin")
    $("capacity").textContent = "One available team host will be assigned";
  if (e.routing_mode === "collective")
    $("capacity").textContent = "Meet with all selected team hosts";
  $("cancel-policy").textContent = e.cancel_notice_minutes
    ? `Online cancellations and rescheduling close ${e.cancel_notice_minutes} minutes before the appointment.`
    : "You can cancel or reschedule online before the appointment starts.";
  document.title = e.title + " · KORLIX 2MEETU";
}
function timezoneOptions() {
  let zones;
  try {
    zones = Intl.supportedValuesOf("timeZone");
  } catch {
    zones = [
      "UTC",
      "America/New_York",
      "America/Chicago",
      "America/Denver",
      "America/Los_Angeles",
      "Europe/London",
    ];
  }
  for (const z of [...new Set([guestZone, "UTC", ...zones])]) {
    const o = node("option", z.replaceAll("_", " "));
    o.value = z;
    $("timezone").append(o);
  }
  $("timezone").value = guestZone;
}
async function loadSlots() {
  show("empty", false);
  $("slots").replaceChildren(node("p", "Finding available times…", "muted"));
  const d = await api(`public/${slug}/slots`, {
    context_token: contextToken,
    date: week,
  });
  slots = d.slots;
  selectedDay = null;
  renderDays();
}
function renderDays() {
  const dates = [...new Set(slots.map((s) => dayKey(s.starts_at)))].sort();
  $("dates").replaceChildren();
  $("week-label").textContent =
    new Intl.DateTimeFormat(undefined, {
      month: "short",
      day: "numeric",
      timeZone: "UTC",
    }).format(new Date(week + "T12:00Z")) +
    " – " +
    new Intl.DateTimeFormat(undefined, {
      month: "short",
      day: "numeric",
      timeZone: "UTC",
    }).format(new Date(dayAdd(week, 6) + "T12:00Z"));
  $("previous").disabled = busy || week <= firstWeek;
  if (!dates.includes(selectedDay)) selectedDay = dates[0];
  // UTC-to-local conversion can shift dates across the host's week boundary.
  const dayStart = dates[0] || week;
  for (
    let i = 0;
    i <
    Math.max(
      7,
      Math.round(
        (Date.parse(dates.at(-1) || dayStart) - Date.parse(dayStart)) /
          86400000,
      ) + 1,
    );
    i++
  ) {
    const key = dayAdd(dayStart, i),
      available = dates.includes(key),
      d = new Date(key + "T12:00Z");
    const b = node(
      "button",
      new Intl.DateTimeFormat(undefined, {
        weekday: "short",
        timeZone: "UTC",
      }).format(d),
      "date" + (key === selectedDay ? " selected" : ""),
    );
    b.append(node("strong", d.getUTCDate()));
    b.disabled = busy || !available;
    b.setAttribute("aria-pressed", String(key === selectedDay));
    b.onclick = () => {
      selectedDay = key;
      renderDays();
    };
    $("dates").append(b);
  }
  $("slots").replaceChildren();
  show("empty", !slots.length);
  $("day-label").textContent = selectedDay
    ? new Intl.DateTimeFormat(undefined, {
        weekday: "long",
        month: "long",
        day: "numeric",
        timeZone: "UTC",
      }).format(new Date(selectedDay + "T12:00Z"))
    : "";
  for (const s of slots.filter((x) => dayKey(x.starts_at) === selectedDay)) {
    const b = node(
      "button",
      format(s.starts_at, {
        hour: "numeric",
        minute: "2-digit",
        timeZoneName: "short",
      }),
      "slot",
    );
    if (event.kind === "group")
      b.append(node("small", s.seats_left + " seats left"));
    b.onclick = () => choose(s);
    $("slots").append(b);
  }
}
function choose(s) {
  selected = s;
  pendingBody = null;
  requestId = crypto.randomUUID();
  $("form-fields").disabled = false;
  $("confirm").textContent =
    event.price_cents > 0
      ? "Reserve time and continue to payment →"
      : "Confirm booking →";
  $("selected-summary").textContent =
    meetingTime(s.starts_at) + ` · ${event.duration_minutes} minutes`;
  show("time-section", false);
  show("details-section");
  $("step1").classList.remove("current");
  $("step2").classList.add("current");
  $("questions").replaceChildren();
  for (const q of event.questions) {
    const label = node("label", q.label + (q.required ? " *" : ""));
    label.htmlFor = "q-" + q.id;
    let input;
    if (q.kind === "choice") {
      input = node("select");
      const empty = node("option", "Select an option");
      empty.value = "";
      input.append(empty);
      for (const option of q.options) {
        const o = node("option", option);
        o.value = option;
        input.append(o);
      }
    } else {
      input = node("textarea");
      input.maxLength = 1000;
      input.rows = 3;
    }
    input.id = "q-" + q.id;
    input.required = q.required;
    $("questions").append(label, input);
  }
  $("guest-name").focus();
}
function download(contents, name, type) {
  const url = URL.createObjectURL(new Blob([contents], { type })),
    a = node("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
function receipt(b) {
  bookingRecord = b;
  const delivery = (b.notifications || [])
    .filter((n) => n.kind !== "reminder")
    .at(-1);
  $("delivery-status").textContent =
    (delivery
      ? {
          accepted:
            "The email provider accepted your booking update. Check your inbox and spam folder.",
          pending: "Your booking email is queued.",
          sending: "Your booking email is being submitted.",
          failed: "Your booking email could not be sent.",
          uncertain: "We could not confirm the email submission.",
          skipped: "The email update was stopped.",
        }[delivery.state] || "Check your booking here for updates."
      : "No booking email was scheduled.") +
    " Add this appointment to your calendar and keep your private booking link.";
  guestZone = b.guest_timezone;
  show("loading", false);
  show("booking-layout", false);
  show("receipt");
  show("reschedule-section", false);
  $("receipt-title").textContent =
    b.state === "awaiting_payment"
      ? "Complete payment to confirm."
      : b.state === "payment_failed"
        ? "Appointment not confirmed."
        : b.state === "canceled"
          ? "Appointment canceled."
          : b.state === "completed"
            ? "Meeting completed."
            : b.state === "no_show"
              ? "Appointment marked missed."
              : "You’re booked.";
  $("receipt-icon").textContent = [
    "awaiting_payment",
    "payment_failed",
    "canceled",
  ].includes(b.state)
    ? "—"
    : "✓";
  $("receipt-subtitle").textContent = b.snapshot.title;
  $("receipt-details").replaceChildren(
    node("p", meetingTime(b.starts_at)),
    node(
      "p",
      `${b.snapshot.duration_minutes} minutes · with ${b.snapshot.host_name}`,
    ),
    node("p", `${b.guest_name} · ${b.guest_email}`),
  );
  const detail = b.snapshot.location_detail;
  if (detail) {
    let link;
    try {
      const u = new URL(detail);
      if (u.protocol === "https:") {
        link = node("a", "Open meeting link");
        link.href = u.href;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
      }
    } catch {}
    $("receipt-details").append(link || node("p", detail));
  }
  for (const q of b.snapshot.questions || []) {
    if (b.answers[q.id])
      $("receipt-details").append(node("p", q.label + ": " + b.answers[q.id]));
  }
  const editable =
    b.state === "confirmed" && Date.parse(b.cancel_until) > Date.now();
  $("reschedule").hidden = !editable;
  $("cancel").hidden = !(editable || b.state === "awaiting_payment");
  $("calendar").hidden =
    ["awaiting_payment", "payment_failed"].includes(b.state) ||
    b.payment?.state === "unpaid";
  $("calendar").textContent =
    b.state === "canceled" ? "Download calendar update" : "Add to calendar";
  if (b.hosts?.length)
    $("receipt-details").append(
      node("p", "Assigned hosts: " + b.hosts.join(", ")),
    );
  if (b.calendar_updates?.length)
    $("receipt-details").append(
      node(
        "p",
        "Host calendar updates: " +
          [...new Set(b.calendar_updates.map((c) => c.state))].join(", "),
      ),
    );
  show("payment-status", !!b.payment);
  show(
    "checkout",
    b.state === "awaiting_payment" &&
      Date.parse(b.payment?.checkout_expires_at) > Date.now(),
  );
  show("payment-refresh", !!b.payment);
  if (b.payment) {
    const p = b.payment,
      awaiting = b.state === "awaiting_payment";
    $("checkout").textContent = "Continue to Stripe · " + money(p.amount_cents);
    $("payment-status").textContent =
      (p.livemode === false ? "TEST MODE — no real payment. " : "") +
      money(p.amount_cents) +
      " · " +
      p.state +
      ". " +
      (awaiting
        ? "Your appointment is not confirmed. Finish checkout before " +
          meetingTime(p.checkout_expires_at) +
          ". Keep this private link to check the result. "
        : "") +
      (p.refund_state !== "none"
        ? "Full refund: " + p.refund_state + ". "
        : "") +
      (b.snapshot.refund_policy || "");
    if (awaiting || b.state === "payment_failed")
      $("delivery-status").textContent =
        "This appointment is not confirmed. Payment and refund status are verified with Stripe. Returning from checkout alone does not confirm a booking.";
  }
  if (manageToken)
    history.replaceState(null, "", `/book/manage#${b.id}.${manageToken}`);
}
$("timezone").onchange = () => {
  guestZone = $("timezone").value;
  renderDays();
};
$("previous").onclick = () =>
  run(async () => {
    week = dayAdd(week, -7);
    await loadSlots();
  });
$("next").onclick = () =>
  run(async () => {
    week = dayAdd(week, 7);
    await loadSlots();
  });
$("back").onclick = () => {
  if (pendingBody) {
    message("Retry this pending request before starting another booking.");
    return;
  }
  show("details-section", false);
  show("time-section");
  $("step1").classList.add("current");
  $("step2").classList.remove("current");
};
$("details-form").onsubmit = (e) => {
  e.preventDefault();
  run(async () => {
    if (!pendingBody) {
      manageToken = randomToken();
      pendingBody = {
        context_token: contextToken,
        request_id: requestId,
        manage_token: manageToken,
        starts_at: selected.starts_at,
        guest_name: $("guest-name").value,
        guest_email: $("guest-email").value,
        guest_timezone: guestZone,
        answers: Object.fromEntries(
          event.questions.map((q) => [q.id, $("q-" + q.id).value]),
        ),
        confirmed: $("consent").checked,
        website: $("website").value,
      };
    }
    $("form-fields").disabled = true;
    $("confirm").textContent = "Retry this booking request";
    try {
      const d = await api(`public/${slug}/book`, pendingBody);
      pendingBody = null;
      receipt(d.booking);
    } catch (error) {
      if ([400, 403, 404, 409].includes(error.status)) {
        pendingBody = null;
        $("form-fields").disabled = false;
        $("confirm").textContent =
          event.price_cents > 0
            ? "Reserve time and continue to payment →"
            : "Confirm booking →";
      }
      throw error;
    }
  });
};
const management = () => ({
  booking_id: bookingRecord.id,
  manage_token: manageToken,
});
$("checkout").onclick = () =>
  run(async () => {
    const d = await api("manage/checkout", {
      ...management(),
      confirmed: true,
    });
    receipt(d.booking);
    const url = d.booking.payment?.checkout_url;
    if (!url)
      throw new Error(
        "Checkout is not ready. Refresh the payment status and try again.",
      );
    const target = new URL(url);
    if (
      target.origin !== "https://checkout.stripe.com" ||
      target.username ||
      target.password
    )
      throw new Error("Checkout link could not be verified.");
    location.assign(target.href);
  });
$("payment-refresh").onclick = () =>
  run(async () => receipt((await api("manage", management())).booking));
setInterval(async () => {
  if (busy || document.hidden || !bookingRecord?.payment || !manageToken)
    return;
  if (
    bookingRecord.state !== "awaiting_payment" &&
    !["required", "sending", "pending"].includes(
      bookingRecord.payment.refund_state,
    )
  )
    return;
  try {
    const d = await api("manage", management());
    if (!busy) receipt(d.booking);
  } catch {}
}, 15000);
$("calendar").onclick = () =>
  run(async () => {
    const d = await api("manage/calendar", management());
    download(d.calendar, d.filename, "text/calendar;charset=utf-8");
    $("feedback").textContent =
      "Calendar file downloaded. Import it into your calendar app.";
  });
$("copy").onclick = () =>
  run(async () => {
    await navigator.clipboard.writeText(location.href);
    $("feedback").textContent = "Private booking link copied.";
  });
$("cancel").onclick = () => {
  if (
    confirm(
      "Cancel this appointment? Paid appointments are not automatically refunded; contact the host under the displayed refund policy. If booking emails are enabled, an update will be queued.",
    )
  )
    run(async () => {
      const d = await api("manage/cancel", {
        ...management(),
        revision: bookingRecord.revision,
        confirmed: true,
      });
      receipt(d.booking);
    });
};
$("reschedule").onclick = () => {
  show("reschedule-section");
  $("reschedule-date").value = new Date().toISOString().slice(0, 10);
  $("reschedule-note").textContent =
    "Your current time stays reserved until the new time is confirmed. Times are shown in " +
    guestZone.replaceAll("_", " ") +
    ".";
};
$("reschedule-search").onclick = () =>
  run(async () => {
    const d = await api("manage/slots", {
      ...management(),
      date: $("reschedule-date").value,
    });
    manageEvent = d.event;
    $("reschedule-slots").replaceChildren();
    if (!d.slots.length)
      $("reschedule-slots").append(
        node("p", "No available times in this week."),
      );
    for (const s of d.slots) {
      const b = node("button", meetingTime(s.starts_at), "slot");
      b.onclick = () => {
        if (confirm(`Move your appointment to ${meetingTime(s.starts_at)}?`))
          run(async () => {
            const next = await api("manage/reschedule", {
              ...management(),
              revision: bookingRecord.revision,
              event_revision: manageEvent.revision,
              starts_at: s.starts_at,
              confirmed: true,
            });
            receipt(next.booking);
            $("feedback").textContent =
              "Appointment rescheduled. Download a new calendar file to update your calendar.";
          });
      };
      $("reschedule-slots").append(b);
    }
  });
run(async () => {
  if (isManage) {
    const match = location.hash.match(/^#([a-f0-9-]{36})\.([a-f0-9]{64})$/);
    if (!match)
      throw new Error(
        "Open the complete private link from your booking confirmation.",
      );
    manageToken = match[2];
    const d = await api("manage", {
      booking_id: match[1],
      manage_token: manageToken,
    });
    receipt(d.booking);
  } else {
    const d = await api(`public/${slug}/context`, {});
    contextToken = d.context_token;
    $("email-policy").textContent = d.notifications.email
      ? "By confirming, you agree to receive appointment confirmations, changes and reminders by email. This does not sign you up for marketing. Keep your private booking link."
      : "This booking does not sign you up for marketing. Save your confirmation and private management link; the host has not enabled booking emails.";
    week = firstWeek = d.today;
    setEvent(d.event);
    timezoneOptions();
    show("loading", false);
    show("booking-layout");
    await loadSlots();
  }
}).finally(() => show("loading", false));
