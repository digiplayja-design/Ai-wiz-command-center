import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import ExcelJS from 'exceljs';
import { PGlite } from '@electric-sql/pglite';
import { previewImport, parseCsv } from '../contacts_crm/imports.mjs';
import { registerContactsCrm } from '../contacts_crm/routes.mjs';
import { createContactStore } from '../contacts_crm/store.mjs';

const csv = text => ({ source: 'spreadsheet', filename: 'contacts.csv', content: Buffer.from(text).toString('base64') });
const xlsx = async book => ({ source: 'spreadsheet', filename: 'contacts.xlsx', content: Buffer.from(await book.xlsx.writeBuffer()).toString('base64') });

test('CSV, semicolon and UTF-16 TSV preserve quoted delimiters and physical row numbers', async () => {
  assert.deepEqual(parseCsv('Name,Notes\nAda,with\ta tab'), [['Name', 'Notes'], ['Ada', 'with\ta tab']]);
  const p = await previewImport(csv('sep=;\r\nFirst Name;Last Name;E-mail Address;Notes\r\nAda;Lovelace;ADA@example.com;"one; two\nthree"\r\n\r\nBad;Email;bad;\r\n'));
  assert.equal(p.contacts[0].name, 'Ada Lovelace');
  assert.equal(p.contacts[0].notes, 'one; two\nthree');
  assert.equal(p.errors[0].row, 6);
  const bytes = Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from('Name\tEmail\nSam, Jr\tsam@example.com', 'utf16le')]);
  const t = await previewImport({ ...csv(''), filename: 'contacts.tsv', content: bytes.toString('base64') });
  assert.equal(t.contacts[0].name, 'Sam, Jr');
});

test('nonstandard columns can be mapped without losing values or granting outreach', async () => {
  const body = csv('Person;Reach me;Account;Next touch\nAvery;avery@example.com;Example Co;2026-11-06');
  const initial = await previewImport(body);
  assert.equal(initial.spreadsheet.needsMapping, true);
  assert.equal(initial.contacts.length, 0);
  const p = await previewImport({ ...body, mapping: { name: 0, email: 1, company: 2, follow_up_on: 3 }, defaultCategory: 'lead' });
  assert.equal(p.contacts[0].name, 'Avery');
  assert.equal(p.contacts[0].category, 'lead');
  assert.equal(p.contacts[0].company, 'Example Co');
  assert.equal(p.contacts[0].follow_up_on, '2026-11-06');
  assert.equal(p.contacts[0].email_permission, 'none');
  for (const mapping of [{ name: -1 }, { name: 20 }, { name: '0' }, { name: 0, email: 0 }, { user_id: 0 }]) {
    await assert.rejects(previewImport({ ...body, mapping }), /column/);
  }
  await assert.rejects(previewImport({ ...body, defaultCategory: 'admin' }), /status/);
});

test('Excel finds contacts beyond a cover sheet and supports explicit worksheet/header selection', async () => {
  const book = new ExcelJS.Workbook();
  book.addWorksheet('Read me').addRow(['Contact export instructions']);
  const sheet = book.addWorksheet('Customers');
  sheet.addRow(['Autumn contacts']); sheet.addRow([]);
  sheet.addRow(['First Name', 'Last Name', 'Email', 'Phone', 'Follow Up On', 'Notes']);
  sheet.addRow(['Avery', 'Sample', 'avery@example.com', 1234567, new Date('2026-11-06T00:00:00Z'), { formula: '"Stored note"', result: 'Stored note' }]);
  sheet.getCell('D4').numFmt = '0000000000';
  const other = book.addWorksheet('Vendors');
  other.addRow(['Person', 'Address']); other.addRow(['Vendor Sample', 'vendor@example.com']);
  book.addWorksheet('Private', { state: 'hidden' }).addRow(['Name']);
  const body = await xlsx(book);
  const p = await previewImport(body);
  assert.equal(p.spreadsheet.worksheet, 'Customers');
  assert.equal(p.spreadsheet.headerRow, 3);
  assert.deepEqual(p.spreadsheet.sheets, ['Read me', 'Customers', 'Vendors']);
  assert.equal(p.contacts[0].phone, '0001234567');
  assert.equal(p.contacts[0].follow_up_on, '2026-11-06');
  assert.equal(p.contacts[0].notes, 'Stored note');
  const v = await previewImport({ ...body, worksheet: 'Vendors', headerRow: 1, mapping: { name: 0, email: 1 }, defaultCategory: 'vendor' });
  assert.equal(v.contacts[0].category, 'vendor');
  await assert.rejects(previewImport({ ...body, worksheet: 'Private' }), /worksheet/);
  await assert.rejects(previewImport({ ...body, headerRow: 2 }), /header row/);
});

