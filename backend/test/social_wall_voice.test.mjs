import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import express from 'express';
import { registerSocial } from '../social/routes.mjs';
import { socialAttachments } from '../social/attachments.mjs';
let db, server, base, profiles;
const users = Array.from({ length: 4 }, () => randomUUID());
const stored = new Map(), signed = [];
const call = async (who, action, data = {}, rpc = 'korlix_social_v1') => (await db.query(`select ${rpc}($1,$2,$3::jsonb) result`, [users[who], action, JSON.stringify(data)])).rows[0].result;
const media = (who, action, data) => call(who, action, data, 'korlix_social_attachment_v1');
const post = (who = 0, data = {}) => call(who, 'create_topic', { id: randomUUID(), surface: 'wall', body: 'A public wall update', ...data });
const reply = (who, topic, attachment, body = '', id = randomUUID()) => call(who, 'reply', { id: topic, reply_id: id, body, ...(attachment ? { attachment_id: attachment } : {}) });
const api = async (action, data = {}, who = 0, method = 'GET', status = 200) => {
 const res = await fetch(base + action + (method === 'GET' ? '?' + new URLSearchParams(data) : ''), { method, headers: { Authorization: users[who] || '', 'Content-Type': 'application/json' }, body: method === 'POST' ? JSON.stringify(data) : undefined });
 const result = await res.json(); assert.equal(res.status, status, JSON.stringify(result)); assert.equal(res.headers.get('cache-control'), 'no-store'); return result;
};
const wav = (milliseconds = 1000) => {
 const size = Math.round(milliseconds * 48), bytes = Buffer.alloc(size + 44);
 bytes.write('RIFF'); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write('WAVEfmt ', 8); bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(1, 22); bytes.writeUInt32LE(24000, 24); bytes.writeUInt32LE(48000, 28); bytes.writeUInt16LE(2, 32); bytes.writeUInt16LE(16, 34); bytes.write('data', 36); bytes.writeUInt32LE(size, 40); return bytes;
};
const upload = async (topic, { who = 1, kind = 'voice', id = randomUUID(), bytes = wav(), status = 200, destination = { topic } } = {}) => {
 const form = new FormData(); form.append('file', new Blob([bytes]), 'Voice note.wav');
 const res = await fetch(base + 'attachment_upload?' + new URLSearchParams({ ...destination, kind, id }), { method: 'POST', headers: { Authorization: users[who] || '' }, body: form });
 const result = await res.json(); assert.equal(res.status, status, JSON.stringify(result)); assert.equal(res.headers.get('cache-control'), 'no-store'); return result;
};
const fixture = async () => { const { id: topic } = await post(); const { attachment } = await upload(topic); const result = await reply(1, topic, attachment.id); return { topic, attachment: attachment.id, reply: result.id }; };
before(async () => {
 db = new PGlite();
 await db.exec('create schema auth; create role anon; create role authenticated; create role service_role bypassrls; create table auth.users(id uuid primary key); create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]); create table storage.objects(id uuid primary key,bucket_id text,name text); alter table storage.objects enable row level security;');
 for (const u of users) await db.query('insert into auth.users values($1)', [u]);
 const folder = new URL('../../supabase/migrations/', import.meta.url);
 for (const file of (await readdir(folder)).filter(f => /_korlix_social(?:_|\.)/.test(f)).sort()) await db.exec(await readFile(new URL(file, folder), 'utf8'));
 const database = {
  storage: { from: () => ({ upload: async (path, bytes) => { if (stored.has(path)) return { error: { statusCode: 409 } }; stored.set(path, bytes); return { data: { path } }; }, remove: async paths => { for (const p of paths) stored.delete(p); return { data: [] }; }, createSignedUrl: async (path, ttl) => { signed.push({ path, ttl }); return { data: { signedUrl: `https://private.fixture/${path}?ttl=${ttl}` } }; } }) },
  rpc: async (name, p) => { try { return { data: (await db.query(`select ${name}($1,$2,$3::jsonb) result`, [p.p_actor, p.p_action, JSON.stringify(p.p_data)])).rows[0].result }; } catch (e) { return { error: { code: e.code, message: e.message } }; } }
 };
 const app = express(); app.use(express.json()); registerSocial(app, { database, requireUser: async req => { if (!users.includes(req.headers.authorization)) throw Error(); return { id: req.headers.authorization, email_confirmed_at: '2026-01-01' }; }, logger: { info() {}, warn() {} } });
 server = app.listen(0); await new Promise(r => server.once('listening', r)); base = `http://127.0.0.1:${server.address().port}/api/social/`;
});
beforeEach(async () => {
 await db.exec('truncate korlix_social_profiles,korlix_social_moderators,korlix_social_limits restart identity cascade'); stored.clear(); signed.length = 0; profiles = [];
 for (let i = 0; i < users.length; i++) profiles.push((await call(i, 'save_profile', { handle: ['alice', 'bruno', 'chris', 'diana'][i], name: `Member ${i}`, color: 'cyan', discoverable: true, show_online: false, accepted_rules: true })).profile);
});
after(async () => { if (server) await new Promise(r => server.close(r)); await db?.close(); });

