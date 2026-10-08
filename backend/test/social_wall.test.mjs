import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import express from 'express';
import { registerSocial } from '../social/routes.mjs';
let db, server, base, profiles;
const users = Array.from({ length: 4 }, () => randomUUID());
const profile = (handle, extra = {}) => ({ handle, name: handle, bio: 'Community member', color: 'cyan', discoverable: true, show_online: false, accepted_rules: true, ...extra });
const call = async (actor, action, data = {}, rpc = 'korlix_social_v1') => (await db.query(`select ${rpc}($1,$2,$3::jsonb) result`, [actor, action, JSON.stringify(data)])).rows[0].result;
const connect = async (from = 0, to = 1) => { await call(users[from], 'request', { peer: profiles[to].id }); await call(users[to], 'accept', { peer: profiles[from].id }); };
const post = (who = 0, extra = {}) => call(users[who], 'create_topic', { id: randomUUID(), surface: 'wall', body: 'My public update 👋🏽', ...extra });
const api = async (action, data = {}, who = 0, method = 'GET', status = 200) => {
 const res = await fetch(base + action + (method === 'GET' ? '?' + new URLSearchParams(data) : ''), { method, headers: { Authorization: users[who] || '', 'Content-Type': 'application/json' }, body: method === 'POST' ? JSON.stringify(data) : undefined });
 const result = await res.json(); assert.equal(res.status, status, JSON.stringify(result)); assert.equal(res.headers.get('cache-control'), 'no-store'); return result;
};
before(async () => {
 db = new PGlite();
 await db.exec('create schema auth; create role anon; create role authenticated; create role service_role bypassrls; create table auth.users(id uuid primary key,last_sign_in_at timestamptz);grant usage on schema auth to service_role;grant select(id) on auth.users to service_role; create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]); create table storage.objects(id uuid primary key,bucket_id text,name text); alter table storage.objects enable row level security;');
 for (const u of users) await db.query('insert into auth.users(id) values($1)', [u]);
 const folder = new URL('../../supabase/migrations/', import.meta.url);
 for (const file of (await readdir(folder)).filter(f => /_korlix_social(?:_|\.)/.test(f)).sort()) await db.exec(await readFile(new URL(file, folder), 'utf8'));
 const database = { rpc: async (name, p) => { try { return { data: await call(p.p_actor, p.p_action, p.p_data, name) }; } catch (e) { return { error: { code: e.code, message: e.message } }; } } };
 const app = express(); app.use(express.json()); registerSocial(app, { database, requireUser: async req => { if (!users.includes(req.headers.authorization)) throw Error(); return { id: req.headers.authorization, email_confirmed_at: '2026-01-01' }; }, logger: { info() {}, warn() {} } });
 server = app.listen(0); await new Promise(r => server.once('listening', r)); base = `http://127.0.0.1:${server.address().port}/api/social/`;
});
beforeEach(async () => {
 await db.exec('truncate korlix_social_profiles,korlix_social_moderators,korlix_social_limits restart identity cascade');
 profiles = [];
 for (let i = 0; i < users.length; i++) profiles.push((await call(users[i], 'save_profile', profile(['alice', 'bruno', 'chris', 'diana'][i]))).profile);
});
after(async () => { if (server) await new Promise(r => server.close(r)); await db?.close(); });

test('profile details remain optional; phone/income default private; omission preserves values and privacy', async () => {
 const saved = (await call(users[0], 'save_profile', profile('alice', { status_caption: 'Building something! 🌟', home_country: ' Jamaica ', city: 'Kingston', phone_number: '+1 555 0100', favorite_color: 'Aqua', profession: 'Developer', current_job: 'KORLIX', favorite_food: 'Ackee', marital_status: 'Married', income_level: 'Prefer not to say' }))).profile;
 assert.equal(saved.home_country, 'Jamaica'); assert.equal(saved.profile_visibility.phone_number, 'private'); assert.equal(saved.profile_visibility.income_level, 'private');
 const stranger = (await call(users[1], 'member', { peer: saved.id })).profile;
 assert.equal(stranger.status_caption, saved.status_caption); assert.equal(stranger.phone_number, undefined); assert.equal(stranger.income_level, undefined); assert.equal(stranger.profile_visibility, undefined);
 await call(users[0], 'save_profile', profile('alice', { profile_visibility: { city: 'private' } }));
 const oldClient = (await call(users[0], 'save_profile', profile('alice'))).profile;
 assert.equal(oldClient.phone_number, saved.phone_number); assert.equal(oldClient.city, 'Kingston'); assert.equal(oldClient.profile_visibility.city, 'private'); assert.equal(oldClient.profession, 'Developer');
 const cleared = (await call(users[0], 'save_profile', profile('alice', { city: '' }))).profile; assert.equal(cleared.city, '');
 assert(!JSON.stringify(saved).includes(users[0]));
});

