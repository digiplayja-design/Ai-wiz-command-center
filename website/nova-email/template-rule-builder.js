// K133_NOVA_EMAIL_TEMPLATE_RULE_BUILDER_V1_BEGIN
(() => {
  "use strict";

  const BUILD = "K133_NOVA_EMAIL_TEMPLATE_RULE_BUILDER_V1";
  const WORKSPACE_ID = "korlix-template-rule-workspace-v1";
  const STORAGE_PREFIX = "korlixNovaEmailTemplatesV1";

  const state = {
    templates: [],
    recipients: [],
    rules: [],
    editingTemplateId: "",
    editingRuleId: "",
    activeTemplateId: "",
    busy: false,
  };

  const byId = (id) => document.getElementById(id);
  const clean = (value) => String(value ?? "").trim();

  const appState = () =>
    typeof APP !== "undefined" &&
    APP &&
    typeof APP === "object"
      ? APP
      : window.APP &&
          typeof window.APP === "object"
        ? window.APP
        : {};

  const escapeHtml = (value) =>
    String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

  const randomToken = () => {
    if (globalThis.crypto?.randomUUID) {
      return globalThis.crypto.randomUUID();
    }

    return (
      `${Date.now()}-` +
      Math.random()
        .toString(36)
        .slice(2, 14)
    );
  };

  const storageKey = () => {
    const agentId =
      clean(appState().agentId) ||
      "nova";

    return `${STORAGE_PREFIX}:${agentId}`;
  };

  function notify(
    message,
    type = "success",
  ) {
    const text =
      clean(message) ||
      "Done.";

    if (typeof toast === "function") {
      toast(text, type);
      return;
    }

    const workspace =
      byId(WORKSPACE_ID);

    const messageBox =
      workspace?.querySelector(
        "[data-k133-builder-message]",
      );

    if (messageBox) {
      messageBox.textContent = text;
      messageBox.dataset.type = type;
      messageBox.hidden = false;

      window.setTimeout(
        () => {
          if (
            messageBox.textContent ===
            text
          ) {
            messageBox.hidden = true;
          }
        },
        7000,
      );

      return;
    }

    window.alert(text);
  }

  function apiBasePath() {
    if (
      typeof emailBase !==
      "function"
    ) {
      throw new Error(
        "Nova Email is not connected. Return to Command Center and reconnect your KORLIX session.",
      );
    }

    return emailBase();
  }

  async function apiRequest(
    path,
    options = {},
  ) {
    if (
      typeof requestJson !==
      "function"
    ) {
      throw new Error(
        "The authenticated Nova Email request client is unavailable. Refresh the page and reconnect.",
      );
    }

    return await requestJson(
      path,
      options,
    );
  }

  function firstList(
    payload,
    keys,
  ) {
    for (const key of keys) {
      if (
        Array.isArray(
          payload?.[key],
        )
      ) {
        return payload[key];
      }
    }

    if (Array.isArray(payload)) {
      return payload;
    }

    return [];
  }

  function loadTemplatesFromBrowser() {
    try {
      const parsed =
        JSON.parse(
          localStorage.getItem(
            storageKey(),
          ) || "[]",
        );

      state.templates =
        Array.isArray(parsed)
          ? parsed.filter(
              (item) =>
                item &&
                typeof item ===
                  "object" &&
                clean(item.id) &&
                clean(item.name) &&
                clean(item.subject) &&
                clean(item.textBody),
            )
          : [];
    } catch {
      state.templates = [];
    }
  }

  function saveTemplatesToBrowser() {
    localStorage.setItem(
      storageKey(),
      JSON.stringify(
        state.templates,
      ),
    );
  }

  function recipientLabel(
    recipient,
  ) {
    const name =
      clean(
        recipient?.displayName,
      );

    const email =
      clean(
        recipient?.email,
      );

    return name
      ? `${name} — ${email}`
      : email ||
          "Approved recipient";
  }

  function activeRecipients() {
    return state.recipients.filter(
      (recipient) => {
        const status =
          clean(
            recipient?.consentStatus,
          ).toLowerCase();

        return (
          recipient?.active !==
            false &&
          ![
            "unsubscribed",
            "suppressed",
          ].includes(status)
        );
      },
    );
  }

  function templateById(id) {
    return (
      state.templates.find(
        (template) =>
          template.id === id,
      ) || null
    );
  }

  function ruleById(id) {
    return (
      state.rules.find(
        (rule) =>
          rule.id === id,
      ) || null
    );
  }

  function workspaceHost() {
    return (
      document.querySelector(
        ".main-content",
      ) ||
      document.querySelector(
        "main",
      ) ||
      document.querySelector(
        ".app-shell",
      ) ||
      document.body
    );
  }

  function workspaceMarkup() {
    return `
      <section id="${WORKSPACE_ID}" class="korlix-template-rule-workspace-v1" hidden aria-label="Nova Email templates and rules">
        <div class="k133-builder-shell">
          <header class="k133-builder-header">
            <div>
              <p class="k133-builder-eyebrow">KORLIX NOVA EMAIL</p>
              <h1>Templates &amp; Autopilot Rules</h1>
              <p>Create reusable transactional templates, test them as unsent drafts, and bind them to approved recipients through server-enforced rules.</p>
            </div>
            <div class="k133-builder-header-actions">
              <button type="button" class="button secondary" data-k133-refresh-all>Refresh Data</button>
              <button type="button" class="button" data-k133-close-builder>Command Center</button>
            </div>
          </header>

          <div class="k133-builder-safety-strip">
            <strong>Safety boundary:</strong>
            Marketing remains off. Creating a template or Draft Only rule does not send email. Approved Autopilot requires a fresh typed confirmation, and this browser never receives the private trigger secret.
          </div>

          <div class="k133-builder-message" data-k133-builder-message hidden></div>

          <div class="k133-builder-tabs" role="tablist" aria-label="Template and rule sections">
            <button type="button" class="active" data-k133-tab="templates">Templates</button>
            <button type="button" data-k133-tab="rules">Autopilot Rules</button>
          </div>

          <div class="k133-builder-panel active" data-k133-panel="templates">
            <div class="k133-builder-toolbar">
              <div>
                <h2>Reusable Templates</h2>
                <p>Templates are stored in this signed-in browser and become server-controlled when attached to a Nova rule or test draft.</p>
              </div>
              <button type="button" class="button" data-k133-new-template>+ Create New Template</button>
            </div>

            <div class="k133-template-grid-v1" data-k133-template-grid></div>

            <form class="k133-builder-editor" data-k133-template-form hidden>
              <input type="hidden" data-k133-template-id>

              <div class="k133-editor-heading">
                <div>
                  <p class="k133-builder-eyebrow">TRANSACTIONAL TEMPLATE</p>
                  <h3 data-k133-template-form-title>Create New Template</h3>
                </div>
                <button type="button" class="button secondary" data-k133-cancel-template>Cancel</button>
              </div>

              <div class="k133-form-grid">
                <label class="k133-field">
                  <span>Template name</span>
                  <input type="text" maxlength="200" autocomplete="off" data-k133-template-name required>
                </label>

                <label class="k133-field">
                  <span>Email subject</span>
                  <input type="text" maxlength="200" autocomplete="off" data-k133-template-subject required>
                </label>
              </div>

              <label class="k133-field">
                <span>Text message</span>
                <textarea rows="10" maxlength="40000" data-k133-template-body required></textarea>
              </label>

              <p class="k133-variable-help">
                Available variables:
                <code>{{recipient_name}}</code>,
                <code>{{recipient_email}}</code>,
                <code>{{event_id}}</code> and
                <code>{{note}}</code>.
              </p>

              <div class="k133-editor-actions">
                <button type="submit" class="button" data-k133-save-template>Save Template</button>
                <button type="button" class="button secondary" data-k133-preview-template>Preview</button>
                <button type="button" class="button secondary" data-k133-create-test-draft>Create Test Draft</button>
              </div>

              <div class="k133-template-preview" data-k133-template-preview hidden>
                <h4>Sample Preview</h4>
                <p data-k133-preview-subject></p>
                <pre data-k133-preview-body></pre>
              </div>
            </form>
          </div>

          <div class="k133-builder-panel" data-k133-panel="rules">
            <div class="k133-builder-toolbar">
              <div>
                <h2>Server-Enforced Rules</h2>
                <p>Every rule uses explicit approved-recipient IDs, a fixed template, a trigger key and a rule-specific daily cap.</p>
              </div>
              <button type="button" class="button" data-k133-new-rule>+ Create New Rule</button>
            </div>

            <div class="k133-rule-grid-v1" data-k133-rule-grid></div>

            <form class="k133-builder-editor" data-k133-rule-form hidden>
              <input type="hidden" data-k133-rule-id>

              <div class="k133-editor-heading">
                <div>
                  <p class="k133-builder-eyebrow">NOVA EMAIL RULE</p>
                  <h3 data-k133-rule-form-title>Create New Rule</h3>
                </div>
                <button type="button" class="button secondary" data-k133-cancel-rule>Cancel</button>
              </div>

              <div class="k133-form-grid">
                <label class="k133-field">
                  <span>Rule name</span>
                  <input type="text" maxlength="200" autocomplete="off" data-k133-rule-name required>
                </label>

                <label class="k133-field">
                  <span>Trigger key</span>
                  <input type="text" maxlength="120" autocomplete="off" placeholder="demo.followup" data-k133-rule-trigger required>
                </label>

                <label class="k133-field">
                  <span>Template</span>
                  <select data-k133-rule-template required></select>
                </label>

                <label class="k133-field">
                  <span>Send mode</span>
                  <select data-k133-rule-mode>
                    <option value="draft_only">Draft Only</option>
                    <option value="autopilot">Approved Autopilot</option>
                  </select>
                </label>

                <label class="k133-field">
                  <span>Maximum sends per day</span>
                  <input type="number" min="1" max="500" value="1" data-k133-rule-cap required>
                </label>

                <label class="k133-check-field">
                  <input type="checkbox" data-k133-rule-enabled checked>
                  <span>Rule enabled</span>
                </label>
              </div>

              <fieldset class="k133-recipient-fieldset">
                <legend>Explicit approved recipients</legend>
                <div class="k133-recipient-choice-grid" data-k133-rule-recipients></div>
              </fieldset>

              <fieldset class="k133-day-fieldset">
                <legend>Allowed sending days</legend>
                <div class="k133-day-grid">
                  <label><input type="checkbox" value="0" data-k133-rule-day checked> Sun</label>
                  <label><input type="checkbox" value="1" data-k133-rule-day checked> Mon</label>
                  <label><input type="checkbox" value="2" data-k133-rule-day checked> Tue</label>
                  <label><input type="checkbox" value="3" data-k133-rule-day checked> Wed</label>
                  <label><input type="checkbox" value="4" data-k133-rule-day checked> Thu</label>
                  <label><input type="checkbox" value="5" data-k133-rule-day checked> Fri</label>
                  <label><input type="checkbox" value="6" data-k133-rule-day checked> Sat</label>
                </div>
              </fieldset>

              <div class="k133-rule-warning">
                Draft Only creates no automatic send. Approved Autopilot requires you to type
                <strong>PREAPPROVE NOVA RULE</strong>. Saving a rule never fires its trigger.
              </div>

              <div class="k133-editor-actions">
                <button type="submit" class="button" data-k133-save-rule>Save Rule</button>
                <button type="button" class="button danger" data-k133-deactivate-rule hidden>Deactivate Rule</button>
              </div>
            </form>
          </div>
        </div>
      </section>
    `;
  }

  function ensureWorkspace() {
    let workspace =
      byId(WORKSPACE_ID);

    if (workspace) {
      return workspace;
    }

    const host =
      workspaceHost();

    host.insertAdjacentHTML(
      "beforeend",
      workspaceMarkup(),
    );

    workspace =
      byId(WORKSPACE_ID);

    if (!workspace) {
      throw new Error(
        "The Templates workspace could not be created.",
      );
    }

    return workspace;
  }

  function setWorkspaceVisible(
    visible,
  ) {
    const workspace =
      ensureWorkspace();

    const host =
      workspace.parentElement;

    for (
      const child
      of Array.from(
        host.children,
      )
    ) {
      if (child === workspace) {
        continue;
      }

      if (visible) {
        if (
          !(
            "k133BuilderWasHidden"
            in child.dataset
          )
        ) {
          child.dataset.k133BuilderWasHidden =
            child.hidden
              ? "1"
              : "0";
        }

        child.hidden = true;
      } else if (
        "k133BuilderWasHidden"
        in child.dataset
      ) {
        child.hidden =
          child.dataset
            .k133BuilderWasHidden ===
          "1";

        delete child.dataset
          .k133BuilderWasHidden;
      }
    }

    workspace.hidden =
      !visible;

    document.body.classList.toggle(
      "k133-template-rule-builder-open",
      visible,
    );
  }

  function switchBuilderTab(
    name,
  ) {
    const workspace =
      ensureWorkspace();

    for (
      const button
      of workspace.querySelectorAll(
        "[data-k133-tab]",
      )
    ) {
      button.classList.toggle(
        "active",
        button.dataset.k133Tab ===
          name,
      );
    }

    for (
      const panel
      of workspace.querySelectorAll(
        "[data-k133-panel]",
      )
    ) {
      panel.classList.toggle(
        "active",
        panel.dataset.k133Panel ===
          name,
      );
    }
  }

  function formatDate(
    value,
  ) {
    const parsed =
      new Date(value || "");

    if (
      Number.isNaN(
        parsed.getTime(),
      )
    ) {
      return "Not recorded";
    }

    return parsed.toLocaleString();
  }

  function renderSample(
    value,
  ) {
    const variables = {
      recipient_name:
        "Ricardo Bailey",
      recipient_email:
        "ricardo@korlixdeveloper.com",
      event_id:
        "nova-demo-001",
      note:
        "Approved KORLIX follow-up",
    };

    return String(
      value ?? "",
    ).replace(
      /\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g,
      (
        original,
        key,
      ) =>
        Object.hasOwn(
          variables,
          key,
        )
          ? variables[key]
          : original,
    );
  }

  function renderTemplateCards() {
    const workspace =
      ensureWorkspace();

    const grid =
      workspace.querySelector(
        "[data-k133-template-grid]",
      );

    if (!grid) {
      return;
    }

    if (
      state.templates.length ===
      0
    ) {
      grid.innerHTML = `
        <div class="k133-builder-empty-state">
          <h3>No templates yet</h3>
          <p>Create your first transactional template. No email is sent when a template is saved.</p>
          <button type="button" class="button" data-k133-new-template>+ Create New Template</button>
        </div>
      `;

      return;
    }

    grid.innerHTML =
      state.templates
        .map(
          (template) => {
            const preview =
              clean(
                template.textBody,
              ).slice(
                0,
                190,
              );

            return `
              <article class="k133-builder-card" data-k133-template-card="${escapeHtml(template.id)}">
                <div class="k133-card-heading">
                  <div>
                    <p class="k133-builder-eyebrow">TRANSACTIONAL</p>
                    <h3>${escapeHtml(template.name)}</h3>
                  </div>
                  <span class="k133-status-pill">Local Template</span>
                </div>

                <p class="k133-card-subject">${escapeHtml(template.subject)}</p>
                <p class="k133-card-preview">${escapeHtml(preview)}${clean(template.textBody).length > 190 ? "…" : ""}</p>
                <p class="k133-card-meta">Updated ${escapeHtml(formatDate(template.updatedAt))}</p>

                <div class="k133-card-actions">
                  <button type="button" class="button small" data-k133-template-action="edit" data-k133-template-id="${escapeHtml(template.id)}">Edit</button>
                  <button type="button" class="button small secondary" data-k133-template-action="duplicate" data-k133-template-id="${escapeHtml(template.id)}">Duplicate</button>
                  <button type="button" class="button small secondary" data-k133-template-action="preview" data-k133-template-id="${escapeHtml(template.id)}">Preview</button>
                  <button type="button" class="button small danger" data-k133-template-action="delete" data-k133-template-id="${escapeHtml(template.id)}">Delete</button>
                </div>
              </article>
            `;
          },
        )
        .join("");
  }

  function renderTemplateOptions(
    selectedId = "",
  ) {
    const workspace =
      ensureWorkspace();

    const select =
      workspace.querySelector(
        "[data-k133-rule-template]",
      );

    if (!select) {
      return;
    }

    select.innerHTML = [
      '<option value="">Choose a template</option>',
      ...state.templates.map(
        (template) =>
          `<option value="${escapeHtml(template.id)}">${escapeHtml(template.name)} — ${escapeHtml(template.subject)}</option>`,
      ),
    ].join("");

    select.value =
      selectedId;
  }

  function renderRecipientChoices(
    selectedIds = [],
  ) {
    const workspace =
      ensureWorkspace();

    const container =
      workspace.querySelector(
        "[data-k133-rule-recipients]",
      );

    if (!container) {
      return;
    }

    const selected =
      new Set(
        Array.isArray(
          selectedIds,
        )
          ? selectedIds
          : [],
      );

    const recipients =
      activeRecipients();

    if (
      recipients.length ===
      0
    ) {
      container.innerHTML = `
        <p class="k133-inline-empty">
          No active approved recipients were found. Return to Recipients and add or reactivate one first.
        </p>
      `;

      return;
    }

    container.innerHTML =
      recipients
        .map(
          (recipient) => `
            <label class="k133-recipient-choice">
              <input
                type="checkbox"
                value="${escapeHtml(recipient.id)}"
                data-k133-rule-recipient
                ${selected.has(recipient.id) ? "checked" : ""}
              >
              <span>
                <strong>${escapeHtml(recipientLabel(recipient))}</strong>
                <small>${escapeHtml(clean(recipient.consentStatus) || "transactional_only")}</small>
              </span>
            </label>
          `,
        )
        .join("");
  }

  function renderRuleCards() {
    const workspace =
      ensureWorkspace();

    const grid =
      workspace.querySelector(
        "[data-k133-rule-grid]",
      );

    if (!grid) {
      return;
    }

    if (
      state.rules.length === 0
    ) {
      grid.innerHTML = `
        <div class="k133-builder-empty-state">
          <h3>No rules yet</h3>
          <p>Create one Draft Only rule first. It will not send email automatically.</p>
          <button type="button" class="button" data-k133-new-rule>+ Create New Rule</button>
        </div>
      `;

      return;
    }

    grid.innerHTML =
      state.rules
        .map(
          (rule) => {
            const mode =
              clean(
                rule.sendMode,
              ) ===
              "autopilot"
                ? "Approved Autopilot"
                : "Draft Only";

            const recipientIds =
              Array.isArray(
                rule.recipientIds,
              )
                ? rule.recipientIds
                : [];

            const recipientNames =
              recipientIds
                .map(
                  (recipientId) =>
                    state.recipients.find(
                      (recipient) =>
                        recipient.id ===
                        recipientId,
                    ),
                )
                .filter(Boolean)
                .map(recipientLabel);

            return `
              <article class="k133-builder-card" data-k133-rule-card="${escapeHtml(rule.id)}">
                <div class="k133-card-heading">
                  <div>
                    <p class="k133-builder-eyebrow">${escapeHtml(mode)}</p>
                    <h3>${escapeHtml(rule.name)}</h3>
                  </div>
                  <span class="k133-status-pill ${rule.enabled === false ? "inactive" : ""}">
                    ${rule.enabled === false ? "Inactive" : "Enabled"}
                  </span>
                </div>

                <dl class="k133-rule-facts">
                  <div><dt>Trigger</dt><dd>${escapeHtml(rule.triggerKey)}</dd></div>
                  <div><dt>Recipients</dt><dd>${escapeHtml(recipientNames.join(", ") || `${recipientIds.length} approved recipient(s)`)}</dd></div>
                  <div><dt>Rule cap</dt><dd>${escapeHtml(rule.maxSendsPerDay || 1)} per day</dd></div>
                  <div><dt>Preapproved</dt><dd>${rule.preapproved ? "Yes" : "No"}</dd></div>
                </dl>

                <div class="k133-card-actions">
                  <button type="button" class="button small" data-k133-rule-action="edit" data-k133-rule-id="${escapeHtml(rule.id)}">Edit</button>
                  <button type="button" class="button small secondary" data-k133-rule-action="duplicate" data-k133-rule-id="${escapeHtml(rule.id)}">Duplicate</button>
                  <button type="button" class="button small danger" data-k133-rule-action="deactivate" data-k133-rule-id="${escapeHtml(rule.id)}">
                    ${rule.enabled === false ? "Already Inactive" : "Deactivate"}
                  </button>
                </div>
              </article>
            `;
          },
        )
        .join("");
  }

  function renderAll() {
    renderTemplateCards();
    renderTemplateOptions();
    renderRecipientChoices();
    renderRuleCards();
  }

  function openTemplateEditor(
    template = null,
  ) {
    const workspace =
      ensureWorkspace();

    const form =
      workspace.querySelector(
        "[data-k133-template-form]",
      );

    const record =
      template || {
        id: "",
        name: "",
        subject: "",
        textBody: "",
      };

    state.editingTemplateId =
      clean(record.id);

    form.querySelector(
      "[data-k133-template-id]",
    ).value =
      state.editingTemplateId;

    form.querySelector(
      "[data-k133-template-name]",
    ).value =
      clean(record.name);

    form.querySelector(
      "[data-k133-template-subject]",
    ).value =
      clean(record.subject);

    form.querySelector(
      "[data-k133-template-body]",
    ).value =
      clean(record.textBody);

    form.querySelector(
      "[data-k133-template-form-title]",
    ).textContent =
      state.editingTemplateId
        ? "Edit Template"
        : "Create New Template";

    form.querySelector(
      "[data-k133-template-preview]",
    ).hidden = true;

    form.hidden = false;

    form.scrollIntoView({
      behavior: "smooth",
      block: "start",
    });
  }

  function closeTemplateEditor() {
    const workspace =
      ensureWorkspace();

    const form =
      workspace.querySelector(
        "[data-k133-template-form]",
      );

    state.editingTemplateId = "";
    form.reset();
    form.hidden = true;
  }

  function openRuleEditor(
    rule = null,
  ) {
    const workspace =
      ensureWorkspace();

    const form =
      workspace.querySelector(
        "[data-k133-rule-form]",
      );

    const record =
      rule || {
        id: "",
        name: "",
        triggerKey:
          "demo.followup",
        recipientIds: [],
        sendMode:
          "draft_only",
        maxSendsPerDay: 1,
        enabled: true,
        allowedDays:
          [0, 1, 2, 3, 4, 5, 6],
      };

    state.editingRuleId =
      clean(record.id);

    const matchedTemplate =
      state.templates.find(
        (template) =>
          template.subject ===
            record.subjectTemplate &&
          template.textBody ===
            record.textTemplate,
      );

    form.querySelector(
      "[data-k133-rule-id]",
    ).value =
      state.editingRuleId;

    form.querySelector(
      "[data-k133-rule-name]",
    ).value =
      clean(record.name);

    form.querySelector(
      "[data-k133-rule-trigger]",
    ).value =
      clean(record.triggerKey) ||
      "demo.followup";

    form.querySelector(
      "[data-k133-rule-mode]",
    ).value =
      clean(record.sendMode) ||
      "draft_only";

    form.querySelector(
      "[data-k133-rule-cap]",
    ).value =
      String(
        record.maxSendsPerDay ||
        1,
      );

    form.querySelector(
      "[data-k133-rule-enabled]",
    ).checked =
      record.enabled !== false;

    renderTemplateOptions(
      matchedTemplate?.id ||
      state.activeTemplateId ||
      "",
    );

    renderRecipientChoices(
      record.recipientIds,
    );

    const allowedDays =
      new Set(
        Array.isArray(
          record.allowedDays,
        )
          ? record.allowedDays.map(
              Number,
            )
          : [
              0,
              1,
              2,
              3,
              4,
              5,
              6,
            ],
      );

    for (
      const checkbox
      of form.querySelectorAll(
        "[data-k133-rule-day]",
      )
    ) {
      checkbox.checked =
        allowedDays.has(
          Number(
            checkbox.value,
          ),
        );
    }

    form.querySelector(
      "[data-k133-rule-form-title]",
    ).textContent =
      state.editingRuleId
        ? "Edit Rule"
        : "Create New Rule";

    form.querySelector(
      "[data-k133-deactivate-rule]",
    ).hidden =
      !state.editingRuleId ||
      record.enabled === false;

    form.hidden = false;

    form.scrollIntoView({
      behavior: "smooth",
      block: "start",
    });
  }

  function closeRuleEditor() {
    const workspace =
      ensureWorkspace();

    const form =
      workspace.querySelector(
        "[data-k133-rule-form]",
      );

    state.editingRuleId = "";
    form.reset();
    form.hidden = true;
  }

// K133_TEMPLATE_RULE_BUILDER_STAGE2A_APPEND_COMPLETE
  function templateFormValues() {
    const workspace =
      ensureWorkspace();

    const form =
      workspace.querySelector(
        "[data-k133-template-form]",
      );

    return {
      id:
        clean(
          form.querySelector(
            "[data-k133-template-id]",
          )?.value,
        ),

      name:
        clean(
          form.querySelector(
            "[data-k133-template-name]",
          )?.value,
        ),

      subject:
        clean(
          form.querySelector(
            "[data-k133-template-subject]",
          )?.value,
        ),

      textBody:
        clean(
          form.querySelector(
            "[data-k133-template-body]",
          )?.value,
        ),
    };
  }

  function validateTemplateValues(
    values,
  ) {
    if (!values.name) {
      throw new Error(
        "Enter a template name.",
      );
    }

    if (!values.subject) {
      throw new Error(
        "Enter an email subject.",
      );
    }

    if (!values.textBody) {
      throw new Error(
        "Enter the email message.",
      );
    }
  }

  function saveTemplateFromForm(
    event,
  ) {
    event?.preventDefault();

    const values =
      templateFormValues();

    validateTemplateValues(
      values,
    );

    const now =
      new Date().toISOString();

    const existing =
      templateById(values.id);

    const record = {
      id:
        existing?.id ||
        randomToken(),

      name:
        values.name,

      subject:
        values.subject,

      textBody:
        values.textBody,

      marketing: false,

      createdAt:
        existing?.createdAt ||
        now,

      updatedAt: now,
    };

    if (existing) {
      state.templates =
        state.templates.map(
          (template) =>
            template.id ===
            record.id
              ? record
              : template,
        );
    } else {
      state.templates = [
        record,
        ...state.templates,
      ];
    }

    state.activeTemplateId =
      record.id;

    saveTemplatesToBrowser();
    closeTemplateEditor();
    renderAll();

    notify(
      existing
        ? "Template updated. No email was sent."
        : "Template saved. No email was sent.",
      "success",
    );

    return record;
  }

  function previewTemplateValues(
    values = templateFormValues(),
  ) {
    validateTemplateValues(
      values,
    );

    const workspace =
      ensureWorkspace();

    const preview =
      workspace.querySelector(
        "[data-k133-template-preview]",
      );

    preview.querySelector(
      "[data-k133-preview-subject]",
    ).textContent =
      `Subject: ${renderSample(values.subject)}`;

    preview.querySelector(
      "[data-k133-preview-body]",
    ).textContent =
      renderSample(values.textBody);

    preview.hidden = false;
  }

  function chooseDraftRecipient() {
    const recipients =
      activeRecipients();

    if (
      recipients.length === 0
    ) {
      throw new Error(
        "Add an active approved Transactional Only recipient before creating a test draft.",
      );
    }

    if (
      recipients.length === 1
    ) {
      return recipients[0];
    }

    const choices =
      recipients
        .map(
          (
            recipient,
            index,
          ) =>
            `${index + 1}. ${recipientLabel(recipient)}`,
        )
        .join("\n");

    const answer =
      window.prompt(
        `Choose the approved recipient number for this unsent test draft:\n\n${choices}`,
        "1",
      );

    if (answer === null) {
      return null;
    }

    const selectedIndex =
      Number.parseInt(
        clean(answer),
        10,
      ) - 1;

    if (
      !Number.isInteger(
        selectedIndex,
      ) ||
      selectedIndex < 0 ||
      selectedIndex >=
        recipients.length
    ) {
      throw new Error(
        "Choose a valid approved recipient number.",
      );
    }

    return recipients[
      selectedIndex
    ];
  }

  function setBuilderBusy(
    busy,
  ) {
    state.busy =
      busy === true;

    const workspace =
      byId(WORKSPACE_ID);

    if (!workspace) {
      return;
    }

    workspace.setAttribute(
      "aria-busy",
      state.busy
        ? "true"
        : "false",
    );

    workspace.classList.toggle(
      "busy",
      state.busy,
    );

    for (
      const button
      of workspace.querySelectorAll(
        "button",
      )
    ) {
      button.disabled =
        state.busy;
    }
  }

  async function runBuilderTask(
    task,
  ) {
    if (state.busy) {
      return null;
    }

    setBuilderBusy(true);

    try {
      return await task();
    } catch (error) {
      notify(
        clean(error?.message) ||
          "The Nova Email builder action failed.",
        "error",
      );

      return null;
    } finally {
      setBuilderBusy(false);
    }
  }

  async function createTestDraftFromForm() {
    return await runBuilderTask(
      async () => {
        const values =
          templateFormValues();

        validateTemplateValues(
          values,
        );

        const recipient =
          chooseDraftRecipient();

        if (!recipient) {
          return null;
        }

        const templateId =
          values.id ||
          state.activeTemplateId ||
          randomToken();

        const result =
          await apiRequest(
            `${apiBasePath()}/drafts`,
            {
              method: "POST",

              timeoutMilliseconds:
                30000,

              body:
                JSON.stringify({
                  recipientId:
                    recipient.id,

                  subject:
                    values.subject,

                  textBody:
                    values.textBody,

                  idempotencyKey:
                    [
                      "template-test",
                      templateId,
                      recipient.id,
                      randomToken(),
                    ].join(":"),

                  marketing: false,
                }),
            },
          );

        const draft =
          result?.draft || {};

        notify(
          result?.replayed
            ? "The same unsent test draft already exists. No email was sent."
            : `Test draft created for ${recipientLabel(recipient)}. No email was sent.`,
          "success",
        );

        if (
          typeof refreshDashboard ===
          "function"
        ) {
          await refreshDashboard({
            silent: true,
          }).catch(
            () => {},
          );
        }

        return draft;
      },
    );
  }

  async function loadRecipients() {
    const payload =
      await apiRequest(
        `${apiBasePath()}/recipients?limit=200`,
        {
          timeoutMilliseconds:
            30000,
        },
      );

    state.recipients =
      firstList(
        payload,
        [
          "recipients",
        ],
      ).filter(
        (recipient) =>
          clean(recipient?.id) &&
          clean(recipient?.email),
      );

    return state.recipients;
  }

  async function loadRules() {
    const payload =
      await apiRequest(
        `${apiBasePath()}/rules?limit=200`,
        {
          timeoutMilliseconds:
            30000,
        },
      );

    state.rules =
      firstList(
        payload,
        [
          "rules",
        ],
      ).filter(
        (rule) =>
          clean(rule?.id),
      );

    return state.rules;
  }

  async function refreshBuilderData(
    {
      announce = false,
    } = {},
  ) {
    return await runBuilderTask(
      async () => {
        await Promise.all([
          loadRecipients(),
          loadRules(),
        ]);

        renderAll();

        if (announce) {
          notify(
            "Templates, approved recipients and rules were refreshed.",
            "success",
          );
        }

        return true;
      },
    );
  }

  function ruleFormValues() {
    const workspace =
      ensureWorkspace();

    const form =
      workspace.querySelector(
        "[data-k133-rule-form]",
      );

    const recipientIds =
      Array.from(
        form.querySelectorAll(
          "[data-k133-rule-recipient]:checked",
        ),
      )
        .map(
          (checkbox) =>
            clean(
              checkbox.value,
            ),
        )
        .filter(Boolean);

    const allowedDays =
      Array.from(
        form.querySelectorAll(
          "[data-k133-rule-day]:checked",
        ),
      )
        .map(
          (checkbox) =>
            Number(
              checkbox.value,
            ),
        )
        .filter(
          (day) =>
            Number.isInteger(day) &&
            day >= 0 &&
            day <= 6,
        );

    return {
      id:
        clean(
          form.querySelector(
            "[data-k133-rule-id]",
          )?.value,
        ),

      name:
        clean(
          form.querySelector(
            "[data-k133-rule-name]",
          )?.value,
        ),

      triggerKey:
        clean(
          form.querySelector(
            "[data-k133-rule-trigger]",
          )?.value,
        ).toLowerCase(),

      templateId:
        clean(
          form.querySelector(
            "[data-k133-rule-template]",
          )?.value,
        ),

      sendMode:
        clean(
          form.querySelector(
            "[data-k133-rule-mode]",
          )?.value,
        ) ||
        "draft_only",

      maxSendsPerDay:
        Number.parseInt(
          clean(
            form.querySelector(
              "[data-k133-rule-cap]",
            )?.value,
          ),
          10,
        ),

      enabled:
        form.querySelector(
          "[data-k133-rule-enabled]",
        )?.checked === true,

      recipientIds:
        [
          ...new Set(
            recipientIds,
          ),
        ],

      allowedDays:
        [
          ...new Set(
            allowedDays,
          ),
        ].sort(
          (
            left,
            right,
          ) =>
            left - right,
        ),
    };
  }

  function validateRuleValues(
    values,
  ) {
    if (!values.name) {
      throw new Error(
        "Enter a rule name.",
      );
    }

    if (
      !/^[a-z][a-z0-9_.:-]{0,119}$/.test(
        values.triggerKey,
      )
    ) {
      throw new Error(
        "Enter a trigger key beginning with a letter and using only letters, numbers, periods, colons, underscores or hyphens.",
      );
    }

    if (
      ![
        "draft_only",
        "autopilot",
      ].includes(
        values.sendMode,
      )
    ) {
      throw new Error(
        "Choose Draft Only or Approved Autopilot.",
      );
    }

    if (
      !Number.isInteger(
        values.maxSendsPerDay,
      ) ||
      values.maxSendsPerDay <
        1 ||
      values.maxSendsPerDay >
        500
    ) {
      throw new Error(
        "Enter a rule daily cap from 1 through 500.",
      );
    }

    if (
      values.recipientIds
        .length === 0
    ) {
      throw new Error(
        "Choose at least one active approved recipient.",
      );
    }

    if (
      values.allowedDays
        .length === 0
    ) {
      throw new Error(
        "Choose at least one allowed sending day.",
      );
    }

    const template =
      templateById(
        values.templateId,
      );

    if (!template) {
      throw new Error(
        "Choose a saved template.",
      );
    }

    return template;
  }

  async function saveRuleFromForm(
    event,
  ) {
    event?.preventDefault();

    return await runBuilderTask(
      async () => {
        const values =
          ruleFormValues();

        const template =
          validateRuleValues(
            values,
          );

        const payload = {
          confirmed: true,

          name:
            values.name,

          triggerKey:
            values.triggerKey,

          recipientIds:
            values.recipientIds,

          subjectTemplate:
            template.subject,

          textTemplate:
            template.textBody,

          htmlTemplate: "",

          marketing: false,

          maxSendsPerDay:
            values.maxSendsPerDay,

          sendMode:
            values.sendMode,

          enabled:
            values.enabled,

          allowedDays:
            values.allowedDays,
        };

        if (
          values.sendMode ===
          "autopilot"
        ) {
          const phrase =
            "PREAPPROVE NOVA RULE";

          const confirmation =
            window.prompt(
              `Type ${phrase} to preapprove this exact recipient scope, subject, message, trigger and daily cap.`,
            );

          if (
            confirmation !==
            phrase
          ) {
            throw new Error(
              "Approved Autopilot preapproval was not granted. The rule was not saved.",
            );
          }

          payload.preapproved =
            true;

          payload.confirmationNonce =
            `rule-preapproval:${randomToken()}:${Date.now()}`;
        }

        const editing =
          Boolean(values.id);

        const path =
          editing
            ? `${apiBasePath()}/rules/${encodeURIComponent(values.id)}`
            : `${apiBasePath()}/rules`;

        const result =
          await apiRequest(
            path,
            {
              method:
                editing
                  ? "PATCH"
                  : "POST",

              timeoutMilliseconds:
                30000,

              body:
                JSON.stringify(
                  payload,
                ),
            },
          );

        const saved =
          result?.rule;

        if (
          !saved ||
          !clean(saved.id)
        ) {
          throw new Error(
            "The server did not return the saved Nova Email rule.",
          );
        }

        const index =
          state.rules.findIndex(
            (rule) =>
              rule.id ===
              saved.id,
          );

        if (index >= 0) {
          state.rules.splice(
            index,
            1,
            saved,
          );
        } else {
          state.rules.unshift(
            saved,
          );
        }

        closeRuleEditor();
        renderAll();

        notify(
          values.sendMode ===
            "autopilot"
            ? "Approved Autopilot rule saved. No trigger was fired and no email was sent."
            : "Draft Only rule saved. No trigger was fired and no email was sent.",
          "success",
        );

        return saved;
      },
    );
  }

// K133_TEMPLATE_RULE_BUILDER_STAGE2B1_APPEND_COMPLETE
  async function deactivateRuleById(
    ruleId,
  ) {
    const rule =
      ruleById(
        clean(ruleId),
      );

    if (!rule) {
      throw new Error(
        "The selected Nova Email rule was not found.",
      );
    }

    if (
      rule.enabled ===
      false
    ) {
      notify(
        "This rule is already inactive.",
        "success",
      );

      return rule;
    }

    const approved =
      window.confirm(
        `Deactivate "${rule.name}"?\n\nThis blocks future matching Autopilot activity. It does not send email and does not delete the rule.`,
      );

    if (!approved) {
      return null;
    }

    return await runBuilderTask(
      async () => {
        const result =
          await apiRequest(
            `${apiBasePath()}/rules/${encodeURIComponent(rule.id)}`,
            {
              method: "PATCH",

              timeoutMilliseconds:
                30000,

              body:
                JSON.stringify({
                  confirmed: true,
                  enabled: false,
                }),
            },
          );

        const saved =
          result?.rule;

        if (
          !saved ||
          !clean(saved.id)
        ) {
          throw new Error(
            "The server did not return the deactivated Nova Email rule.",
          );
        }

        state.rules =
          state.rules.map(
            (item) =>
              item.id ===
              saved.id
                ? saved
                : item,
          );

        if (
          state.editingRuleId ===
          saved.id
        ) {
          closeRuleEditor();
        }

        renderAll();

        notify(
          "Rule deactivated. No trigger was fired and no email was sent.",
          "success",
        );

        return saved;
      },
    );
  }

  function duplicateTemplateById(
    templateId,
  ) {
    const source =
      templateById(
        clean(templateId),
      );

    if (!source) {
      throw new Error(
        "The selected template was not found.",
      );
    }

    const now =
      new Date().toISOString();

    const copy = {
      ...source,

      id:
        randomToken(),

      name:
        `Copy of ${source.name}`.slice(
          0,
          200,
        ),

      createdAt: now,
      updatedAt: now,
    };

    state.templates = [
      copy,
      ...state.templates,
    ];

    state.activeTemplateId =
      copy.id;

    saveTemplatesToBrowser();
    renderAll();
    openTemplateEditor(copy);

    notify(
      "Template duplicated locally. No email was sent.",
      "success",
    );

    return copy;
  }

  function previewTemplateById(
    templateId,
  ) {
    const template =
      templateById(
        clean(templateId),
      );

    if (!template) {
      throw new Error(
        "The selected template was not found.",
      );
    }

    state.activeTemplateId =
      template.id;

    openTemplateEditor(
      template,
    );

    previewTemplateValues({
      id:
        template.id,

      name:
        template.name,

      subject:
        template.subject,

      textBody:
        template.textBody,
    });
  }

  function deleteTemplateById(
    templateId,
  ) {
    const template =
      templateById(
        clean(templateId),
      );

    if (!template) {
      throw new Error(
        "The selected template was not found.",
      );
    }

    const linkedRules =
      state.rules.filter(
        (rule) =>
          clean(
            rule.subjectTemplate,
          ) ===
            template.subject &&
          clean(
            rule.textTemplate,
          ) ===
            template.textBody,
      ).length;

    const message =
      linkedRules > 0
        ? `Delete the local template "${template.name}"?\n\n${linkedRules} existing server rule(s) will keep their currently saved subject and message. No rule will be changed and no email will be sent.`
        : `Delete the local template "${template.name}"?\n\nNo email will be sent.`;

    if (
      !window.confirm(message)
    ) {
      return false;
    }

    state.templates =
      state.templates.filter(
        (item) =>
          item.id !==
          template.id,
      );

    if (
      state.activeTemplateId ===
      template.id
    ) {
      state.activeTemplateId =
        "";
    }

    if (
      state.editingTemplateId ===
      template.id
    ) {
      closeTemplateEditor();
    }

    saveTemplatesToBrowser();
    renderAll();

    notify(
      linkedRules > 0
        ? "Local template deleted. Existing server rules were preserved."
        : "Local template deleted.",
      "success",
    );

    return true;
  }

  function duplicateRuleById(
    ruleId,
  ) {
    const source =
      ruleById(
        clean(ruleId),
      );

    if (!source) {
      throw new Error(
        "The selected Nova Email rule was not found.",
      );
    }

    openRuleEditor({
      ...source,

      id: "",

      name:
        `Copy of ${source.name}`.slice(
          0,
          200,
        ),

      sendMode:
        "draft_only",

      enabled: false,

      preapproved: false,
      preapprovedAt: null,
      preapprovedBy: null,
    });

    notify(
      "A safe Draft Only copy is ready for review. It has not been saved and no email was sent.",
      "success",
    );
  }

  function navControlFromTarget(
    target,
  ) {
    return target?.closest?.(
      [
        "[data-view]",
        "[data-page]",
        "[data-nav]",
        ".nav-item",
        ".sidebar a",
        ".sidebar button",
        "nav a",
        "nav button",
      ].join(","),
    ) || null;
  }

  function navControlLabel(
    control,
  ) {
    return clean(
      [
        control?.dataset?.view,
        control?.dataset?.page,
        control?.dataset?.nav,
        control?.getAttribute?.(
          "aria-label",
        ),
        control?.textContent,
      ]
        .filter(Boolean)
        .join(" "),
    )
      .replace(
        /\s+/g,
        " ",
      )
      .toLowerCase();
  }

  function isTemplatesNav(
    control,
  ) {
    const label =
      navControlLabel(
        control,
      );

    return (
      label ===
        "templates" ||
      label.includes(
        " templates",
      ) ||
      label.includes(
        "templates ",
      )
    );
  }

  function isSidebarControl(
    control,
  ) {
    return Boolean(
      control?.closest?.(
        ".sidebar, nav",
      ),
    );
  }

  function updateNavVisual(
    activeControl = null,
  ) {
    const controls =
      document.querySelectorAll(
        [
          "[data-view]",
          "[data-page]",
          "[data-nav]",
          ".nav-item",
          ".sidebar a",
          ".sidebar button",
        ].join(","),
      );

    for (
      const control
      of controls
    ) {
      const label =
        navControlLabel(
          control,
        );

      const active =
        activeControl
          ? control ===
            activeControl
          : label.includes(
              "command center",
            );

      control.classList.toggle(
        "active",
        active,
      );

      if (
        control.hasAttribute(
          "aria-current",
        )
      ) {
        control.setAttribute(
          "aria-current",
          active
            ? "page"
            : "false",
        );
      }
    }
  }

  async function openBuilder(
    tab = "templates",
    navControl = null,
  ) {
    loadTemplatesFromBrowser();

    ensureWorkspace();
    setWorkspaceVisible(true);
    switchBuilderTab(
      tab,
    );

    renderAll();
    updateNavVisual(
      navControl,
    );

    await refreshBuilderData({
      announce: false,
    });
  }

  function closeBuilder() {
    closeTemplateEditor();
    closeRuleEditor();
    setWorkspaceVisible(false);
    updateNavVisual();
  }

  function bindWorkspaceEvents() {
    const workspace =
      ensureWorkspace();

    if (
      workspace.dataset
        .k133BuilderBound ===
      BUILD
    ) {
      return;
    }

    workspace.dataset
      .k133BuilderBound =
      BUILD;

    const templateForm =
      workspace.querySelector(
        "[data-k133-template-form]",
      );

    const ruleForm =
      workspace.querySelector(
        "[data-k133-rule-form]",
      );

    templateForm.addEventListener(
      "submit",
      (event) => {
        try {
          saveTemplateFromForm(
            event,
          );
        } catch (error) {
          notify(
            clean(error?.message) ||
              "The template could not be saved.",
            "error",
          );
        }
      },
    );

    ruleForm.addEventListener(
      "submit",
      (event) => {
        void saveRuleFromForm(
          event,
        );
      },
    );

    workspace.addEventListener(
      "click",
      (event) => {
        const button =
          event.target.closest(
            "button",
          );

        if (
          !button ||
          !workspace.contains(
            button,
          )
        ) {
          return;
        }

        if (
          button.matches(
            "[data-k133-close-builder]",
          )
        ) {
          closeBuilder();
          return;
        }

        if (
          button.matches(
            "[data-k133-refresh-all]",
          )
        ) {
          void refreshBuilderData({
            announce: true,
          });

          return;
        }

        if (
          button.matches(
            "[data-k133-tab]",
          )
        ) {
          switchBuilderTab(
            clean(
              button.dataset
                .k133Tab,
            ) ||
              "templates",
          );

          return;
        }

        if (
          button.matches(
            "[data-k133-new-template]",
          )
        ) {
          switchBuilderTab(
            "templates",
          );

          openTemplateEditor();
          return;
        }

        if (
          button.matches(
            "[data-k133-cancel-template]",
          )
        ) {
          closeTemplateEditor();
          return;
        }

        if (
          button.matches(
            "[data-k133-preview-template]",
          )
        ) {
          try {
            previewTemplateValues();
          } catch (error) {
            notify(
              clean(
                error?.message,
              ) ||
                "The template preview could not be created.",
              "error",
            );
          }

          return;
        }

        if (
          button.matches(
            "[data-k133-create-test-draft]",
          )
        ) {
          void createTestDraftFromForm();
          return;
        }

        if (
          button.matches(
            "[data-k133-new-rule]",
          )
        ) {
          switchBuilderTab(
            "rules",
          );

          openRuleEditor();
          return;
        }

        if (
          button.matches(
            "[data-k133-cancel-rule]",
          )
        ) {
          closeRuleEditor();
          return;
        }

        if (
          button.matches(
            "[data-k133-deactivate-rule]",
          )
        ) {
          void deactivateRuleById(
            state.editingRuleId,
          );

          return;
        }

        const templateAction =
          clean(
            button.dataset
              .k133TemplateAction,
          );

        if (templateAction) {
          const templateId =
            clean(
              button.dataset
                .k133TemplateId,
            );

          try {
            if (
              templateAction ===
              "edit"
            ) {
              const template =
                templateById(
                  templateId,
                );

              if (!template) {
                throw new Error(
                  "The selected template was not found.",
                );
              }

              state.activeTemplateId =
                template.id;

              openTemplateEditor(
                template,
              );
            } else if (
              templateAction ===
              "duplicate"
            ) {
              duplicateTemplateById(
                templateId,
              );
            } else if (
              templateAction ===
              "preview"
            ) {
              previewTemplateById(
                templateId,
              );
            } else if (
              templateAction ===
              "delete"
            ) {
              deleteTemplateById(
                templateId,
              );
            }
          } catch (error) {
            notify(
              clean(
                error?.message,
              ) ||
                "The template action failed.",
              "error",
            );
          }

          return;
        }

        const ruleAction =
          clean(
            button.dataset
              .k133RuleAction,
          );

        if (ruleAction) {
          const ruleId =
            clean(
              button.dataset
                .k133RuleId,
            );

          try {
            if (
              ruleAction ===
              "edit"
            ) {
              const rule =
                ruleById(
                  ruleId,
                );

              if (!rule) {
                throw new Error(
                  "The selected Nova Email rule was not found.",
                );
              }

              openRuleEditor(
                rule,
              );
            } else if (
              ruleAction ===
              "duplicate"
            ) {
              duplicateRuleById(
                ruleId,
              );
            } else if (
              ruleAction ===
              "deactivate"
            ) {
              void deactivateRuleById(
                ruleId,
              );
            }
          } catch (error) {
            notify(
              clean(
                error?.message,
              ) ||
                "The rule action failed.",
              "error",
            );
          }
        }
      },
    );
  }

  function bindNavigationEvents() {
    if (
      document.documentElement
        .dataset
        .k133TemplateBuilderNavBound ===
      BUILD
    ) {
      return;
    }

    document.documentElement
      .dataset
      .k133TemplateBuilderNavBound =
      BUILD;

    document.addEventListener(
      "click",
      (event) => {
        const control =
          navControlFromTarget(
            event.target,
          );

        if (!control) {
          return;
        }

        if (
          isTemplatesNav(
            control,
          )
        ) {
          event.preventDefault();
          event.stopPropagation();
          event.stopImmediatePropagation();

          void openBuilder(
            "templates",
            control,
          );

          return;
        }

        const workspace =
          byId(
            WORKSPACE_ID,
          );

        if (
          workspace &&
          !workspace.hidden &&
          isSidebarControl(
            control,
          )
        ) {
          setWorkspaceVisible(
            false,
          );
        }
      },
      true,
    );
  }

  function korlixInstallTemplateRuleBuilderV1() {
    if (
      globalThis
        .K133_NOVA_EMAIL_TEMPLATE_RULE_BUILDER_V1_INSTALLED ===
      true
    ) {
      return;
    }

    globalThis
      .K133_NOVA_EMAIL_TEMPLATE_RULE_BUILDER_V1_INSTALLED =
      true;

    loadTemplatesFromBrowser();
    ensureWorkspace();
    bindWorkspaceEvents();
    bindNavigationEvents();
    renderAll();
  }

  globalThis
    .korlixInstallTemplateRuleBuilderV1 =
    korlixInstallTemplateRuleBuilderV1;

  if (
    document.readyState ===
    "loading"
  ) {
    document.addEventListener(
      "DOMContentLoaded",
      () => {
        korlixInstallTemplateRuleBuilderV1();
      },
      {
        once: true,
      },
    );
  } else {
    korlixInstallTemplateRuleBuilderV1();
  }

// K133_TEMPLATE_RULE_BUILDER_STAGE2B2_APPEND_COMPLETE
// K133_NOVA_EMAIL_TEMPLATE_RULE_BUILDER_V1_END
})();
