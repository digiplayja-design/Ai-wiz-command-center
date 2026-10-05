import test from "node:test";
import assert from "node:assert/strict";
import { createCliSessionFetch, parseCliResponse } from "./stripe_cli_session_transport.mjs";
import { acceptanceConfig, createAcceptanceHarness } from "./stripe_sandbox_acceptance.mjs";

const context = "acct_sandboxcontext", merchant = "acct_merchantfixture", marker = "manual-cli-session:" + context;
const version = "2026-09-30.endive";
const identity = (id = context) => ({ account_id: id, mode: "test", authorized_accounts: [{ id, modes: ["test"] }] });
const base = { configPath: "/private/acceptance/config.toml", expectedContext: context,
  expectedPlatform: "acct_platformfixture", merchant, marker };
const headers = (more = {}) => ({ Authorization: "Bearer " + marker, "Stripe-Version": version, ...more });
function evidence({ method = "GET", path = "/v1/account", query = new URLSearchParams(), connected = false, status = 200, body = {}, exitCode = 0 } = {}) {
  const url = "https://api.stripe.com" + path + (query.size ? "?" + query : "");
  return { exitCode, stdout: JSON.stringify(body), stderr: ["> " + method + " " + url,
    "> Authorization: Bearer [REDACTED]", "> Stripe-Version: " + version, "> Stripe-Livemode: false",
    connected ? "> Stripe-Account: " + context + "/" + merchant : "> Stripe-Context: " + context,
    "< HTTP " + status, "< Request-Id: req_fixture", ""].join("\n") };
}

test("CLI mode cannot accept API credentials or fall through to native fetch", async () => {
  const env = { KORLIX_ACCEPTANCE_RUN: "isolated-stripe-sandbox", KORLIX_ACCEPTANCE_AUTH_MODE: "cli_session",
    KORLIX_ACCEPTANCE_CLI_CONTEXT: context, KORLIX_ACCEPTANCE_CLI_CONFIG: base.configPath,
    KORLIX_ACCEPTANCE_PLATFORM_ID: base.expectedPlatform, KORLIX_ACCEPTANCE_MERCHANT_ID: merchant,
    KORLIX_ACCEPTANCE_WEBHOOK_SECRET: "whsec_fixture" };
  assert.equal(acceptanceConfig(env).key, marker);
  for (const key of ["STRIPE_API_KEY", "KORLIX_ACCEPTANCE_STRIPE_SECRET_KEY", "KORLIX_SCHEDULING_STRIPE_SECRET_KEY"])
    assert.throws(() => acceptanceConfig({ ...env, [key]: "sk_live_shouldnotappear" }));
  await assert.rejects(createAcceptanceHarness({ environment: env, fetcher: fetch }), /guarded CLI transport/);
});

