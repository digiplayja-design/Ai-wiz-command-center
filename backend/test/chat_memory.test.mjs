import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import crypto from 'node:crypto';
import vm from 'node:vm';
import express from 'express';
import { PGlite } from '@electric-sql/pglite';
import { registerChatMemory, prepareChatMemory, memoryAction, rememberText, memoryPrompt } from '../chat_memory/memory.mjs';
import { resumeTextPolicy } from '../resume_studio/policy.mjs';
import chatQuality from '../chat_quality.cjs';

let db, server, base, prompts = [];
const ids = [randomUUID(), randomUUID()];
const users = ids.map(id => ({ id, email_confirmed_at: '2026-01-01' }));
const actor = users[0];
const database = { rpc: async (_, p) => {
  try { return { data: (await db.query('select korlix_main_chat_memory_v1($1,$2,$3::jsonb) result', [p.p_actor, p.p_action, JSON.stringify(p.p_data)])).rows[0].result }; }
  catch (error) { return { error }; }
} };
const act = (action, data = {}, user = actor) => memoryAction(database, user, action, data);
const save = (body = 'My name is Alex', user = actor, extra = {}) => act('save', { id: randomUUID(), body, category: 'personal', ...extra }, user);
const request = async (path, data, id = ids[0], status = 200) => {
  const res = await fetch(base + path, { method: data == null ? 'GET' : 'POST', headers: { Authorization: id, 'Content-Type': 'application/json' }, body: data == null ? undefined : JSON.stringify(data) });
  const result = await res.json(); assert.equal(res.status, status, JSON.stringify(result));
  assert.equal(res.headers.get('cache-control'), 'no-store'); return result;
};

before(async () => {
  db = new PGlite();
  await db.exec('create schema auth; create role anon; create role authenticated; create role service_role bypassrls; create table auth.users(id uuid primary key);');
  for (const id of ids) await db.query('insert into auth.users values($1)', [id]);
  const folder = new URL('../../supabase/migrations/', import.meta.url);
  const migration = (await readdir(folder)).find(f => f.endsWith('_korlix_main_chat_memory.sql'));
  await db.exec(await readFile(new URL(migration, folder), 'utf8'));
  const app = express(); app.use(express.json());
  const requireUser = async req => { const user = users.find(u => u.id === req.headers.authorization); if (!user) throw Object.assign(Error('Sign in'), { statusCode: 401 }); return user; };
  registerChatMemory(app, { database, requireUser });
  const source = await readFile(new URL('../server.js', import.meta.url), 'utf8');
  const generateRoute = source.slice(source.indexOf('app.post("/api/generate",'), source.indexOf('// CREDIT DISPUTE LETTERS'));
  const context = {
    app, process: { env: { OPENAI_API_KEY: 'fixture-key' } }, console: { error() {} },
    supabaseAdmin: database, prepareChatMemory, resumeTextPolicy, ...chatQuality,
    languageMap: { en: { name: 'English', instruction: 'Use English' } }, shouldUseLiveSearch: () => false, wantsFile: () => false, calculateCredits: () => 1,
    getAuthenticatedUser: requireUser, getOrCreateProfile: async () => ({ tier: 'basic' }), getOrCreateUsageCounter: async () => ({}), checkUsageAllowed: () => ({ allowed: true }),
    sanitize: x => x, getKorlixUserFacingError: e => e.message, OpenAI: class {}, CHAT_MODEL: 'fixture', CHAT_EFFORT: 'fixture',
    getCharacterPersonality: () => ({ name: 'KORLIX', style: 'Helpful' }),
    createOpenAIResponse: async (_, options) => { prompts.push(options.input); return { output_text: 'Fixture answer' }; },
    saveGenerationHistory: async () => ({}), incrementUsage: async () => ({}),
  };
  vm.runInNewContext(generateRoute, context);
  const jobs = source.slice(source.indexOf('// KORLIX_RESUMABLE_JSON_JOBS_BEGIN'), source.indexOf('// KORLIX_RESUMABLE_JSON_JOBS_END'));
  vm.runInNewContext(jobs, { app, requireUser, crypto, global: {}, process: { env: {} }, sanitize: x => x, setImmediate: f => f(), fetch: async () => ({ status: 200, text: async () => JSON.stringify({ content: 'A private result' }) }) });
  server = app.listen(0); await new Promise(r => server.once('listening', r)); base = `http://127.0.0.1:${server.address().port}`;
});
beforeEach(async () => { prompts = []; await db.exec('truncate korlix_main_chat_memories, korlix_main_chat_memory_settings;'); });
after(async () => { if (server) await new Promise(r => server.close(r)); await db?.close(); });