test('profile audiences distinguish pending, accepted, removed and blocked members', async () => {
 await call(users[0], 'save_profile', profile('alice', { phone_number: 'Visible after acceptance', income_level: 'Never public', status_caption: 'Connection status', profile_visibility: { phone_number: 'connections', status_caption: 'connections' } }));
 await call(users[1], 'request', { peer: profiles[0].id });
 let p = (await call(users[1], 'member', { peer: profiles[0].id })).profile; assert.equal(p.connection, 'pending'); assert.equal(p.phone_number, undefined);
 await call(users[0], 'accept', { peer: profiles[1].id });
 p = (await call(users[1], 'member', { peer: profiles[0].id })).profile; assert.equal(p.connection, 'accepted'); assert.equal(p.phone_number, 'Visible after acceptance'); assert.equal(p.income_level, undefined);
 await call(users[1], 'remove', { peer: profiles[0].id }); assert.equal((await call(users[1], 'member', { peer: profiles[0].id })).profile.phone_number, undefined);
 await call(users[1], 'block', { peer: profiles[0].id }); await assert.rejects(call(users[1], 'member', { peer: profiles[0].id }), /unavailable/);
 const card = (await db.query('select korlix_social_card(p,$1) card from korlix_social_profiles p where id=$2', [profiles[1].id, profiles[0].id])).rows[0].card;
 assert.equal(card.phone_number, undefined); assert.equal(card.status_caption, undefined);
});

test('private profession cannot be inferred from member or connection searches', async () => {
 await connect();
 await call(users[0], 'save_profile', profile('alice', { profession: 'RareSecretProfession', profile_visibility: { profession: 'private' } }));
 for (const who of [1, 2]) assert.equal((await call(users[who], 'members', { q: 'RareSecret' })).items.length, 0);
 assert.equal((await call(users[1], 'connections', { q: 'RareSecret' })).items.length, 0);
 await call(users[0], 'save_profile', profile('alice', { profile_visibility: { profession: 'connections' } }));
 assert.equal((await call(users[1], 'members', { q: 'RareSecret' })).items.length, 1); assert.equal((await call(users[2], 'members', { q: 'RareSecret' })).items.length, 0);
 assert.equal((await call(users[1], 'connections', { q: 'RareSecret' })).items[0].profession, 'RareSecretProfession');
});

test('all optional text bounds and invalid visibility structures are rejected atomically', async () => {
 const limits = { status_caption: 160, home_country: 80, city: 100, phone_number: 40, favorite_color: 60, profession: 100, current_job: 120, favorite_food: 100, marital_status: 60, income_level: 100 };
 for (const [field, max] of Object.entries(limits)) {
  await assert.rejects(call(users[0], 'save_profile', profile('alice', { [field]: 'x'.repeat(max + 1) })), /characters/);
  await assert.rejects(call(users[0], 'save_profile', profile('alice', { [field]: { secret: 'nested' } })), /text/);
 }
 for (const visibility of [null, [], { phone_number: 'public' }, { phone_number: null }, { unknown: 'private' }, { city: true }]) await assert.rejects(call(users[0], 'save_profile', profile('alice', { city: 'Not committed', profile_visibility: visibility })), /privacy/);
 assert.equal((await call(users[0], 'bootstrap')).profile.city, '');
});

