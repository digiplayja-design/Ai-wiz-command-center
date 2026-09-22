import { fail } from "./core.mjs";
export function createWorkforceStore(db) {
  return {
    async command(actor, email, action, org, payload = {}) {
      const { data, error } = await db.rpc("korlix_workforce_command_v1", {
        p_actor: actor,
        p_email: email,
        p_action: action,
        p_org: org,
        p: payload,
      });
      if (error) {
        const match = /WF(403|404|409)?: (.+)/.exec(error.message || "");
        if (match)
          fail(
            match[2],
            Number(match[1] || 400),
            "WORKFORCE_" + (match[1] || "INVALID"),
          );
        if (["23514", "22007", "22008", "22P02"].includes(error.code))
          fail(
            "Check the dates, duration and field values before saving.",
            400,
            "WORKFORCE_INVALID",
          );
        if (error.code === "23505")
          fail(
            "This action conflicts with another record. Refresh before trying again.",
            409,
            "WORKFORCE_CONFLICT",
          );
        fail(
          "Workforce storage is temporarily unavailable.",
          503,
          "WORKFORCE_STORAGE_UNAVAILABLE",
        );
      }
      return data;
    },
    async upload(path, bytes) {
      const staged = await db
        .from("korlix_workforce_photo_uploads")
        .insert({ path });
      if (staged.error)
        fail(
          "The attendance photo could not be saved. Please retry.",
          503,
          "WORKFORCE_PHOTO_FAILED",
        );
      const { error } = await db.storage
        .from("korlix-workforce-evidence")
        .upload(path, bytes, { contentType: "image/jpeg", upsert: false });
      if (error)
        fail(
          "The attendance photo could not be saved. Please retry.",
          503,
          "WORKFORCE_PHOTO_FAILED",
        );
    },
    async photo(path) {
      const { data, error } = await db.storage
        .from("korlix-workforce-evidence")
        .download(path);
      if (error)
        fail(
          "This attendance photo is unavailable.",
          404,
          "WORKFORCE_PHOTO_UNAVAILABLE",
        );
      return Buffer.from(await data.arrayBuffer());
    },
    async remove(path) {
      const { error } = await db.storage
        .from("korlix-workforce-evidence")
        .remove([path]);
      if (error) throw error;
      await db.from("korlix_workforce_photo_uploads").delete().eq("path", path);
    },
    async purge() {
      // A lost response can leave an upload without a punch. Resolve after a 24h grace
      // period; never delete evidence referenced by a committed attendance event.
      const staged = await db
        .from("korlix_workforce_photo_uploads")
        .select("path")
        .lt("created_at", new Date(Date.now() - 86400000).toISOString())
        .limit(100);
      if (!staged.error && staged.data?.length) {
        const paths = staged.data.map((x) => x.path);
        const referenced = await db
          .from("korlix_workforce_events")
          .select("photo_path")
          .in("photo_path", paths);
        if (!referenced.error) {
          const keep = new Set(
            (referenced.data || []).map((x) => x.photo_path),
          );
          for (const path of paths) {
            if (!keep.has(path)) {
              const deleted = await db.storage
                .from("korlix-workforce-evidence")
                .remove([path]);
              if (deleted.error) continue;
            }
            await db
              .from("korlix_workforce_photo_uploads")
              .delete()
              .eq("path", path);
          }
        }
      }
      const { data, error } = await db
        .from("korlix_workforce_events")
        .select("id,photo_path")
        .lt("photo_expires_at", new Date().toISOString())
        .or("photo_path.not.is.null,location.not.is.null")
        .limit(100);
      if (error) return;
      for (const row of data || []) {
        if (row.photo_path) {
          const r = await db.storage
            .from("korlix-workforce-evidence")
            .remove([row.photo_path]);
          if (r.error) continue;
        }
        await db
          .from("korlix_workforce_events")
          .update({ photo_path: null, location: null })
          .eq("id", row.id);
      }
    },
  };
}
