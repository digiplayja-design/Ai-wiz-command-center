# Workforce business workspaces and K-Nova

Workforce is for any Enterprise subscriber's business, agency, independent team or nonprofit. It is not restricted to KORLIX employees. Invited people use their existing KORLIX accounts; the workspace owner's current Enterprise entitlement funds workspace access. This release keeps that plan model and expands the product beyond attendance-focused employer screens.

## Business and team setup

- Twelve industry presets: general, construction/trades, field services, retail, hospitality, care/support, logistics, professional services, technology/remote teams, education, nonprofit and events/creative work.
- Company name and description, plus on-site, field, remote or hybrid work mode. Owners can update the business profile. Industry presets choose an initial output unit without enabling camera or location requirements. Changing an existing profile does not replace attendance policies.
- Employee, contractor, freelancer, volunteer and partner labels, job title/specialty and usual site. Labels are descriptive; the existing owner/manager/member access rules remain authoritative. Invitation acceptance carries those labels into the team profile. No real invitation or message is sent by deployment.
- Existing multiple-company switching, teams, attendance, work logs, timesheets, schedules, corrections, CSV exports and paused-by-default follow-ups continue to work.

## Work board

Tasks are independent of clock-in. Managers assign tasks to active members of their own workspace; ordinary members can create their own tasks and see only tasks currently assigned to them. Task descriptions, project/customer, site, priority and optional due time support office, field, remote and volunteer work. Search, status filters and Assigned to me narrow the board. Deadlines are shown in the device timezone with an explicit label.

Assignees report To do, In progress, Blocked or Done with a progress note. Only managers edit/reassign/cancel tasks or reopen cancelled work. Progress does not add shift output units, approve time or trigger payroll. Stale versions reject rather than overwrite; stable request IDs prevent retry duplicates. Reassignment removes the previous assignee's access on subsequent requests. The board returns the latest 500 tasks and labels truncation; each workspace supports 5,000 stored tasks.

## K-Nova

Talk to K-Nova opens the existing LIVE CONVO voice experience with five isolated tools:

- `get_workforce_context`: current workspace day/timezone, role, recorded metrics and bounded authorized records.
- `search_workforce_records`: members, tasks, schedules or work updates within the returned window.
- `draft_workforce_task`: personal tasks for members, team assignments for managers/owners.
- `draft_workforce_schedule`: manager/owner shift drafts with explicit timezone and a maximum 24-hour span.
- `draft_workforce_update`: only the speaker's own current or recently ended shift, with newly completed units.

Voice tools never write business records. Review in Workforce first stops microphone tracks, WebRTC and the usage session, then opens the normal editable form. Only its save button submits the command. Drafts pin the workspace, signed-in member and membership version. Account changes, revoked access, stale memberships, pause and late responses discard pending results. Existing LIVE CONVO allowance applies; membership and plan are checked before a Workforce voice session reaches the reservation middleware.

AI sharing permission explicitly covers authorized company/team/task/schedule/work-update records and voice. Tool output excludes attendance photos, precise location events, member emails, invitation codes and audit history. Ordinary members' context is filtered to their own records. Context uses the current workspace day, schedules extend seven days, and truncated results are labeled. Notes and tool data are untrusted content, never instructions. K-Nova cannot clock people in/out, approve corrections/time, change roles/policies, contact anyone, run other app tools or activate automations.

## Storage and rollout

The applied migration `20261002135317_workforce_business_workspace.sql` adds profile columns, private task storage and `korlix_workforce_workspace_v2`. The original attendance function stays unchanged for rollback. Both tables and functions are unavailable to browser roles; service-role execution requires the backend's verified actor, fresh membership and owner plan. Task foreign keys bind creators and assignees to the same organization; mutation locks match the original workspace lock, and optimistic versions protect edits. Existing records are preserved.

Apply the additive migration, deploy the existing backend release branch, verify `/api/health` reports Workforce version 2 and anonymous Workforce requests return 401, then deploy the frontend release branch. No new Render service, paid resource, provider key, invitation, automation rule or outbound communication is created. Email follow-ups retain the existing approved owner/agent binding and delivery controls; this release does not make outbound email or calling generally available to every business.

Rollback: redeploy the previous backend/frontend revisions. Keep the additive schema and recorded tasks. The original attendance RPC and existing policies remain usable by the old backend.

## Verification

- Backend Workforce, automations, voice and FieldProof voice regression suites: 28 tests passed against isolated PostgreSQL and HTTP fixtures.
- Flutter Workforce, new business/task/review flows, Workforce voice and FieldProof voice lifecycle suites: 37 tests passed. Coverage includes responsive 390/768/1440-pixel screens, unsaved drafts, editable save handoff, replay rejection, microphone cleanup failure, account changes, tenant/role boundaries and stale membership.
- Workforce module and tests: analyzer clean. Shared main/voice files retain pre-existing informational style/deprecation findings, without analysis errors or warnings.
- Release web build passed. Production migration verification confirms task RLS, service-only table/RPC access, preserved organization count and unchanged attendance RPC body (`fb0029a12a3532360a6eb7f3e3c1e768`). Public deployment checks complete the rollout.
- A real microphone conversation and device permissions still need the user's device acceptance check; mocked transport tests do not replace it.