test('wall separates forum posts and supports following, explore, mine and member feeds', async () => {
 const own = await post(0), follow = await post(1), unrelated = await post(2);
 await call(users[1], 'create_topic', { id: randomUUID(), category: 'sports', title: 'Forum only', body: 'Sports body' });
 assert.equal((await call(users[0], 'wall')).items.length, 1);
 await call(users[0], 'request', { peer: profiles[1].id }); assert.equal((await call(users[0], 'wall')).items.length, 1);
 await call(users[1], 'accept', { peer: profiles[0].id });
 assert.deepEqual(new Set((await call(users[0], 'wall')).items.map(p => p.id)), new Set([own.id, follow.id]));
 assert.equal((await call(users[0], 'wall', { feed: 'explore' })).items.length, 3);
 assert.deepEqual((await call(users[0], 'wall', { feed: 'mine' })).items.map(p => p.id), [own.id]);
 assert.deepEqual((await call(users[0], 'wall', { member: profiles[2].id })).items.map(p => p.id), [unrelated.id]);
 assert.equal((await call(users[0], 'topics')).items.length, 1); assert.equal((await call(users[0], 'topics')).items[0].surface, 'forum');
 const t = (await call(users[1], 'topic', { id: own.id })).topic; assert.equal(t.surface, 'wall'); assert.equal(t.title, '');
});

test('wall idempotency prevents content changes and cross-surface or cross-author collisions', async () => {
 const id = randomUUID(); const payload = { id, surface: 'wall', body: 'Same content' };
 await call(users[0], 'create_topic', payload); await call(users[0], 'create_topic', payload);
 assert.equal((await call(users[0], 'wall', { feed: 'mine' })).items.length, 1);
 await assert.rejects(call(users[0], 'create_topic', { ...payload, body: 'Changed' }), /already used/);
 await assert.rejects(call(users[1], 'create_topic', payload), /already used/);
 await assert.rejects(call(users[0], 'create_topic', { id, category: 'sports', title: 'Cross', body: 'Forum' }), /already used/);
 await call(users[0], 'delete_topic', { id }); await assert.rejects(call(users[0], 'create_topic', payload), /already used/);
 await assert.rejects(post(0, { surface: 'unexpected' }), /post type/);
});

test('wall edit/replies/deletion/reporting reuse ownership and moderation protections', async () => {
 const { id } = await post(0); const reply = randomUUID();
 await call(users[1], 'reply', { id, reply_id: reply, body: 'Reply here' });
 assert.equal((await call(users[2], 'wall', { feed: 'explore' })).items[0].reply_count, 1);
 await call(users[0], 'edit_topic', { id, body: 'Updated caption' }); assert.equal((await call(users[2], 'topic', { id })).topic.body, 'Updated caption');
 await assert.rejects(call(users[1], 'edit_topic', { id, body: 'Hijack' }), /own/);
 const report = randomUUID(); await call(users[2], 'report', { id: report, kind: 'topic', target: id, reason: 'Review' });
 await db.query('insert into korlix_social_moderators values($1)', [users[3]]);
 await call(users[3], 'moderate', { id: report, decision: 'lock' }); await assert.rejects(call(users[1], 'reply', { id, reply_id: randomUUID(), body: 'Locked' }), /locked/);
 await call(users[0], 'delete_topic', { id }); await assert.rejects(call(users[2], 'topic', { id }), /not found/);
 assert.equal((await call(users[2], 'wall', { feed: 'explore' })).items.length, 0);
});

test('public wall posts survive hidden discoverability, while profile walls require access; blocks and suspensions hide content', async () => {
 const { id } = await post(0); await call(users[0], 'save_profile', profile('alice', { discoverable: false }));
 assert.equal((await call(users[1], 'wall', { feed: 'explore' })).items[0].id, id); assert.equal((await call(users[1], 'topic', { id })).topic.id, id);
 await assert.rejects(call(users[1], 'wall', { member: profiles[0].id }), /unavailable/); await assert.rejects(call(users[1], 'member', { peer: profiles[0].id }), /unavailable/);
 await call(users[0], 'request', { peer: profiles[1].id }); await call(users[1], 'accept', { peer: profiles[0].id }); assert.equal((await call(users[1], 'wall', { member: profiles[0].id })).items.length, 1);
 await call(users[1], 'block', { peer: profiles[0].id }); assert.equal((await call(users[1], 'wall', { feed: 'explore' })).items.length, 0); await assert.rejects(call(users[1], 'topic', { id }), /not found/);
 await db.query('update korlix_social_profiles set suspended=true where id=$1', [profiles[0].id]); assert.equal((await call(users[2], 'wall', { feed: 'explore' })).items.length, 0); await assert.rejects(call(users[0], 'wall'), /suspended/);
});