test('wall voice-only and caption replies persist; playback URLs require an explicit authenticated access check', async () => {
 const f = await fixture();
 const result = await api('topic', { id: f.topic }, 2); assert.equal(result.items[0].body, ''); assert.equal(result.items[0].attachment.kind, 'voice'); assert.equal(result.items[0].attachment.duration_ms, 1000); assert.equal(result.items[0].attachment.scope, 'wall'); assert.equal(result.items[0].attachment.url, undefined); assert.equal(result.items[0].attachment.object_path, undefined); assert.equal(signed.length, 0);
 const link = await api('attachment_link', { id: f.attachment }, 2); assert.match(link.url, /ttl=60$/); assert.equal(signed.length, 1);
 await api('attachment_link', { id: f.attachment }, 9, 'GET', 401); await api('reply', { id: f.topic, reply_id: randomUUID(), body: 'A caption', attachment_id: f.attachment }, 2, 'POST', 403);
 await call(1, 'edit_reply', { id: f.reply, body: 'Thanks for sharing! 🎤' }); assert.equal((await call(2, 'topic', { id: f.topic })).items[0].body, 'Thanks for sharing! 🎤');
 await call(1, 'edit_reply', { id: f.reply, body: '' }); assert.equal((await call(2, 'topic', { id: f.topic })).items[0].body, '');
});

test('upload requires exactly one accessible wall destination and a validated recorded WAV', async () => {
 const { id } = await post();
 await upload(id, { who: 9, status: 401 }); await upload(id, { kind: 'image', status: 400 }); await upload(id, { kind: 'file', status: 400 }); await upload(id, { bytes: Buffer.from('not audio'), status: 400 }); await upload(id, { bytes: wav(100), status: 400 }); await upload(id, { bytes: wav(180001), status: 400 });
 await upload(id, { destination: { topic: id, peer: profiles[0].id }, status: 400 }); await upload(id, { destination: {}, status: 400 }); await upload(randomUUID(), { status: 404 });
 const forum = await post(0, { surface: 'forum', title: 'Forum title', category: 'sports' }); await upload(forum.id, { status: 404 });
 assert.equal(stored.size, 0);
});

test('same upload and reply retry is idempotent; altered payload, caption, author or attachment reuse is refused', async () => {
 const { id: topic } = await post(), id = randomUUID(), request = randomUUID();
 await upload(topic, { id }); await upload(topic, { id }); await reply(1, topic, id, 'Same caption', request); await reply(1, topic, id, 'Same caption', request); await upload(topic, { id });
 assert.equal((await call(2, 'topic', { id: topic })).items.length, 1); assert.equal(stored.size, 1);
 await assert.rejects(reply(1, topic, id, 'Changed caption', request), /different content/); await assert.rejects(reply(1, topic, null, 'Same caption', request), /different content/); await assert.rejects(reply(2, topic, null, 'Same caption', request), /already used/); await assert.rejects(reply(1, topic, id), /unavailable/);
 await upload(topic, { id, bytes: wav(2000), status: 409 });
 await call(1, 'delete_reply', { id: request }); await assert.rejects(reply(1, topic, id, 'Same caption', request), /unavailable/); await assert.rejects(reply(1, topic, null, 'Same caption', request), /different content/);
});

