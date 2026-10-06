# Employee and manager missed-update emails

Workforce's workspace email channel can send a separate email to an employee
and their manager for the same missed update. Configure two **Work update
reminders** in Workforce → Automations, both scoped to the same employee:

1. Select the employee's approved notification address as the first recipient.
2. Select the manager's approved notification address as the second recipient.
3. Match the delay, weekdays, sending window and daily limit. Choose **Send
   automatically**, review each rule, and enable both.

Each rule has its own recipient approval, delivery record and opt-out. Use an
explicit employee scope for an employee-facing reminder: an **All members**
rule sends all matching employees' reminders to its one selected address.
New employees need their own approved recipient and reminder configuration;
Workforce does not infer notification addresses from names or sign-in emails.

The existing backend checks conditions every minute while the app is closed.
Timing includes the shift's update interval, its policy grace period, and the
rule's extra delay. A 60-minute interval, 10-minute grace and 10-minute delay
therefore trigger after 80 worked minutes without an update, subject to the
sending window, weekdays and daily caps. Breaks pause the condition, and a new
update or clock-out resolves it.

Each recipient gets at most one email for an overdue update cycle, rather than
another message on every worker tick. Another missed update after a submission
creates a new cycle. Pausing one rule or opting out affects that recipient's
copy independently. Provider acceptance is recorded separately from delivery.

Validation: `node --test backend/test/workforce_emails.test.mjs` includes a real
in-memory Postgres check of two automatic rules sharing one event key. It checks
separate recipients, separate delivery records, and no repeats across worker
ticks. Its email provider is mocked; the test sends no real messages.