test('wall stable chronological paging and literal search do not skip or duplicate posts', async () => {
 for (let i = 0; i < 25; i++) await db.query("insert into korlix_social_topics(id,author,category,title,body,surface,created_at) values($1,$2,'community',$3,$3,'wall',now()-make_interval(secs=>$4))", [randomUUID(), profiles[0].id, `Post ${i}`, i]);
 const first = (await call(users[1], 'wall', { feed: 'explore' })).items; assert.equal(first.length, 21);
 const second = (await call(users[1], 'wall', { feed: 'explore', offset: 20 })).items; assert.equal(second.length, 5);
 assert.equal(new Set([...first.slice(0, 20), ...second].map(x => x.id)).size, 25);
 assert.equal((await call(users[1], 'wall', { feed: 'explore', q: '%' })).items.length, 0); assert.equal((await call(users[1], 'wall', { feed: 'explore', q: 'Post 24' })).items.length, 1);
});

test('legacy card omits new details; avatar owner save retains private fields', async () => {
 await call(users[0], 'save_profile', profile('alice', { phone_number: 'Secret phone', city: 'Public city', profile_visibility: { profession: 'private' }, profession: 'Secret job' }));
 const card = (await db.query('select korlix_social_card(p) card from korlix_social_profiles p where id=$1', [profiles[0].id])).rows[0].card;
 assert.equal(card.phone_number, undefined); assert.equal(card.city, undefined); assert.equal(card.profession, '');
 const self = (await db.query("select korlix_social_avatar($1,'save',null) result", [users[0]])).rows[0].result.profile;
 assert.equal(self.phone_number, 'Secret phone'); assert.equal(self.city, 'Public city'); assert.equal(self.profile_visibility.profession, 'private');
});

test('wall and member HTTP reads require auth, resist actor spoofing and obey GET-only contract', async () => {
 await post(0); await post(1);
 assert.equal((await api('wall', { feed: 'mine', p_actor: users[1], actor: users[1] })).items[0].author.id, profiles[0].id);
 const p = (await api('member', { peer: profiles[1].id })).profile; assert.equal(p.id, profiles[1].id); assert.equal(p.connection, null);
 await api('wall', {}, 8, 'GET', 401); await api('wall', {}, 0, 'POST', 404); await api('member', {}, 0, 'POST', 404);
 await api('wall', { feed: 'bad' }, 0, 'GET', 400);
});

test('all new and replaced functions remain service-only invokers; tables retain RLS', async () => {
 for (const name of ['korlix_social_card(korlix_social_profiles)', 'korlix_social_card(korlix_social_profiles,uuid)', 'korlix_social_v1(uuid,text,jsonb)', 'korlix_social_avatar(uuid,text,text)']) {
  const row = (await db.query("select has_function_privilege('anon',$1,'execute') anon,has_function_privilege('authenticated',$1,'execute') authenticated,(select prosecdef from pg_proc where oid=$1::regprocedure) definer", [name])).rows[0]; assert.deepEqual(row, { anon: false, authenticated: false, definer: false });
 }
 for (const table of ['korlix_social_profiles', 'korlix_social_topics']) assert.deepEqual((await db.query("select has_table_privilege('authenticated',$1,'select') access,(select relrowsecurity from pg_class where oid=$1::regclass) rls", [table])).rows[0], { access: false, rls: true });
 await db.exec('set role service_role'); try { assert.equal((await call(users[0], 'bootstrap')).profile.id, profiles[0].id); await post(); } finally { await db.exec('reset role'); }
});


test('own member view preserves profile discoverability and online controls through edits', async () => {
 await call(users[0], 'save_profile', profile('alice', { discoverable: false, show_online: true }));
 const self = (await call(users[0], 'member', { peer: profiles[0].id })).profile;
 assert.equal(self.discoverable, false); assert.equal(self.show_online, true);
 await call(users[0], 'save_profile', { ...self, city: 'Updated city' });
 const result = (await call(users[0], 'bootstrap')).profile;
 assert.equal(result.discoverable, false); assert.equal(result.show_online, true);
 const other = (await call(users[0], 'member', { peer: profiles[1].id })).profile;
 assert.equal(other.discoverable, undefined); assert.equal(other.show_online, undefined);
});