test('voice attachment is bound to its uploading owner, exact wall post and ready unexpired state', async () => {
 const { id: first } = await post(), { id: second } = await post(2); const { attachment } = await upload(first);
 await assert.rejects(reply(2, first, attachment.id), /unavailable/); await assert.rejects(reply(1, second, attachment.id), /unavailable/);
 await db.query("update korlix_social_attachments set state='uploading' where id=$1", [attachment.id]); await assert.rejects(reply(1, first, attachment.id), /unavailable/);
 await db.query("update korlix_social_attachments set state='ready',expires_at=now()-interval '1 second' where id=$1", [attachment.id]); await assert.rejects(reply(1, first, attachment.id), /unavailable/); await assert.rejects(media(1, 'link', { id: attachment.id }), /unavailable/); await assert.rejects(media(1, 'ready', { id: attachment.id }), /expired/);
});

test('draft discard is owner-only, attached voice must be deleted through its reply', async () => {
 const { id: topic } = await post(); const { attachment } = await upload(topic);
 await assert.rejects(media(2, 'link', { id: attachment.id }), /unavailable/); await assert.rejects(media(2, 'discard', { id: attachment.id }), /unavailable/);
 await media(1, 'discard', { id: attachment.id }); await assert.rejects(reply(1, topic, attachment.id), /unavailable/);
 const f = await fixture(); await assert.rejects(media(1, 'discard', { id: f.attachment }), /Remove the message/);
});

test('text-only and forum reply behavior remains intact; empty text cannot become an attachment-free reply', async () => {
 const { id: topic } = await post(); await assert.rejects(reply(1, topic, null), /Write a reply/);
 const text = await reply(1, topic, null, 'Text is still welcome'); await assert.rejects(call(1, 'edit_reply', { id: text.id, body: '' }), /reply length/);
 const forum = await post(0, { surface: 'forum', title: 'Forum topic', category: 'sports' }); const r = await reply(1, forum.id, null, 'Forum reply'); assert.equal((await call(2, 'topic', { id: forum.id })).items[0].id, r.id);
 const { attachment } = await upload(topic); await assert.rejects(reply(1, forum.id, attachment.id), /wall posts/);
});

test('blocking either the wall author or voice author hides replies and denies fresh links', async () => {
 const f = await fixture();
 await call(2, 'block', { peer: profiles[1].id }); assert.equal((await api('topic', { id: f.topic }, 2)).items.length, 0); await api('attachment_link', { id: f.attachment }, 2, 'GET', 404);
 await call(2, 'unblock', { peer: profiles[1].id }); await call(1, 'block', { peer: profiles[2].id }); await api('attachment_link', { id: f.attachment }, 2, 'GET', 404);
 await call(1, 'unblock', { peer: profiles[2].id }); await call(2, 'block', { peer: profiles[0].id }); await api('topic', { id: f.topic }, 2, 'GET', 404); await api('attachment_link', { id: f.attachment }, 2, 'GET', 404);
 assert.equal(signed.length, 0);
});

test('blocking wall author after upload prevents publish, ready and preview; suspension denies all new access', async () => {
 const { id: topic } = await post(); const { attachment } = await upload(topic);
 await call(1, 'block', { peer: profiles[0].id }); await assert.rejects(reply(1, topic, attachment.id), /not found/); await assert.rejects(media(1, 'ready', { id: attachment.id }), /unavailable/); await assert.rejects(media(1, 'link', { id: attachment.id }), /unavailable/); await upload(topic, { status: 404 });
 await call(1, 'unblock', { peer: profiles[0].id }); await db.query('update korlix_social_profiles set suspended=true where id=$1', [profiles[0].id]); await assert.rejects(reply(1, topic, attachment.id), /not found/); await assert.rejects(media(1, 'link', { id: attachment.id }), /unavailable/);
 await db.query('update korlix_social_profiles set suspended=false where id=$1', [profiles[0].id]); await reply(1, topic, attachment.id); await db.query('update korlix_social_profiles set suspended=true where id=$1', [profiles[1].id]); await api('attachment_link', { id: attachment.id }, 2, 'GET', 404); await api('attachment_link', { id: attachment.id }, 1, 'GET', 403); assert.equal((await call(2, 'topic', { id: topic })).items.length, 0);
});