test("CLI pins context and connected account after whoami, strips ambient auth and preserves query/form values", async () => {
  const calls = [];
  let expected = evidence();
  const transport = createCliSessionFetch({ ...base,
    childEnvironment: { HOME: "/private/home", PATH: "/usr/bin", STRIPE_API_KEY: "sk_live_neverforward", STRIPE_CLI_UNIX_SOCKET: "/tmp/evil", HTTPS_PROXY: "http://evil", KORLIX_ACCEPTANCE_STRIPE_SECRET_KEY: "bad" },
    runner: async (file, args, options) => {
      calls.push({ file, args, options });
      assert.deepEqual(options.env, { HOME: "/private/home", PATH: "/usr/bin" });
      assert.equal(options.maxBuffer, 4 * 1024 * 1024); assert.equal(options.timeout, 15000);
      assert(!args.some((value) => value.includes(marker) || value === "--api-key" || value === "--live"));
      if (args.includes("whoami")) return { exitCode: 0, stdout: JSON.stringify(identity()), stderr: "" };
      // The active global context could switch here; these final custom header
      // constants override CLI-derived headers, rather than trusting that state.
      assert(args.includes("Stripe-Livemode: false"));
      assert(args.includes(args.includes("--stripe-account") ? "Stripe-Account: " + context + "/" + merchant : "Stripe-Context: " + context));
      return expected;
    } });
  const query = new URLSearchParams([["include[0]", "configuration.merchant"], ["include[1]", "defaults"], ["x", "a&b=c"]]);
  expected = evidence({ path: "/v2/core/accounts/" + merchant, query, body: { object: "v2.core.account" } });
  assert.equal((await transport("https://api.stripe.com/v2/core/accounts/" + merchant + "?" + query, { headers: headers() })).status, 200);
  const getArgs = calls.at(-1).args;
  assert(getArgs.includes("/v2/core/accounts/" + merchant + "?" + query));
  assert(!getArgs.includes("--data"), "CLI v2 GET merges query and accepts only JSON --data.");
  const v1query = new URLSearchParams([["limit", "100"]]);
  expected = evidence({ path: "/v1/webhook_endpoints", query: v1query, body: { object: "list", data: [] } });
  await transport("https://api.stripe.com/v1/webhook_endpoints?" + v1query, { headers: headers() });
  assert(calls.at(-1).args.includes("limit=100"), "CLI v1 GET needs form parameters because it replaces path queries.");
  const key = "korlix-scheduling-checkout-01234567-89ab-4cde-8fab-0123456789ab";
  const wire = new URLSearchParams({ "metadata[korlix_booking]": "local-booking", success_url: "https://korlix-acceptance.invalid/manage#test", "custom_text[submit][message]": "a&b=c" }).toString();
  expected = evidence({ method: "POST", path: "/v1/checkout/sessions", connected: true, body: { id: "cs_test_fixture" } });
  await transport("https://api.stripe.com/v1/checkout/sessions", { method: "POST", headers: headers({ "Stripe-Account": merchant, "Content-Type": "application/x-www-form-urlencoded", "Idempotency-Key": key }), body: wire });
  const postArgs = calls.at(-1).args;
  assert(postArgs.includes("--stripe-account") && postArgs.includes(merchant));
  assert(postArgs.includes("--idempotency") && postArgs.includes(key));
  assert(postArgs.includes("custom_text[submit][message]=a&b=c"));
  assert.equal(calls.filter((call) => call.args.includes("whoami")).length, 3);
});

test("context mismatch and aborted requests fail before Stripe command execution", async () => {
  let calls = 0;
  const transport = createCliSessionFetch({ ...base, runner: async () => { calls++; return { exitCode: 0, stdout: JSON.stringify(identity("acct_wrong")), stderr: "" }; } });
  await assert.rejects(transport("https://api.stripe.com/v1/account", { headers: headers() }), /could not be verified/);
  assert.equal(calls, 1);
  await assert.rejects(transport("https://api.stripe.com/v1/account", { headers: headers(), signal: AbortSignal.abort() }));
  assert.equal(calls, 1);
  await assert.rejects(transport("https://api.stripe.com/v1/customers", { headers: headers() }));
  assert.equal(calls, 1);
});

test("CLI exit zero does not hide HTTP errors; missing status, wrong pin and truncated output fail closed", async () => {
  const expected = { method: "GET", path: "/v1/account", query: new URLSearchParams(), version, context, merchant: null };
  const result = evidence({ status: 403, body: { error: { code: "account_not_yet_compatible_with_v2", message: "sensitive raw message" } } });
  const response = parseCliResponse(result, expected);
  assert.equal(response.status, 403); assert.equal(response.headers.get("request-id"), "req_fixture");
  const parsed = await response.json(); assert.equal(parsed.error.code, "account_not_yet_compatible_with_v2");
  assert(!JSON.stringify(parsed).includes("sensitive"));
  assert.throws(() => parseCliResponse({ ...result, stdout: "non-JSON raw error" }, expected));
  const good = evidence({ body: { object: "account" } });
  for (const bad of [{ ...good, exitCode: 1 }, { ...good, failed: true }, { ...good, stdout: "not json" },
    { ...good, stderr: good.stderr.replace("< HTTP 200", "status unknown") },
    { ...good, stderr: good.stderr.replace("> Stripe-Context: " + context, "> Stripe-Context: acct_wrong") },
    { ...good, stderr: good.stderr.replace("> Stripe-Livemode: false", "> Stripe-Livemode: true") },
    { ...good, stderr: good.stderr.replace("< Request-Id: req_fixture", "") }]) assert.throws(() => parseCliResponse(bad, expected));
});
