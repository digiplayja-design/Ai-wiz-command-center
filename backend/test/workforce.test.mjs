import test from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import express from "express";
import { registerWorkforce } from "../workforce/routes.mjs";
import { createWorkforceStore } from "../workforce/store.mjs";
import {
  defaults,
  policy,
  location,
  shiftSeconds,
  enrichSnapshot,
  csvCell,
  tokenHash,
  evidenceFlags,
} from "../workforce/core.mjs";
const ids = Array.from({ length: 5 }, () => randomUUID());
const [owner, worker, manager, outsider, otherOwner] = ids;
let db, org, shift, api, server;
const call = async (
  actor,
  action,
  p = {},
  o = org,
  email = `${actor}@example.com`,
) => {
  const r = await db.query(
    "select public.korlix_workforce_workspace_v2($1,$2,$3,$4,$5::jsonb) as value",
    [actor, email, action, o, JSON.stringify(p)],
  );
  return r.rows[0].value;
};
const punch = (action, version = 1, extra = {}) => ({
  request_id: randomUUID(),
  version,
  client_time: new Date().toISOString(),
  flags: [],
  ...extra,
});
const join = async (user, role = "employee", o = org) => {
  const token = randomUUID();
  await call(
    owner,
    "invite",
    {
      email: `${user}@example.com`,
      display_name: role,
      role,
      token_hash: tokenHash(token),
    },
    o,
  );
  await call(user, "accept", { token_hash: tokenHash(token) }, null);
  return token;
};
test.before(async () => {
  db = new PGlite();
  await db.exec(
    `create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema storage;create table auth.users(id uuid primary key);create table public.user_profiles(id uuid primary key,tier text);create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);grant usage on schema public to service_role;grant select on public.user_profiles to service_role;`,
  );
  for (const u of ids) {
    await db.query("insert into auth.users values($1)", [u]);
    await db.query("insert into user_profiles values($1,$2)", [
      u,
      [owner, otherOwner].includes(u) ? "enterprise" : "basic",
    ]);
  }
  await db.exec(
    await readFile(
      new URL(
        "../../supabase/migrations/20260922000006_enterprise_workforce.sql",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  for(const f of await readdir(new URL('../../supabase/migrations/',import.meta.url))) if(f.endsWith('_workforce_business_workspace.sql')) await db.exec(await readFile(new URL('../../supabase/migrations/'+f,import.meta.url),'utf8'));
  await db.exec("set role service_role");
});
test.after(async () => {
  if (server) await new Promise((r) => server.close(r));
  await db?.close();
});
test("Enterprise workspace, email-bound one-use invitations, private tables and RPC", async () => {
  await assert.rejects(
    call(
      worker,
      "create",
      { name: "No", display_name: "No", timezone: "UTC" },
      null,
    ),
    /Enterprise/,
  );
  org = (
    await call(
      owner,
      "create",
      {
        name: "KORLIX Team",
        display_name: "Owner",
        timezone: "America/New_York",
      },
      null,
    )
  ).id;
  const token = randomUUID();
  await call(owner, "invite", {
    email: `${worker}@example.com`,
    display_name: "Ari",
    role: "employee",
    token_hash: tokenHash(token),
  });
  await assert.rejects(
    call(outsider, "accept", { token_hash: tokenHash(token) }, null),
    /different email/,
  );
  await call(worker, "accept", { token_hash: tokenHash(token) }, null);
  await assert.rejects(
    call(worker, "accept", { token_hash: tokenHash(token) }, null),
    /used/,
  );
  await join(manager, "manager");
  await assert.rejects(call(outsider, "snapshot"), /access/);
  await assert.rejects(
    call(worker, "policy", { version: 1, policy: defaults }),
    /Manager/,
  );
  const w = await call(worker, "workspaces", {}, null);
  assert.equal(w.can_create, false);
  assert.equal(w.workspaces.length, 1);
  for (const role of ["anon", "authenticated"]) {
    await db.exec(`reset role;set role ${role}`);
    await assert.rejects(
      db.query("select * from korlix_workforce_shifts"),
      /permission denied/,
    );
    await assert.rejects(call(owner, "snapshot"), /permission denied/);
  }
  await db.exec("reset role;set role service_role");
});
test("Clock-in idempotency, breaks, optimistic concurrency and hourly updates", async () => {
  await call(owner, "policy", {
    version: 1,
    policy: { ...defaults, hourly_updates: true },
  });
  const p = punch();
  const first = await call(worker, "clock_in", p);
  shift = first.shift;
  assert.equal((await call(worker, "clock_in", p)).replayed, true);
  await assert.rejects(call(worker, "clock_out", p), /already used/);
  await assert.rejects(call(worker, "clock_in", punch()), /active shift/);
  await db.query(
    "update korlix_workforce_shifts set segment_start=clock_timestamp()-interval '71 minutes' where id=$1",
    [shift.id],
  );
  let snap = enrichSnapshot(await call(worker, "snapshot"));
  assert.equal(snap.shifts[0].update_due, true);
  await call(worker, "start_break", punch("start_break", 1));
  snap = enrichSnapshot(await call(worker, "snapshot"));
  assert.equal(snap.shifts[0].update_due, false);
  assert(snap.shifts[0].worked_seconds >= 4260);
  await assert.rejects(
    call(worker, "end_break", punch("end_break", 1)),
    /Shift changed/,
  );
  await db.query(
    "update korlix_workforce_shifts set segment_start=clock_timestamp()-interval '15 minutes' where id=$1",
    [shift.id],
  );
  await call(worker, "end_break", punch("end_break", 2));
  const upd = {
    request_id: randomUUID(),
    shift_id: shift.id,
    summary: "Completed installation",
    blockers: "",
    project: "Project A",
    quantity: 3,
  };
  assert.equal((await call(worker, "update", upd)).quantity, 3);
  await call(worker, "update", upd);
  snap = enrichSnapshot(await call(worker, "snapshot"));
  assert.equal(snap.updates.length, 1);
  assert.equal(snap.metrics.output.tasks, 3);
  assert.equal(snap.shifts[0].update_due, false);
  assert(snap.shifts[0].break_seconds >= 900);
  await assert.rejects(
    call(manager, "update", { ...upd, request_id: randomUUID() }),
    /current or recently/,
  );
  await assert.rejects(
    call(owner, "member", {
      user_id: worker,
      active: false,
      role: "employee",
      version: 1,
      team: "",
      policy_override: null,
    }),
    /active shift/,
  );
});
test("Plan lapse blocks new work while preserving clock-out and own history", async () => {
  await db.exec("reset role");
  await db.query("update user_profiles set tier='basic' where id=$1", [owner]);
  await db.exec("set role service_role");
  await assert.rejects(call(manager, "clock_in", punch()), /Enterprise/);
  const out = await call(worker, "clock_out", punch("clock_out", 3));
  assert.equal(out.shift.state, "ended");
  assert.equal((await call(worker, "snapshot")).active_plan, false);
  await db.exec("reset role");
  await db.query("update user_profiles set tier='enterprise' where id=$1", [
    owner,
  ]);
  await db.exec("set role service_role");
});
test("Corrections preserve original evidence, need another manager and reject overlaps", async () => {
  const start = new Date(Date.now() - 3600000).toISOString(),
    end = new Date(Date.now() - 1800000).toISOString();
  const c = await call(worker, "correction", {
    shift_id: shift.id,
    proposed_start: start,
    proposed_end: end,
    break_minutes: 5,
    reason: "Forgot to end my break",
  });
  await assert.rejects(
    call(worker, "review_correction", {
      id: c.id,
      decision: "approved",
      review_note: "ok",
    }),
    /Manager/,
  );
  await call(manager, "review_correction", {
    id: c.id,
    decision: "approved",
    review_note: "Confirmed with employee",
  });
  const corrected = enrichSnapshot(await call(worker, "snapshot")).shifts[0];
  assert.equal(corrected.worked_seconds, 1500);
  assert(corrected.raw_worked_seconds >= 4260);
  await assert.rejects(
    call(manager, "review_correction", {
      id: c.id,
      decision: "approved",
      review_note: "Again",
    }),
    /already reviewed/,
  );
  const overlap = await call(worker, "correction", {
    proposed_start: start,
    proposed_end: end,
    break_minutes: 0,
    reason: "Missing shift",
  });
  await assert.rejects(
    call(manager, "review_correction", {
      id: overlap.id,
      decision: "approved",
      review_note: "test",
    }),
    /overlaps/,
  );
  const own = await call(manager, "correction", {
    proposed_start: start,
    proposed_end: end,
    break_minutes: 0,
    reason: "Missed clock-in",
  });
  await assert.rejects(
    call(manager, "review_correction", {
      id: own.id,
      decision: "approved",
      review_note: "self",
    }),
    /Another manager/,
  );
  await call(owner, "review_correction", {
    id: own.id,
    decision: "approved",
    review_note: "Confirmed",
  });
  await assert.rejects(
    call(owner, "correction", {
      proposed_start: start,
      proposed_end: new Date(Date.now() + 3600000).toISOString(),
      break_minutes: 0,
      reason: "Future shift",
    }),
    /future/,
  );
});
test("Schedules and company boundaries", async () => {
  const starts_at = new Date(Date.now() + 86400000).toISOString(),
    ends_at = new Date(Date.now() + 115200000).toISOString();
  await call(manager, "schedule", {
    user_id: worker,
    starts_at,
    ends_at,
    worksite: "HQ",
    notes: "",
  });
  await assert.rejects(
    call(owner, "schedule", {
      user_id: worker,
      starts_at,
      ends_at,
      worksite: "HQ",
      notes: "",
    }),
    /overlaps/,
  );
  const other = (
    await call(
      otherOwner,
      "create",
      { name: "Other", display_name: "Other", timezone: "UTC" },
      null,
    )
  ).id;
  await assert.rejects(call(worker, "snapshot", {}, other), /access/);
  await assert.rejects(call(worker, "audit"), /Manager/);
  const snap = await call(worker, "snapshot");
  assert(snap.members.every((m) => m.user_id === worker));
  assert(snap.shifts.every((s) => s.user_id === worker));
  assert(snap.corrections.every((s) => s.user_id === worker));
});
test("Capture exceptions remain reviewable; expired evidence is inaccessible before purge", async () => {
  await call(owner, "policy", {
    version: 2,
    policy: { ...defaults, require_selfie: true, require_location: true },
  });
  await assert.rejects(call(worker, "clock_in", punch()), /evidence/);
  const x = await call(
    worker,
    "clock_in",
    punch("clock_in", 1, {
      exception_reason: "Camera permission blocked",
      flags: ["Selfie missing", "Location missing"],
    }),
  );
  assert.equal(x.shift.review_status, "needs_review");
  const out = await call(
    worker,
    "clock_out",
    punch("clock_out", 1, { flags: ["Selfie missing"] }),
  );
  assert.equal(out.shift.state, "ended");
  await db.query(
    "update korlix_workforce_events set photo_path='private.jpg',location='{\"latitude\":1}',photo_expires_at=clock_timestamp()-interval '1 hour' where id=$1",
    [out.event.id],
  );
  await assert.rejects(
    call(worker, "evidence", { id: out.event.id }),
    /expired/,
  );
  const event = (await call(worker, "snapshot")).events.find(
    (e) => e.id === out.event.id,
  );
  assert.equal(event.location, undefined);
  assert.equal(event.has_photo, false);
  assert.equal(event.photo_path, undefined);
});
test("Pure validation, daily output boundary, formula escaping and work/break timer", () => {
  assert.throws(() => policy({ ...defaults, require_selfie: "yes" }));
  assert.throws(() => policy({ ...defaults, latitude: 200, longitude: 1 }));
  assert.throws(() =>
    location({
      latitude: 1,
      longitude: 1,
      accuracy: 1,
      captured_at: "2000-01-01",
    }),
  );
  assert.deepEqual(
    evidenceFlags(
      { ...defaults, require_location: true },
      { latitude: 2, longitude: 2, accuracy: 150 },
      false,
    ),
    ["Location accuracy needs review"],
  );
  const s = {
    state: "break",
    segment_start: "2026-09-21T10:00:00Z",
    worked_seconds: 3600,
    break_seconds: 60,
  };
  assert.deepEqual(shiftSeconds(s, Date.parse("2026-09-21T10:15:00Z")), {
    worked_seconds: 3600,
    raw_worked_seconds: 3600,
    break_seconds: 960,
  });
  const enriched = enrichSnapshot({
    period_start: "2026-09-21T00:00:00Z",
    period_end: "2026-09-22T00:00:00Z",
    updates: [
      {
        created_at: "2026-09-20T23:00:00Z",
        quantity: 50,
        output_unit: "tasks",
      },
      { created_at: "2026-09-21T10:00:00Z", quantity: 3, output_unit: "tasks" },
    ],
  });
  assert.equal(enriched.metrics.output.tasks, 3);
  assert.equal(csvCell("=SUM(1)"), `"'=SUM(1)"`);
});
test("HTTP uses verified identity, enforces email verification and never sends a report", async () => {
  const persistence = createWorkforceStore({
    rpc: async (name, p) => {
      try {
        return {
          data: await call(p.p_actor, p.p_action, p.p, p.p_org, p.p_email),
        };
      } catch (e) {
        return { error: { message: e.message, code: e.code } };
      }
    },
  });
  const app = express();
  app.use(express.json({ limit: "4mb" }));
  let draft;
  registerWorkforce(app, {
    store: persistence,
    requireUser: async (req) => {
      const u = req.headers["x-user"];
      if (!u) throw Error();
      return {
        id: u,
        email: `${u}@example.com`,
        email_confirmed_at: req.headers["x-verified"] ? "yes" : null,
      };
    },
    emailService: {
      createDraft: async (args) => {
        draft = args;
        return { draft: { id: randomUUID() } };
      },
    },
    environment: {},
  });
  server = app.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  api = `http://127.0.0.1:${server.address().port}/api/workforce`;
  const req = (path, method = "GET", body, user = worker) =>
    fetch(api + path, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(user ? { "x-user": user } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
  assert.equal((await req("/workspaces", "GET", null, null)).status, 401);
  assert.equal(
    (await req("/accept-invite", "POST", { token: "a".repeat(40) })).status,
    403,
  );
  assert.equal(
    (
      await req("/" + org + "/commands", "POST", {
        action: "policy",
        payload: { version: 3, policy: defaults },
        user_id: owner,
        role: "owner",
      })
    ).status,
    403,
  );
  assert.equal(
    (
      await req(
        "/" + org + "/email-draft",
        "POST",
        {
          confirmed: true,
          recipient_id: randomUUID(),
          request_id: randomUUID(),
        },
        owner,
      )
    ).status,
    409,
  );
  assert.equal(draft, undefined);
  const r = await req("/" + org);
  assert.equal(r.headers.get("cache-control"), "no-store");
  assert.equal((await r.json()).member.user_id, worker);
});

test('Business profiles and member types support independent companies and preserve roles',async()=>{
 const {businessProfile,presetPolicy}=await import('../workforce/workspace.mjs');
 const created=await call(otherOwner,'create',{name:'Independent Delivery Co',display_name:'Owner',timezone:'UTC',profile:businessProfile({industry:'logistics',work_mode:'field'}),initial_policy:presetPolicy('logistics')},null);
 assert.equal(created.business_profile.industry,'logistics');assert.equal(created.policy.output_unit,'deliveries');assert.equal(created.policy.require_location,false);
 await assert.rejects(call(worker,'business',{name:'Spoof',version:1,profile:{}},created.id),/access/);
 const current=await call(owner,'snapshot');
 await call(owner,'business',{name:'Independent Services',version:current.organization.version,profile:businessProfile({industry:'professional',work_mode:'remote',description:'Client projects'})});
 await assert.rejects(call(manager,'business',{name:'Bad',version:1,profile:{}}),/Owner/);
 const member=current.members.find(m=>m.user_id===worker);
 await call(owner,'team_profile',{user_id:worker,version:member.version,member_kind:'contractor',job_title:'Installer',worksite:'Client sites'});
 const fresh=(await call(worker,'snapshot')).member;assert.equal(fresh.role,'employee');assert.equal(fresh.member_kind,'contractor');
 await assert.rejects(call(owner,'team_profile',{user_id:worker,version:member.version,member_kind:'partner',job_title:'',worksite:''}),/changed/);
 const token=tokenHash(randomUUID());
 await call(owner,'invite',{email:`${outsider}@example.com`,display_name:'Volunteer',role:'employee',token_hash:token,member_kind:'volunteer',job_title:'Coordinator',worksite:'Remote'});
 await call(outsider,'accept',{token_hash:token},null);
 assert.equal((await call(outsider,'snapshot')).member.member_kind,'volunteer');
});
test('Work board enforces assignments, tenant isolation, current access and retry/version checks',async()=>{
 const task={request_id:randomUUID(),title:'Prepare client visit',details:'Checklist at the site',assignee_id:worker,priority:'high',project:'Client A',worksite:'East',due_at:new Date(Date.now()+86400000).toISOString()};
 const result=await call(manager,'task_create',task);assert.equal(result.status,'todo');
 assert.equal((await call(manager,'task_create',task)).id,result.id);
 await assert.rejects(call(manager,'task_create',{...task,title:'Changed'}),/request changed/);
 assert.equal((await call(worker,'snapshot')).tasks.length,1);
 assert.equal((await call(outsider,'snapshot')).tasks.length,0);
 await assert.rejects(call(outsider,'task_status',{id:result.id,version:1,status:'done',progress_note:''}),/access/);
 await assert.rejects(call(worker,'task_create',{...task,request_id:randomUUID(),assignee_id:manager}),/Managers/);
 await assert.rejects(call(manager,'task_create',{...task,request_id:randomUUID(),assignee_id:otherOwner}),/active member/);
 await assert.rejects(call(otherOwner,'task_status',{id:result.id,version:1,status:'done',progress_note:''}),/access/);
 const updated=await call(worker,'task_status',{id:result.id,version:1,status:'blocked',progress_note:'Waiting for parts'});assert.equal(updated.version,2);
 await assert.rejects(call(manager,'task_edit',{...task,id:result.id,version:1}),/changed/);
 await assert.rejects(call(worker,'task_edit',{...task,id:result.id,version:2}),/Managers/);
 const edited=await call(manager,'task_edit',{...task,id:result.id,version:2,assignee_id:outsider});assert.equal(edited.version,3);
 assert.equal((await call(worker,'snapshot')).tasks.length,0);
 await assert.rejects(call(worker,'task_status',{id:result.id,version:3,status:'done',progress_note:''}),/access/);
 const self=await call(worker,'task_create',{...task,request_id:randomUUID()});assert.equal(self.assignee_id,worker); // no open shift needed
 const mv=(await call(worker,'snapshot')).member.version;
 await assert.rejects(call(worker,'task_create',{...task,request_id:randomUUID(),expected_member_version:mv-1}),/access changed/);
 const done=await call(worker,'task_status',{id:self.id,version:1,status:'done',progress_note:'Ready'});assert(done.completed_at);
 const reopen=await call(worker,'task_status',{id:self.id,version:2,status:'in_progress',progress_note:'More work'});assert.equal(reopen.completed_at,null);
 await assert.rejects(call(worker,'task_status',{id:self.id,version:3,status:'cancelled',progress_note:''}),/manager/);
 for(const role of ['anon','authenticated']) {await db.exec(`reset role;set role ${role}`);await assert.rejects(db.query('select * from korlix_workforce_tasks'),/permission denied/);await assert.rejects(call(owner,'snapshot'),/permission denied/);}
 await db.exec('reset role;set role service_role');
});
test('Rici context excludes evidence and invitations; drafts cannot write or broaden employee access',async()=>{
 const {workforceVoiceContext,prepareWorkforceVoiceDraft}=await import('../workforce/voice.mjs');
 const data=enrichSnapshot(await call(worker,'snapshot'));
 const context=workforceVoiceContext(data);assert.equal(context.members.length,1);assert.equal(context.members[0].email,undefined);assert.equal(context.events,undefined);assert.equal(context.invites,undefined);assert.equal(context.policy,undefined);
 assert.equal(context.capabilities.draft_schedule,false);
 const payload={title:'New task',assignee_id:worker,priority:'normal',due_at:null};
 const r=prepareWorkforceVoiceDraft(data,{action:'task_create',member_version:data.member.version,payload});assert.equal(r.saved,false);assert.equal(r.reviewRequired,true);
 assert.equal((await call(worker,'snapshot')).tasks.length,data.tasks.length);
 assert.throws(()=>prepareWorkforceVoiceDraft(data,{action:'task_create',member_version:data.member.version,payload:{...payload,assignee_id:manager}}),/yourself/);
 assert.throws(()=>prepareWorkforceVoiceDraft(data,{action:'task_create',member_version:data.member.version,payload:{...payload,status:'done'}}),/supported/);
 assert.throws(()=>prepareWorkforceVoiceDraft(data,{action:'policy',member_version:data.member.version,payload:{}}),/prepare/);
 assert.throws(()=>prepareWorkforceVoiceDraft(data,{action:'schedule',member_version:data.member.version,payload:{}}),/Manager/);
 assert.throws(()=>prepareWorkforceVoiceDraft(data,{action:'update',member_version:data.member.version,payload:{shift_id:randomUUID(),summary:'Done',quantity:1}}),/shift/);
 assert.throws(()=>prepareWorkforceVoiceDraft(data,{action:'task_create',member_version:999,payload}),/access changed/);
 assert.throws(()=>prepareWorkforceVoiceDraft({...data,active_plan:false},{action:'task_create',member_version:data.member.version,payload}),/Enterprise/);
});
test('Workforce voice HTTP uses fresh membership and only prepares validated drafts',async()=>{
 const req=(path,body,user=worker)=>fetch(api+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json','x-user':user},body:body?JSON.stringify(body):undefined});
 const ctx=await(await req(`/${org}/voice/context`)).json();assert.equal(ctx.member.user_id,worker);
 const body={action:'task_create',member_version:ctx.member.version,payload:{title:'Voice note task',assignee_id:worker,priority:'normal',details:'Review me'}};
 const before=(await call(worker,'snapshot')).tasks.length;
 const res=await req(`/${org}/voice/draft`,body);assert.equal(res.status,200);assert.equal((await res.json()).saved,false);
 assert.equal((await call(worker,'snapshot')).tasks.length,before);
 assert.equal((await req(`/${org}/voice/draft`,{...body,payload:{...body.payload,assignee_id:otherOwner}})).status,403);
 assert.equal((await req(`/${randomUUID()}/voice/context`)).status,403);
 await db.exec('reset role');await db.query("update user_profiles set tier='basic' where id=$1",[owner]);await db.exec('set role service_role');
 assert.equal((await req(`/${org}/voice/draft`,body)).status,403);
 await assert.rejects(call(worker,'task_create',{...body.payload,request_id:randomUUID()}),/Enterprise/);
 assert.equal((await call(worker,'snapshot')).tasks.length,before);
 await db.exec('reset role');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);await db.exec('set role service_role');
});
