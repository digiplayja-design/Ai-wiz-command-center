import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";

import {
  KORLIX_AI_GAS_PACKAGES,
  KorlixAiGasError,
  createKorlixAiGasService,
  hashKorlixAiGasSensitiveValue,
  normalizeKorlixAiGasSku,
  sanitizeKorlixAiGasMetadata,
} from "./korlix_ai_gas.mjs";

const USER_A =
  "11111111-1111-4111-8111-111111111111";

const USER_B =
  "22222222-2222-4222-8222-222222222222";

const FIXED_TIME =
  "2026-08-07T19:45:00.000Z";

function catalogRows() {
  return [
    {
      sku: "korlix_ai_gas_1h",
      display_name: "1 Hour AI GAS",
      seconds: 3600,
      base_usd_cents: 3000,
      apple_product_id:
        "com.korlix.ai_gas.1h",
      google_product_id:
        "korlix_ai_gas_1h_android",
      web_price_id:
        "price_korlix_ai_gas_1h",
    },
    {
      sku: "korlix_ai_gas_2h",
      display_name: "2 Hours AI GAS",
      seconds: 7200,
      base_usd_cents: 5500,
      apple_product_id:
        "com.korlix.ai_gas.2h",
      google_product_id:
        "korlix_ai_gas_2h_android",
      web_price_id:
        "price_korlix_ai_gas_2h",
    },
    {
      sku: "korlix_ai_gas_3h",
      display_name: "3 Hours AI GAS",
      seconds: 10800,
      base_usd_cents: 8000,
      apple_product_id:
        "com.korlix.ai_gas.3h",
      google_product_id:
        "korlix_ai_gas_3h_android",
      web_price_id:
        "price_korlix_ai_gas_3h",
    },
    {
      sku: "korlix_ai_gas_5h",
      display_name: "5 Hours AI GAS",
      seconds: 18000,
      base_usd_cents: 12499,
      apple_product_id:
        "com.korlix.ai_gas.5h",
      google_product_id:
        "korlix_ai_gas_5h_android",
      web_price_id:
        "price_korlix_ai_gas_5h",
    },
  ];
}

function createRpcHarness({
  catalog = catalogRows(),
  balanceSeconds = 9000,
  errors = {},
} = {}) {
  const calls = [];

  const packageBySku = new Map(
    KORLIX_AI_GAS_PACKAGES.map(
      (item) => [item.sku, item]
    )
  );

  const supabaseAdmin = {
    async rpc(name, args = {}) {
      calls.push({
        name,
        args: structuredClone(args),
      });

      if (errors[name]) {
        return {
          data: null,
          error: errors[name],
        };
      }

      switch (name) {
        case "korlix_ai_gas_get_catalog":
          return {
            data: structuredClone(catalog),
            error: null,
          };

        case "korlix_ai_gas_get_balance":
          return {
            data: balanceSeconds,
            error: null,
          };

        case "korlix_ai_gas_grant_verified_purchase": {
          const product =
            packageBySku.get(args.p_sku);

          return {
            data: {
              purchaseId:
                "33333333-3333-4333-8333-333333333333",
              sku: args.p_sku,
              seconds: product?.seconds ?? 0,
              balanceSeconds:
                balanceSeconds +
                (product?.seconds ?? 0),
              granted: true,
              idempotent: false,
            },
            error: null,
          };
        }

        case "korlix_ai_gas_reverse_verified_purchase":
          return {
            data: {
              purchaseId:
                "33333333-3333-4333-8333-333333333333",
              status: args.p_reason,
              reversedSeconds: 3600,
              balanceSeconds:
                Math.max(
                  balanceSeconds - 3600,
                  0
                ),
            },
            error: null,
          };

        case "korlix_ai_gas_consume":
          return {
            data: {
              consumedSeconds:
                args.p_seconds,
              balanceSeconds:
                balanceSeconds -
                args.p_seconds,
              idempotent: false,
            },
            error: null,
          };

        default:
          return {
            data: null,
            error: {
              code: "undefined_rpc",
            },
          };
      }
    },
  };

  return {
    calls,
    supabaseAdmin,
  };
}

