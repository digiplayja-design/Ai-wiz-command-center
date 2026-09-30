import { providerRequest, ProviderError } from "./provider_core.mjs";
const scopes = {
  google: [
    "openid",
    "email",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
    "https://www.googleapis.com/auth/calendar.events",
  ],
  microsoft: ["offline_access", "User.Read", "Calendars.ReadWrite"],
};
const cleanId = (v) =>
  typeof v === "string" &&
  v.length > 0 &&
  v.length < 2000 &&
  !/[\x00-\x1f]/.test(v);
const utc = (v) =>
  typeof v === "string" && /(Z|[+-]\d\d:\d\d)$/.test(v) ? v : v + "Z";
const iso = (v) => {
  if (
    typeof v !== "string" ||
    !Number.isFinite(Date.parse(v)) ||
    !/(Z|[+-]\d\d:\d\d)$/.test(v)
  )
    throw new ProviderError("The calendar returned an invalid time.");
  return new Date(v).toISOString();
};
export function calendarProvider(
  config,
  { fetcher = fetch, now = Date.now } = {},
) {
  const google = config.name === "google",
    apiRoot = google
      ? "https://www.googleapis.com/calendar/v3"
      : "https://graph.microsoft.com/v1.0";
  const authRoot = google
    ? "https://accounts.google.com/o/oauth2/v2/auth"
    : "https://login.microsoftonline.com/common/oauth2/v2.0/authorize";
  const tokenUrl = google
    ? "https://oauth2.googleapis.com/token"
    : "https://login.microsoftonline.com/common/oauth2/v2.0/token";
  async function api(path, access, { method = "GET", body, allow = [] } = {}) {
    const url = new URL(path.startsWith("https://") ? path : apiRoot + path);
    if (
      url.origin !== new URL(apiRoot).origin ||
      !url.pathname.startsWith(google ? "/calendar/v3/" : "/v1.0/")
    )
      throw new ProviderError(
        "The calendar returned an invalid continuation link.",
      );
    return providerRequest(
      fetcher,
      url.href,
      {
        method,
        headers: {
          Authorization: "Bearer " + access,
          "Content-Type": "application/json",
          ...(google
            ? {}
            : { Prefer: 'outlook.timezone="UTC", IdType="ImmutableId"' }),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      },
      allow,
    );
  }
  async function token(values, previous) {
    const { data } = await providerRequest(fetcher, tokenUrl, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: config.id,
        client_secret: config.secret,
        ...(!google ? { scope: scopes.microsoft.join(" ") } : {}),
        ...values,
      }).toString(),
    });
    if (
      !(
        typeof data.access_token === "string" &&
        data.access_token.length > 0 &&
        data.access_token.length < 16000 &&
        !/\s/.test(data.access_token)
      ) ||
      data.token_type?.toLowerCase() !== "bearer" ||
      !Number.isFinite(data.expires_in) ||
      data.expires_in < 60
    )
      throw new ProviderError(
        "The calendar did not return valid authorization.",
      );
    const required = google
        ? scopes.google.slice(2)
        : scopes.microsoft.slice(1),
      granted = String(data.scope || previous?.scope || "").split(" ");
    if (
      required.some(
        (s) =>
          !granted.some(
            (g) =>
              g.toLowerCase() === s.toLowerCase() ||
              g.toLowerCase() ===
                "https://graph.microsoft.com/" + s.toLowerCase(),
          ),
      )
    )
      throw new ProviderError(
        "Approve the requested calendar permissions to connect.",
        409,
        "missing_scopes",
      );
    const refresh = data.refresh_token || previous?.refresh_token;
    if (!refresh || typeof refresh !== "string" || refresh.length > 20000)
      throw new ProviderError(
        "Offline calendar access was not granted. Start a new connection.",
        409,
      );
    return {
      access_token: data.access_token,
      refresh_token: refresh,
      expires_at: new Date(now() + data.expires_in * 1000).toISOString(),
      scope: granted.join(" "),
    };
  }
  async function paged(path, access, max = 5000) {
    let url = path,
      result = [],
      seen = new Set();
    for (let n = 0; n < 20; n++) {
      const { data } = await api(url, access),
        items = google ? data.items : data.value;
      if (!Array.isArray(items))
        throw new ProviderError("The calendar returned an unreadable list.");
      result.push(...items);
      if (result.length > max)
        throw new ProviderError(
          "This calendar is too large to check safely. Choose fewer calendars or a shorter window.",
          409,
        );
      if (google) {
        if (!data.nextPageToken) return result;
        if (!cleanId(data.nextPageToken) || seen.has(data.nextPageToken)) break;
        seen.add(data.nextPageToken);
        const u = new URL(apiRoot + path);
        u.searchParams.set("pageToken", data.nextPageToken);
        url = u.href;
      } else {
        if (!data["@odata.nextLink"]) return result;
        url = data["@odata.nextLink"];
        if (seen.has(url)) break;
        seen.add(url);
      }
    }
    throw new ProviderError("The calendar list could not be completed.");
  }
  return {
    authorizationUrl(state, challenge) {
      const u = new URL(authRoot);
      u.search = new URLSearchParams({
        client_id: config.id,
        redirect_uri: config.callback,
        response_type: "code",
        scope: scopes[config.name].join(" "),
        state,
        code_challenge: challenge,
        code_challenge_method: "S256",
        ...(google
          ? { access_type: "offline", prompt: "consent select_account" }
          : { response_mode: "query", prompt: "select_account" }),
      });
      return u.href;
    },
    exchange: (code, verifier) =>
      token({
        grant_type: "authorization_code",
        code,
        code_verifier: verifier,
        redirect_uri: config.callback,
      }),
    refresh: (grant) =>
      token(
        { grant_type: "refresh_token", refresh_token: grant.refresh_token },
        grant,
      ),
    async identity(grant) {
      const { data } = google
        ? await providerRequest(
            fetcher,
            "https://openidconnect.googleapis.com/v1/userinfo",
            { headers: { Authorization: "Bearer " + grant.access_token } },
          )
        : await api(
            "/me?$select=id,mail,userPrincipalName,displayName",
            grant.access_token,
          );
      const id = google ? data.sub : data.id,
        label = google
          ? data.email
          : data.mail || data.userPrincipalName || data.displayName;
      if (
        !cleanId(id) ||
        !cleanId(label) ||
        (google && data.email_verified !== true)
      )
        throw new ProviderError(
          "The calendar account identity could not be verified.",
        );
      return { id, label: String(label).slice(0, 250) };
    },
    async calendars(grant) {
      const rows = await paged(
        google
          ? "/users/me/calendarList?maxResults=250"
          : "/me/calendars?$select=id,name,canEdit,isDefaultCalendar&$top=100",
        grant.access_token,
        500,
      );
      return rows
        .filter((r) => !r.deleted)
        .map((r) => {
          if (!cleanId(r.id))
            throw new ProviderError(
              "The calendar returned an invalid identifier.",
            );
          return {
            id: r.id,
            name: String(google ? r.summary : r.name).slice(0, 250),
            timezone: google ? r.timeZone || "UTC" : "UTC",
            writable: google
              ? ["owner", "writer"].includes(r.accessRole)
              : r.canEdit === true,
            primary: google ? r.primary === true : r.isDefaultCalendar === true,
          };
        });
    },
    async busy(grant, calendars, from, to) {
      const result = [];
      for (const calendar of calendars) {
        const id = encodeURIComponent(calendar.id),
          query = new URLSearchParams(
            google
              ? {
                  timeMin: from,
                  timeMax: to,
                  singleEvents: "true",
                  maxResults: "2500",
                  fields:
                    "items(id,status,start,end,transparency),nextPageToken",
                }
              : {
                  startDateTime: from,
                  endDateTime: to,
                  $top: "1000",
                  $select: "id,start,end,isCancelled,showAs",
                },
          ),
          rows = await paged(
            google
              ? `/calendars/${id}/events?${query}`
              : `/me/calendars/${id}/calendarView?${query}`,
            grant.access_token,
          );
        for (const e of rows) {
          if (
            google
              ? e.status === "cancelled" || e.transparency === "transparent"
              : e.isCancelled || ["free", "workingElsewhere"].includes(e.showAs)
          )
            continue;
          if (!cleanId(e.id))
            throw new ProviderError("The calendar returned an invalid event.");
          const common = { calendar_id: calendar.id, remote_id: e.id };
          if (google && e.start?.date && e.end?.date) {
            if (
              !/^\d{4}-\d{2}-\d{2}$/.test(e.start.date) ||
              !/^\d{4}-\d{2}-\d{2}$/.test(e.end.date)
            )
              throw new ProviderError(
                "The calendar returned an invalid all-day event.",
              );
            result.push({
              ...common,
              start_date: e.start.date,
              end_date: e.end.date,
              timezone: e.start.timeZone || calendar.timezone,
            });
          } else {
            if (
              !google &&
              (e.start?.timeZone !== "UTC" || e.end?.timeZone !== "UTC")
            )
              throw new ProviderError("The calendar did not return UTC times.");
            result.push({
              ...common,
              starts_at: iso(
                google ? e.start?.dateTime : utc(e.start?.dateTime),
              ),
              ends_at: iso(google ? e.end?.dateTime : utc(e.end?.dateTime)),
            });
          }
        }
      }
      if (result.length > 10000)
        throw new ProviderError("Too many calendar events were returned.");
      return result;
    },
    async write(grant, job, onCreated = async () => {}) {
      const id = encodeURIComponent(job.calendar_id),
        remote = job.provider_event_id,
        base = google
          ? `/calendars/${id}/events`
          : `/me/calendars/${id}/events`,
        wire = job.create_wire,
        b = job.booking;
      let eventId = remote;
      if (!eventId && job.creation_attempted) {
        const response = await api(base, grant.access_token, {
          method: "POST",
          body: wire,
          allow: google ? [409] : [],
        });
        if (response.status === 409) {
          eventId = wire.id;
          const existing = await api(
            base + "/" + encodeURIComponent(eventId),
            grant.access_token,
          );
          if (
            existing.data.extendedProperties?.private?.korlix_booking !==
              b.id ||
            existing.data.extendedProperties?.private?.korlix_link !== job.id
          )
            throw new ProviderError(
              "An existing calendar event has a different owner.",
            );
        } else eventId = response.data.id;
        if (!cleanId(eventId))
          throw new ProviderError(
            "The provider did not confirm the calendar event.",
          );
        await onCreated(eventId);
      }
      if (!eventId) return { event_id: null };
      if (["canceled", "payment_failed"].includes(b.state) || job.removed) {
        await api(
          base + "/" + encodeURIComponent(eventId),
          grant.access_token,
          { method: "DELETE", allow: [404, 410] },
        );
        return { event_id: eventId, deleted: true };
      }
      const current = calendarWire(config.name, job, false);
      await api(base + "/" + encodeURIComponent(eventId), grant.access_token, {
        method: "PATCH",
        body: current,
      });
      return { event_id: eventId };
    },
  };
}
export function calendarWire(provider, job, creating = true) {
  const b = job.booking,
    s = b.snapshot,
    description = `KORLIX 2MEETU appointment\nGuest: ${b.guest_name} (${b.guest_email})\nManage in KORLIX 2MEETU: https://www.korlixdeveloper.com/app/`;
  if (provider === "google")
    return {
      ...(creating
        ? {
            id:
              "k" +
              job.id.replaceAll("-", "") +
              "v" +
              (job.generation || 0).toString(16),
          }
        : {}),
      summary: s.title,
      description,
      location: s.location_detail || "",
      start: { dateTime: b.starts_at, timeZone: "UTC" },
      end: { dateTime: b.ends_at, timeZone: "UTC" },
      transparency: "opaque",
      extendedProperties: {
        private: { korlix_booking: b.id, korlix_link: job.id },
      },
    };
  return {
    ...(creating
      ? { transactionId: job.id + ":" + (job.generation || 0) }
      : {}),
    subject: s.title,
    body: { contentType: "text", content: description },
    location: { displayName: s.location_detail || "" },
    start: {
      dateTime: new Date(b.starts_at).toISOString().replace(/Z$/, ""),
      timeZone: "UTC",
    },
    end: {
      dateTime: new Date(b.ends_at).toISOString().replace(/Z$/, ""),
      timeZone: "UTC",
    },
    showAs: "busy",
    isReminderOn: true,
    reminderMinutesBeforeStart: 15,
  };
}
