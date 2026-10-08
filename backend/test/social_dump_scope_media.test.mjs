import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, createECDH, randomBytes } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

let db, profiles;
const users = Array.from({ length: 4 }, () => randomUUID());
const service = fn => db.transaction(async tx => {
  await tx.exec('set local role service_role');
  return fn(tx);
});
const rpc = (who, action, data = {}, fn = 'korlix_social_v1') => service(async tx =>
  (await tx.query(`select ${fn}($1,$2,$3::jsonb) result`, [who === null ? null : users[who], action, JSON.stringify(data)])).rows[0].result);
const chat = (who, action, data) => rpc(who, action, data, 'korlix_social_media_chat_v1');
const group = (who, action, data) => rpc(who, action, data, 'korlix_social_groups_v1');
const media = (who, action, data) => rpc(who, action, data, 'korlix_social_attachment_v1');
const dump = (who, data) => rpc(who, 'dump_schedule', { request_id: randomUUID(), seconds: 86400, dump_scope: 'everyone', ...data }, 'korlix_social_dump_v1');
const expire = (id, scope) => db.query("update korlix_social_shared_message_dumps set dump_at=clock_timestamp()-interval '1 second' where scope=$1 and message_id=$2", [scope, id]);
const room = async () => {
  const id = randomUUID();
  await group(0, 'group_create', { group: id, name: 'Shared dump media review', members: [profiles[1].id, profiles[2].id] });
  for (const who of [1, 2]) await group(who, 'group_accept', { group: id });
  return id;
};
const subscribe = who => {
  const key = createECDH('prime256v1'); key.generateKeys();
  return rpc(who, 'subscribe', {
    device: randomUUID(), binding: randomUUID(), messages: true, calls: false,
    subscription: { endpoint: `https://fcm.googleapis.com/fcm/send/${randomUUID()}`, keys: { p256dh: key.getPublicKey().toString('base64url'), auth: randomBytes(16).toString('base64url') } },
  }, 'korlix_social_push_v1');
};

before(async () => {
  db = new PGlite();
  await db.exec(`create schema auth; create role anon; create role authenticated; create role service_role bypassrls;
    create table auth.users(id uuid primary key,last_sign_in_at timestamptz); grant usage on schema auth to service_role; grant select(id) on auth.users to service_role;
    create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key,bucket_id text,name text); alter table storage.objects enable row level security;`);
  for (const id of users) await db.query('insert into auth.users(id) values($1)', [id]);
  const folder = new URL('../../supabase/migrations/', import.meta.url);
  for (const file of (await readdir(folder)).filter(f => /_korlix_social(?:_|\.)/.test(f)).sort()) await db.exec(await readFile(new URL(file, folder), 'utf8'));
});
beforeEach(async () => {
  await db.exec('truncate korlix_social_profiles,korlix_social_moderators,korlix_social_limits restart identity cascade');
  profiles = [];
  for (let i = 0; i < users.length; i++) profiles.push((await rpc(i, 'save_profile', { handle: `scope_media_${i}`, name: `Scope media ${i}`, color: 'cyan', discoverable: true, show_online: true, accepted_rules: true })).profile);
  for (const [a, b] of [[0, 1], [0, 2], [1, 2]]) {
    await rpc(a, 'request', { peer: profiles[b].id });
    await rpc(b, 'accept', { peer: profiles[a].id });
  }
});
after(async () => { await db?.close(); });

test('everyone expiry denies new attachment access to sender and all recipients without claiming storage destruction', async () => {
  for (const isGroup of [false, true]) {
    const destination = isGroup ? { group: await room() } : { peer: profiles[1].id };
    const attachment = { ...destination, id: randomUUID(), kind: 'file', extension: 'pdf', filename: 'Scoped-private.pdf', content_type: 'application/pdf', size_bytes: 256, checksum: 'a'.repeat(64) };
    const prepared = await media(0, 'prepare', attachment);
    await media(0, 'ready', { id: attachment.id });
    const message = await chat(0, isGroup ? 'group_send' : 'send', { ...destination, id: randomUUID(), body: 'SHARED FILE CAPTION', attachment_id: attachment.id });
    const participants = isGroup ? [0, 1, 2] : [0, 1];
    for (const who of participants) assert.equal((await media(who, 'link', { id: attachment.id })).attachment.object_path, prepared.attachment.object_path);
    await dump(0, { ...destination, id: message.id });
    await expire(message.id, isGroup ? 'group' : 'direct');
    for (const who of participants) {
      await assert.rejects(media(who, 'link', { id: attachment.id }), /unavailable/i);
      const visible = await chat(who, isGroup ? 'group_messages' : 'messages', isGroup ? destination : { peer: profiles[who === 0 ? 1 : 0].id });
      assert(!JSON.stringify(visible).includes('SHARED FILE CAPTION'));
      assert(!JSON.stringify(visible).includes(prepared.attachment.object_path));
      assert(visible.dumped_ids.includes(message.id));
    }
    await assert.rejects(media(0, 'ready', { id: attachment.id }), /unavailable/i);
    await assert.rejects(media(0, 'prepare', attachment), /unavailable/i);
    assert.deepEqual((await db.query('select state,purged_at from korlix_social_attachments where id=$1', [attachment.id])).rows[0], { state: 'attached', purged_at: null });
    const cleanup = await service(async tx => (await tx.query('select korlix_social_attachment_cleanup() result')).rows[0].result);
    assert(!cleanup.some(x => x.id === attachment.id));
  }
});