function serviceFor(
  harness,
  {
    appleAdapter = null,
    googleAdapter = null,
  } = {}
) {
  return createKorlixAiGasService({
    supabaseAdmin:
      harness.supabaseAdmin,

    appleAdapter,
    googleAdapter,

    logger: {
      error() {},
    },

    now: () => new Date(FIXED_TIME),
  });
}

function findCall(harness, name) {
  return harness.calls.find(
    (call) => call.name === name
  );
}

async function rejectsCode(
  promise,
  expectedCode
) {
  await assert.rejects(
    promise,
    (error) => {
      assert.equal(
        error instanceof KorlixAiGasError,
        true
      );

      assert.equal(
        error.code,
        expectedCode
      );

      return true;
    }
  );
}

test(
  "catalog constants contain four exact packages",
  () => {
    assert.deepEqual(
      KORLIX_AI_GAS_PACKAGES.map(
        (item) => [
          item.sku,
          item.displayName,
          item.seconds,
          item.baseUsdCents,
        ]
      ),
      [
        [
          "korlix_ai_gas_1h",
          "1 Hour AI GAS",
          3600,
          3000,
        ],
        [
          "korlix_ai_gas_2h",
          "2 Hours AI GAS",
          7200,
          5500,
        ],
        [
          "korlix_ai_gas_3h",
          "3 Hours AI GAS",
          10800,
          8000,
        ],
        [
          "korlix_ai_gas_5h",
          "5 Hours AI GAS",
          18000,
          12499,
        ],
      ]
    );
  }
);

test(
  "SKU normalization accepts approved SKUs and rejects unknown SKUs",
  () => {
    assert.equal(
      normalizeKorlixAiGasSku(
        " KORLIX_AI_GAS_2H "
      ),
      "korlix_ai_gas_2h"
    );

    assert.throws(
      () =>
        normalizeKorlixAiGasSku(
          "client_defined_pack"
        ),
      (error) => {
        assert.equal(
          error.code,
          "ai_gas_product_invalid"
        );

        return true;
      }
    );
  }
);

test(
  "sensitive values are hashed and secret metadata keys are removed",
  () => {
    const raw =
      "apple-server-verification-secret";

    const expected =
      crypto
        .createHash("sha256")
        .update(raw)
        .digest("hex");

    assert.equal(
      hashKorlixAiGasSensitiveValue(raw),
      expected
    );

    assert.notEqual(
      hashKorlixAiGasSensitiveValue(raw),
      raw
    );

    const safe =
      sanitizeKorlixAiGasMetadata({
        receipt: "remove",
        authorization: "remove",
        safeLabel: "keep",
        nested: {
          purchaseToken: "remove",
          campaign: "keep",
        },
        list: [
          {
            signedPayload: "remove",
            event: "keep",
          },
        ],
      });

    assert.deepEqual(
      safe,
      {
        safeLabel: "keep",
        nested: {
          campaign: "keep",
        },
        list: [
          {
            event: "keep",
          },
        ],
      }
    );
  }
);

test(
  "service refuses to start without the server-owned database RPC client",
  () => {
    assert.throws(
      () =>
        createKorlixAiGasService({}),
      (error) => {
        assert.equal(
          error.code,
          "ai_gas_database_unavailable"
        );

        assert.equal(
          error.statusCode,
          503
        );

        return true;
      }
    );
  }
);

