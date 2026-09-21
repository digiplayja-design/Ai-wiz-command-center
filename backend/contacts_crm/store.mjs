import { fail, CATEGORIES, validateQuery } from "./core.mjs";
const TABLE = "korlix_contacts";
function checked(r) {
  if (r.error) {
    if (r.error.code === "23505")
      fail(
        "This email or phone already belongs to a contact.",
        409,
        "CONTACT_DUPLICATE",
      );
    fail(
      "Contacts storage is unavailable. Please try again.",
      503,
      "CONTACT_STORAGE_UNAVAILABLE",
    );
  }
  return r;
}
export function createContactStore(db) {
  const owned = (u) =>
    db.from(TABLE).select("*").eq("user_id", u).is("archived_at", null);
  const filter = (q, f) => {
    if (f.category) q = q.eq("category", f.category);
    if (f.source) q = q.eq("source", f.source);
    if (f.q)
      q = q.or(
        ["name", "email", "phone", "company"]
          .map((k) => `${k}.ilike.%${f.q}%`)
          .join(","),
      );
    if (f.segment === "favorites") q = q.eq("favorite", true);
    if (f.segment === "follow_up")
      q = q.lte("follow_up_on", new Date().toISOString().slice(0, 10));
    if (f.segment === "missing_details")
      q = q.or("email.is.null,phone.is.null");
    if (f.segment === "email_ready")
      q = q
        .not("email", "is", null)
        .in("email_permission", ["transactional", "marketing"])
        .eq("do_not_contact", false);
    if (f.segment === "call_ready")
      q = q
        .like("phone", "+%")
        .eq("call_permission", "allowed")
        .eq("do_not_contact", false);
    return q;
  };
  return {
    async enterprise(u) {
      const r = checked(
        await db
          .from("user_profiles")
          .select("id,tier")
          .eq("id", u)
          .maybeSingle(),
      );
      return (
        r.data?.id === u && r.data?.tier?.trim().toLowerCase() === "enterprise"
      );
    },
    async list(u, input) {
      const f = validateQuery(input);
      let q = db
        .from(TABLE)
        .select("*", { count: "exact" })
        .eq("user_id", u)
        .is("archived_at", null);
      q = filter(q, f)
        .order(f.sort, {
          ascending: f.sort !== "updated_at",
          nullsFirst: false,
        })
        .order("id")
        .range(f.offset, f.offset + f.limit - 1);
      const r = checked(await q);
      return {
        contacts: r.data,
        count: r.count,
        offset: f.offset,
        limit: f.limit,
      };
    },
    async counts(u) {
      const count = async (category) => {
        let q = db
          .from(TABLE)
          .select("id", { count: "exact", head: true })
          .eq("user_id", u)
          .is("archived_at", null);
        if (category) q = q.eq("category", category);
        return checked(await q).count;
      };
      return {
        total: await count(),
        categories: Object.fromEntries(
          await Promise.all(CATEGORIES.map(async (c) => [c, await count(c)])),
        ),
      };
    },
    async get(u, id) {
      const r = checked(await owned(u).eq("id", id).maybeSingle());
      if (!r.data) fail("Contact not found.", 404, "CONTACT_NOT_FOUND");
      return r.data;
    },
    async create(u, c) {
      return checked(
        await db
          .from(TABLE)
          .insert({ ...c, user_id: u })
          .select()
          .single(),
      ).data;
    },
    async update(u, id, c, version) {
      const r = checked(
        await db
          .from(TABLE)
          .update({
            ...c,
            version: version + 1,
            updated_at: new Date().toISOString(),
          })
          .eq("id", id)
          .eq("user_id", u)
          .eq("version", version)
          .is("archived_at", null)
          .select()
          .maybeSingle(),
      );
      if (!r.data)
        fail(
          "This contact changed. Refresh and try again.",
          409,
          "CONTACT_VERSION_CONFLICT",
        );
      return r.data;
    },
    async archive(u, id, version) {
      return this.update(
        u,
        id,
        { archived_at: new Date().toISOString() },
        version,
      );
    },
    async import(u, contacts) {
      return checked(
        await db.rpc("korlix_contacts_import_v1", {
          p_user_id: u,
          p_contacts: contacts,
        }),
      ).data;
    },
    async emailContacts(u) {
      const r = checked(
        await db
          .from("korlix_agent_email_recipients")
          .select("display_name,email,consent_status")
          .eq("user_id", u)
          .eq("active", true)
          .in("consent_status", ["transactional_only", "marketing_opt_in"])
          .limit(1001),
      );
      if (r.data.length > 1000)
        fail("Export your email contacts as CSV to import them in batches.");
      return r.data.map((c) => ({
        name: c.display_name || c.email,
        email: c.email,
      }));
    },
  };
}
