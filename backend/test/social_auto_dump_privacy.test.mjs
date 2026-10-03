import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

let db, profiles;
const users = Array.from({ length: 4 }, () => randomUUID());
const rpc = async (who, action, data = {}, fn = 'korlix_social_v1') =>
  (await db.query(`select ${fn}($1,$2,$3::jsonb) result`, [users[who], action, JSON.stringify(data)])).rows[0].result;
const chat = (who, action, data) => rpc(who, action, data, 'korlix_social_media_chat_v1');
const group = (who, action, data) => rpc(who, action, data, 'korlix_social_groups_v1');
const media = (who, action, data) => rpc(who, action, data, 'korlix_social_attachment_v1');
const dump = (who, data, action = 'dump_schedule') => rpc(who, action, { request_id: randomUUID(), ...(action === 'dump_schedule' ? { seconds: 15 } : {}), ...data }, 'korlix_social_dump_v1');
const expire = who => db.query("update korlix_social_message_dumps set dump_at=clock_timestamp()-interval '1 second' where viewer=$1", [profiles[who].id]);
const send = (who, peer, body, extra = {}) => chat(who, 'send', { id: randomUUID(), peer: profiles[peer].id, body, ...extra });
const createGroup = async () => {
  const id = randomUUID();
  await group(0, 'group_create', { group: id, name: 'Privacy review group', members: [profiles[1].id, profiles[2].id] });
  await group(1, 'group_accept', { group: id });
  await group(2, 'group_accept', { group: id });
  return id;
};
const noText = (result, text) => assert.equal(JSON.stringify(result).includes(text), false, `Dumped text escaped into ${JSON.stringify(result)}`);

before(async () => {
  db = new PGlite();
  await db.exec('create schema auth; create role anon; create role authenticated; create role service_role bypassrls; create table auth.users(id uuid primary key); create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]); create table storage.objects(id uuid primary key,bucket_id text,name text); alter table storage.objects enable row level security;');
  for (const user of users) await db.query('insert into auth.users values($1)', [user]);
  const folder = new URL('../../supabase/migrations/', import.meta.url);
  for (const file of (await readdir(folder)).filter(f => /_korlix_social(?:_|\.)/.test(f)).sort()) {
    const sql = await readFile(new URL(file, folder), 'utf8');
    assert(sql.trim(), `Empty migration: ${file}`);
    await db.exec(sql);
  }
});
beforeEach(async () => {
  await db.exec('truncate korlix_social_profiles,korlix_social_moderators,korlix_social_limits restart identity cascade');
  profiles = [];
  for (let i = 0; i < users.length; i++) profiles.push((await rpc(i, 'save_profile', { handle: `dump_audit_${i}`, name: `Audit ${i}`, color: 'cyan', discoverable: true, show_online: false, accepted_rules: true })).profile);
  for (const [a, b] of [[0, 1], [0, 2], [1, 2]]) {
    await rpc(a, 'request', { peer: profiles[b].id });
    await rpc(b, 'accept', { peer: profiles[a].id });
  }
});
after(async () => { await db?.close(); });

test('a viewer dump removes direct history, originals, nested quotes and unread text without changing the other copy', async () => {
  const secret = 'DIRECT UNIQUE PRIVATE MESSAGE';
  const first = await send(0, 1, secret);
  const reply = await send(1, 0, 'Visible response', { reply_to: first.id });
  await dump(1, { id: first.id, peer: profiles[0].id });
  const pending = await chat(1, 'messages', { peer: profiles[0].id });
  assert(pending.items.find(x => x.id === first.id).dump_at);
  assert(pending.items.find(x => x.id === reply.id).reply.dump_at);
  await expire(1);
  for (const fn of ['korlix_social_media_chat_v1', 'korlix_social_chat_v1', 'korlix_social_v1']) {
    const result = await rpc(1, 'messages', { peer: profiles[0].id }, fn);
    noText(result, secret);
    assert.equal(result.items.some(x => x.id === first.id), false);
  }
  await assert.rejects(chat(1, 'message', { peer: profiles[0].id, id: first.id }));
  await assert.rejects(send(1, 0, 'Forbidden new quote', { reply_to: first.id }));
  const connection = (await rpc(1, 'connections')).items.find(x => x.id === profiles[0].id);
  assert.equal(connection.unread, 0);
  noText(connection, secret);
  const other = await chat(0, 'messages', { peer: profiles[1].id });
  assert.equal(other.items.find(x => x.id === first.id).body, secret);
  assert.equal(other.items.find(x => x.id === reply.id).reply.body, secret);
  assert.equal(other.items.find(x => x.id === first.id).dump_at, null);
  assert.equal((await db.query('select body,deleted from korlix_social_messages where id=$1', [first.id])).rows[0].body, secret);
});