test(
  "catalog loads all approved provider mappings",
  async () => {
    const harness =
      createRpcHarness();

    const service =
      serviceFor(harness);

    const catalog =
      await service.getCatalog();

    assert.equal(
      catalog.length,
      4
    );

    assert.equal(
      catalog[0].appleProductId,
      "com.korlix.ai_gas.1h"
    );

    assert.equal(
      catalog[2].googleProductId,
      "korlix_ai_gas_3h_android"
    );

    assert.equal(
      catalog[3].webPriceId,
      "price_korlix_ai_gas_5h"
    );

    assert.equal(
      findCall(
        harness,
        "korlix_ai_gas_get_catalog"
      ) !== undefined,
      true
    );
  }
);

test(
  "tampered catalog prices or seconds fail closed",
  async () => {
    const tampered =
      catalogRows();

    tampered[1].seconds = 999999;

    const harness =
      createRpcHarness({
        catalog: tampered,
      });

    const service =
      serviceFor(harness);

    await rejectsCode(
      service.getCatalog(),
      "ai_gas_catalog_mismatch"
    );
  }
);

test(
  "missing Apple and Google provider adapters fail closed",
  async () => {
    const harness =
      createRpcHarness();

    const service =
      serviceFor(harness);

    await rejectsCode(
      service.verifyApplePurchase({
        user: {
          id: USER_A,
        },
        purchase: {
          verificationData:
            "apple-secret",
        },
      }),
      "ai_gas_apple_unavailable"
    );

    await rejectsCode(
      service.verifyGooglePurchase({
        user: {
          id: USER_A,
        },
        purchase: {
          purchaseToken:
            "google-secret",
        },
      }),
      "ai_gas_google_unavailable"
    );
  }
);

test(
  "verified Apple purchase uses server catalog and ignores client-authored seconds and prices",
  async () => {
    const harness =
      createRpcHarness({
        balanceSeconds: 100,
      });

    const adapterCalls = [];

    const appleAdapter = {
      async verifyPurchase(input) {
        adapterCalls.push(
          structuredClone(input)
        );

        return {
          verified: true,
          status: "purchased",
          userId: USER_A,
          productId:
            "com.korlix.ai_gas.2h",
          transactionId:
            "apple-transaction-1",
          originalTransactionId:
            "apple-original-1",
          purchasedAt:
            FIXED_TIME,
          metadata: {
            receipt:
              "must-not-reach-rpc",
            campaign:
              "summer",
          },
        };
      },
    };

    const service =
      serviceFor(
        harness,
        {
          appleAdapter,
        }
      );

    const result =
      await service.verifyApplePurchase({
        user: {
          id: USER_A,
        },
        purchase: {
          productId:
            "com.korlix.ai_gas.2h",
          purchaseId:
            "client-purchase-1",
          verificationData:
            "apple-secret-value",
          source:
            "app_store",
          restored: false,

          seconds: 999999,
          baseUsdCents: 1,
        },
      });

    assert.equal(
      result.verified,
      true
    );

    assert.equal(
      result.product.sku,
      "korlix_ai_gas_2h"
    );

    assert.equal(
      result.product.seconds,
      7200
    );

    assert.equal(
      result.product.baseUsdCents,
      5500
    );

    assert.equal(
      Object.hasOwn(
        adapterCalls[0],
        "seconds"
      ),
      false
    );

    assert.equal(
      Object.hasOwn(
        adapterCalls[0],
        "baseUsdCents"
      ),
      false
    );

    const grant =
      findCall(
        harness,
        "korlix_ai_gas_grant_verified_purchase"
      );

    assert.ok(grant);

    assert.equal(
      grant.args.p_user_id,
      USER_A
    );

    assert.equal(
      grant.args.p_provider,
      "apple"
    );

    assert.equal(
      grant.args.p_sku,
      "korlix_ai_gas_2h"
    );

    assert.equal(
      Object.hasOwn(
        grant.args,
        "p_seconds"
      ),
      false
    );

    assert.equal(
      Object.hasOwn(
        grant.args,
        "p_base_usd_cents"
      ),
      false
    );

    assert.equal(
      grant.args
        .p_receipt_or_token_hash,
      hashKorlixAiGasSensitiveValue(
        "apple-secret-value"
      )
    );

    assert.equal(
      grant.args.p_metadata.campaign,
      "summer"
    );

    assert.equal(
      Object.hasOwn(
        grant.args.p_metadata,
        "receipt"
      ),
      false
    );
  }
);