test('validation reports bad dates and contacts while removing file duplicates', async () => {
  const p = await previewImport(csv('Name,Email,Follow Up On\nA,a@example.com,2026-11-06\nAgain,A@example.com,\nBad Date,d@example.com,2026-02-31\nBad Email,bad,\nNo Email,,2026-12-01'));
  assert.equal(p.contacts.length, 2); assert.equal(p.duplicates, 1);
  assert.deepEqual(p.errors.map(e => e.row), [4, 5]);
  const phone = await previewImport(csv('Mobile\n+14155550123'));
  assert.equal(phone.contacts[0].name, '+14155550123');
  assert.equal(phone.contacts[0].phone, '+14155550123');
});

test('row/column limits and malformed quoted input fail before importing', async () => {
  const thousand = 'Name,Email\n' + Array.from({ length: 1000 }, (_, i) => `Contact ${i},c${i}@example.com`).join('\n');
  assert.equal((await previewImport(csv(thousand))).contacts.length, 1000);
  await assert.rejects(previewImport(csv(thousand + '\nToo many,extra@example.com')), /1,000/);
  await assert.rejects(previewImport(csv(Array(101).fill('Name').join(','))), /100 columns/);
  assert.throws(() => parseCsv('Name\n"Unfinished'), /unfinished/);
});

let db;
const owner = '00000000-0000-4000-8000-000000000001';
const otherOwner = '00000000-0000-4000-8000-000000000002';
before(async () => {
  db = new PGlite();
  await db.exec(`create schema auth; create role anon; create role authenticated; create role service_role bypassrls;
    create table auth.users(id uuid primary key);
    create table user_profiles(id uuid primary key, tier text);
    create table korlix_agent_email_recipients(user_id uuid, email text, active boolean, consent_status text, suppressed_at timestamptz, suppression_reason text, updated_at timestamptz, source_reference text);
    grant select on user_profiles to service_role;
    insert into auth.users values ('${owner}'), ('${otherOwner}');
    insert into user_profiles values ('${owner}', 'enterprise'), ('${otherOwner}', 'enterprise');`);
  await db.exec(await readFile(new URL('../../supabase/migrations/20260921162128_enterprise_contacts_crm.sql', import.meta.url), 'utf8'));
});
after(async () => await db?.close());

test('real upload preview and import routes persist owner-scoped contacts and safely retry duplicates', async () => {
  const store = createContactStore({ rpc: async (name, args) => {
    assert.equal(name, 'korlix_contacts_import_v1');
    return db.transaction(async tx => {
      await tx.exec('set local role service_role');
      return { data: (await tx.query('select korlix_contacts_import_v1($1,$2::jsonb) as result', [args.p_user_id, JSON.stringify(args.p_contacts)])).rows[0].result };
    });
  } });
  store.enterprise = async id => id === owner;
  const routes = new Map();
  const app = Object.fromEntries(['get', 'post', 'put', 'delete'].map(method => [method, (path, handler) => routes.set(`${method} ${path}`, handler)]));
  registerContactsCrm(app, { store, requireUser: async () => ({ id: owner }) });
  const invoke = async (path, body) => {
    const res = { statusCode: 200, set() { return this; }, status(value) { this.statusCode = value; return this; }, json(value) { this.body = value; return this; } };
    await routes.get(`post /api/contacts${path}`)({ body }, res);
    assert.equal(res.statusCode, 200, res.body?.error);
    return res.body;
  };
  const preview = await invoke('/imports/preview', csv('Name,Email,Phone,Company,Tags,Follow Up On\nAvery,avery@example.com,+14155550123,Example Co,vip;launch,2026-11-06'));
  const request = { confirmed: true, user_id: otherOwner, contacts: preview.contacts.map(c => ({ ...c, user_id: otherOwner, email_permission: 'marketing' })) };
  assert.deepEqual(await invoke('/imports', request), { imported: 1, duplicates: 0 });
  assert.deepEqual(await invoke('/imports', request), { imported: 0, duplicates: 1 });
  const rows = (await db.query('select * from korlix_contacts')).rows;
  assert.equal(rows.length, 1); assert.equal(rows[0].user_id, owner);
  assert.equal(rows[0].company, 'Example Co'); assert.deepEqual(rows[0].tags, ['vip', 'launch']);
  assert.equal(rows[0].email_permission, 'none'); assert.equal(rows[0].call_permission, 'none');
  assert.equal(rows[0].follow_up_on.toISOString().slice(0, 10), '2026-11-06');
});