test('authenticated ownership ignores spoofed actor fields and browser roles have no access', async () => {
  await request('/api/chat-memory/list', null, '', 401);
  await request('/api/chat-memory/save', { actor: ids[1], user_id: ids[1], id: randomUUID(), body: 'My dog is Pepper' });
  assert.equal((await act('list')).items.length, 1); assert.equal((await act('list', {}, users[1])).items.length, 0);
  const grants = await db.query("select has_table_privilege('authenticated','korlix_main_chat_memories','select') browser, has_function_privilege('anon','korlix_main_chat_memory_v1(uuid,text,jsonb)','execute') rpc, (select relrowsecurity from pg_class where oid='korlix_main_chat_memories'::regclass) rls, (select prosecdef from pg_proc where oid='korlix_main_chat_memory_v1(uuid,text,jsonb)'::regprocedure) definer");
  assert.deepEqual(grants.rows[0], { browser: false, rpc: false, rls: true, definer: false });
  await db.exec('set role service_role'); try { assert.equal((await act('list')).items.length, 1); } finally { await db.exec('reset role'); }
});
test('save, deduplicate retry, edit version, delete and account isolation', async () => {
  const note = (await save()).items[0];
  await save('My name is Alex'); await save('my name is alex'); assert.equal((await act('list')).items.length, 1);
  await assert.rejects(act('save', { ...note, body: 'Spoof' }, users[1]), /not found/);
  const updated = await act('save', { ...note, body: 'My name is Alex Morgan' }); assert.equal(updated.items[0].version, 2);
  await assert.rejects(act('save', { ...note, body: 'Old edit' }), /changed on another device/);
  await act('delete', { id: note.id }, users[1]); assert.equal((await act('list')).items.length, 1);
  await act('delete', { id: note.id }); assert.equal((await act('list')).items.length, 0);
});
test('new notes cannot hijack another account ID and deletion cannot be undone by a stale edit', async () => {
  const note = (await save()).items[0];
  await assert.rejects(save(note.body, users[1], { id: note.id }), /new memory ID/);
  await act('delete', { id: note.id }); await assert.rejects(act('save', { ...note, body: 'Restore' }), /not found/);
});
test('clear requires confirmation and affects only the caller', async () => {
  await save(); await save('Other account', users[1]); await assert.rejects(act('clear'), /Confirm/);
  await act('clear', { confirm: true }); assert.equal((await act('list')).items.length, 0); assert.equal((await act('list', {}, users[1])).items.length, 1);
});
test('bounds, categories, secret guard and per-account capacity', async () => {
  for (const body of ['', 'a'.repeat(501), 'My password is private123', 'API key: sk-test']) await assert.rejects(save(body));
  await assert.rejects(save('Something', actor, { category: 'invalid' }));
  for (let i = 0; i < 100; i++) await save(`Fact ${i}`);
  await assert.rejects(save('Beyond capacity'), /100 memories/);
  assert.equal((await save('Fact 0')).items.length, 100);
  assert.equal((await save('New account fact', users[1])).items.length, 1);
});
test('remember commands require explicit wording and do not turn questions into saved notes', () => {
  assert.equal(rememberText('Please remember that I prefer short answers.'), 'I prefer short answers.');
  assert.equal(rememberText('Remember this: My name is Alex'), 'My name is Alex');
  for (const text of ['Do you remember my name?', 'Remember when we talked?', 'Remember to call Bob', 'My name is Alex']) assert.equal(rememberText(text), null);
  assert.equal(rememberText('KORLIX AI PRODUCTION QUALITY POLICY:\nRules\nUSER REQUEST:\nRemember that my name is Alex'), 'my name is Alex');
});
test('main generate saves explicitly without AI calls; a fresh topic receives only this account’s notes', async () => {
  const reply = await request('/api/generate', { command: 'Remember that my dog is Pepper', mainChatMemory: true });
  assert.equal(reply.memorySaved, true); assert.equal(reply.creditsUsed, 0); assert.equal(prompts.length, 0);
  await save('Secret for another account', users[1]);
  await request('/api/generate', { command: 'What is my dog called?', mainChatMemory: true, history: [], topicId: 'new-topic' });
  assert.match(prompts[0], /my dog is Pepper/); assert(!prompts[0].includes('Secret for another account'));
  assert.match(prompts[0], /untrusted user-authored data/); assert.match(prompts[0], /Never claim you saved/);
});
test('pause excludes saved data and refuses chat saves; resume restores recall; forgetting removes future context', async () => {
  const note = (await save('My dog is Pepper')).items[0];
  await act('settings', { enabled: false });
  await request('/api/generate', { command: 'What is my dog called?', mainChatMemory: true }); assert(!prompts.at(-1).includes('Pepper'));
  const r = await request('/api/generate', { command: 'Remember that my cat is Leo', mainChatMemory: true }); assert.equal(r.memorySaved, false); assert.equal((await act('list')).items.length, 1);
  await act('settings', { enabled: true });
  await request('/api/generate', { command: 'My dog?', mainChatMemory: true }); assert.match(prompts.at(-1), /Pepper/);
  await act('delete', { id: note.id });
  await request('/api/generate', { command: 'My dog?', mainChatMemory: true }); assert(!prompts.at(-1).includes('Pepper'));
});
test('ordinary prompts never autosave; other tools cannot inherit main memory', async () => {
  await save('Unique private memory');
  for (const extra of [{}, { purpose: 'resume_studio', mainChatMemory: true }, { disableAccountMemory: 'true', mainChatMemory: true }]) {
    await request('/api/generate', { command: 'Remember that I live in Tokyo', ...extra });
    assert(!prompts.at(-1).includes('Unique private memory'));
  }
  await request('/api/generate', { command: 'I live in London', mainChatMemory: true });
  assert.equal((await act('list')).items.length, 1);
  assert.equal(memoryPrompt({ enabled: false, items: [{ body: 'private' }] }).includes('private"'), false);
});
test('memory storage failure does not produce false success or silently omit expected context', async () => {
  await assert.rejects(prepareChatMemory({ database: { rpc: async () => ({ error: { code: 'XX000' } }) }, user: actor, body: { command: 'Hello', mainChatMemory: true } }), /could not be confirmed/);
  await request('/api/chat-memory/save', { id: 'not-an-id', body: 'Hello' }, ids[0], 400);
});
test('background results require the verified creating account; IDs and caches do not expose memory', async () => {
  await request('/api/korlix/jobs', { endpoint: '/api/generate' }, '', 401);
  const job = await request('/api/korlix/jobs', { endpoint: '/api/generate', ownerId: ids[1], payload: { command: 'Hi' } }, ids[0], 202);
  assert.match(job.jobId, /^korlix_job_[0-9a-f-]{36}$/); assert.equal(job.ownerId, undefined);
  await request(`/api/korlix/jobs/${job.jobId}`, null, '', 401);
  await request(`/api/korlix/jobs/${job.jobId}`, null, ids[1], 404);
  assert.equal((await request(`/api/korlix/jobs/${job.jobId}`, null)).result.json.content, 'A private result');
});