test(
  "verified Google purchase uses the approved Google product mapping",
  async () => {
    const harness =
      createRpcHarness();

    const adapterCalls = [];

    const googleAdapter = {
      async verifyPurchase(input) {
        adapterCalls.push(
          structuredClone(input)
        );

        return {
          verified: true,
          status: "paid",
          userId: USER_A,
          productId:
            "korlix_ai_gas_3h_android",
          transactionId:
            "GPA.1234-5678-9012-34567",
          originalTransactionId:
            "GPA.1234-5678-9012-34567",
          purchasedAt:
            FIXED_TIME,
          metadata: {
            orderRegion: "US",
          },
        };
      },
    };

    const service =
      serviceFor(
        harness,
        {
          googleAdapter,
        }
      );

    const result =
      await service.verifyGooglePurchase({
        user: {
          id: USER_A,
        },
        purchase: {
          productId:
            "korlix_ai_gas_3h_android",
          purchaseToken:
            "google-purchase-secret",
          orderId:
            "GPA.1234-5678-9012-34567",
          packageName:
            "com.korlix.app",

          seconds: 1,
          price: 1,
        },
      });

    assert.equal(
      result.product.sku,
      "korlix_ai_gas_3h"
    );

    assert.equal(
      adapterCalls[0].purchaseToken,
      "google-purchase-secret"
    );

    assert.equal(
      Object.hasOwn(
        adapterCalls[0],
        "seconds"
      ),
      false
    );

    assert.equal(
      Object.hasOwn(
        adapterCalls[0],
        "price"
      ),
      false
    );

    const grant =
      findCall(
        harness,
        "korlix_ai_gas_grant_verified_purchase"
      );

    assert.equal(
      grant.args.p_provider,
      "google"
    );

    assert.equal(
      grant.args.p_sku,
      "korlix_ai_gas_3h"
    );

    assert.equal(
      grant.args
        .p_receipt_or_token_hash,
      hashKorlixAiGasSensitiveValue(
        "google-purchase-secret"
      )
    );
  }
);

test(
  "verified purchase for another account is rejected before ledger grant",
  async () => {
    const harness =
      createRpcHarness();

    const service =
      serviceFor(
        harness,
        {
          appleAdapter: {
            async verifyPurchase() {
              return {
                verified: true,
                status: "verified",
                userId: USER_B,
                productId:
                  "com.korlix.ai_gas.1h",
                transactionId:
                  "apple-account-mismatch",
                purchasedAt:
                  FIXED_TIME,
              };
            },
          },
        }
      );

    await rejectsCode(
      service.verifyApplePurchase({
        user: {
          id: USER_A,
        },
        purchase: {
          productId:
            "com.korlix.ai_gas.1h",
          verificationData:
            "apple-secret",
        },
      }),
      "ai_gas_purchase_user_mismatch"
    );

    assert.equal(
      findCall(
        harness,
        "korlix_ai_gas_grant_verified_purchase"
      ),
      undefined
    );
  }
);

test(
  "unknown verified provider product is rejected before ledger grant",
  async () => {
    const harness =
      createRpcHarness();

    const service =
      serviceFor(
        harness,
        {
          appleAdapter: {
            async verifyPurchase() {
              return {
                verified: true,
                status: "verified",
                userId: USER_A,
                productId:
                  "com.korlix.ai_gas.unknown",
                transactionId:
                  "apple-unknown-product",
                purchasedAt:
                  FIXED_TIME,
              };
            },
          },
        }
      );

    await rejectsCode(
      service.verifyApplePurchase({
        user: {
          id: USER_A,
        },
        purchase: {
          productId:
            "com.korlix.ai_gas.unknown",
          verificationData:
            "apple-secret",
        },
      }),
      "ai_gas_provider_product_unknown"
    );

    assert.equal(
      findCall(
        harness,
        "korlix_ai_gas_grant_verified_purchase"
      ),
      undefined
    );
  }
);

