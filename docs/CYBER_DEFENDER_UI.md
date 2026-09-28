# Cybersecurity Defender interface

Open Utilities → Cybersecurity Defender. The main tabs are Check a message, Safety checklist, Incident help and Saved reports. Uses the active KORLIX theme, including Pure White and Midnight, with phone and desktop layouts.

A free quick check is the default. The deeper KORLIX review is opt-in and displays its one-credit cost and OpenAI consent before submission. Text limits, privacy guidance and the feature's text-only scope are visible in the form. A sample lets users try the flow immediately. Original pasted text is cleared once a report is acknowledged.

Saved reports show qualitative concern, findings, defanged destinations, optional AI observations and action progress. No suspicious URL is clickable. Official resource buttons use a compiled allowlist of FTC/CISA URLs rather than model or server-supplied destinations. Report exports are plain text. Deletion requires confirmation and is disabled during a pending AI review or uncertain progress update.

Unconfirmed creation/progress retains the exact idempotency key for explicit retry. Refresh reconciles durable server state. Session changes immediately clear private fields, dialogs and reports; in-flight responses and exports from the old session are discarded. Token refresh in the same session remains valid. Polling stops on disposal, never submits new work and cannot roll action progress back to an older revision.

Tests: `flutter test --no-pub test/cyber_defender_test.dart`. They cover API response binding, authentication changes, UTF-8 results, form enablement, consent refusal, uncertain request retries, checklist persistence, guides, progress, export/delete, pending AI review, and 320/390/1280px layouts with 125% text in light/dark themes. Optional `DEFENDER_CAPTURE_DIR` captures actual Flutter screenshots with synthetic data. Provider behavior is stubbed; no user secrets or generation credits are used.

The UI and documentation do not claim continuous monitoring, antivirus, reputation verification, device scanning or automatic remediation. Habit completion is self-reported.
