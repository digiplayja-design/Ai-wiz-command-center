"use strict";

// K134B_NOVA_EMAIL_SCHEDULE_DASHBOARD_V1_BEGIN
(() => {
  const state = {
    busyRuleId: "",
  };

  // K134B_SCHEDULE_STATUS_NORMALIZATION_V1_BEGIN
  const placeholderTexts = new Set([
    "",
    "undefined",
    "null",
    "nan",
  ]);

  const isMeaningful = (value) => {
    if (
      value === undefined ||
      value === null
    ) {
      return false;
    }

    if (
      typeof value !==
      "string"
    ) {
      return true;
    }

    return !placeholderTexts.has(
      value
        .trim()
        .toLowerCase(),
    );
  };

  const first = (...values) =>
    values.find(
      isMeaningful,
    );

  const optionalText = (value) => {
    const selected =
      first(value);

    return selected === undefined
      ? ""
      : String(selected).trim();
  };

  const bool = (
    value,
    fallback = false,
  ) => {
    if (typeof value === "boolean") {
      return value;
    }

    const normalized = String(
      value ?? "",
    )
      .trim()
      .toLowerCase();

    if (
      [
        "true",
        "1",
        "yes",
        "on",
        "enabled",
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
      ].includes(normalized)
    ) {
      return false;
    }

    return fallback;
  };

  const html = (value) =>
    String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

  const ruleId = (rule) =>
    String(
      first(
        rule?.id,
        rule?.ruleId,
        rule?.rule_id,
        "",
      ),
    );

  const scheduleType = (rule) =>
    String(
      first(
        rule?.scheduleType,
        rule?.schedule_type,
        "",
      ),
    ).toLowerCase();

  const nextRun = (rule) =>
    first(
      rule?.nextRunAt,
      rule?.next_run_at,
    );

  const scheduledFor = (rule) =>
    first(
      rule?.scheduledFor,
      rule?.scheduled_for,
      nextRun(rule),
    );

  const timezone = (rule) =>
    String(
      first(
        rule?.scheduleTimezone,
        rule?.schedule_timezone,
        APP.settings?.timezone,
        "America/New_York",
      ),
    );

  const lastRun = (rule) =>
    first(
      rule?.lastRunAt,
      rule?.last_run_at,
    );

  const completedAt = (rule) =>
    first(
      rule?.completedAt,
      rule?.completed_at,
    );

  const deletedAt = (rule) =>
    first(
      rule?.deletedAt,
      rule?.deleted_at,
    );

  const lastAttempt = (rule) =>
    first(
      rule?.lastAttempt,
      rule?.last_attempt,
      rule?.metadata?.lastScheduleAttemptAt,
    );

  const lastResult = (rule) =>
    optionalText(
      first(
        rule?.lastResult,
        rule?.last_result,
        rule?.metadata?.lastScheduleResult,
        "",
      ),
    );

  const firstErrorCode = (value) => {
    if (
      Array.isArray(value)
    ) {
      return optionalText(
        first(
          ...value,
        ),
      );
    }

    return optionalText(
      value,
    );
  };

  const failureCode = (
    rule,
    message,
  ) =>
    optionalText(
      first(
        rule?.failureCode,
        rule?.failure_code,
        message?.failureCode,
        message?.failure_code,
        firstErrorCode(
          rule?.errorCodes,
        ),
        firstErrorCode(
          rule?.error_codes,
        ),
        firstErrorCode(
          message?.errorCodes,
        ),
        firstErrorCode(
          message?.error_codes,
        ),
        firstErrorCode(
          rule?.metadata
            ?.lastScheduleErrorCodes,
        ),
        "",
      ),
    );

  const messageStatusLabel = (
    rule,
    message,
  ) => {
    const explicit =
      optionalText(
        first(
          message?.status,
          lastResult(rule),
        ),
      );

    if (explicit) {
      return explicit;
    }

    if (deletedAt(rule)) {
      return "Deleted";
    }

    if (completedAt(rule)) {
      return "Completed";
    }

    if (
      !bool(
        first(
          rule?.enabled,
          rule?.isEnabled,
        ),
        false,
      )
    ) {
      return scheduleType(rule) ===
        "weekly"
        ? "Paused before send"
        : "Cancelled before send";
    }

    return "No message attempt yet";
  };

  const nextRunForDisplay = (rule) => {
    if (
      deletedAt(rule) ||
      completedAt(rule)
    ) {
      return null;
    }

    if (
      !bool(
        first(
          rule?.enabled,
          rule?.isEnabled,
        ),
        false,
      )
    ) {
      return null;
    }

    return (
      first(
        nextRun(rule),
        scheduledFor(rule),
      ) ??
      null
    );
  };

  const isScheduled = (rule) => {
    const type = scheduleType(rule);

    return (
      type === "once" ||
      type === "weekly" ||
      Boolean(
        scheduledFor(rule) ||
        nextRun(rule),
      )
    );
  };

  const recipientIds = (rule) => {
    const scope = first(
      rule?.recipientScope,
      rule?.recipient_scope,
      {},
    );

    const raw = first(
      scope?.recipientIds,
      scope?.recipient_ids,
      rule?.recipientIds,
      rule?.recipient_ids,
      [],
    );

    return Array.isArray(raw)
      ? [
          ...new Set(
            raw.map(String),
          ),
        ]
      : [];
  };

  const maskEmail = (value) => {
    const [
      left,
      domain,
    ] = String(
      value ?? "",
    ).split("@");

    if (
      !left ||
      !domain
    ) {
      return "Recipient saved";
    }

    return `${left.slice(0, 2)}***@${domain}`;
  };

  const recipientLabel = (rule) => {
    const ids = recipientIds(rule);

    const recipients = (
      APP.recipients ||
      []
    ).filter(
      (item) =>
        ids.includes(
          String(
            first(
              item?.id,
              item?.recipientId,
              item?.recipient_id,
              "",
            ),
          ),
        ),
    );

    if (!recipients.length) {
      return ids.length
        ? `${ids.length} approved recipient${ids.length === 1 ? "" : "s"}`
        : "Approved recipient scope";
    }

    return recipients
      .map(
        (item) =>
          String(
            first(
              item?.displayName,
              item?.display_name,
              item?.name,
              maskEmail(
                item?.email,
              ),
            ),
          ),
      )
      .join(", ");
  };

  const messageForRule = (rule) => {
    const id = ruleId(rule);

    const messages =
      APP.drafts ||
      [];

    return (
      messages.find(
        (message) =>
          String(
            first(
              message?.ruleId,
              message?.rule_id,
              "",
            ),
          ) === id,
      ) ||
      null
    );
  };

  const formatDate = (
    value,
    zone,
  ) => {
    if (!value) {
      return "—";
    }

    const date = new Date(value);

    if (
      Number.isNaN(
        date.getTime(),
      )
    ) {
      return String(value);
    }

    try {
      return new Intl.DateTimeFormat(
        undefined,
        {
          dateStyle: "medium",
          timeStyle: "short",
          timeZone:
            zone ||
            undefined,
          timeZoneName: "short",
        },
      ).format(date);
    } catch {
      return date.toLocaleString();
    }
  };

  const statusFor = (
    rule,
    message,
  ) => {
    if (deletedAt(rule)) {
      return {
        label: "DELETED",
        tone: "muted",
      };
    }

    if (completedAt(rule)) {
      return {
        label: "COMPLETED",
        tone: "green",
      };
    }

    const enabled =
      bool(
        first(
          rule?.enabled,
          rule?.isEnabled,
        ),
        false,
      );

    if (!enabled) {
      return {
        label:
          scheduleType(rule) ===
          "once"
            ? "CANCELLED"
            : "PAUSED",
        tone: "muted",
      };
    }

    const result =
      lastResult(rule)
        .toLowerCase();

    const messageStatus =
      optionalText(
        first(
          message?.status,
          "",
        ),
      ).toLowerCase();

    const code =
      failureCode(
        rule,
        message,
      );

    if (
      code ||
      result.includes("fail") ||
      messageStatus.includes(
        "fail",
      )
    ) {
      return {
        label: "FAILED",
        tone: "red",
      };
    }

    if (
      messageStatus ===
        "delivered" ||
      first(
        message?.deliveredAt,
        message?.delivered_at,
        message?.metadata
          ?.deliveredAt,
      )
    ) {
      return {
        label: "DELIVERED",
        tone: "green",
      };
    }

    if (
      messageStatus === "sent" ||
      result.includes("sent")
    ) {
      return {
        label: "SENT",
        tone: "green",
      };
    }

    const dueValue =
      first(
        nextRun(rule),
        scheduledFor(rule),
      );

    const due =
      new Date(
        dueValue || "",
      );

    if (
      !Number.isNaN(
        due.getTime(),
      ) &&
      due.getTime() <
        Date.now()
    ) {
      return {
        label: "OVERDUE",
        tone: "red",
      };
    }

    return {
      label: "SCHEDULED",
      tone: "gold",
    };
  };

  function ensurePanel() {
    let panel =
      document.getElementById(
        "scheduledEmailsPanel",
      );

    if (panel) {
      return panel;
    }

    panel =
      document.createElement(
        "article",
      );

    panel.className =
      "panel k134b-schedule-panel";

    panel.id =
      "scheduledEmailsPanel";

    panel.innerHTML = `
      <div class="panel-heading">
        <h2>◷ SCHEDULED EMAILS</h2>
        <button
          class="small-action"
          id="refreshSchedulesButton"
          type="button"
        >
          Refresh
        </button>
      </div>

      <div class="metric-pair k134b-schedule-metrics">
        <div>
          <strong id="scheduledEmailCount">0</strong>
          <span>Saved Schedules</span>
        </div>

        <div>
          <strong id="overdueScheduleCount">0</strong>
          <span>Needs Review</span>
        </div>
      </div>

      <div
        id="scheduledEmailList"
        class="k134b-schedule-list"
      >
        <div class="empty-state">
          No scheduled emails loaded.
        </div>
      </div>
    `;

    const anchor =
      document.getElementById(
        "draftsPanel",
      ) ||
      document.getElementById(
        "recipientsPanel",
      );

    if (anchor?.parentNode) {
      anchor.insertAdjacentElement(
        "afterend",
        panel,
      );
    } else {
      document
        .querySelector("main")
        ?.appendChild(panel);
    }

    panel
      .querySelector(
        "#refreshSchedulesButton",
      )
      ?.addEventListener(
        "click",
        async () => {
          await refreshDashboard({
            silent: false,
          });
        },
      );

    panel
      .querySelector(
        "#scheduledEmailList",
      )
      ?.addEventListener(
        "click",
        async (event) => {
          const button =
            event.target.closest(
              "button[data-k134b-disable-schedule]",
            );

          if (!button) {
            return;
          }

          const id =
            button.dataset
              .k134bDisableSchedule ||
            "";

          const rule = (
            APP.rules ||
            []
          ).find(
            (item) =>
              ruleId(item) === id,
          );

          if (
            !rule ||
            state.busyRuleId
          ) {
            return;
          }

          const type =
            scheduleType(rule);

          const action =
            type === "once"
              ? "Cancel"
              : "Pause";

          const approved =
            window.confirm(
              `${action} this scheduled email?\n\n` +
                "This prevents future scheduled execution. " +
                "It does not delete the record and does not send an email.",
            );

          if (!approved) {
            return;
          }

          state.busyRuleId = id;

          renderScheduledEmails();

          try {
            await requestJson(
              `${emailBase()}/rules/${encodeURIComponent(id)}`,
              {
                method: "PATCH",
                body: JSON.stringify({
                  confirmed: true,
                  enabled: false,
                }),
              },
            );

            const pastAction =
              type === "once"
                ? "cancelled"
                : "paused";

            if (
              typeof toast ===
              "function"
            ) {
              toast(
                `Schedule ${pastAction}. No email was sent.`,
                "success",
              );
            }

            await refreshDashboard({
              silent: true,
            });
          } catch (error) {
            if (
              typeof toast ===
              "function"
            ) {
              toast(
                error?.message ||
                  "The schedule could not be updated.",
                "error",
              );
            }
          } finally {
            state.busyRuleId = "";

            renderScheduledEmails();
          }
        },
      );

    return panel;
  }

  function renderScheduledEmails() {
    const panel =
      ensurePanel();

    if (!panel) {
      return;
    }

    const rules = (
      APP.rules ||
      []
    )
      .filter(isScheduled)
      .sort(
        (
          left,
          right,
        ) => {
          const a =
            new Date(
              nextRun(left) ||
                scheduledFor(left) ||
                0,
            ).getTime();

          const b =
            new Date(
              nextRun(right) ||
                scheduledFor(right) ||
                0,
            ).getTime();

          return a - b;
        },
      );

    const statuses =
      rules.map(
        (rule) =>
          statusFor(
            rule,
            messageForRule(rule),
          ),
      );

    panel.querySelector(
      "#scheduledEmailCount",
    ).textContent =
      String(rules.length);

    panel.querySelector(
      "#overdueScheduleCount",
    ).textContent =
      String(
        statuses.filter(
          (item) =>
            [
              "OVERDUE",
              "FAILED",
            ].includes(item.label),
        ).length,
      );

    const list =
      panel.querySelector(
        "#scheduledEmailList",
      );

    if (!rules.length) {
      list.innerHTML =
        '<div class="empty-state">' +
        "No one-time or weekly schedules are saved for this Nova profile." +
        "</div>";

      return;
    }

    list.innerHTML =
      rules
        .map((rule) => {
          const message =
            messageForRule(rule);

          const status =
            statusFor(
              rule,
              message,
            );

          const type =
            scheduleType(rule) ||
            "scheduled";

          const enabled =
            bool(
              first(
                rule?.enabled,
                rule?.isEnabled,
              ),
              false,
            );

          const canDisable =
            enabled &&
            !deletedAt(rule) &&
            !completedAt(rule);

          const messageStatus =
            messageStatusLabel(
              rule,
              message,
            );

          const delivered =
            first(
              message?.deliveredAt,
              message?.delivered_at,
              message?.metadata
                ?.deliveredAt,
            );

          const code =
            failureCode(
              rule,
              message,
            );

          return `
            <section
              class="k134b-schedule-row"
              data-state="${html(status.tone)}"
            >
              <div class="k134b-schedule-row-head">
                <div>
                  <strong>
                    ${html(
                      first(
                        rule?.subjectTemplate,
                        rule?.subject_template,
                        rule?.name,
                        "Scheduled Nova Email",
                      ),
                    )}
                  </strong>

                  <small>
                    ${html(recipientLabel(rule))}
                  </small>
                </div>

                <span
                  class="k134b-schedule-badge ${html(status.tone)}"
                >
                  ${html(status.label)}
                </span>
              </div>

              <dl class="k134b-schedule-grid">
                <div>
                  <dt>Type</dt>
                  <dd>
                    ${html(
                      type === "once"
                        ? "One-time"
                        : type === "weekly"
                          ? "Weekly"
                          : type,
                    )}
                  </dd>
                </div>

                <div>
                  <dt>Timezone</dt>
                  <dd>${html(timezone(rule))}</dd>
                </div>

                <div>
                  <dt>Scheduled</dt>
                  <dd>
                    ${html(
                      formatDate(
                        scheduledFor(rule),
                        timezone(rule),
                      ),
                    )}
                  </dd>
                </div>

                <div>
                  <dt>Next run</dt>
                  <dd>
                    ${html(
                      formatDate(
                        nextRunForDisplay(
                          rule,
                        ),
                        timezone(rule),
                      ),
                    )}
                  </dd>
                </div>

                <div>
                  <dt>Last run</dt>
                  <dd>
                    ${html(
                      formatDate(
                        lastRun(rule),
                        timezone(rule),
                      ),
                    )}
                  </dd>
                </div>

                <div>
                  <dt>Last attempt</dt>
                  <dd>
                    ${html(
                      formatDate(
                        lastAttempt(rule),
                        timezone(rule),
                      ),
                    )}
                  </dd>
                </div>

                <div>
                  <dt>Message status</dt>
                  <dd>${html(messageStatus)}</dd>
                </div>

                <div>
                  <dt>Delivered</dt>
                  <dd>
                    ${html(
                      formatDate(
                        delivered,
                        timezone(rule),
                      ),
                    )}
                  </dd>
                </div>

                <div class="wide">
                  <dt>Failure code</dt>
                  <dd>${html(code || "—")}</dd>
                </div>
              </dl>

              ${
                canDisable
                  ? `
                    <button
                      type="button"
                      class="button button-secondary k134b-schedule-stop"
                      data-k134b-disable-schedule="${html(ruleId(rule))}"
                      ${state.busyRuleId ? "disabled" : ""}
                    >
                      ${
                        type === "once"
                          ? "CANCEL SCHEDULE"
                          : "PAUSE SCHEDULE"
                      }
                    </button>
                  `
                  : ""
              }
            </section>
          `;
        })
        .join("");
  }

  globalThis.KorlixK134BScheduleDashboardTest =
    Object.freeze({
      first,
      optionalText,
      nextRun,
      scheduledFor,
      nextRunForDisplay,
      lastResult,
      failureCode,
      messageStatusLabel,
      statusFor,
    });
  // K134B_SCHEDULE_STATUS_NORMALIZATION_V1_END

  const originalRenderDashboard =
    renderDashboard;

  renderDashboard =
    function k134bRenderDashboardWithSchedules(
      ...argumentsList
    ) {
      const result =
        originalRenderDashboard(
          ...argumentsList
        );

      renderScheduledEmails();

      return result;
    };

  const start = () => {
    ensurePanel();
    renderScheduledEmails();
  };

  if (
    document.readyState ===
    "loading"
  ) {
    document.addEventListener(
      "DOMContentLoaded",
      start,
      {
        once: true,
      },
    );
  } else {
    start();
  }
})();
// K134B_NOVA_EMAIL_SCHEDULE_DASHBOARD_V1_END