test(
  "verified refund routes to the reversal RPC and does not grant again",
  async () => {
    const harness =
      createRpcHarness();

    const service =
      serviceFor(
        harness,
        {
          googleAdapter: {
            async verifyPurchase() {
              return {
                verified: true,
                status: "refunded",
                userId: USER_A,
                productId:
                  "korlix_ai_gas_1h_android",
                transactionId:
                  "GPA.REFUND.1",
                purchasedAt:
                  FIXED_TIME,
              };
            },
          },
        }
      );

    const result =
      await service.verifyGooglePurchase({
        user: {
          id: USER_A,
        },
        purchase: {
          purchaseToken:
            "refunded-google-secret",
        },
      });

    const reversal =
      findCall(
        harness,
        "korlix_ai_gas_reverse_verified_purchase"
      );

    assert.ok(reversal);

    assert.equal(
      reversal.args.p_provider,
      "google"
    );

    assert.equal(
      reversal.args
        .p_provider_transaction_id,
      "GPA.REFUND.1"
    );

    assert.equal(
      reversal.args.p_reason,
      "refunded"
    );

    assert.equal(
      result.status,
      "refunded"
    );

    assert.equal(
      findCall(
        harness,
        "korlix_ai_gas_grant_verified_purchase"
      ),
      undefined
    );
  }
);

test(
  "balance and atomic consumption use server RPCs with idempotency",
  async () => {
    const harness =
      createRpcHarness({
        balanceSeconds: 9000,
      });

    const service =
      serviceFor(harness);

    const balance =
      await service.getBalance({
        userId: USER_A,
      });

    assert.equal(
      balance.balanceSeconds,
      9000
    );

    const consumed =
      await service.consume({
        userId: USER_A,
        seconds: 75,
        idempotencyKey:
          "live-convo:session-1:report-1",
        liveConvoSessionId:
          "session-1",
        metadata: {
          source:
            "live_convo",
          purchaseToken:
            "must-be-removed",
        },
      });

    assert.equal(
      consumed.consumedSeconds,
      75
    );

    assert.equal(
      consumed.balanceSeconds,
      8925
    );

    const consumeCall =
      findCall(
        harness,
        "korlix_ai_gas_consume"
      );

    assert.equal(
      consumeCall.args.p_user_id,
      USER_A
    );

    assert.equal(
      consumeCall.args.p_seconds,
      75
    );

    assert.equal(
      consumeCall.args
        .p_idempotency_key,
      "live-convo:session-1:report-1"
    );

    assert.equal(
      consumeCall.args
        .p_live_convo_session_id,
      "session-1"
    );

    assert.equal(
      Object.hasOwn(
        consumeCall.args.p_metadata,
        "purchaseToken"
      ),
      false
    );

    await rejectsCode(
      service.consume({
        userId: USER_A,
        seconds: 0,
        idempotencyKey:
          "invalid-zero",
      }),
      "ai_gas_seconds_invalid"
    );

    await rejectsCode(
      service.consume({
        userId: USER_A,
        seconds: 30,
        idempotencyKey: "",
      }),
      "ai_gas_idempotency_key_required"
    );
  }
);

test(
  "database failures are converted to a safe unavailable error",
  async () => {
    const harness =
      createRpcHarness({
        errors: {
          korlix_ai_gas_get_catalog: {
            code: "PGRST202",
            message:
              "private database detail",
          },
        },
      });

    const service =
      serviceFor(harness);

    await rejectsCode(
      service.getCatalog(),
      "ai_gas_database_error"
    );
  }
);