test('shared expiry cancels queued direct and group push even after the worker has claimed them', async () => {
  for (const who of [1, 2]) await subscribe(who);
  const groupId = await room();
  const direct = await chat(0, 'send', { id: randomUUID(), peer: profiles[1].id, body: 'Private direct notification' });
  const shared = await chat(0, 'group_send', { id: randomUUID(), group: groupId, body: 'Private group notification' });
  const allowedBefore = await service(async tx => (await tx.query('select korlix_social_push_allowed(o) allowed from korlix_social_push_outbox o')).rows);
  assert.equal(allowedBefore.length, 3);
  assert(allowedBefore.every(row => row.allowed));
  const claims = (await rpc(null, 'claim', {}, 'korlix_social_push_v1')).items;
  assert.equal(claims.length, 3);
  await dump(0, { id: direct.id, peer: profiles[1].id });
  await dump(0, { id: shared.id, group: groupId });
  await expire(direct.id, 'direct');
  await expire(shared.id, 'group');
  for (const claim of claims) assert.equal((await rpc(null, 'authorize', claim, 'korlix_social_push_v1')).delivery, null);
  assert.deepEqual((await db.query('select distinct status from korlix_social_push_outbox')).rows, [{ status: 'cancelled' }]);
});

test('older-page snapshots carry everyone deadlines and tombstones while keeping personal schedules private', async () => {
  for (const isGroup of [false, true]) {
    const groupId = isGroup ? await room() : null;
    const ids = [];
    for (let i = 0; i < 70; i++) {
      const id = randomUUID(); ids.push(id);
      if (isGroup) await db.query('insert into korlix_social_group_messages(id,group_id,sender,body) values($1,$2,$3,$4)', [id, groupId, profiles[0].id, `Group page ${i}`]);
      else await db.query('insert into korlix_social_messages(id,sender,recipient,body) values($1,$2,$3,$4)', [id, profiles[0].id, profiles[1].id, `Direct page ${i}`]);
    }
    const target = isGroup ? { group: groupId } : { peer: profiles[1].id };
    const viewerTarget = isGroup ? target : { peer: profiles[0].id };
    const everyone = await dump(0, { ...target, id: ids[0] });
    const personal = await dump(1, { ...viewerTarget, id: ids[1], dump_scope: 'self' });
    const first = await chat(1, isGroup ? 'group_messages' : 'messages', viewerTarget);
    assert.equal(first.items.length, 51);
    assert(!first.items.some(x => x.id === ids[0] || x.id === ids[1]));
    assert.equal(first.dump_everyone_schedules[ids[0]], everyone.everyone_dump_at);
    assert.equal(first.dump_self_schedules[ids[1]], personal.self_dump_at);
    const senderView = await chat(0, isGroup ? 'group_messages' : 'messages', target);
    assert.deepEqual(senderView.dump_self_schedules, {});
    assert(!senderView.dump_schedules[ids[1]]);
    await expire(ids[0], isGroup ? 'group' : 'direct');
    for (const who of isGroup ? [0, 1, 2] : [0, 1]) {
      const destination = isGroup ? target : { peer: profiles[who === 0 ? 1 : 0].id };
      const latest = await chat(who, isGroup ? 'group_messages' : 'messages', destination);
      assert(latest.dumped_ids.includes(ids[0]));
      assert(!latest.dump_everyone_schedules[ids[0]]);
      const older = await chat(who, isGroup ? 'group_messages' : 'messages', { ...destination, before: latest.items[0].seq });
      assert(older.dumped_ids.includes(ids[0]));
      assert(!older.items.some(x => x.id === ids[0]));
    }
  }
});

test('shared direct and group timers remain isolated when messages have the same UUID', async () => {
  const id = randomUUID(), groupId = await room();
  await chat(0, 'send', { id, peer: profiles[1].id, body: 'Direct same UUID' });
  await chat(0, 'group_send', { id, group: groupId, body: 'Group same UUID' });
  await dump(0, { id, peer: profiles[1].id });
  await expire(id, 'direct');
  for (const who of [0, 1, 2]) {
    const groupView = await chat(who, 'group_messages', { group: groupId });
    assert.equal(groupView.items.find(x => x.id === id).body, 'Group same UUID');
    assert.deepEqual(groupView.dumped_ids, []);
    assert.deepEqual(groupView.dump_everyone_schedules, {});
  }
  await dump(0, { id, group: groupId });
  for (const who of [0, 1]) {
    const directView = await chat(who, 'messages', { peer: profiles[who === 0 ? 1 : 0].id });
    assert(directView.dumped_ids.includes(id));
    assert.deepEqual(directView.dump_everyone_schedules, {});
  }
  await expire(id, 'group');
  for (const who of [0, 1, 2]) await assert.rejects(chat(who, 'group_message', { id, group: groupId }), /not found/);
});
