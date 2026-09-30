import { fail, object } from "./core.mjs";
import { normalizeSchedulingPlan, schedulingContext } from "./ai.mjs";

// Voice reads use the same authenticated owner boundary as the scheduling UI.
// Changes still go through immutable /ai/propose and explicit /ai/:id/apply.
export function schedulingVoice({
  app,
  base,
  route,
  call,
  ownerCall,
  connected,
  now = Date.now,
}) {
  app.get(
    base + "/voice/context",
    route(async (_q, r, u) => {
      const dashboard = await ownerCall(u.id, "dashboard");
      r.json(schedulingContext(dashboard, now));
    }, true),
  );
  app.post(
    base + "/voice/slots",
    route(async (q, r, u) => {
      object(q.body);
      if (Object.keys(q.body).some((k) => !["event_id", "date"].includes(k)))
        fail("Unsupported scheduling field.");
      const dashboard = await ownerCall(u.id, "dashboard");
      if (!dashboard.profile)
        fail(
          "Save your host name and availability in KORLIX 2MEETU first.",
          409,
        );
      r.json(
        await normalizeSchedulingPlan(
          { action: "slots", message: "Available times", ...q.body },
          { dashboard, actor: u.id, connected, call, now },
        ),
      );
    }, true),
  );
}