test('locked wall prevents uploads and new replies while already published voice remains playable', async () => {
 const f = await fixture(); const { attachment: pending } = await upload(f.topic);
 await db.query('update korlix_social_topics set locked=true where id=$1', [f.topic]);
 await upload(f.topic, { status: 403 }); await assert.rejects(reply(1, f.topic, pending.id), /locked/); await assert.rejects(media(1, 'ready', { id: pending.id }), /locked/); await assert.rejects(media(1, 'link', { id: pending.id }), /locked/); await assert.rejects(call(1, 'edit_reply', { id: f.reply, body: 'Changed' }), /closed/);
 await api('attachment_link', { id: f.attachment }, 2); assert.equal(signed.at(-1).ttl, 60);
});

test('reply deletion immediately revokes access and queues object cleanup without purging healthy wall attachments', async () => {
 const f = await fixture();
 let cleanup = (await db.query('select korlix_social_attachment_cleanup() result')).rows[0].result; assert(!cleanup.some(x => x.id === f.attachment));
 await assert.rejects(call(2, 'delete_reply', { id: f.reply }), /not found/); await call(1, 'delete_reply', { id: f.reply });
 await api('attachment_link', { id: f.attachment }, 1, 'GET', 404); await api('attachment_link', { id: f.attachment }, 2, 'GET', 404); assert.equal((await call(2, 'topic', { id: f.topic })).items.length, 0);
 cleanup = (await db.query('select korlix_social_attachment_cleanup() result')).rows[0].result; assert(cleanup.some(x => x.id === f.attachment)); await db.query('select korlix_social_attachment_cleanup($1::uuid[])', [[f.attachment]]); assert.equal((await db.query('select count(*)::int n from korlix_social_attachments where id=$1', [f.attachment])).rows[0].n, 0);
});

test('deleting wall post purges both published replies and unsent drafts', async () => {
 const f = await fixture(), { attachment: pending } = await upload(f.topic);
 await call(0, 'delete_topic', { id: f.topic });
 await api('attachment_link', { id: f.attachment }, 2, 'GET', 404); await api('attachment_link', { id: pending.id }, 1, 'GET', 404); await assert.rejects(reply(1, f.topic, pending.id), /not found/);
 const rows = (await db.query('select id,purged_at is not null purged from korlix_social_attachments')).rows; assert.equal(rows.length, 2); assert(rows.every(r => r.purged));
});

test('moderation removal of reply or post revokes audio, and hard deletion retains cleanup evidence', async () => {
 await db.query('insert into korlix_social_moderators values($1)', [users[3]]);
 for (const kind of ['reply', 'topic']) {
  const f = await fixture(), report = randomUUID(); await call(2, 'report', { id: report, kind, target: kind === 'reply' ? f.reply : f.topic, reason: 'Please review this voice note.' }); if (kind === 'reply') { const snapshot = (await call(3, 'reports')).items.find(x => x.id === report).snapshot; assert.equal(snapshot.body, 'Voice note'); assert.equal(snapshot.topic_id, f.topic); assert.equal(snapshot.attachment.id, f.attachment); assert.equal(snapshot.attachment.duration_ms, 1000); assert.equal(snapshot.attachment.object_path, undefined); assert.equal(snapshot.attachment.url, undefined); } await call(3, 'moderate', { id: report, decision: 'remove' }); await api('attachment_link', { id: f.attachment }, 2, 'GET', 404);
 }
 const f = await fixture(); await db.query('delete from korlix_social_topics where id=$1', [f.topic]); const row = (await db.query('select topic_id,reply_id,purged_at is not null purged from korlix_social_attachments where id=$1', [f.attachment])).rows[0]; assert.deepEqual(row, { topic_id: null, reply_id: null, purged: true });
});

