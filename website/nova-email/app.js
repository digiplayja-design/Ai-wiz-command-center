"use strict";

const APP = {
  apiBase:
    localStorage.getItem("korlixNovaEmailApiBase") ||
    "https://chee-chai-chee-backend.onrender.com",

  token: null,

  agentId:
    new URLSearchParams(location.search).get("agentId") ||
    localStorage.getItem("korlixNovaEmailAgentId") ||
    "",

  statusPayload: null,
  settings: {},
  recipients: [],
  drafts: [],
  events: [],
  rules: [],
  delivery: {},
  selectedDraft: null,
  connected: false,
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

const els = {
  sidebar: $("#sidebar"),
  connectionButton: $("#connectionButton"),
  connectionLabel: $("#connectionLabel"),
  connectionState: $("#connectionState"),
  mobileMenuButton: $("#mobileMenuButton"),

  systemStatus: $("#systemStatus"),
  systemStatusIndicator: $("#systemStatusIndicator"),
  webhookStatus: $("#webhookStatus"),
  webhookIndicator: $("#webhookIndicator"),
  autopilotStatus: $("#autopilotStatus"),
  autopilotIndicator: $("#autopilotIndicator"),
  pauseStatus: $("#pauseStatus"),
  pauseIndicator: $("#pauseIndicator"),
  dailyCapStatus: $("#dailyCapStatus"),

  refreshButton: $("#refreshButton"),
  createDraftButton: $("#createDraftButton"),
  pauseSystemButton: $("#pauseSystemButton"),
  stopAutopilotButton: $("#stopAutopilotButton"),
  autopilotToggle: $("#autopilotToggle"),

  dailyCapLabel: $("#dailyCapLabel"),
  dailyCapUsage: $("#dailyCapUsage"),
  dailyCapProgress: $("#dailyCapProgress"),
  quietHoursValue: $("#quietHoursValue"),

  recipientCount: $("#recipientCount"),
  recipientRecentCount: $("#recipientRecentCount"),
  recipientList: $("#recipientList"),

  draftCount: $("#draftCount"),
  draftList: $("#draftList"),

  sentMetric: $("#sentMetric"),
  deliveredMetric: $("#deliveredMetric"),
  openedMetric: $("#openedMetric"),
  clickedMetric: $("#clickedMetric"),
  deliveryChartLine: $("#deliveryChartLine"),
  lastRefreshValue: $("#lastRefreshValue"),

  eventList: $("#eventList"),

  healthApi: $("#healthApi"),
  healthWebhook: $("#healthWebhook"),
  healthDatabase: $("#healthDatabase"),
  healthAutopilot: $("#healthAutopilot"),
  healthEmail: $("#healthEmail"),
  healthLimits: $("#healthLimits"),

  connectionModal: $("#connectionModal"),
  agentIdInput: $("#agentIdInput"),
  apiBaseInput: $("#apiBaseInput"),
  connectSessionButton: $("#connectSessionButton"),
  openKorlixAppButton: $("#openKorlixAppButton"),
  connectionMessage: $("#connectionMessage"),

  recipientModal: $("#recipientModal"),
  recipientForm: $("#recipientForm"),
  recipientNameInput: $("#recipientNameInput"),
  recipientEmailInput: $("#recipientEmailInput"),
  recipientPermissionInput: $("#recipientPermissionInput"),
  recipientMessage: $("#recipientMessage"),

  draftModal: $("#draftModal"),
  draftForm: $("#draftForm"),
  draftRecipientInput: $("#draftRecipientInput"),
  draftSubjectInput: $("#draftSubjectInput"),
  draftBodyInput: $("#draftBodyInput"),
  draftTransactionalInput: $("#draftTransactionalInput"),
  draftMessage: $("#draftMessage"),

  detailsModal: $("#detailsModal"),
  draftDetails: $("#draftDetails"),
  approveSendButton: $("#approveSendButton"),
  detailsMessage: $("#detailsMessage"),

  toastContainer: $("#toastContainer"),
};

function firstDefined(...values) {
  return values.find(
    (value) =>
      value !== undefined &&
      value !== null &&
      value !== "",
  );
}

function asBoolean(value, fallback = false) {
  if (typeof value === "boolean") {
    return value;
  }

  const normalized = String(
    value ?? "",
  ).trim().toLowerCase();

  if (
    [
      "true",
      "1",
      "yes",
      "on",
      "enabled",
      "active",
    ].includes(normalized)
  ) {
    return true;
  }

  if (
    [
      "false",
      "0",
      "no",
      "off",
      "disabled",
      "inactive",
    ].includes(normalized)
  ) {
    return false;
  }

  return fallback;
}

function asNumber(value, fallback = 0) {
  const numeric = Number(value);

  return Number.isFinite(numeric)
    ? numeric
    : fallback;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatDateTime(value) {
  if (!value) {
    return "—";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return String(value);
  }

  return new Intl.DateTimeFormat(
    undefined,
    {
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
    },
  ).format(date);
}

function formatTime(value) {
  if (!value) {
    return "—";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return String(value);
  }

  return new Intl.DateTimeFormat(
    undefined,
    {
      hour: "numeric",
      minute: "2-digit",
      second: "2-digit",
    },
  ).format(date);
}

function showModal(id) {
  const modal = document.getElementById(id);

  if (!modal) {
    return;
  }

  modal.classList.remove("hidden");

  const input = modal.querySelector(
    "input,select,textarea,button",
  );

  setTimeout(
    () => input?.focus(),
    30,
  );
}

function closeModal(id) {
  document
    .getElementById(id)
    ?.classList.add("hidden");
}

function setMessage(element, message, type = "") {
  if (!element) {
    return;
  }

  element.textContent = message || "";
  element.classList.remove(
    "error",
    "success",
  );

  if (type) {
    element.classList.add(type);
  }
}

function toast(message, type = "") {
  const node = document.createElement("div");

  node.className = [
    "toast",
    type,
  ].filter(Boolean).join(" ");

  node.textContent = message;

  els.toastContainer.appendChild(node);

  setTimeout(
    () => node.remove(),
    5200,
  );
}

function setHealth(element, value) {
  if (!element) {
    return;
  }

  element.textContent = value;
}

function decodeJwtPayload(token) {
  try {
    const encoded = token.split(".")[1];

    if (!encoded) {
      return null;
    }

    const normalized = encoded
      .replaceAll("-", "+")
      .replaceAll("_", "/");

    const padded = normalized.padEnd(
      normalized.length +
      ((4 - (normalized.length % 4)) % 4),
      "=",
    );

    return JSON.parse(
      decodeURIComponent(
        [...atob(padded)]
          .map(
            (character) =>
              `%${character
                .charCodeAt(0)
                .toString(16)
                .padStart(2, "0")}`,
          )
          .join(""),
      ),
    );
  } catch {
    return null;
  }
}

function tokenUsable(token) {
  if (
    !token ||
    !/^eyJ[A-Za-z0-9_-]+\./.test(token)
  ) {
    return false;
  }

  const payload = decodeJwtPayload(token);

  if (
    payload?.exp &&
    Number(payload.exp) * 1000 <
      Date.now() + 30_000
  ) {
    return false;
  }

  return true;
}

function searchObjectForToken(
  value,
  depth = 0,
  seen = new Set(),
) {
  if (
    value === null ||
    value === undefined ||
    depth > 8
  ) {
    return null;
  }

  if (typeof value === "string") {
    if (tokenUsable(value)) {
      return value;
    }

    const match = value.match(
      /eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/,
    );

    if (
      match &&
      tokenUsable(match[0])
    ) {
      return match[0];
    }

    try {
      const parsed = JSON.parse(value);

      return searchObjectForToken(
        parsed,
        depth + 1,
        seen,
      );
    } catch {
      return null;
    }
  }

  if (typeof value !== "object") {
    return null;
  }

  if (seen.has(value)) {
    return null;
  }

  seen.add(value);

  for (
    const key
    of [
      "access_token",
      "accessToken",
      "token",
      "jwt",
    ]
  ) {
    if (
      tokenUsable(value[key])
    ) {
      return value[key];
    }
  }

  for (const child of Object.values(value)) {
    const token = searchObjectForToken(
      child,
      depth + 1,
      seen,
    );

    if (token) {
      return token;
    }
  }

  return null;
}

function storageValues(storage) {
  const values = [];

  try {
    for (
      let index = 0;
      index < storage.length;
      index += 1
    ) {
      const key = storage.key(index);

      if (!key) {
        continue;
      }

      values.push({
        key,
        value: storage.getItem(key),
      });
    }
  } catch {
    return [];
  }

  return values;
}

function findSessionToken() {
  const hash = new URLSearchParams(
    location.hash.replace(/^#/, ""),
  );

  const query = new URLSearchParams(
    location.search,
  );

  const direct = firstDefined(
    hash.get("access_token"),
    query.get("access_token"),
  );

  if (tokenUsable(direct)) {
    history.replaceState(
      {},
      "",
      location.pathname +
        (APP.agentId
          ? `?agentId=${encodeURIComponent(APP.agentId)}`
          : ""),
    );

    return direct;
  }

  const all = [
    ...storageValues(localStorage),
    ...storageValues(sessionStorage),
  ];

  all.sort(
    (left, right) =>
      Number(
        /supabase|auth|session|token/i.test(
          right.key,
        ),
      ) -
      Number(
        /supabase|auth|session|token/i.test(
          left.key,
        ),
      ),
  );

  for (const item of all) {
    const token = searchObjectForToken(
      item.value,
    );

    if (token) {
      return token;
    }
  }

  return null;
}

function findAgentInObject(
  value,
  depth = 0,
  seen = new Set(),
) {
  if (
    value === null ||
    value === undefined ||
    depth > 8
  ) {
    return null;
  }

  if (typeof value === "string") {
    try {
      return findAgentInObject(
        JSON.parse(value),
        depth + 1,
        seen,
      );
    } catch {
      return null;
    }
  }

  if (typeof value !== "object") {
    return null;
  }

  if (seen.has(value)) {
    return null;
  }

  seen.add(value);

  const name = String(
    firstDefined(
      value.name,
      value.displayName,
      value.title,
      value.agentName,
      "",
    ),
  ).toLowerCase();

  const explicitAgentId = firstDefined(
    value.agentId,
    value.agent_id,
    value.currentAgentId,
    value.selectedAgentId,
  );

  if (
    explicitAgentId &&
    (
      name.includes("nova") ||
      String(explicitAgentId).startsWith("custom_") ||
      /^[0-9a-f-]{30,}$/i.test(
        String(explicitAgentId),
      )
    )
  ) {
    return String(explicitAgentId);
  }

  if (
    name.includes("nova") &&
    value.id
  ) {
    return String(value.id);
  }

  for (const child of Object.values(value)) {
    const found = findAgentInObject(
      child,
      depth + 1,
      seen,
    );

    if (found) {
      return found;
    }
  }

  return null;
}

function findStoredAgentId() {
  if (APP.agentId) {
    return APP.agentId;
  }

  for (
    const item
    of [
      ...storageValues(localStorage),
      ...storageValues(sessionStorage),
    ]
  ) {
    const found = findAgentInObject(
      item.value,
    );

    if (found) {
      return found;
    }
  }

  return "";
}

function findList(
  payload,
  preferredKeys = [],
) {
  if (Array.isArray(payload)) {
    return payload;
  }

  if (
    !payload ||
    typeof payload !== "object"
  ) {
    return [];
  }

  for (const key of preferredKeys) {
    if (Array.isArray(payload[key])) {
      return payload[key];
    }
  }

  for (
    const key
    of [
      "data",
      "items",
      "results",
      "rows",
    ]
  ) {
    const value = payload[key];

    if (Array.isArray(value)) {
      return value;
    }

    if (
      value &&
      typeof value === "object"
    ) {
      const nested = findList(
        value,
        preferredKeys,
      );

      if (nested.length) {
        return nested;
      }
    }
  }

  for (const value of Object.values(payload)) {
    if (
      value &&
      typeof value === "object"
    ) {
      const nested = findList(
        value,
        preferredKeys,
      );

      if (nested.length) {
        return nested;
      }
    }
  }

  return [];
}

function emailBase() {
  if (!APP.agentId) {
    throw new Error(
      "Nova Agent ID is not configured.",
    );
  }

  return (
    `/api/live-convo/agents/` +
    `${encodeURIComponent(APP.agentId)}/email`
  );
}

async function requestJson(
  path,
  options = {},
) {
  if (!APP.token) {
    throw new Error(
      "No authenticated KORLIX browser session was found.",
    );
  }

  const url = path.startsWith("http")
    ? path
    : `${APP.apiBase}${path}`;

  const response = await fetch(
    url,
    {
      ...options,
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${APP.token}`,
        ...(options.body
          ? {
              "Content-Type":
                "application/json",
            }
          : {}),
        ...(options.headers || {}),
      },
    },
  );

  const text = await response.text();

  let payload = {};

  try {
    payload = text
      ? JSON.parse(text)
      : {};
  } catch {
    payload = {
      message:
        text ||
        `HTTP ${response.status}`,
    };
  }

  if (!response.ok) {
    const error = new Error(
      firstDefined(
        payload.message,
        payload.error,
        payload.detail,
        payload.code,
        `Request failed with HTTP ${response.status}.`,
      ),
    );

    error.status = response.status;
    error.payload = payload;

    throw error;
  }

  return payload;
}

async function discoverNovaAgent() {
  const candidates = [
    "/api/live-convo/agents",
    "/api/agent-hub/agents",
    "/api/agents",
  ];

  for (const path of candidates) {
    try {
      const payload = await requestJson(
        path,
      );

      const agents = findList(
        payload,
        [
          "agents",
          "profiles",
        ],
      );

      const nova = agents.find(
        (agent) => {
          const name = String(
            firstDefined(
              agent.name,
              agent.displayName,
              agent.title,
              agent.agentName,
              "",
            ),
          ).toLowerCase();

          return (
            name.includes("nova") &&
            asBoolean(
              firstDefined(
                agent.active,
                agent.isActive,
                true,
              ),
              true,
            )
          );
        },
      );

      const id = firstDefined(
        nova?.agentId,
        nova?.agent_id,
        nova?.id,
      );

      if (id) {
        return String(id);
      }
    } catch {
      // Continue through supported Agent Hub discovery routes.
    }
  }

  return "";
}

function setConnectedState(
  connected,
  label = "",
) {
  APP.connected = connected;

  els.connectionState.classList.toggle(
    "connected",
    connected,
  );

  els.connectionState.lastChild.textContent =
    connected
      ? " Production connected"
      : " Not connected";

  els.connectionLabel.textContent =
    label ||
    (
      connected
        ? "Nova Email connected"
        : "Connect session"
    );
}

function setTopStatus({
  operational,
  webhook,
  autopilot,
  paused,
  dailyCap,
}) {
  els.systemStatus.textContent =
    operational
      ? "PRODUCTION LIVE"
      : "UNAVAILABLE";

  els.systemStatus.className =
    operational
      ? "state-positive"
      : "state-negative";

  els.systemStatusIndicator.className =
    `indicator ${
      operational
        ? "active"
        : "danger"
    }`;

  els.webhookStatus.textContent =
    webhook
      ? "ENABLED"
      : "DISABLED";

  els.webhookStatus.className =
    webhook
      ? "state-positive"
      : "state-negative";

  els.webhookIndicator.className =
    `indicator ${
      webhook
        ? "active"
        : "danger"
    }`;

  els.autopilotStatus.textContent =
    autopilot
      ? "ENABLED"
      : "DISABLED";

  els.autopilotStatus.className =
    autopilot
      ? "state-neutral"
      : "state-negative";

  els.autopilotIndicator.className =
    `indicator ${
      autopilot
        ? "active"
        : "danger"
    }`;

  els.pauseStatus.textContent =
    paused
      ? "ON"
      : "OFF";

  els.pauseStatus.className =
    paused
      ? "state-negative"
      : "";

  els.pauseIndicator.className =
    `indicator ${
      paused
        ? "danger"
        : "active"
    }`;

  els.dailyCapStatus.textContent =
    `${dailyCap} / DAY`;

  els.autopilotToggle.checked =
    autopilot;

  els.pauseSystemButton.textContent =
    paused
      ? "▶ Resume Nova"
      : "Ⅱ Pause Nova";

  els.stopAutopilotButton.disabled =
    !autopilot;
}

function statusRoot(payload) {
  return firstDefined(
    payload?.status,
    payload?.data?.status,
    payload?.data,
    payload,
    {},
  );
}

function normalizedSettings(payload) {
  const root = statusRoot(payload);

  return firstDefined(
    root?.settings,
    payload?.settings,
    payload?.data?.settings,
    {},
  );
}

function normalizeRecipient(row) {
  return {
    id: firstDefined(
      row.id,
      row.recipientId,
      row.recipient_id,
      row.email,
    ),

    name: firstDefined(
      row.name,
      row.displayName,
      row.recipientName,
      "",
    ),

    email: firstDefined(
      row.email,
      row.emailAddress,
      row.recipientEmail,
      "Unknown",
    ),

    status: String(
      firstDefined(
        row.consentStatus,
        row.consent_status,
        row.status,
        "transactional_only",
      ),
    ),

    active: asBoolean(
      firstDefined(
        row.active,
        row.isActive,
        true,
      ),
      true,
    ),

    createdAt: firstDefined(
      row.createdAt,
      row.created_at,
      row.addedAt,
      "",
    ),
  };
}

function normalizeDraft(row) {
  return {
    id: firstDefined(
      row.id,
      row.messageId,
      row.message_id,
    ),

    subject: firstDefined(
      row.subject,
      row.subjectLine,
      "Untitled Draft",
    ),

    recipientId: firstDefined(
      row.recipientId,
      row.recipient_id,
    ),

    recipientEmail: firstDefined(
      row.recipientEmail,
      row.recipient_email,
      row.to,
      "",
    ),

    recipientName: firstDefined(
      row.recipientName,
      row.recipient_name,
      "",
    ),

    status: String(
      firstDefined(
        row.status,
        row.deliveryStatus,
        row.approvalStatus,
        "draft",
      ),
    ),

    text: firstDefined(
      row.textBody,
      row.text_body,
      row.bodyText,
      row.body,
      "",
    ),

    html: firstDefined(
      row.htmlBody,
      row.html_body,
      row.bodyHtml,
      "",
    ),

    createdAt: firstDefined(
      row.createdAt,
      row.created_at,
      "",
    ),

    raw: row,
  };
}

function normalizeEvent(row) {
  return {
    id: firstDefined(
      row.id,
      row.eventId,
      row.event_id,
    ),

    type: String(
      firstDefined(
        row.eventType,
        row.event_type,
        row.type,
        row.status,
        "event",
      ),
    ),

    email: firstDefined(
      row.recipientEmail,
      row.recipient_email,
      row.email,
      row.to,
      "",
    ),

    createdAt: firstDefined(
      row.createdAt,
      row.created_at,
      row.occurredAt,
      row.occurred_at,
      "",
    ),

    providerMessageId: firstDefined(
      row.providerMessageId,
      row.provider_message_id,
      row.messageId,
      "",
    ),

    raw: row,
  };
}

function renderRecipients() {
  const activeRecipients =
    APP.recipients
      .map(normalizeRecipient)
      .filter(
        (recipient) =>
          recipient.active &&
          ![
            "unsubscribed",
            "suppressed",
          ].includes(
            recipient.status.toLowerCase(),
          ),
      );

  els.recipientCount.textContent =
    String(activeRecipients.length);

  const recent = activeRecipients.filter(
    (recipient) => {
      if (!recipient.createdAt) {
        return false;
      }

      const created =
        new Date(recipient.createdAt)
          .getTime();

      return (
        Number.isFinite(created) &&
        created >
          Date.now() -
          7 * 24 * 60 * 60 * 1000
      );
    },
  ).length;

  els.recipientRecentCount.textContent =
    `+${recent}`;

  if (!activeRecipients.length) {
    els.recipientList.innerHTML = `
      <div class="empty-state">
        No approved Agent Email recipients.
      </div>
    `;
  } else {
    els.recipientList.innerHTML =
      activeRecipients
        .slice(0, 7)
        .map(
          (recipient) => `
            <div class="compact-row">
              <i></i>
              <span title="${escapeHtml(recipient.email)}">
                ${escapeHtml(recipient.email)}
              </span>
              <small>
                ${escapeHtml(
                  recipient.name ||
                  recipient.status.replaceAll("_", " "),
                )}
              </small>
            </div>
          `,
        )
        .join("");
  }

  els.draftRecipientInput.innerHTML = `
    <option value="">
      Select an approved recipient
    </option>
    ${activeRecipients
      .map(
        (recipient) => `
          <option value="${escapeHtml(recipient.id)}">
            ${escapeHtml(
              recipient.name
                ? `${recipient.name} — ${recipient.email}`
                : recipient.email,
            )}
          </option>
        `,
      )
      .join("")}
  `;
}

function draftBadge(status) {
  const normalized =
    status.toLowerCase();

  if (
    normalized.includes("sent") ||
    normalized.includes("delivered")
  ) {
    return "green";
  }

  if (
    normalized.includes("approved") ||
    normalized.includes("pending")
  ) {
    return "gold";
  }

  if (
    normalized.includes("failed") ||
    normalized.includes("bounce")
  ) {
    return "red";
  }

  return "blue";
}

function renderDrafts() {
  const drafts = APP.drafts
    .map(normalizeDraft)
    .filter(
      (draft) =>
        !draft.status
          .toLowerCase()
          .includes("deleted"),
    );

  els.draftCount.textContent =
    String(drafts.length);

  if (!drafts.length) {
    els.draftList.innerHTML = `
      <div class="empty-state">
        No Agent Email drafts are waiting.
      </div>
    `;

    return;
  }

  els.draftList.innerHTML =
    drafts
      .slice(0, 4)
      .map(
        (draft, index) => `
          <div class="draft-row">
            <span class="draft-number">
              ${index + 1}
            </span>

            <div class="draft-copy">
              <strong title="${escapeHtml(draft.subject)}">
                ${escapeHtml(draft.subject)}
              </strong>

              <small>
                ${escapeHtml(
                  draft.recipientEmail ||
                  draft.recipientName ||
                  draft.status,
                )}
              </small>

              <small>
                ${escapeHtml(formatDateTime(draft.createdAt))}
                ·
                <span class="status-badge ${draftBadge(draft.status)}">
                  ${escapeHtml(draft.status)}
                </span>
              </small>
            </div>

            <button
              class="launch-button"
              type="button"
              data-draft-id="${escapeHtml(draft.id)}"
            >
              OPEN
            </button>
          </div>
        `,
      )
      .join("");

  $$("[data-draft-id]").forEach(
    (button) => {
      button.addEventListener(
        "click",
        () => openDraftDetails(
          button.dataset.draftId,
        ),
      );
    },
  );
}

function eventLabel(type) {
  return type
    .replaceAll("_", " ")
    .replaceAll(".", " ")
    .trim();
}

function eventBadge(type) {
  const normalized =
    type.toLowerCase();

  if (
    normalized.includes("deliver") ||
    normalized.includes("success")
  ) {
    return "green";
  }

  if (
    normalized.includes("open") ||
    normalized.includes("sent") ||
    normalized.includes("click")
  ) {
    return "blue";
  }

  if (
    normalized.includes("fail") ||
    normalized.includes("bounce") ||
    normalized.includes("complain")
  ) {
    return "red";
  }

  return "gold";
}

function renderEvents() {
  const events = APP.events
    .map(normalizeEvent)
    .sort(
      (left, right) =>
        new Date(right.createdAt).getTime() -
        new Date(left.createdAt).getTime(),
    );

  if (!events.length) {
    els.eventList.innerHTML = `
      <div class="empty-state">
        No Agent Email delivery events yet.
      </div>
    `;

    return;
  }

  els.eventList.innerHTML =
    events
      .slice(0, 7)
      .map(
        (event) => `
          <div class="event-row">
            <time>
              ${escapeHtml(formatTime(event.createdAt))}
            </time>

            <div class="event-copy">
              <strong>
                ${escapeHtml(eventLabel(event.type))}
              </strong>

              <small title="${escapeHtml(event.email)}">
                ${escapeHtml(
                  event.email ||
                  event.providerMessageId ||
                  "KORLIX Agent Email",
                )}
              </small>
            </div>

            <span class="status-badge ${eventBadge(event.type)}">
              ${escapeHtml(
                event.type
                  .split(".")
                  .pop()
                  .replaceAll("_", " "),
              )}
            </span>
          </div>
        `,
      )
      .join("");
}

function calculateDeliveryMetrics() {
  const metrics = {
    sent: 0,
    delivered: 0,
    opened: 0,
    clicked: 0,
  };

  for (const raw of APP.events) {
    const event = normalizeEvent(raw);
    const type =
      event.type.toLowerCase();

    if (
      type.includes("sent") &&
      !type.includes("resent")
    ) {
      metrics.sent += 1;
    }

    if (type.includes("deliver")) {
      metrics.delivered += 1;
    }

    if (type.includes("open")) {
      metrics.opened += 1;
    }

    if (type.includes("click")) {
      metrics.clicked += 1;
    }
  }

  const delivery = APP.delivery || {};

  metrics.sent = Math.max(
    metrics.sent,
    asNumber(
      firstDefined(
        delivery.sentToday,
        delivery.sent_today,
        delivery.sent,
        0,
      ),
    ),
  );

  metrics.delivered = Math.max(
    metrics.delivered,
    asNumber(
      firstDefined(
        delivery.deliveredToday,
        delivery.delivered_today,
        delivery.delivered,
        0,
      ),
    ),
  );

  metrics.opened = Math.max(
    metrics.opened,
    asNumber(
      firstDefined(
        delivery.openedToday,
        delivery.opened_today,
        delivery.opened,
        0,
      ),
    ),
  );

  metrics.clicked = Math.max(
    metrics.clicked,
    asNumber(
      firstDefined(
        delivery.clickedToday,
        delivery.clicked_today,
        delivery.clicked,
        0,
      ),
    ),
  );

  return metrics;
}

function renderDelivery() {
  const metrics =
    calculateDeliveryMetrics();

  els.sentMetric.textContent =
    String(metrics.sent);

  els.deliveredMetric.textContent =
    String(metrics.delivered);

  els.openedMetric.textContent =
    String(metrics.opened);

  els.clickedMetric.textContent =
    String(metrics.clicked);

  const maximum = Math.max(
    metrics.sent,
    metrics.delivered,
    metrics.opened,
    metrics.clicked,
    1,
  );

  const values = [
    0,
    0,
    Math.min(maximum, metrics.sent),
    Math.min(maximum, metrics.delivered),
    Math.min(maximum, metrics.opened),
    Math.min(maximum, metrics.clicked),
    Math.min(
      maximum,
      Math.max(
        metrics.sent,
        metrics.delivered,
      ),
    ),
  ];

  const points = values.map(
    (value, index) => {
      const x =
        45 +
        index *
          ((540 - 45) / (values.length - 1));

      const y =
        175 -
        (value / maximum) * 135;

      return `${x.toFixed(1)},${y.toFixed(1)}`;
    },
  );

  els.deliveryChartLine.setAttribute(
    "points",
    points.join(" "),
  );

  els.lastRefreshValue.textContent =
    new Date().toLocaleTimeString();
}

function renderDashboard() {
  const root =
    statusRoot(APP.statusPayload);

  APP.settings =
    normalizedSettings(APP.statusPayload);

  const enabled = asBoolean(
    firstDefined(
      APP.settings.enabled,
      root.enabled,
      root.canDraft,
      true,
    ),
    true,
  );

  const paused = asBoolean(
    firstDefined(
      APP.settings.paused,
      APP.settings.emergencyPaused,
      root.paused,
      root.emergencyPaused,
      false,
    ),
  );

  const mode = String(
    firstDefined(
      APP.settings.mode,
      APP.settings.operatingMode,
      root.mode,
      "",
    ),
  ).toLowerCase();

  const autopilot = asBoolean(
    firstDefined(
      APP.settings.autopilotEnabled,
      root.autopilotEnabled,
      root.canAutopilot,
      mode === "autopilot",
    ),
    mode === "autopilot",
  );

  const webhook = asBoolean(
    firstDefined(
      root.webhookEnabled,
      root.webhook?.enabled,
      APP.delivery.webhookEnabled,
      true,
    ),
    true,
  );

  const dailyCap = Math.max(
    1,
    asNumber(
      firstDefined(
        APP.settings.dailySendCap,
        APP.settings.daily_send_cap,
        root.dailySendCap,
        APP.delivery.dailySendCap,
        5,
      ),
      5,
    ),
  );

  const metrics =
    calculateDeliveryMetrics();

  const used = Math.min(
    dailyCap,
    Math.max(
      metrics.sent,
      asNumber(
        firstDefined(
          root.sentToday,
          APP.delivery.sentToday,
          0,
        ),
      ),
    ),
  );

  setTopStatus({
    operational: enabled,
    webhook,
    autopilot,
    paused,
    dailyCap,
  });

  els.dailyCapLabel.textContent =
    `${dailyCap} emails per day`;

  els.dailyCapUsage.textContent =
    `${used} / ${dailyCap} used`;

  els.dailyCapProgress.style.width =
    `${Math.min(
      100,
      (used / dailyCap) * 100,
    )}%`;

  els.quietHoursValue.textContent =
    firstDefined(
      APP.settings.quietHoursLabel,
      APP.settings.quiet_hours_label,
      "10:00 PM – 6:00 AM",
    );

  renderRecipients();
  renderDrafts();
  renderEvents();
  renderDelivery();
}

async function loadHealth() {
  try {
    const response = await fetch(
      `${APP.apiBase}/api/health`,
      {
        headers: {
          Accept: "application/json",
        },
      },
    );

    const payload =
      await response.json();

    if (!response.ok) {
      throw new Error(
        `Health HTTP ${response.status}`,
      );
    }

    const supabaseConfigured =
      payload.supabaseConfigured === true;

    const supabaseAuthConfigured =
      payload.supabaseAuthConfigured === true;

    setHealth(
      els.healthApi,
      "OPERATIONAL",
    );

    setHealth(
      els.healthDatabase,
      supabaseConfigured
        ? "OPERATIONAL"
        : "CHECK CONFIG",
    );

    setHealth(
      els.healthEmail,
      supabaseAuthConfigured
        ? "OPERATIONAL"
        : "CHECK CONFIG",
    );

    setHealth(
      els.healthWebhook,
      "OPERATIONAL",
    );

    setHealth(
      els.healthAutopilot,
      "OPERATIONAL",
    );

    setHealth(
      els.healthLimits,
      "OPERATIONAL",
    );

    return true;
  } catch (error) {
    [
      els.healthApi,
      els.healthDatabase,
      els.healthEmail,
      els.healthWebhook,
      els.healthAutopilot,
      els.healthLimits,
    ].forEach(
      (element) =>
        setHealth(
          element,
          "UNAVAILABLE",
        ),
    );

    throw error;
  }
}

async function settledRequest(
  path,
  preferredKeys,
) {
  try {
    const payload = await requestJson(
      path,
    );

    return {
      payload,
      list: findList(
        payload,
        preferredKeys,
      ),
      error: null,
    };
  } catch (error) {
    return {
      payload: null,
      list: [],
      error,
    };
  }
}

async function refreshDashboard({
  silent = false,
} = {}) {
  if (
    !APP.token ||
    !APP.agentId
  ) {
    if (!silent) {
      showModal("connectionModal");
    }

    return;
  }

  els.refreshButton.disabled = true;

  setConnectedState(
    true,
    `Nova · ${APP.agentId}`,
  );

  const base = emailBase();

  const [
    statusResult,
    recipientResult,
    draftResult,
    deliveryResult,
    eventResult,
    ruleResult,
    healthResult,
  ] = await Promise.all([
    settledRequest(
      `${base}/status`,
      [],
    ),

    settledRequest(
      `${base}/recipients?limit=100`,
      ["recipients"],
    ),

    settledRequest(
      `${base}/drafts?limit=100`,
      ["drafts", "messages"],
    ),

    settledRequest(
      `${base}/delivery/status`,
      [],
    ),

    settledRequest(
      `${base}/events?limit=100`,
      ["events"],
    ),

    settledRequest(
      `${base}/rules?limit=100`,
      ["rules"],
    ),

    loadHealth().catch(
      (error) => ({
        error,
      }),
    ),
  ]);

  APP.statusPayload =
    statusResult.payload || {};

  APP.recipients =
    recipientResult.list;

  APP.drafts =
    draftResult.list;

  APP.delivery =
    firstDefined(
      deliveryResult.payload?.status,
      deliveryResult.payload?.deliveryStatus,
      deliveryResult.payload?.data,
      deliveryResult.payload,
      {},
    );

  APP.events =
    eventResult.list;

  APP.rules =
    ruleResult.list;

  const criticalError =
    statusResult.error;

  if (criticalError) {
    setConnectedState(
      false,
      "Connection failed",
    );

    setTopStatus({
      operational: false,
      webhook: false,
      autopilot: false,
      paused: true,
      dailyCap: 5,
    });

    if (!silent) {
      toast(
        criticalError.message,
        "error",
      );
    }

    els.refreshButton.disabled = false;

    return;
  }

  renderDashboard();

  const optionalErrors = [
    recipientResult,
    draftResult,
    deliveryResult,
    eventResult,
    ruleResult,
    healthResult,
  ].filter(
    (result) => result?.error,
  );

  if (
    optionalErrors.length &&
    !silent
  ) {
    toast(
      `Connected. ${optionalErrors.length} optional panel request(s) could not be loaded.`,
    );
  } else if (!silent) {
    toast(
      "Nova Email production data refreshed.",
      "success",
    );
  }

  els.refreshButton.disabled = false;
}

function fullSettingsPayload(patch) {
  const current =
    APP.settings || {};

  const payload = {
    confirmed: true,
    confirmation: true,

    enabled: asBoolean(
      firstDefined(
        current.enabled,
        true,
      ),
      true,
    ),

    mode: firstDefined(
      current.mode,
      current.operatingMode,
      "approval_required",
    ),

    paused: asBoolean(
      firstDefined(
        current.paused,
        false,
      ),
    ),

    dailySendCap: Math.max(
      1,
      asNumber(
        firstDefined(
          current.dailySendCap,
          current.daily_send_cap,
          5,
        ),
        5,
      ),
    ),

    maxFollowUps: Math.max(
      0,
      asNumber(
        firstDefined(
          current.maxFollowUps,
          current.max_follow_ups,
          0,
        ),
        0,
      ),
    ),

    ...patch,
  };

  const fromEmail = firstDefined(
    current.fromEmail,
    current.from_email,
  );

  const replyToEmail = firstDefined(
    current.replyToEmail,
    current.reply_to_email,
  );

  if (fromEmail) {
    payload.fromEmail = fromEmail;
  }

  if (replyToEmail) {
    payload.replyToEmail =
      replyToEmail;
  }

  return payload;
}

async function updateSettings(patch) {
  const path =
    `${emailBase()}/settings`;

  const payload =
    fullSettingsPayload(patch);

  try {
    return await requestJson(
      path,
      {
        method: "PATCH",
        body: JSON.stringify(payload),
      },
    );
  } catch (error) {
    if (
      ![404, 405].includes(
        error.status,
      )
    ) {
      throw error;
    }

    return requestJson(
      path,
      {
        method: "PUT",
        body: JSON.stringify(payload),
      },
    );
  }
}

async function setPaused(paused) {
  const phrase = paused
    ? "PAUSE NOVA"
    : "RESUME NOVA";

  const confirmation = prompt(
    `Type ${phrase} to continue.`,
  );

  if (confirmation !== phrase) {
    return;
  }

  els.pauseSystemButton.disabled = true;

  try {
    await updateSettings({
      paused,
    });

    toast(
      paused
        ? "Nova Agent Email is paused."
        : "Nova Agent Email is active.",
      "success",
    );

    await refreshDashboard({
      silent: true,
    });
  } catch (error) {
    toast(
      error.message,
      "error",
    );
  } finally {
    els.pauseSystemButton.disabled = false;
  }
}

async function setAutopilot(enabled) {
  const phrase = enabled
    ? "ENABLE AUTOPILOT"
    : "STOP AUTOPILOT";

  const confirmation = prompt(
    `Type ${phrase} to continue.`,
  );

  if (confirmation !== phrase) {
    els.autopilotToggle.checked =
      !enabled;

    return;
  }

  els.autopilotToggle.disabled = true;
  els.stopAutopilotButton.disabled = true;

  try {
    await updateSettings({
      mode: enabled
        ? "autopilot"
        : "approval_required",

      autopilotEnabled: enabled,
    });

    toast(
      enabled
        ? "Nova Autopilot is enabled."
        : "Nova Autopilot is stopped.",
      "success",
    );

    await refreshDashboard({
      silent: true,
    });
  } catch (error) {
    els.autopilotToggle.checked =
      !enabled;

    toast(
      error.message,
      "error",
    );
  } finally {
    els.autopilotToggle.disabled = false;
  }
}

async function addRecipient(event) {
  event.preventDefault();

  setMessage(
    els.recipientMessage,
    "Saving approved recipient…",
  );

  const email =
    els.recipientEmailInput
      .value
      .trim()
      .toLowerCase();

  const name =
    els.recipientNameInput
      .value
      .trim();

  if (
    !email ||
    !name ||
    !els.recipientPermissionInput.checked
  ) {
    setMessage(
      els.recipientMessage,
      "Complete every field and confirm permission.",
      "error",
    );

    return;
  }

  const body = {
    confirmed: true,
    confirmation: true,

    name,
    displayName: name,

    email,

    sourceKind: "user_entered",
    sourceReference:
      "korlix-nova-email-web-control-center",

    consentStatus:
      "transactional_only",

    active: true,
  };

  try {
    await requestJson(
      `${emailBase()}/recipients`,
      {
        method: "POST",
        body: JSON.stringify(body),
      },
    );

    setMessage(
      els.recipientMessage,
      "Recipient saved successfully.",
      "success",
    );

    els.recipientForm.reset();

    await refreshDashboard({
      silent: true,
    });

    setTimeout(
      () => closeModal("recipientModal"),
      600,
    );
  } catch (error) {
    setMessage(
      els.recipientMessage,
      error.message,
      "error",
    );
  }
}

function recipientById(id) {
  return APP.recipients
    .map(normalizeRecipient)
    .find(
      (recipient) =>
        String(recipient.id) ===
        String(id),
    );
}

async function createDraft(event) {
  event.preventDefault();

  setMessage(
    els.draftMessage,
    "Saving Agent Email draft…",
  );

  const recipientId =
    els.draftRecipientInput.value;

  const recipient =
    recipientById(recipientId);

  const subject =
    els.draftSubjectInput
      .value
      .trim();

  const text =
    els.draftBodyInput
      .value
      .trim();

  if (
    !recipient ||
    !subject ||
    !text ||
    !els.draftTransactionalInput.checked
  ) {
    setMessage(
      els.draftMessage,
      "Select an approved recipient, complete the draft, and confirm it is transactional.",
      "error",
    );

    return;
  }

  const html = text
    .split(/\n{2,}/)
    .map(
      (paragraph) =>
        `<p>${escapeHtml(paragraph)
          .replaceAll("\n", "<br>")}</p>`,
    )
    .join("");

  const clientReference =
    `nova-web-${crypto.randomUUID()}`;

  const body = {
    confirmed: true,
    confirmation: true,

    recipientId: recipient.id,
    recipient_id: recipient.id,

    recipientEmail: recipient.email,
    recipientName: recipient.name,

    subject,
    subjectLine: subject,

    textBody: text,
    bodyText: text,
    body: text,

    htmlBody: html,
    bodyHtml: html,

    marketing: false,
    isMarketing: false,
    purpose: "transactional",

    clientReference,
    idempotencyKey: clientReference,
  };

  try {
    await requestJson(
      `${emailBase()}/drafts`,
      {
        method: "POST",
        body: JSON.stringify(body),
      },
    );

    setMessage(
      els.draftMessage,
      "Draft saved successfully.",
      "success",
    );

    els.draftForm.reset();

    await refreshDashboard({
      silent: true,
    });

    setTimeout(
      () => closeModal("draftModal"),
      600,
    );
  } catch (error) {
    setMessage(
      els.draftMessage,
      error.message,
      "error",
    );
  }
}

function openDraftDetails(id) {
  const draft = APP.drafts
    .map(normalizeDraft)
    .find(
      (item) =>
        String(item.id) ===
        String(id),
    );

  if (!draft) {
    toast(
      "The selected draft could not be found.",
      "error",
    );

    return;
  }

  APP.selectedDraft = draft;

  els.draftDetails.textContent = [
    `Subject: ${draft.subject}`,
    `Recipient: ${
      draft.recipientEmail ||
      draft.recipientName ||
      "Approved recipient"
    }`,
    `Status: ${draft.status}`,
    "",
    draft.text ||
    "HTML email draft available.",
  ].join("\n");

  setMessage(
    els.detailsMessage,
    "",
  );

  showModal("detailsModal");
}

async function approvalRequest(
  draftId,
) {
  const body = {
    confirmed: true,
    confirmation: true,
    approved: true,
    approvalStatus: "approved",
    status: "approved",
  };

  const candidates = [
    {
      path:
        `${emailBase()}/drafts/` +
        `${encodeURIComponent(draftId)}/approve`,
      method: "POST",
    },

    {
      path:
        `${emailBase()}/drafts/` +
        `${encodeURIComponent(draftId)}/approval`,
      method: "PATCH",
    },

    {
      path:
        `${emailBase()}/drafts/` +
        `${encodeURIComponent(draftId)}`,
      method: "PATCH",
    },
  ];

  let lastError = null;

  for (const candidate of candidates) {
    try {
      return await requestJson(
        candidate.path,
        {
          method: candidate.method,
          body: JSON.stringify(body),
        },
      );
    } catch (error) {
      lastError = error;

      if (
        ![404, 405].includes(
          error.status,
        )
      ) {
        throw error;
      }
    }
  }

  throw (
    lastError ||
    new Error(
      "The production approval route was not available.",
    )
  );
}

async function approveAndSendDraft() {
  const draft =
    APP.selectedDraft;

  if (!draft?.id) {
    return;
  }

  const phrase =
    "APPROVE AND SEND";

  const confirmation = prompt(
    `Type ${phrase} to send this real production email.`,
  );

  if (confirmation !== phrase) {
    return;
  }

  els.approveSendButton.disabled = true;

  setMessage(
    els.detailsMessage,
    "Recording approval…",
  );

  try {
    await approvalRequest(
      draft.id,
    );

    setMessage(
      els.detailsMessage,
      "Approval recorded. Sending through the production Agent Email provider…",
    );

    const nonce =
      crypto.randomUUID();

    const result = await requestJson(
      `${emailBase()}/drafts/` +
      `${encodeURIComponent(draft.id)}/send`,
      {
        method: "POST",
        body: JSON.stringify({
          confirmed: true,
          confirmation: true,
          confirmationNonce: nonce,
          confirmation_nonce: nonce,
          idempotencyKey: nonce,
        }),
      },
    );

    const providerId = firstDefined(
      result.providerMessageId,
      result.provider_message_id,
      result.message?.providerMessageId,
      result.messageId,
      "recorded",
    );

    setMessage(
      els.detailsMessage,
      `Email sent successfully. Provider reference: ${providerId}`,
      "success",
    );

    toast(
      "Nova sent the approved production email.",
      "success",
    );

    await refreshDashboard({
      silent: true,
    });
  } catch (error) {
    setMessage(
      els.detailsMessage,
      error.message,
      "error",
    );
  } finally {
    els.approveSendButton.disabled = false;
  }
}

async function connectSession() {
  setMessage(
    els.connectionMessage,
    "Looking for the active KORLIX session…",
  );

  APP.apiBase =
    els.apiBaseInput.value
      .trim()
      .replace(/\/+$/, "") ||
    APP.apiBase;

  APP.token =
    findSessionToken();

  APP.agentId =
    els.agentIdInput.value.trim() ||
    findStoredAgentId();

  if (!APP.token) {
    setMessage(
      els.connectionMessage,
      "No active KORLIX browser session was found. Open KORLIX Login, sign in, then return to this page and press Connect Session.",
      "error",
    );

    return;
  }

  if (!APP.agentId) {
    setMessage(
      els.connectionMessage,
      "Searching your KORLIX Agent Hub for Nova…",
    );

    APP.agentId =
      await discoverNovaAgent();
  }

  if (!APP.agentId) {
    setMessage(
      els.connectionMessage,
      "Nova was not discovered automatically. Enter Nova’s Agent Hub ID in the field above.",
      "error",
    );

    return;
  }

  localStorage.setItem(
    "korlixNovaEmailApiBase",
    APP.apiBase,
  );

  localStorage.setItem(
    "korlixNovaEmailAgentId",
    APP.agentId,
  );

  els.agentIdInput.value =
    APP.agentId;

  setMessage(
    els.connectionMessage,
    "Session found. Loading production Agent Email data…",
    "success",
  );

  await refreshDashboard({
    silent: true,
  });

  if (APP.connected) {
    setTimeout(
      () => closeModal("connectionModal"),
      500,
    );
  }
}

function scrollToPanel(id) {
  closeMobileSidebar();

  document
    .getElementById(id)
    ?.scrollIntoView({
      behavior: "smooth",
      block: "start",
    });
}

function closeMobileSidebar() {
  els.sidebar.classList.remove("open");
}

function updateClock() {
  const now = new Date();

  $("#systemDate").textContent =
    new Intl.DateTimeFormat(
      undefined,
      {
        month: "short",
        day: "numeric",
        year: "numeric",
      },
    ).format(now);

  $("#systemTime").textContent =
    new Intl.DateTimeFormat(
      undefined,
      {
        hour: "numeric",
        minute: "2-digit",
        second: "2-digit",
        timeZoneName: "short",
      },
    ).format(now);
}

function bindEvents() {
  els.mobileMenuButton.addEventListener(
    "click",
    () =>
      els.sidebar.classList.toggle("open"),
  );

  els.connectionButton.addEventListener(
    "click",
    () => {
      els.agentIdInput.value =
        APP.agentId;

      els.apiBaseInput.value =
        APP.apiBase;

      showModal("connectionModal");
    },
  );

  els.connectSessionButton.addEventListener(
    "click",
    connectSession,
  );

  els.openKorlixAppButton.addEventListener(
    "click",
    () => {
      location.href = "/app/";
    },
  );

  els.refreshButton.addEventListener(
    "click",
    () => refreshDashboard(),
  );

  els.createDraftButton.addEventListener(
    "click",
    () => {
      if (!APP.connected) {
        showModal("connectionModal");

        return;
      }

      showModal("draftModal");
    },
  );

  els.pauseSystemButton.addEventListener(
    "click",
    () => {
      const currentlyPaused =
        asBoolean(
          firstDefined(
            APP.settings.paused,
            false,
          ),
        );

      setPaused(
        !currentlyPaused,
      );
    },
  );

  els.stopAutopilotButton.addEventListener(
    "click",
    () => setAutopilot(false),
  );

  els.autopilotToggle.addEventListener(
    "change",
    () => setAutopilot(
      els.autopilotToggle.checked,
    ),
  );

  [
    "#manageRecipientsButton",
    "#manageRecipientsFooterButton",
  ].forEach(
    (selector) =>
      $(selector).addEventListener(
        "click",
        () => {
          if (!APP.connected) {
            showModal("connectionModal");

            return;
          }

          showModal("recipientModal");
        },
      ),
  );

  [
    "#viewDraftsButton",
    "#viewDraftsFooterButton",
  ].forEach(
    (selector) =>
      $(selector).addEventListener(
        "click",
        () => scrollToPanel("draftsPanel"),
      ),
  );

  [
    "#viewLogsButton",
    "#viewLogsFooterButton",
  ].forEach(
    (selector) =>
      $(selector).addEventListener(
        "click",
        () => scrollToPanel("logsPanel"),
      ),
  );

  [
    "#viewHealthButton",
    "#viewHealthFooterButton",
  ].forEach(
    (selector) =>
      $(selector).addEventListener(
        "click",
        () =>
          Promise.allSettled([
            loadHealth(),
            refreshDashboard({
              silent: true,
            }),
          ]),
      ),
  );

  els.recipientForm.addEventListener(
    "submit",
    addRecipient,
  );

  els.draftForm.addEventListener(
    "submit",
    createDraft,
  );

  els.approveSendButton.addEventListener(
    "click",
    approveAndSendDraft,
  );

  $$("[data-close-modal]").forEach(
    (button) =>
      button.addEventListener(
        "click",
        () => closeModal(
          button.dataset.closeModal,
        ),
      ),
  );

  $$(".modal-backdrop").forEach(
    (modal) =>
      modal.addEventListener(
        "click",
        (event) => {
          if (event.target === modal) {
            closeModal(modal.id);
          }
        },
      ),
  );

  $$(".nav-item").forEach(
    (button) =>
      button.addEventListener(
        "click",
        () => {
          $$(".nav-item").forEach(
            (item) =>
              item.classList.remove("active"),
          );

          button.classList.add("active");

          const mapping = {
            command: "commandPanel",
            drafts: "draftsPanel",
            recipients: "recipientsPanel",
            templates: "draftsPanel",
            analytics: "analyticsPanel",
            logs: "logsPanel",
            settings: "commandPanel",
            integrations: "healthPanel",
            health: "healthPanel",
          };

          scrollToPanel(
            mapping[button.dataset.section] ||
            "commandPanel",
          );
        },
      ),
  );

  document.addEventListener(
    "keydown",
    (event) => {
      if (event.key === "Escape") {
        $$(".modal-backdrop").forEach(
          (modal) =>
            modal.classList.add("hidden"),
        );

        closeMobileSidebar();
      }
    },
  );
}

async function boot() {
  bindEvents();

  updateClock();

  setInterval(
    updateClock,
    1000,
  );

  APP.token =
    findSessionToken();

  APP.agentId =
    findStoredAgentId();

  els.agentIdInput.value =
    APP.agentId;

  els.apiBaseInput.value =
    APP.apiBase;

  if (
    APP.token &&
    APP.agentId
  ) {
    await refreshDashboard({
      silent: true,
    });

    return;
  }

  if (
    APP.token &&
    !APP.agentId
  ) {
    APP.agentId =
      await discoverNovaAgent();

    if (APP.agentId) {
      localStorage.setItem(
        "korlixNovaEmailAgentId",
        APP.agentId,
      );

      els.agentIdInput.value =
        APP.agentId;

      await refreshDashboard({
        silent: true,
      });

      return;
    }
  }

  setConnectedState(
    false,
    "Connect KORLIX session",
  );

  showModal("connectionModal");

  loadHealth().catch(() => {});
}

// K133_NOVA_EMAIL_WEB_AUTH_LOGO_FIX_V2_BEGIN
const KORLIX_NOVA_EMAIL_FIX_VERSION_V2 = "2026-08-25-auth-logo-v2";

APP.refreshToken = null;
APP.userEmail = null;
APP.deviceId = null;
APP.deviceLabel = "Nova Email Web Control Center";

function korlixParseStoredValueV2(raw) {
  if (raw === null || raw === undefined) {
    return null;
  }

  let value = raw;

  for (let attempt = 0; attempt < 4; attempt += 1) {
    if (typeof value !== "string") {
      break;
    }

    const trimmed = value.trim();

    if (!trimmed) {
      return "";
    }

    try {
      const parsed = JSON.parse(trimmed);

      if (parsed === value) {
        break;
      }

      value = parsed;
    } catch {
      break;
    }
  }

  return value;
}

function korlixStorageEntriesV2() {
  const output = [];

  for (const storage of [localStorage, sessionStorage]) {
    try {
      for (let index = 0; index < storage.length; index += 1) {
        const key = storage.key(index);

        if (!key) {
          continue;
        }

        output.push({
          storage,
          key,
          value: storage.getItem(key),
        });
      }
    } catch {
      // Browser privacy settings can block one storage area.
    }
  }

  return output;
}

function korlixStoredStringV2(names) {
  const requested = new Set(
    names.map((name) => String(name).toLowerCase()),
  );

  for (const item of korlixStorageEntriesV2()) {
    const lowerKey = String(item.key).toLowerCase();
    const matches = [...requested].some(
      (name) =>
        lowerKey === name ||
        lowerKey === `flutter.${name}` ||
        lowerKey.endsWith(`.${name}`) ||
        lowerKey.endsWith(`:${name}`),
    );

    if (!matches) {
      continue;
    }

    const parsed = korlixParseStoredValueV2(item.value);

    if (typeof parsed === "string" && parsed.trim()) {
      return parsed.trim();
    }
  }

  return "";
}

function korlixOwnSessionValueV2(key) {
  try {
    return String(localStorage.getItem(key) || "").trim();
  } catch {
    return "";
  }
}

function korlixReadSessionBundleV2() {
  const accessToken = firstDefined(
    korlixOwnSessionValueV2("korlixNovaEmailAccessTokenV2"),
    korlixStoredStringV2([
      "korlix_access_token",
      "access_token",
      "accessToken",
    ]),
    findSessionToken(),
    "",
  );

  const refreshToken = firstDefined(
    korlixOwnSessionValueV2("korlixNovaEmailRefreshTokenV2"),
    korlixStoredStringV2([
      "korlix_refresh_token",
      "refresh_token",
      "refreshToken",
    ]),
    "",
  );

  const email = firstDefined(
    korlixOwnSessionValueV2("korlixNovaEmailUserEmailV2"),
    korlixStoredStringV2([
      "korlix_user_email",
      "user_email",
      "email",
    ]),
    "",
  );

  return {
    accessToken: String(accessToken || "").trim(),
    refreshToken: String(refreshToken || "").trim(),
    email: String(email || "").trim(),
  };
}

function korlixPersistOwnSessionV2(bundle) {
  try {
    if (bundle.accessToken) {
      localStorage.setItem(
        "korlixNovaEmailAccessTokenV2",
        bundle.accessToken,
      );
    }

    if (bundle.refreshToken) {
      localStorage.setItem(
        "korlixNovaEmailRefreshTokenV2",
        bundle.refreshToken,
      );
    }

    if (bundle.email) {
      localStorage.setItem(
        "korlixNovaEmailUserEmailV2",
        bundle.email,
      );
    }
  } catch {
    // In-memory session remains usable when browser storage is unavailable.
  }
}

function korlixJwtSecondsRemainingV2(token) {
  const payload = decodeJwtPayload(token);

  if (!payload?.exp) {
    return 0;
  }

  return Math.floor(Number(payload.exp) - Date.now() / 1000);
}

function korlixEnsureDeviceV2() {
  const storedDeviceId = firstDefined(
    korlixOwnSessionValueV2("korlixNovaEmailDeviceIdV2"),
    korlixStoredStringV2([
      "korlix_device_id",
      "device_id",
    ]),
    "",
  );

  APP.deviceId = String(storedDeviceId || "").trim();

  if (!APP.deviceId) {
    APP.deviceId =
      `korlix_web_${Date.now()}_` +
      Math.random().toString(36).slice(2, 12);

    try {
      localStorage.setItem(
        "korlixNovaEmailDeviceIdV2",
        APP.deviceId,
      );
    } catch {
      // In-memory device ID is sufficient for this page load.
    }
  }

  APP.deviceLabel = firstDefined(
    korlixStoredStringV2([
      "korlix_device_label",
      "device_label",
    ]),
    APP.deviceLabel,
  );
}

function korlixAuthHeadersV2(extra = {}) {
  korlixEnsureDeviceV2();

  return {
    Accept: "application/json",
    ...(APP.token
      ? { Authorization: `Bearer ${APP.token}` }
      : {}),
    "X-Korlix-Device-Id": APP.deviceId,
    "X-Korlix-Device-Label": APP.deviceLabel,
    "X-Korlix-Platform": "web",
    ...(APP.userEmail
      ? { "X-Korlix-User-Email": APP.userEmail }
      : {}),
    ...extra,
  };
}

async function korlixFetchWithTimeoutV2(
  url,
  options = {},
  timeoutMilliseconds = 25000,
) {
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    timeoutMilliseconds,
  );

  try {
    return await fetch(url, {
      ...options,
      signal: controller.signal,
    });
  } catch (error) {
    if (error?.name === "AbortError") {
      throw new Error(
        "The production request timed out. Please try Connect Session again.",
      );
    }

    throw error;
  } finally {
    clearTimeout(timer);
  }
}

function korlixResponseErrorV2(response, payload) {
  const message = firstDefined(
    payload?.message,
    payload?.error,
    payload?.detail,
    payload?.code,
    `Request failed with HTTP ${response.status}.`,
  );

  const error = new Error(String(message));
  error.status = response.status;
  error.payload = payload;
  error.code = firstDefined(
    payload?.code,
    payload?.errorCode,
    payload?.error_code,
    "",
  );

  return error;
}

async function korlixReadJsonResponseV2(response) {
  const text = await response.text();

  if (!text) {
    return {};
  }

  try {
    return JSON.parse(text);
  } catch {
    return { message: text };
  }
}

async function korlixRefreshSessionV2(bundle, force = false) {
  korlixEnsureDeviceV2();

  let session = {
    accessToken: String(bundle?.accessToken || "").trim(),
    refreshToken: String(bundle?.refreshToken || "").trim(),
    email: String(bundle?.email || "").trim(),
  };

  const shouldRefresh = Boolean(
    session.refreshToken &&
      (force ||
        !tokenUsable(session.accessToken) ||
        korlixJwtSecondsRemainingV2(session.accessToken) < 600),
  );

  if (shouldRefresh) {
    const response = await korlixFetchWithTimeoutV2(
      `${APP.apiBase}/api/auth/refresh`,
      {
        method: "POST",
        headers: korlixAuthHeadersV2({
          "Content-Type": "application/json",
        }),
        body: JSON.stringify({
          refresh_token: session.refreshToken,
          device_id: APP.deviceId,
          device_label: APP.deviceLabel,
          platform: "web",
        }),
      },
      30000,
    );

    const payload = await korlixReadJsonResponseV2(response);

    if (!response.ok) {
      if (!tokenUsable(session.accessToken)) {
        throw korlixResponseErrorV2(response, payload);
      }
    } else {
      const refreshed = payload?.session || {};

      session = {
        accessToken: String(
          refreshed.access_token || session.accessToken || "",
        ).trim(),
        refreshToken: String(
          refreshed.refresh_token || session.refreshToken || "",
        ).trim(),
        email: String(
          payload?.user?.email || session.email || "",
        ).trim(),
      };
    }
  }

  if (!tokenUsable(session.accessToken)) {
    throw new Error(
      "Your KORLIX browser session has expired. Open KORLIX Login, sign in again, then return and press Connect Session.",
    );
  }

  APP.token = session.accessToken;
  APP.refreshToken = session.refreshToken;
  APP.userEmail = session.email;

  korlixPersistOwnSessionV2(session);

  return session;
}

findSessionToken = function findSessionTokenV2() {
  const own = korlixOwnSessionValueV2(
    "korlixNovaEmailAccessTokenV2",
  );

  if (tokenUsable(own)) {
    return own;
  }

  const explicit = korlixStoredStringV2([
    "korlix_access_token",
    "access_token",
    "accessToken",
  ]);

  if (tokenUsable(explicit)) {
    return explicit;
  }

  for (const item of korlixStorageEntriesV2()) {
    const token = searchObjectForToken(item.value);

    if (tokenUsable(token)) {
      return token;
    }
  }

  return null;
};

requestJson = async function requestJsonV2(path, options = {}) {
  if (!APP.token) {
    throw new Error(
      "No authenticated KORLIX browser session was found.",
    );
  }

  const url = path.startsWith("http")
    ? path
    : `${APP.apiBase}${path}`;

  const response = await korlixFetchWithTimeoutV2(
    url,
    {
      ...options,
      headers: korlixAuthHeadersV2({
        ...(options.body
          ? { "Content-Type": "application/json" }
          : {}),
        ...(options.headers || {}),
      }),
    },
    Number(options.timeoutMilliseconds || 25000),
  );

  const payload = await korlixReadJsonResponseV2(response);

  if (!response.ok) {
    throw korlixResponseErrorV2(response, payload);
  }

  return payload;
};

function korlixAgentRecordV2(row) {
  if (!row || typeof row !== "object") {
    return {};
  }

  return firstDefined(
    row.agent,
    row.profile,
    row.data,
    row,
    {},
  );
}

function korlixAgentScoreV2(row) {
  const record = korlixAgentRecordV2(row);
  const id = String(
    firstDefined(
      record.agentId,
      record.agent_id,
      record.id,
      row.agentId,
      row.agent_id,
      row.id,
      "",
    ),
  ).trim();

  const name = String(
    firstDefined(
      record.name,
      record.displayName,
      record.display_name,
      record.title,
      record.agentName,
      row.name,
      "",
    ),
  ).toLowerCase();

  const toolValues = firstDefined(
    record.toolIds,
    record.tool_ids,
    record.tools,
    row.toolIds,
    row.tool_ids,
    row.tools,
    [],
  );

  const tools = Array.isArray(toolValues)
    ? toolValues.map((value) =>
        String(
          value?.id || value?.toolId || value,
        ).toLowerCase(),
      )
    : [String(toolValues).toLowerCase()];

  let score = 0;

  if (name.includes("nova")) score += 120;
  if (id.toLowerCase().includes("nova")) score += 80;
  if (id === "custom_nova") score += 20;
  if (tools.some((tool) => tool.includes("agent_email"))) score += 60;

  if (
    asBoolean(
      firstDefined(
        record.isCustom,
        record.is_custom,
        record.custom,
        row.isCustom,
        row.is_custom,
        false,
      ),
      false,
    )
  ) {
    score += 30;
  }

  if (
    asBoolean(
      firstDefined(
        record.active,
        record.isActive,
        record.is_active,
        row.active,
        row.isActive,
        true,
      ),
      true,
    )
  ) {
    score += 10;
  }

  return { id, name, score, row };
}

discoverNovaAgent = async function discoverNovaAgentV2() {
  const payload = await requestJson(
    "/api/live-convo/agents",
  );

  const agents = findList(payload, [
    "agents",
    "profiles",
  ]);

  const ranked = agents
    .map(korlixAgentScoreV2)
    .filter((candidate) => candidate.id && candidate.score > 0)
    .sort((left, right) => right.score - left.score);

  return ranked[0]?.id || "";
};

function korlixConnectionErrorTextV2(error) {
  const code = firstDefined(
    error?.code,
    error?.payload?.code,
    error?.payload?.errorCode,
    "",
  );

  const status = Number(error?.status || 0);
  const parts = [];

  if (status) {
    parts.push(`HTTP ${status}`);
  }

  if (code) {
    parts.push(String(code));
  }

  parts.push(
    String(error?.message || "Production Agent Email connection failed."),
  );

  return parts.join(" — ");
}

function korlixNovaBindingErrorV2(error) {
  const code = String(
    firstDefined(
      error?.code,
      error?.payload?.code,
      "",
    ),
  ).toLowerCase();

  const message = String(error?.message || "").toLowerCase();

  return (
    code.includes("existing_nova") ||
    code.includes("custom_active_nova") ||
    code.includes("tool_not_authorized") ||
    message.includes("existing nova") ||
    message.includes("selected nova")
  );
}

async function korlixValidateLoginV2() {
  const payload = await requestJson(
    "/api/me",
    { timeoutMilliseconds: 25000 },
  );

  APP.userEmail = String(
    firstDefined(
      payload?.user?.email,
      payload?.profile?.email,
      APP.userEmail,
      "",
    ),
  ).trim();

  korlixPersistOwnSessionV2({
    accessToken: APP.token,
    refreshToken: APP.refreshToken,
    email: APP.userEmail,
  });

  return payload;
}

refreshDashboard = async function refreshDashboardV2(
  { silent = false, statusPayload = null } = {},
) {
  if (!APP.token || !APP.agentId) {
    setMessage(
      els.connectionMessage,
      "A valid signed-in KORLIX session and Nova Agent ID are required.",
      "error",
    );
    showModal("connectionModal");
    return false;
  }

  els.refreshButton.disabled = true;
  setConnectedState(true, "Connecting to Nova…");

  const base = emailBase();

  const [
    statusResult,
    recipientResult,
    draftResult,
    deliveryResult,
    eventResult,
    ruleResult,
    healthResult,
  ] = await Promise.all([
    statusPayload
      ? Promise.resolve({
          payload: statusPayload,
          list: [],
          error: null,
        })
      : settledRequest(`${base}/status`, []),
    settledRequest(`${base}/recipients?limit=100`, ["recipients"]),
    settledRequest(`${base}/drafts?limit=100`, ["drafts", "messages"]),
    settledRequest(`${base}/delivery/status`, []),
    settledRequest(`${base}/events?limit=100`, ["events"]),
    settledRequest(`${base}/rules?limit=100`, ["rules"]),
    loadHealth().catch((error) => ({ error })),
  ]);

  if (statusResult.error) {
    const message = korlixConnectionErrorTextV2(statusResult.error);

    setConnectedState(false, "Connection failed");
    setTopStatus({
      operational: false,
      webhook: false,
      autopilot: false,
      paused: true,
      dailyCap: 5,
    });

    setMessage(
      els.connectionMessage,
      `Connection failed: ${message}`,
      "error",
    );

    showModal("connectionModal");

    if (!silent) {
      toast(message, "error");
    }

    els.refreshButton.disabled = false;
    return false;
  }

  APP.statusPayload = statusResult.payload || {};
  APP.recipients = recipientResult.list;
  APP.drafts = draftResult.list;
  APP.delivery = firstDefined(
    deliveryResult.payload?.status,
    deliveryResult.payload?.deliveryStatus,
    deliveryResult.payload?.data,
    deliveryResult.payload,
    {},
  );
  APP.events = eventResult.list;
  APP.rules = ruleResult.list;

  renderDashboard();

  setConnectedState(
    true,
    `Nova · ${APP.agentId}`,
  );

  setMessage(
    els.connectionMessage,
    "Nova Agent Email connected. Production data loaded successfully.",
    "success",
  );

  closeModal("connectionModal");

  const optionalErrors = [
    recipientResult,
    draftResult,
    deliveryResult,
    eventResult,
    ruleResult,
    healthResult,
  ].filter((result) => result?.error);

  if (optionalErrors.length && !silent) {
    toast(
      `Connected. ${optionalErrors.length} optional panel request(s) could not be loaded.`,
    );
  } else if (!silent) {
    toast(
      "Nova Email production data refreshed.",
      "success",
    );
  }

  els.refreshButton.disabled = false;
  return true;
};

connectSession = async function connectSessionV2() {
  if (els.connectSessionButton.disabled) {
    return;
  }

  els.connectSessionButton.disabled = true;

  APP.apiBase =
    els.apiBaseInput.value.trim().replace(/\/+$/, "") ||
    APP.apiBase;

  localStorage.setItem(
    "korlixNovaEmailApiBase",
    APP.apiBase,
  );

  setMessage(
    els.connectionMessage,
    "Validating and refreshing the KORLIX browser session…",
  );

  try {
    const bundle = korlixReadSessionBundleV2();

    if (!bundle.accessToken && !bundle.refreshToken) {
      throw new Error(
        "No KORLIX login session was found. Press Open KORLIX Login, sign in, then return to this page.",
      );
    }

    await korlixRefreshSessionV2(bundle, true);
    await korlixValidateLoginV2();

    setMessage(
      els.connectionMessage,
      "Session verified. Locating your exact active Nova Agent Hub profile…",
    );

    const enteredAgentId = els.agentIdInput.value.trim();
    let discoveredAgentId = "";

    try {
      discoveredAgentId = await discoverNovaAgent();
    } catch (discoveryError) {
      if (!enteredAgentId) {
        throw discoveryError;
      }
    }

    APP.agentId = discoveredAgentId || enteredAgentId || findStoredAgentId();

    if (!APP.agentId) {
      throw new Error(
        "Nova was not found in this KORLIX account. Confirm that Nova is an active custom Agent Hub agent with the Agent Email tool authorized.",
      );
    }

    els.agentIdInput.value = APP.agentId;

    localStorage.setItem(
      "korlixNovaEmailAgentId",
      APP.agentId,
    );

    setMessage(
      els.connectionMessage,
      `Nova profile ${APP.agentId} found. Loading production Agent Email data…`,
    );

    let statusPayload;

    try {
      statusPayload = await requestJson(
        `${emailBase()}/status`,
        { timeoutMilliseconds: 25000 },
      );
    } catch (statusError) {
      if (korlixNovaBindingErrorV2(statusError)) {
        const retryAgentId = await discoverNovaAgent();

        if (retryAgentId && retryAgentId !== APP.agentId) {
          APP.agentId = retryAgentId;
          els.agentIdInput.value = retryAgentId;
          localStorage.setItem(
            "korlixNovaEmailAgentId",
            retryAgentId,
          );

          statusPayload = await requestJson(
            `${emailBase()}/status`,
            { timeoutMilliseconds: 25000 },
          );
        } else {
          throw statusError;
        }
      } else {
        throw statusError;
      }
    }

    const connected = await refreshDashboard({
      silent: true,
      statusPayload,
    });

    if (!connected) {
      throw new Error(
        "The Nova status request did not complete successfully.",
      );
    }
  } catch (error) {
    const message = korlixConnectionErrorTextV2(error);

    setConnectedState(false, "Connection failed");
    setMessage(
      els.connectionMessage,
      message,
      "error",
    );
    showModal("connectionModal");
  } finally {
    els.connectSessionButton.disabled = false;
  }
};

boot = async function bootV2() {
  bindEvents();
  updateClock();
  setInterval(updateClock, 1000);

  APP.apiBase =
    localStorage.getItem("korlixNovaEmailApiBase") ||
    APP.apiBase;

  APP.agentId =
    new URLSearchParams(location.search).get("agentId") ||
    localStorage.getItem("korlixNovaEmailAgentId") ||
    findStoredAgentId();

  els.agentIdInput.value = APP.agentId;
  els.apiBaseInput.value = APP.apiBase;

  const bundle = korlixReadSessionBundleV2();

  if (bundle.accessToken || bundle.refreshToken) {
    setMessage(
      els.connectionMessage,
      "Session found. Verifying and loading Nova Agent Email…",
    );
    showModal("connectionModal");

    try {
      await korlixRefreshSessionV2(bundle, false);
      await korlixValidateLoginV2();

      const discovered = await discoverNovaAgent().catch(() => "");

      if (discovered) {
        APP.agentId = discovered;
        els.agentIdInput.value = discovered;
        localStorage.setItem(
          "korlixNovaEmailAgentId",
          discovered,
        );
      }

      if (!APP.agentId) {
        throw new Error(
          "Nova was not discovered automatically. Enter Nova’s Agent Hub ID and press Connect Session.",
        );
      }

      const statusPayload = await requestJson(
        `${emailBase()}/status`,
        { timeoutMilliseconds: 25000 },
      );

      const connected = await refreshDashboard({
        silent: true,
        statusPayload,
      });

      if (connected) {
        return;
      }
    } catch (error) {
      setConnectedState(false, "Connection failed");
      setMessage(
        els.connectionMessage,
        korlixConnectionErrorTextV2(error),
        "error",
      );
      showModal("connectionModal");
    }
  } else {
    setConnectedState(false, "Connect KORLIX session");
    setMessage(
      els.connectionMessage,
      "No KORLIX browser session was found. Open KORLIX Login, sign in, then return and press Connect Session.",
      "error",
    );
    showModal("connectionModal");
  }

  loadHealth().catch(() => {});
};

window.addEventListener("unhandledrejection", (event) => {
  const message = korlixConnectionErrorTextV2(event.reason);

  if (!APP.connected) {
    setMessage(
      els.connectionMessage,
      message,
      "error",
    );
    showModal("connectionModal");
  }
});
// K133_NOVA_EMAIL_WEB_AUTH_LOGO_FIX_V2_END

boot();
