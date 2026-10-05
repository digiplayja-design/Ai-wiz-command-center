import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from "node:crypto";
import { fail } from "./core.mjs";

export const challenge = (value) =>
  createHash("sha256").update(value).digest("base64url");
export function providerCipher(environment) {
  const key = Buffer.from(
    environment.KORLIX_SCHEDULING_TOKEN_KEY || "",
    "base64",
  );
  return {
    ready: key.length === 32,
    seal(value, binding) {
      if (key.length !== 32)
        fail("Secure connection storage is not configured.", 503);
      const iv = randomBytes(12),
        cipher = createCipheriv("aes-256-gcm", key, iv);
      cipher.setAAD(Buffer.from("korlix-scheduling-provider:" + binding));
      return [
        iv,
        Buffer.concat([
          cipher.update(JSON.stringify(value), "utf8"),
          cipher.final(),
        ]),
        cipher.getAuthTag(),
      ]
        .map((x) => x.toString("base64url"))
        .join(".");
    },
    open(value, binding) {
      try {
        const [iv, data, tag] = value
            .split(".")
            .map((x) => Buffer.from(x, "base64url")),
          decipher = createDecipheriv("aes-256-gcm", key, iv);
        decipher.setAAD(Buffer.from("korlix-scheduling-provider:" + binding));
        decipher.setAuthTag(tag);
        return JSON.parse(
          Buffer.concat([decipher.update(data), decipher.final()]).toString(
            "utf8",
          ),
        );
      } catch {
        fail("Reconnect this account to restore secure access.", 409);
      }
    },
  };
}
export class ProviderError extends Error {
  constructor(message, status = 503, code = "provider_unavailable") {
    super(message);
    this.status = status;
    this.code = code;
  }
}
export async function providerRequest(
  fetcher,
  url,
  options = {},
  allowedStatuses = [],
) {
  let response, data;
  try {
    response = await fetcher(url, {
      ...options,
      redirect: "error",
      signal: AbortSignal.timeout(15000),
    });
    const reader = response.body?.getReader();
    if (!reader) throw Error();
    let bytes = 0,
      chunks = [];
    try {
      for (;;) {
        const r = await reader.read();
        if (r.done) break;
        bytes += r.value.byteLength;
        if (bytes > 4 * 1024 * 1024) throw Error();
        chunks.push(Buffer.from(r.value));
      }
    } finally {
      await reader.cancel().catch(() => {});
    }
    const raw = Buffer.concat(chunks).toString("utf8");
    data = raw ? JSON.parse(raw) : {};
  } catch {
    throw new ProviderError(
      "The provider response could not be confirmed. Try again shortly.",
    );
  }
  if (!response.ok && !allowedStatuses.includes(response.status)) {
    const code = data.error?.code || data.error;
    throw new ProviderError(
      response.status === 401 || code === "invalid_grant"
        ? "Reconnect this account to restore access."
        : response.status === 429
          ? "The provider is limiting requests. Try again shortly."
          : "The provider could not complete this request.",
      response.status === 401 ? 409 : response.status === 429 ? 429 : 503,
      code === "invalid_grant" || response.status === 401
        ? "reconnect_required"
        : "provider_unavailable",
    );
  }
  return { status: response.status, data };
}
export function providerSettings(environment, publicRoot) {
  const cipher = providerCipher(environment),
    origin = new URL(publicRoot).origin;
  const providers = {};
  for (const name of ["google", "microsoft", "stripe"]) {
    const prefix = "KORLIX_SCHEDULING_" + name.toUpperCase(),
      id = environment[prefix + "_CLIENT_ID"] || "",
      secret = environment[prefix + "_CLIENT_SECRET"] || "";
    const callback = origin + "/api/scheduling/connect/" + name + "/callback";
    const stripeKey = environment.KORLIX_SCHEDULING_STRIPE_SECRET_KEY || "";
    const ready =
      cipher.ready &&
      !!id &&
      (name === "stripe" ? !!stripeKey : !!secret) &&
      origin.startsWith("https://");
    providers[name] = {
      name,
      id,
      secret,
      callback,
      ready,
      // Saving credentials must not enable new customer payments.
      enabled:
        name === "stripe" &&
        environment.KORLIX_SCHEDULING_STRIPE_ENABLED === "true",
      tenant: "common",
      key: stripeKey,
      webhook: environment.KORLIX_SCHEDULING_STRIPE_WEBHOOK_SECRET || "",
      version:
        environment.KORLIX_SCHEDULING_STRIPE_API_VERSION || "2026-09-30.endive",
    };
    providers[name].fingerprint = createHash("sha256")
      .update(
        JSON.stringify([
          name,
          id,
          secret,
          callback,
          name === "stripe" ? stripeKey : "",
        ]),
      )
      .digest("hex");
  }
  return { cipher, providers };
}
