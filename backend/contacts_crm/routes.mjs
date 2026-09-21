import {
  normalizeContact,
  fail,
  validId,
  CATEGORIES,
  SOURCES,
  ContactError,
} from "./core.mjs";
import { previewImport } from "./imports.mjs";
import { createContactStore } from "./store.mjs";
import {
  createKorlixAgentEmailDraftService,
  createKorlixAgentEmailSupabaseStore,
} from "../korlix_agent_email_routes.mjs";
import { korlixAgentEmailNovaBinding } from "../korlix_agent_email.mjs";
export function registerContactsCrm(
  app,
  {
    database,
    requireUser,
    loadAgentProfile,
    environment = process.env,
    store = null,
    emailService = null,
  } = {},
) {
  const persistence = store || (database ? createContactStore(database) : null);
  const email =
    emailService ||
    (database
      ? createKorlixAgentEmailDraftService({
          environment,
          store: createKorlixAgentEmailSupabaseStore(database),
          loadAgentProfile,
          providerSendPathImplemented: true,
          autopilotExecutionImplemented: true,
          webhookEventsImplemented: true,
        })
      : null);
  const binding = korlixAgentEmailNovaBinding(environment);
  const route = (fn) => async (req, res) => {
    res.set("Cache-Control", "no-store");
    try {
      let user;
      try {
        user = await requireUser(req);
      } catch {
        fail("Sign in to use Contacts.", 401, "CONTACT_AUTH_REQUIRED");
      }
      if (!user?.id)
        fail("Sign in to use Contacts.", 401, "CONTACT_AUTH_REQUIRED");
      if (!persistence)
        fail(
          "Contacts storage is not configured.",
          503,
          "CONTACT_STORAGE_UNAVAILABLE",
        );
      if (!(await persistence.enterprise(user.id)))
        fail(
          "Contacts CRM is available with Enterprise.",
          403,
          "CONTACT_ENTERPRISE_REQUIRED",
        );
      return await fn(req, res, user.id);
    } catch (e) {
      const known =
        e instanceof ContactError || e.code?.startsWith("agent_email_");
      res
        .status(known ? e.status || e.statusCode || 400 : 503)
        .json({
          error: known
            ? e.message
            : "Contacts is temporarily unavailable. Please try again.",
          code: known ? e.code : "CONTACT_SERVICE_UNAVAILABLE",
        });
    }
  };
  const base = "/api/contacts";
  app.get(
    base + "/capabilities",
    route(async (_req, res, u) =>
      res.json({
        enterprise: true,
        categories: CATEGORIES,
        sources: SOURCES,
        emailAgentId:
          binding.configured && binding.ownerUid === u ? binding.agentId : null,
        outboundCallingEnabled: false,
        imports: ["csv", "xlsx", "vcf", "json", "phone_picker"],
      }),
    ),
  );
  app.get(
    base + "/counts",
    route(async (_req, res, u) => res.json(await persistence.counts(u))),
  );
  app.get(
    base,
    route(async (req, res, u) =>
      res.json(await persistence.list(u, req.query)),
    ),
  );
  app.post(
    base + "/imports/preview",
    route(async (req, res) => res.json(await previewImport(req.body || {}))),
  );
  app.post(
    base + "/imports/email-preview",
    route(async (_req, res, u) =>
      res.json(
        await previewImport({
          source: "email",
          contacts: await persistence.emailContacts(u),
        }),
      ),
    ),
  );
  app.post(
    base + "/imports",
    route(async (req, res, u) => {
      if (req.body?.confirmed !== true)
        fail("Review and confirm the import first.");
      const rows = req.body.contacts;
      if (!Array.isArray(rows) || !rows.length || rows.length > 1000)
        fail("Choose between 1 and 1,000 contacts.");
      const contacts = rows.map((c) => normalizeContact(c, { imported: true }));
      res.json(await persistence.import(u, contacts));
    }),
  );
  app.post(
    base,
    route(async (req, res, u) =>
      res
        .status(201)
        .json({
          contact: await persistence.create(u, normalizeContact(req.body)),
        }),
    ),
  );
  app.get(
    base + "/:id",
    route(async (req, res, u) =>
      res.json({ contact: await persistence.get(u, validId(req.params.id)) }),
    ),
  );
  app.put(
    base + "/:id",
    route(async (req, res, u) => {
      const version = req.body?.version;
      if (!Number.isInteger(version) || version < 1)
        fail("Refresh this contact before saving.");
      res.json({
        contact: await persistence.update(
          u,
          validId(req.params.id),
          normalizeContact(req.body),
          version,
        ),
      });
    }),
  );
  app.delete(
    base + "/:id",
    route(async (req, res, u) => {
      if (req.body?.confirmed !== true) fail("Confirm archiving this contact.");
      if (!Number.isInteger(req.body.version) || req.body.version < 1)
        fail("Refresh this contact first.");
      await persistence.archive(u, validId(req.params.id), req.body.version);
      res.json({ archived: true });
    }),
  );
  app.post(
    base + "/:id/email-link",
    route(async (req, res, u) => {
      if (req.body?.confirmed !== true)
        fail("Confirm adding this contact to Nova Email.");
      const c = await persistence.get(u, validId(req.params.id));
      if (
        c.do_not_contact ||
        !["transactional", "marketing"].includes(c.email_permission) ||
        !c.email
      )
        fail(
          "Record email permission on this contact before linking it to Nova.",
          409,
          "CONTACT_EMAIL_PERMISSION_REQUIRED",
        );
      if (!email) fail("Nova Email is not configured.", 503);
      const result = await email.saveRecipient({
        userId: u,
        agentId: req.body.agentId,
        body: {
          confirmed: true,
          email: c.email,
          displayName: c.name,
          approvalSource: "user_confirmed",
          consentScope: c.email_permission,
          consentAt: c.consent_at,
          sourceReference: "crm:" + c.id,
        },
      });
      res.json({
        ...result,
        sent: false,
        message:
          "Contact linked to Nova Email. Choose a rule or draft in Email Center.",
      });
    }),
  );
  app.get(
    base + "/:id/call-brief",
    route(async (req, res, u) => {
      const c = await persistence.get(u, validId(req.params.id));
      if (
        c.do_not_contact ||
        c.call_permission !== "allowed" ||
        !/^\+[1-9]\d{6,14}$/.test((c.phone || "").replace(/[ ()-]/g, ""))
      )
        fail(
          "Record call permission and a phone number with country code first.",
          409,
          "CONTACT_CALL_PERMISSION_REQUIRED",
        );
      res.json({
        contactId: c.id,
        name: c.name,
        phone: c.phone,
        brief: c.call_brief,
        outboundCallingEnabled: false,
        called: false,
        message:
          "Call brief ready. Outbound Nova calling is not enabled on this server.",
      });
    }),
  );
  return { route };
}
