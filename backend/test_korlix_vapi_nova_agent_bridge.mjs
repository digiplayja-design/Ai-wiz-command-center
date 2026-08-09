import assert from "node:assert/strict";
import test from "node:test";

import {
  KORLIX_VAPI_NOVA_AGENT_BRIDGE_POLICY,
  createKorlixVapiNovaAgentBridgeFetch,
} from "./korlix_vapi_nova_agent_bridge.mjs";


function modelRequest(
  instructions = "Existing public telephone instructions.",
) {
  return {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "test-model",
      instructions,
      input: [
        {
          role: "user",
          content: "Tell me about stock 5S-U202.",
        },
      ],
      store: false,
    }),
  };
}


test(
  "disabled bridge preserves the original model request",
  async () => {
    let loaderCalls = 0;
    let capturedBody = "";

    const bridge =
      createKorlixVapiNovaAgentBridgeFetch({
        environment: {
          KORLIX_VAPI_NOVA_AGENT_BRAIN_ENABLED:
            "false",
        },

        loadAgentRuntime: async () => {
          loaderCalls += 1;

          return {
            instructions:
              "This should not be loaded.",
          };
        },

        fetchImpl: async (
          _url,
          options,
        ) => {
          capturedBody = options.body;

          return {
            ok: true,
          };
        },
      });

    const original =
      modelRequest();

    await bridge(
      "https://model.invalid/responses",
      original,
    );

    assert.equal(
      loaderCalls,
      0,
    );

    assert.equal(
      capturedBody,
      original.body,
    );
  },
);


test(
  "enabled bridge injects the approved Agent Hub runtime and final telephone policy",
  async () => {
    const ownerUid =
      "11111111-1111-4111-8111-111111111111";

    const agentId =
      "custom_nova_test_agent";

    let loaderArguments = null;
    let capturedPayload = null;

    const bridge =
      createKorlixVapiNovaAgentBridgeFetch({
        environment: {
          KORLIX_VAPI_NOVA_AGENT_BRAIN_ENABLED:
            "true",

          KORLIX_VAPI_NOVA_AGENT_BRAIN_REQUIRED:
            "true",

          KORLIX_VAPI_NOVA_OWNER_UID:
            ownerUid,

          KORLIX_VAPI_NOVA_AGENT_ID:
            agentId,
        },

        loadAgentRuntime:
          async (argumentsValue) => {
            loaderArguments =
              argumentsValue;

            return {
              instructions: [
                "You are NOVA, the 5 Star Digital Sales and Negotiation Concierge.",
                "Stock 5S-U202 is a fictional demonstration vehicle.",
                "The manager floor is protected and must never be disclosed.",
              ].join("\n"),
            };
          },

        fetchImpl: async (
          _url,
          options,
        ) => {
          capturedPayload =
            JSON.parse(
              options.body,
            );

          return {
            ok: true,
          };
        },
      });

    await bridge(
      "https://model.invalid/responses",
      modelRequest(),
    );

    assert.deepEqual(
      loaderArguments,
      {
        ownerUid,
        agentId,
      },
    );

    assert.match(
      capturedPayload.instructions,
      /Existing public telephone instructions/,
    );

    assert.match(
      capturedPayload.instructions,
      /5 Star Digital Sales and Negotiation Concierge/,
    );

    assert.match(
      capturedPayload.instructions,
      /5S-U202/,
    );

    assert.match(
      capturedPayload.instructions,
      /manager floor is protected/i,
    );

    assert.match(
      capturedPayload.instructions,
      /must never be revealed/i,
    );

    assert.match(
      capturedPayload.instructions,
      /Do not transfer calls/i,
    );

    assert.equal(
      capturedPayload.instructions.includes(
        ownerUid,
      ),
      false,
    );

    assert.equal(
      capturedPayload.instructions.includes(
        agentId,
      ),
      false,
    );

    assert.equal(
      capturedPayload.store,
      false,
    );
  },
);