test('group dump excludes quotes and unread for its viewer while respecting membership floors and other members', async () => {
  const id = await createGroup(), secret = 'GROUP UNIQUE PRIVATE MESSAGE';
  const first = await chat(0, 'group_send', { id: randomUUID(), group: id, body: secret });
  const reply = await chat(2, 'group_send', { id: randomUUID(), group: id, body: 'Group follow-up', reply_to: first.id });
  await dump(1, { id: first.id, group: id });
  await expire(1);
  const own = await chat(1, 'group_messages', { group: id });
  noText(own, secret);
  assert.equal(own.items.some(x => x.id === first.id), false);
  assert.equal(own.peer.unread, 1);
  await assert.rejects(chat(1, 'group_message', { group: id, id: first.id }));
  await assert.rejects(chat(1, 'group_send', { id: randomUUID(), group: id, body: 'Forbidden group quote', reply_to: first.id }));
  const other = await chat(2, 'group_messages', { group: id });
  assert.equal(other.items.find(x => x.id === first.id).body, secret);
  assert.equal(other.items.find(x => x.id === reply.id).reply.body, secret);
  assert.equal(other.peer.unread, 1);
  await assert.rejects(dump(3, { id: first.id, group: id }));
  await assert.rejects(dump(1, { id: first.id, group: randomUUID() }));
  await db.query('update korlix_social_group_members set joined_after=(select max(seq) from korlix_social_group_messages where group_id=$1) where group_id=$1 and member=$2', [id, profiles[2].id]);
  await assert.rejects(dump(2, { id: first.id, group: id }));
});

test('dumped attachment links and attached upload retries cannot recreate the owner history or purge the recipient file', async () => {
  for (const groupChat of [false, true]) {
    const destination = groupChat ? { group: await createGroup() } : { peer: profiles[1].id };
    const data = { ...destination, id: randomUUID(), kind: 'file', extension: 'pdf', filename: 'Private.pdf', content_type: 'application/pdf', size_bytes: 256, checksum: 'a'.repeat(64) };
    const prepared = await media(0, 'prepare', data);
    await media(0, 'ready', { id: data.id });
    const sent = await chat(0, groupChat ? 'group_send' : 'send', { ...destination, id: randomUUID(), body: 'File caption', attachment_id: data.id });
    await dump(0, { ...destination, id: sent.id });
    await expire(0);
    for (const action of ['link', 'ready']) await assert.rejects(media(0, action, { id: data.id }));
    await assert.rejects(media(0, 'prepare', data));
    const recipient = await media(1, 'link', { id: data.id });
    assert.equal(recipient.attachment.object_path, prepared.attachment.object_path);
    const row = (await db.query('select state,purged_at from korlix_social_attachments where id=$1', [data.id])).rows[0];
    assert.deepEqual(row, { state: 'attached', purged_at: null });
    const cleanup = (await db.query('select korlix_social_attachment_cleanup() result')).rows[0].result;
    assert.equal(cleanup.some(x => x.id === data.id), false);
  }
});

test('filtered history pages cross runs of hidden rows and retain tombstones outside the current page', async () => {
  const messages = [];
  for (let i = 0; i < 125; i++) {
    const id = randomUUID();
    await db.query('insert into korlix_social_messages(id,sender,recipient,body) values($1,$2,$3,$4)', [id, profiles[0].id, profiles[1].id, `History ${i}`]);
    messages.push(id);
  }
  // A server-side fixture represents 60 independently confirmed expired schedules.
  for (const id of messages.slice(65)) await db.query("insert into korlix_social_message_dumps(viewer,scope,message_id,dump_at) values($1,'direct',$2,now()-interval '1 second')", [profiles[1].id, id]);
  const first = await chat(1, 'messages', { peer: profiles[0].id });
  assert.equal(first.items.length, 51);
  assert.equal(first.items.at(-1).id, messages[64]);
  assert.equal(first.dumped_ids.length, 60);
  const visible = first.items.slice(1);
  const older = await chat(1, 'messages', { peer: profiles[0].id, before: visible[0].seq });
  assert.equal(older.items.length, 15);
  assert.equal(new Set([...older.items, ...visible].map(x => x.id)).size, 65);
  assert.equal(older.dumped_ids.length, 60);
});

