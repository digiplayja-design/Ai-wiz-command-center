import test from "node:test";
import assert from "node:assert/strict";
import { normalizeContact, validateQuery } from "../contacts_crm/core.mjs";
import { previewImport, parseCsv } from "../contacts_crm/imports.mjs";
import { registerContactsCrm } from "../contacts_crm/routes.mjs";
import { createContactStore } from "../contacts_crm/store.mjs";
import ExcelJS from "exceljs";
const uid = "00000000-0000-4000-8000-000000000001",
  cid = "00000000-0000-4000-8000-000000000002";
const file = (filename, text, source = "spreadsheet") => ({
  filename,
  source,
  content: Buffer.from(text).toString("base64"),
});
test("validates contact fields and import cannot grant permissions", () => {
  const c = normalizeContact(
    {
      name: " Sam ",
      email: "SAM@example.com",
      phone: "+1 (415) 555-0123",
      category: "Customer",
      email_permission: "marketing",
      call_permission: "allowed",
      consent_at: "invalid",
      do_not_contact: true,
    },
    { imported: true },
  );
  assert.equal(c.email, "sam@example.com");
  assert.equal(c.phone_key, "14155550123");
  assert.equal(c.email_permission, "none");
  assert.equal(c.call_permission, "none");
  assert.equal(c.consent_at, null);
  for (const raw of [
    { name: "" },
    { name: "a", email: "bad" },
    { name: "a", phone: "123" },
    { name: "a", category: "admin" },
    { name: "a", email_permission: "marketing" },
    { name: "a", follow_up_on: "2026-02-31" },
  ])
    assert.throws(() => normalizeContact(raw));
  assert.throws(() => validateQuery({ limit: 100000 }));
  assert.throws(() => validateQuery({ category: "admin" }));
  assert(!validateQuery({ q: "a),user_id.eq.hack%" }).q.includes(","));
});
test("CSV handles quotes, multiline fields, Google aliases, duplicates and invalid rows", async () => {
  const p = await previewImport(
    file(
      "contacts.csv",
      'Name,Email 1 - Value,Phone 1 - Value,Status,Notes\r\n"Sam, Lee",sam@example.com,+14155550123,customer,"line 1\nline 2"\r\nDuplicate,SAM@example.com,,friend,\r\nBad,no-email,,friend,',
    ),
  );
  assert.equal(p.total, 3);
  assert.equal(p.contacts.length, 1);
  assert.equal(p.duplicates, 1);
  assert.equal(p.errors.length, 1);
  assert.equal(p.contacts[0].notes, "line 1\nline 2");
  assert.throws(() => parseCsv('Name\n"unfinished'));
});
test("phone vCards and Facebook friend exports", async () => {
  const v = await previewImport(
    file(
      "contacts.vcf",
      "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ada Lovelace\r\nTEL;TYPE=CELL:+442012345678\r\nEMAIL:ada@example.com\r\nEND:VCARD",
      "phone",
    ),
  );
  assert.equal(v.contacts[0].name, "Ada Lovelace");
  assert.equal(v.contacts[0].source, "phone");
  const f = await previewImport(
    file(
      "friends.json",
      JSON.stringify({
        friends_v2: [
          { name: "Alex", timestamp: 123 },
          { name: "Alex" },
          { name: "Robin" },
        ],
      }),
      "facebook",
    ),
  );
  assert.equal(f.contacts.length, 2);
  assert.equal(f.duplicates, 1);
  assert.equal(f.contacts[0].email, null);
});
test("Excel workbook imports first worksheet and treats formulas as text", async () => {
  const w = new ExcelJS.Workbook(),
    s = w.addWorksheet("Contacts");
  s.addRow(["Name", "Email", "Status"]);
  s.addRow(["Nova User", "user@example.com", "family"]);
  const p = await previewImport({
    source: "spreadsheet",
    filename: "contacts.xlsx",
    content: Buffer.from(await w.xlsx.writeBuffer()).toString("base64"),
  });
  assert.equal(p.contacts[0].category, "family");
  await assert.rejects(
    previewImport(file("bad.xlsx", "invalid")),
    /valid Excel/,
  );
});
test("rejects oversized and incomplete imports", async () => {
  await assert.rejects(
    previewImport({
      source: "phone",
      contacts: Array.from({ length: 1001 }, () => ({ name: "a" })),
    }),
    /1,000/,
  );
  await assert.rejects(
    previewImport(file("contacts.vcf", "BEGIN:VCARD\nFN:Sam", "phone")),
    /incomplete/,
  );
  await assert.rejects(
    previewImport({
      source: "spreadsheet",
      filename: "x.csv",
      content: "a".repeat(3 * 1024 * 1024),
    }),
    /2 MB/,
  );
});
function harness({
  enterprise = true,
  user = { id: uid },
  contact = {
    id: cid,
    name: "Sam",
    version: 1,
    email: "sam@example.com",
    email_permission: "transactional",
  },
  emailService,
} = {}) {
  const routes = [],
    calls = [];
  const app = {};
  for (const method of ["get", "post", "put", "delete"])
    app[method] = (path, fn) => routes.push({ method, path, fn });
  const store = {
    enterprise: async (u) => {
      calls.push(["enterprise", u]);
      return enterprise;
    },
    counts: async (u) => ({ total: 3 }),
    list: async (u, q) => {
      calls.push(["list", u, q]);
      return { contacts: [] };
    },
    get: async (u, id) => {
      calls.push(["get", u, id]);
      return contact;
    },
    create: async (u, c) => {
      calls.push(["create", u, c]);
      return c;
    },
    update: async (u, id, c, v) => {
      calls.push(["update", u, id, c, v]);
      return c;
    },
    archive: async (...args) => calls.push(["archive", ...args]),
    import: async (u, rows) => {
      calls.push(["import", u, rows]);
      return { imported: rows.length };
    },
    emailContacts: async () => [],
  };
  registerContactsCrm(app, {
    store,
    requireUser: async () => user,
    emailService: emailService ?? {
      saveRecipient: async (args) => {
        calls.push(["email", args]);
        return { created: true };
      },
    },
  });
  const invoke = async (route, body = {}, params = { id: cid }) => {
    const res = {
      statusCode: 200,
      headers: {},
      set(k, v) {
        this.headers[k] = v;
        return this;
      },
      status(s) {
        this.statusCode = s;
        return this;
      },
      json(v) {
        this.body = v;
        return this;
      },
    };
    await route.fn({ body, params, query: {} }, res);
    return res;
  };
  return {
    routes,
    calls,
    invoke,
    by: (method, path) =>
      routes.find((r) => r.method === method && r.path === path),
  };
}
test("every CRM endpoint rejects anonymous and non-Enterprise callers", async () => {
  for (const options of [{ user: null }, { enterprise: false }]) {
    const h = harness(options);
    for (const r of h.routes) {
      const res = await h.invoke(r);
      assert.equal(res.statusCode, options.user === null ? 401 : 403, r.path);
      assert.equal(res.headers["Cache-Control"], "no-store");
    }
    assert(h.calls.every((c) => c[0] === "enterprise"));
  }
});
test("create ignores client owner IDs and imports force review and no permissions", async () => {
  const h = harness();
  await h.invoke(h.by("post", "/api/contacts"), {
    name: "Sam",
    user_id: "other-owner",
  });
  const call = h.calls.find((c) => c[0] === "create");
  assert.equal(call[1], uid);
  assert(!("user_id" in call[2]));
  assert.equal(
    (
      await h.invoke(h.by("post", "/api/contacts/imports"), {
        contacts: [{ name: "Sam" }],
      })
    ).statusCode,
    400,
  );
  const r = await h.invoke(h.by("post", "/api/contacts/imports"), {
    confirmed: true,
    contacts: [
      {
        name: "Sam",
        email_permission: "marketing",
        call_permission: "allowed",
      },
    ],
  });
  assert.equal(r.statusCode, 200);
  assert.equal(
    h.calls.find((c) => c[0] === "import")[2][0].email_permission,
    "none",
  );
});
test("blocked contacts cannot be handed to email and call provider is never invoked", async () => {
  for (const contact of [
    { do_not_contact: true, email: "a@b.co", email_permission: "marketing" },
    { email: "a@b.co", email_permission: "none" },
  ]) {
    const h = harness({ contact });
    assert.equal(
      (
        await h.invoke(h.by("post", "/api/contacts/:id/email-link"), {
          confirmed: true,
          agentId: "nova",
        })
      ).statusCode,
      409,
    );
    assert(!h.calls.some((c) => c[0] === "email"));
  }
  const h = harness({
    contact: {
      name: "Sam",
      id: cid,
      call_permission: "allowed",
      phone: "+14155550123",
      call_brief: "Discuss demo",
    },
  });
  const result = await h.invoke(h.by("get", "/api/contacts/:id/call-brief"));
  assert.equal(result.body.called, false);
  assert.equal(result.body.outboundCallingEnabled, false);
});
test("email linking uses verified owner and stored contact permission", async () => {
  const h = harness();
  const result = await h.invoke(h.by("post", "/api/contacts/:id/email-link"), {
    confirmed: true,
    agentId: "nova",
    email: "attacker@example.com",
    userId: "other",
  });
  assert.equal(result.body.sent, false);
  const args = h.calls.find((c) => c[0] === "email")[1];
  assert.equal(args.userId, uid);
  assert.equal(args.body.email, "sam@example.com");
  assert.equal(args.body.sourceReference, "crm:" + cid);
});
test("store scopes reads and writes and rejects stale update versions", async () => {
  const steps = [];
  let response = { data: null, error: null };
  const chain = new Proxy(
    {},
    {
      get(_t, key) {
        if (key === "then") return (resolve) => resolve(response);
        return (...args) => {
          steps.push([key, ...args]);
          return chain;
        };
      },
    },
  );
  const db = {
    from: (t) => {
      steps.push(["from", t]);
      return chain;
    },
  };
  const store = createContactStore(db);
  await assert.rejects(store.get(uid, cid), /not found/);
  assert(
    steps.some((s) => s[0] === "eq" && s[1] === "user_id" && s[2] === uid),
  );
  steps.length = 0;
  await assert.rejects(store.update(uid, cid, { name: "a" }, 3), /changed/);
  assert(steps.some((s) => s[0] === "eq" && s[1] === "version" && s[2] === 3));
  assert(steps.some((s) => s[0] === "eq" && s[1] === "user_id"));
});