test('wall and direct/group attachments cannot be reused across destinations', async () => {
 await call(0, 'request', { peer: profiles[1].id }); await call(1, 'accept', { peer: profiles[0].id });
 const { id: topic } = await post(); const { attachment: wall } = await upload(topic);
 await assert.rejects(call(1, 'send', { id: randomUUID(), peer: profiles[0].id, body: '', attachment_id: wall.id }, 'korlix_social_media_chat_v1'), /unavailable/);
 const { attachment: direct } = await upload(topic, { destination: { peer: profiles[0].id } }); await assert.rejects(reply(1, topic, direct.id), /unavailable/);
 const groupId = randomUUID(); const group = await call(0, 'group_create', { group: groupId, name: 'Friends', members: [profiles[1].id] }, 'korlix_social_groups_v1'); await call(1, 'group_accept', { group: group.group.id }, 'korlix_social_groups_v1');
 const { attachment: grouped } = await upload(topic, { destination: { group: group.group.id } }); await assert.rejects(reply(1, topic, grouped.id), /unavailable/); await assert.rejects(call(1, 'group_send', { id: randomUUID(), group: group.group.id, body: '', attachment_id: wall.id }, 'korlix_social_media_chat_v1'), /unavailable/);
 await upload(topic, { id: direct.id, status: 409 });
});

test('new helpers and attachment columns retain service-only RLS and invoker permissions', async () => {
 for (const name of ['korlix_social_wall_voice_access(uuid,uuid,uuid,boolean)', 'korlix_social_wall_voice_removed()', 'korlix_social_attachment_v1(uuid,text,jsonb)', 'korlix_social_attachment_cleanup(uuid[])', 'korlix_social_v1(uuid,text,jsonb)']) {
  assert.deepEqual((await db.query("select has_function_privilege('anon',$1,'execute') anon,has_function_privilege('authenticated',$1,'execute') authenticated,has_function_privilege('service_role',$1,'execute') service,(select prosecdef from pg_proc where oid=$1::regprocedure) definer", [name])).rows[0], { anon: false, authenticated: false, service: true, definer: false });
 }
 assert.deepEqual((await db.query("select has_table_privilege('authenticated','korlix_social_attachments','select') access,(select relrowsecurity from pg_class where oid='korlix_social_attachments'::regclass) rls,(select public from storage.buckets where id='korlix-social-attachments') public")).rows[0], { access: false, rls: true, public: false });
 await db.exec('set role service_role'); try { const f = await fixture(); assert.equal((await media(2, 'link', { id: f.attachment })).attachment.scope, 'wall'); } finally { await db.exec('reset role'); }
});

test('wall cards never mint signed links even if generic serializer processes nested reply data', async () => {
 let minted = false; const data = { items: [{ attachment: { id: randomUUID(), kind: 'voice', scope: 'wall', object_path: `${randomUUID()}/${randomUUID()}.wav` } }] };
 await socialAttachments({ storage: { from: () => ({ createSignedUrl: async () => { minted = true; return {}; } }) } }, data);
 assert.equal(minted, false); assert.equal(data.items[0].attachment.object_path, undefined); assert.equal(data.items[0].attachment.url, undefined);
});

test('hard deletion of either wall author or voice author preserves cleanup records', async () => {
 for (const who of [0, 1]) {
  const f = await fixture(); await db.query('delete from korlix_social_profiles where id=$1', [profiles[who].id]);
  const row = (await db.query('select purged_at is not null purged from korlix_social_attachments where id=$1', [f.attachment])).rows[0]; assert.equal(row.purged, true);
  const old = profiles[who]; profiles[who] = (await call(who, 'save_profile', { handle: old.handle, name: old.name, color: 'cyan', discoverable: true, show_online: false, accepted_rules: true })).profile;
 }
});
