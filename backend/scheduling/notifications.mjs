import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

export function schedulingNotifications({
  database,
  environment = process.env,
  fetcher = fetch,
  publicRoot,
  autoStart = true,
}) {
  const key = Buffer.from(
    environment.KORLIX_SCHEDULING_TOKEN_KEY || "",
    "base64",
  );
  const ready =
    key.length === 32 &&
    !!environment.RESEND_API_KEY &&
    !!environment.KORLIX_AGENT_EMAIL_FROM;
  const aad = (id) => Buffer.from("korlix-scheduling:" + id);
  function seal(value, id) {
    if (key.length !== 32) return null;
    const iv = randomBytes(12),
      c = createCipheriv("aes-256-gcm", key, iv);
    c.setAAD(aad(id));
    return [
      iv,
      Buffer.concat([c.update(value, "utf8"), c.final()]),
      c.getAuthTag(),
    ]
      .map((b) => b.toString("base64url"))
      .join(".");
  }
  function open(value, id) {
    const [iv, body, tag] = value
        .split(".")
        .map((s) => Buffer.from(s, "base64url")),
      c = createDecipheriv("aes-256-gcm", key, iv);
    c.setAAD(aad(id));
    c.setAuthTag(tag);
    return Buffer.concat([c.update(body), c.final()]).toString("utf8");
  }
  async function queue(action, job = null, data = {}) {
    const r = await database.rpc("korlix_schedule_queue_v1", {
      p_action: action,
      p_id: job?.id || null,
      p_lease: job?.lease_id || null,
      p_data: data,
    });
    if (r.error) throw new Error("Scheduling queue unavailable");
    return r.data;
  }
  function render(job) {
    const b = job.payload.booking,
      s = b.snapshot,
      guest = job.recipient_role === "guest",
      label = {
        confirmation: "Booking confirmed",
        reschedule: "Appointment rescheduled",
        cancellation: "Appointment canceled",
        reminder: "Appointment reminder",
      }[job.kind];
    const time = new Intl.DateTimeFormat("en-US", {
      timeZone: guest ? b.guest_timezone : s.host_timezone,
      dateStyle: "full",
      timeStyle: "long",
    }).format(new Date(b.starts_at));
    const link = guest
      ? `${publicRoot}/book/manage#${b.id}.${open(job.sealed_manage_token, job.request_id)}`
      : "https://www.korlixdeveloper.com/app/";
    return {
      from: environment.KORLIX_AGENT_EMAIL_FROM,
      to: [job.payload.to],
      subject: ("KORLIX · " + label + ": " + s.title)
        .replace(/[\r\n]/g, " ")
        .slice(0, 200),
      text: [
        label,
        s.title,
        `${time} (${s.duration_minutes} minutes)`,
        `Host: ${s.host_name}`,
        `Guest: ${b.guest_name}`,
        job.kind === "cancellation" ? "" : s.location_detail || "",
        guest
          ? "Manage this appointment (keep this private):"
          : "Open Scheduling in KORLIX:",
        link,
        "",
        "This is an appointment update, not a marketing message. Calendar files are available from your booking page.",
      ]
        .filter(Boolean)
        .join("\n"),
    };
  }
  let running = false,
    timer;
  async function tick() {
    if (!ready || running || !database) return;
    running = true;
    try {
      for (let i = 0; i < 8; i++) {
        const job = await queue("claim");
        if (!job) break;
        let result = { state: "failed" };
        try {
          // Verify the host is still active and owns the notification address before sending.
          if (database.auth?.admin?.getUserById) {
            const { data, error } = await database.auth.admin.getUserById(
              job.owner_id,
            );
            if (error) throw new Error("Host verification unavailable");
            const u = data?.user;
            if (
              !u?.email_confirmed_at ||
              u.is_anonymous ||
              (u.banned_until && Date.parse(u.banned_until) > Date.now()) ||
              u.email?.toLowerCase() !== job.host_email?.toLowerCase()
            ) {
              await queue("finish", job, { state: "skipped" });
              continue;
            }
          }
          const sealedWire = await queue("prepare", job, {
            wire: job.wire || seal(JSON.stringify(render(job)), job.id),
          });
          if (!sealedWire) continue;
          const wire = JSON.parse(open(sealedWire, job.id));
          const response = await fetcher("https://api.resend.com/emails", {
            method: "POST",
            redirect: "error",
            signal: AbortSignal.timeout(15000),
            headers: {
              Authorization: "Bearer " + environment.RESEND_API_KEY,
              "Content-Type": "application/json",
              "Idempotency-Key": "korlix-scheduling/" + job.id,
            },
            body: JSON.stringify(wire),
          });
          let data = {};
          try {
            data = await response.json();
          } catch {}
          result =
            response.ok && typeof data.id === "string"
              ? { state: "accepted", provider_id: data.id }
              : response.status === 429 ||
                  response.status >= 500 ||
                  response.status === 409
                ? { state: "pending" }
                : { state: "failed" };
        } catch {
          result = { state: "pending" };
        }
        await queue("finish", job, result);
      }
    } catch {
      console.warn(
        "[scheduling] Notification queue temporarily unavailable; retrying on the next cycle.",
      );
    } finally {
      running = false;
    }
  }
  if (autoStart)
    console.info(
      ready
        ? "[scheduling] Email worker configured; hosts must opt in."
        : "[scheduling] Booking email unavailable: delivery configuration incomplete.",
    );
  if (ready && autoStart) {
    timer = setInterval(() => void tick(), 30000);
    timer.unref();
  }
  return { ready, seal, open, tick, stop: () => clearInterval(timer) };
}