test('same message UUID in different scopes and stale request replays cannot undo an expired viewer dump', async () => {
  const id = randomUUID(), room = await createGroup();
  await send(0, 1, 'Direct shared ID', { id });
  await chat(0, 'group_send', { id, group: room, body: 'Group shared ID' });
  const request = { id, peer: profiles[0].id, request_id: randomUUID() };
  await dump(1, request);
  await expire(1);
  assert.equal((await chat(1, 'group_message', { group: room, id })).message.body, 'Group shared ID');
  for (const action of ['dump_cancel', 'dump_schedule']) {
    const result = await dump(1, { id, peer: profiles[0].id, ...(action === 'dump_schedule' ? { seconds: 86400 } : {}) }, action);
    assert.equal(result.dumped, true);
    assert(Date.parse(result.dump_at) < Date.parse(result.server_time));
  }
  const replay = await dump(1, request);
  assert.equal(replay.dumped, true);
  await assert.rejects(chat(1, 'message', { peer: profiles[0].id, id }));
  await assert.rejects(dump(2, { id, peer: profiles[0].id }));
  await assert.rejects(dump(1, { id, peer: profiles[2].id }));
  assert.equal((await chat(0, 'message', { peer: profiles[1].id, id })).message.body, 'Direct shared ID');
});

test('group snapshots reconcile old-page schedules and cross-device changes without exposing another member timers', async () => {
  const room = await createGroup(), ids = [];
  for (let i = 0; i < 70; i++) {
    const id = randomUUID();
    await db.query('insert into korlix_social_group_messages(id,group_id,sender,body) values($1,$2,$3,$4)', [id, room, profiles[0].id, `Group history ${i}`]);
    ids.push(id);
  }
  const selected = ids[0];
  const initial = await dump(1, { id: selected, group: room, seconds: 86400 });
  const latest = await chat(1, 'group_messages', { group: room });
  assert.equal(latest.items.length, 51);
  assert.equal(latest.items.some(x => x.id === selected), false);
  assert.equal(latest.dump_schedules[selected], initial.dump_at);
  for (const who of [0, 2]) assert.deepEqual((await chat(who, 'group_messages', { group: room })).dump_schedules, {});
  const changed = await dump(1, { id: selected, group: room, seconds: 45 });
  assert(Date.parse(changed.dump_at) < Date.parse(initial.dump_at));
  assert.equal((await chat(1, 'group_messages', { group: room })).dump_schedules[selected], changed.dump_at);
  await dump(1, { id: selected, group: room }, 'dump_cancel');
  const cancelled = await chat(1, 'group_messages', { group: room });
  assert.deepEqual(cancelled.dump_schedules, {});
  assert.deepEqual(cancelled.dumped_ids, []);
  assert.equal((await chat(1, 'group_message', { group: room, id: selected })).message.body, 'Group history 0');
});

test('new dump state and every privileged Social RPC remain inaccessible to browser roles', async () => {
  for (const name of ['korlix_social_message_dumps', 'korlix_social_dump_requests']) {
    const row = (await db.query("select has_table_privilege('anon',$1,'select') anon,has_table_privilege('authenticated',$1,'select,insert,update,delete') browser,(select relrowsecurity from pg_class where oid=$1::regclass) rls", [name])).rows[0];
    assert.deepEqual(row, { anon: false, browser: false, rls: true });
  }
  const rows = (await db.query("select oid::regprocedure::text signature,prosecdef,has_function_privilege('anon',oid,'execute') anon,has_function_privilege('authenticated',oid,'execute') browser from pg_proc where pronamespace='public'::regnamespace and proname like 'korlix_social_%'")).rows;
  for (const row of rows) {
    assert.equal(row.prosecdef, false, row.signature);
    assert.equal(row.anon, false, row.signature);
    assert.equal(row.browser, false, row.signature);
  }
});