test(
  "required bridge fails closed when its server-controlled identity is missing",
  async () => {
    let fetchCalls = 0;

    const bridge =
      createKorlixVapiNovaAgentBridgeFetch({
        environment: {
          KORLIX_VAPI_NOVA_AGENT_BRAIN_ENABLED:
            "true",

          KORLIX_VAPI_NOVA_AGENT_BRAIN_REQUIRED:
            "true",
        },

        loadAgentRuntime:
          async () => ({
            instructions:
              "Unexpected.",
          }),

        fetchImpl:
          async () => {
            fetchCalls += 1;

            return {
              ok: true,
            };
          },
      });

    await assert.rejects(
      () => bridge(
        "https://model.invalid/responses",
        modelRequest(),
      ),
      {
        code:
          "vapi_nova_agent_brain_not_configured",
      },
    );

    assert.equal(
      fetchCalls,
      0,
    );
  },
);


test(
  "required bridge fails closed when Agent Hub loading fails",
  async () => {
    let fetchCalls = 0;

    const bridge =
      createKorlixVapiNovaAgentBridgeFetch({
        environment: {
          KORLIX_VAPI_NOVA_AGENT_BRAIN_ENABLED:
            "true",

          KORLIX_VAPI_NOVA_AGENT_BRAIN_REQUIRED:
            "true",

          KORLIX_VAPI_NOVA_OWNER_UID:
            "11111111-1111-4111-8111-111111111111",

          KORLIX_VAPI_NOVA_AGENT_ID:
            "custom_nova_test_agent",
        },

        loadAgentRuntime:
          async () => {
            throw new Error(
              "Sensitive database error.",
            );
          },

        fetchImpl:
          async () => {
            fetchCalls += 1;

            return {
              ok: true,
            };
          },
      });

    await assert.rejects(
      () => bridge(
        "https://model.invalid/responses",
        modelRequest(),
      ),
      {
        code:
          "vapi_nova_agent_brain_unavailable",
      },
    );

    assert.equal(
      fetchCalls,
      0,
    );
  },
);


test(
  "optional bridge may preserve the generic responder during a controlled fallback",
  async () => {
    let fetchCalls = 0;
    let capturedBody = "";

    const original =
      modelRequest();

    const bridge =
      createKorlixVapiNovaAgentBridgeFetch({
        environment: {
          KORLIX_VAPI_NOVA_AGENT_BRAIN_ENABLED:
            "true",

          KORLIX_VAPI_NOVA_AGENT_BRAIN_REQUIRED:
            "false",

          KORLIX_VAPI_NOVA_OWNER_UID:
            "11111111-1111-4111-8111-111111111111",

          KORLIX_VAPI_NOVA_AGENT_ID:
            "custom_nova_test_agent",
        },

        loadAgentRuntime:
          async () => {
            throw new Error(
              "Controlled test failure.",
            );
          },

        fetchImpl:
          async (
            _url,
            options,
          ) => {
            fetchCalls += 1;
            capturedBody =
              options.body;

            return {
              ok: true,
            };
          },
      });

    await bridge(
      "https://model.invalid/responses",
      original,
    );

    assert.equal(
      fetchCalls,
      1,
    );

    assert.equal(
      capturedBody,
      original.body,
    );
  },
);


test(
  "telephone policy explicitly protects internal dealership authority",
  () => {
    assert.match(
      KORLIX_VAPI_NOVA_AGENT_BRIDGE_POLICY,
      /manager floors/i,
    );

    assert.match(
      KORLIX_VAPI_NOVA_AGENT_BRIDGE_POLICY,
      /must never be revealed/i,
    );

    assert.match(
      KORLIX_VAPI_NOVA_AGENT_BRIDGE_POLICY,
      /Do not access Brain Vault/i,
    );

    assert.match(
      KORLIX_VAPI_NOVA_AGENT_BRIDGE_POLICY,
      /Do not place outbound calls/i,
    );
  },
);
