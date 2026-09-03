"use strict";

// K134B_SAFE_DRAFT_DELETE_UI_V1_BEGIN
(() => {
  const deleteStatuses = new Set([
    "draft",
    "pending_approval",
    "approved",
    "failed",
  ]);

  const typedStatuses = new Set([
    "approved",
    "failed",
  ]);

  const busy = new Set();

  const first = (...values) =>
    values.find(
      (value) =>
        value !== undefined &&
        value !== null &&
        value !== "",
    );

  const escapeHtml = (value) =>
    String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

  const draftId = (draft) =>
    String(
      first(
        draft?.id,
        draft?.messageId,
        draft?.message_id,
        "",
      ),
    );

  const draftStatus = (draft) =>
    String(
      first(
        draft?.status,
        "draft",
      ),
    ).toLowerCase();

  const providerMessageId = (draft) =>
    String(
      first(
        draft?.providerMessageId,
        draft?.provider_message_id,
        "",
      ),
    );

  const canDelete = (draft) => {
    if (
      !draft ||
      !draftId(draft)
    ) {
      return false;
    }

    if (
      typeof draft.canDelete ===
      "boolean"
    ) {
      return draft.canDelete;
    }

    return (
      deleteStatuses.has(
        draftStatus(draft),
      ) &&
      !first(
        draft?.sentAt,
        draft?.sent_at,
      ) &&
      !providerMessageId(draft)
    );
  };

  const requiresTypedPhrase = (draft) =>
    draft?.deleteConfirmationRequired === true ||
    typedStatuses.has(
      draftStatus(draft),
    );

  const subject = (draft) =>
    String(
      first(
        draft?.subject,
        "Untitled draft",
      ),
    );

  const recipient = (draft) =>
    String(
      first(
        draft?.toEmail,
        draft?.to_email,
        "Recipient saved",
      ),
    );

  const formatDate = (value) => {
    if (!value) {
      return "—";
    }

    const parsed =
      new Date(value);

    return Number.isNaN(
      parsed.getTime(),
    )
      ? String(value)
      : parsed.toLocaleString();
  };

  const requireGlobals = () =>
    typeof APP === "object" &&
    typeof requestJson === "function" &&
    typeof emailBase === "function" &&
    typeof refreshDashboard === "function";

  function managerModal() {
    let modal =
      document.getElementById(
        "k134bDraftDeleteManager",
      );

    if (modal) {
      return modal;
    }

    modal =
      document.createElement(
        "div",
      );

    modal.id =
      "k134bDraftDeleteManager";

    modal.className =
      "k134b-delete-overlay";

    modal.hidden =
      true;

    modal.innerHTML = `
      <section
        class="k134b-delete-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="k134bDeleteManagerTitle"
      >
        <div class="k134b-delete-dialog-head">
          <div>
            <small>UNSENT EMAIL MANAGEMENT</small>
            <h2 id="k134bDeleteManagerTitle">Delete Drafts</h2>
          </div>

          <button
            type="button"
            class="k134b-delete-close"
            data-k134b-delete-close
            aria-label="Close"
          >
            ×
          </button>
        </div>

        <p class="k134b-delete-help">
          Deletion cancels an unsent draft and removes it from the active queue.
          Sent or actively sending email cannot be deleted.
        </p>

        <div
          id="k134bDraftDeleteRows"
          class="k134b-delete-list"
        ></div>
      </section>
    `;

    document.body.appendChild(
      modal,
    );

    modal.addEventListener(
      "click",
      (event) => {
        if (
          event.target === modal ||
          event.target.closest(
            "[data-k134b-delete-close]",
          )
        ) {
          closeManager();
          return;
        }

        const button =
          event.target.closest(
            "button[data-k134b-delete-id]",
          );

        if (!button) {
          return;
        }

        const id =
          button.dataset
            .k134bDeleteId ||
          "";

        const draft =
          (APP.drafts || []).find(
            (item) =>
              draftId(item) ===
              id,
          );

        if (draft) {
          void deleteDraft(
            draft,
          );
        }
      },
    );

    return modal;
  }

  function openManager() {
    const modal =
      managerModal();

    renderManager();

    modal.hidden =
      false;

    document.documentElement
      .classList
      .add(
        "k134b-delete-modal-open",
      );
  }

  function closeManager() {
    const modal =
      document.getElementById(
        "k134bDraftDeleteManager",
      );

    if (modal) {
      modal.hidden =
        true;
    }

    document.documentElement
      .classList
      .remove(
        "k134b-delete-modal-open",
      );
  }

  function renderManager() {
    const rows =
      document.getElementById(
        "k134bDraftDeleteRows",
      );

    if (
      !rows ||
      !requireGlobals()
    ) {
      return;
    }

    const drafts =
      (APP.drafts || []).filter(
        (draft) =>
          draftStatus(draft) !==
          "cancelled",
      );

    if (!drafts.length) {
      rows.innerHTML = `
        <div class="k134b-delete-empty">
          There are no active drafts to manage.
        </div>
      `;

      return;
    }

    rows.innerHTML =
      drafts
        .map((draft) => {
          const id =
            draftId(draft);

          const allowed =
            canDelete(draft);

          const isBusy =
            busy.has(id);

          const status =
            draftStatus(draft);

          return `
            <article class="k134b-delete-row">
              <div class="k134b-delete-row-copy">
                <strong>
                  ${escapeHtml(subject(draft))}
                </strong>

                <span>
                  ${escapeHtml(recipient(draft))}
                </span>

                <small>
                  ${escapeHtml(status.toUpperCase())}
                  ·
                  ${escapeHtml(
                    formatDate(
                      first(
                        draft?.createdAt,
                        draft?.created_at,
                      ),
                    ),
                  )}
                </small>
              </div>

              <button
                type="button"
                class="k134b-delete-button"
                data-k134b-delete-id="${escapeHtml(id)}"
                ${allowed && !isBusy ? "" : "disabled"}
                title="${
                  allowed
                    ? "Delete this unsent draft"
                    : "This record is sent, sending, cancelled, or requires safety review"
                }"
              >
                ${
                  isBusy
                    ? "DELETING…"
                    : allowed
                      ? "DELETE DRAFT"
                      : "LOCKED"
                }
              </button>
            </article>
          `;
        })
        .join("");
  }

  function ensureManagerButton() {
    if (
      document.getElementById(
        "k134bManageDraftsButton",
      )
    ) {
      return;
    }

    const heading =
      document.querySelector(
        "#draftsPanel .panel-heading",
      );

    if (!heading) {
      return;
    }

    const button =
      document.createElement(
        "button",
      );

    button.type =
      "button";

    button.id =
      "k134bManageDraftsButton";

    button.className =
      "small-action k134b-delete-toolbar-button";

    button.textContent =
      "Delete Drafts";

    button.addEventListener(
      "click",
      openManager,
    );

    heading.appendChild(
      button,
    );
  }

  function ensureDetailsButton() {
    let button =
      document.getElementById(
        "deleteDraftButton",
      );

    if (!button) {
      const approve =
        document.getElementById(
          "approveSendButton",
        );

      const actions =
        approve?.closest(
          ".modal-actions",
        ) ||
        document.querySelector(
          "#detailsModal .modal-actions",
        );

      if (!actions) {
        return;
      }

      button =
        document.createElement(
          "button",
        );

      button.type =
        "button";

      button.id =
        "deleteDraftButton";

      button.className =
        "button k134b-delete-details-button";

      button.textContent =
        "DELETE DRAFT";

      button.addEventListener(
        "click",
        () => {
          if (
            APP.selectedDraft
          ) {
            void deleteDraft(
              APP.selectedDraft,
            );
          }
        },
      );

      if (approve) {
        actions.insertBefore(
          button,
          approve,
        );
      } else {
        actions.appendChild(
          button,
        );
      }
    }

    const selected =
      APP.selectedDraft;

    const allowed =
      canDelete(
        selected,
      );

    const id =
      draftId(
        selected,
      );

    button.hidden =
      !selected;

    button.disabled =
      !allowed ||
      busy.has(id);

    button.title =
      allowed
        ? "Delete this unsent draft"
        : "This email can no longer be deleted";
  }

  function closeDetails() {
    if (
      typeof hideModal ===
      "function"
    ) {
      try {
        hideModal(
          "detailsModal",
        );

        return;
      } catch {
        // Continue to DOM-only close.
      }
    }

    const modal =
      document.getElementById(
        "detailsModal",
      );

    if (modal) {
      modal.hidden =
        true;

      modal.classList.remove(
        "open",
        "visible",
        "active",
      );
    }
  }

  async function deleteDraft(
    draft,
  ) {
    if (!requireGlobals()) {
      window.alert(
        "Nova Email is not connected yet. Press Refresh and try again.",
      );

      return;
    }

    const id =
      draftId(draft);

    if (
      !id ||
      busy.has(id) ||
      !canDelete(draft)
    ) {
      return;
    }

    let confirmationPhrase =
      "";

    if (
      requiresTypedPhrase(
        draft,
      )
    ) {
      confirmationPhrase =
        window.prompt(
          `Type DELETE DRAFT to remove this ${draftStatus(draft)} item from the active Draft Queue.`,
          "",
        ) ||
        "";

      if (
        confirmationPhrase !==
        "DELETE DRAFT"
      ) {
        return;
      }
    } else {
      const confirmed =
        window.confirm(
          `Delete the unsent draft “${subject(draft)}”?\n\n`
          + "The record will be safely cancelled and no email will be sent.",
        );

      if (!confirmed) {
        return;
      }
    }

    busy.add(
      id,
    );

    renderManager();
    ensureDetailsButton();

    try {
      const result =
        await requestJson(
          `${emailBase()}/drafts/${encodeURIComponent(id)}`,
          {
            method:
              "DELETE",

            body:
              JSON.stringify({
                confirmed:
                  true,

                confirmation:
                  true,

                confirmationPhrase,
              }),
          },
        );

      if (
        result?.deleted !==
        true
      ) {
        throw new Error(
          result?.error ||
          "The draft deletion was not confirmed by the server.",
        );
      }

      APP.drafts =
        (APP.drafts || []).filter(
          (item) =>
            draftId(item) !==
            id,
        );

      if (
        draftId(
          APP.selectedDraft,
        ) === id
      ) {
        APP.selectedDraft =
          null;

        closeDetails();
      }

      renderManager();

      if (
        typeof toast ===
        "function"
      ) {
        toast(
          "Draft deleted safely. No email was sent.",
          "success",
        );
      }

      await refreshDashboard({
        silent:
          true,
      });
    } catch (error) {
      if (
        typeof toast ===
        "function"
      ) {
        toast(
          error?.message ||
          "The draft could not be deleted.",
          "error",
        );
      } else {
        window.alert(
          error?.message ||
          "The draft could not be deleted.",
        );
      }
    } finally {
      busy.delete(
        id,
      );

      renderManager();
      ensureDetailsButton();
    }
  }

  function refreshDeleteUi() {
    if (!requireGlobals()) {
      return;
    }

    ensureManagerButton();
    managerModal();
    renderManager();
    ensureDetailsButton();
  }

  function install() {
    refreshDeleteUi();

    const originalRenderDashboard =
      renderDashboard;

    renderDashboard =
      function k134bRenderDashboardWithDraftDelete(
        ...argumentsList
      ) {
        const result =
          originalRenderDashboard(
            ...argumentsList,
          );

        queueMicrotask(
          refreshDeleteUi,
        );

        return result;
      };

    document.addEventListener(
      "click",
      () => {
        window.setTimeout(
          ensureDetailsButton,
          0,
        );
      },
    );

    document.addEventListener(
      "keydown",
      (event) => {
        if (
          event.key ===
          "Escape"
        ) {
          closeManager();
        }
      },
    );
  }

  if (
    document.readyState ===
    "loading"
  ) {
    document.addEventListener(
      "DOMContentLoaded",
      install,
      {
        once:
          true,
      },
    );
  } else {
    install();
  }
})();
// K134B_SAFE_DRAFT_DELETE_UI_V1_END
