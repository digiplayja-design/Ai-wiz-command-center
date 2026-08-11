import crypto from "node:crypto";

const PACKAGE_ROWS = [
  ["korlix_ai_gas_1h", "1 Hour AI GAS", 3600, 3000],
  ["korlix_ai_gas_2h", "2 Hours AI GAS", 7200, 5500],
  ["korlix_ai_gas_3h", "3 Hours AI GAS", 10800, 8000],
  ["korlix_ai_gas_5h", "5 Hours AI GAS", 18000, 12499],
];

export const KORLIX_AI_GAS_PACKAGES = Object.freeze(
  PACKAGE_ROWS.map(([sku, displayName, seconds, baseUsdCents]) =>
    Object.freeze({ sku, displayName, seconds, baseUsdCents })
  )
);

const PACKAGE_BY_SKU = new Map(
  KORLIX_AI_GAS_PACKAGES.map((item) => [item.sku, item])
);

const PROVIDERS = new Set(["apple", "google", "web"]);
const TERMINAL_STATUSES = new Set(["refunded", "revoked"]);

const VERIFIED_STATUSES = new Set([
  "active",
  "paid",
  "purchased",
  "success",
  "succeeded",
  "verified",
]);

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const SECRET_KEY_PATTERN =
  /(^|_)(authorization|receipt|signed_?payload|purchase_?token|verification_?data|server_?verification_?data|raw_?body|secret|token)($|_)/i;

export class KorlixAiGasError extends Error {
  constructor(
    message,
    {
      statusCode = 400,
      code = "ai_gas_error",
      cause,
    } = {}
  ) {
    super(String(message || "AI GAS request failed."), { cause });

    this.name = "KorlixAiGasError";
    this.statusCode = Number.isInteger(statusCode)
      ? statusCode
      : 400;
    this.code = String(code || "ai_gas_error");
  }
}

function cleanText(value, maximum = 512) {
  return String(value ?? "")
    .trim()
    .slice(0, Math.max(0, maximum));
}

function requireUserId(value) {
  const candidate =
    typeof value === "string"
      ? value
      : value?.id;

  const userId = cleanText(candidate, 64);

  if (!UUID_PATTERN.test(userId)) {
    throw new KorlixAiGasError(
      "A valid signed-in KORLIX user is required.",
      {
        statusCode: 401,
        code: "ai_gas_sign_in_required",
      }
    );
  }

  return userId;
}

function normalizeProvider(value) {
  const provider = cleanText(value, 32).toLowerCase();

  if (!PROVIDERS.has(provider)) {
    throw new KorlixAiGasError(
      "Unsupported AI GAS purchase provider.",
      {
        code: "ai_gas_provider_invalid",
      }
    );
  }

  return provider;
}

export function normalizeKorlixAiGasSku(value) {
  const sku = cleanText(value, 80).toLowerCase();

  if (!PACKAGE_BY_SKU.has(sku)) {
    throw new KorlixAiGasError(
      "Unknown AI GAS package.",
      {
        code: "ai_gas_product_invalid",
      }
    );
  }

  return sku;
}

export function hashKorlixAiGasSensitiveValue(value) {
  const text = String(value ?? "");

  return text
    ? crypto
        .createHash("sha256")
        .update(text)
        .digest("hex")
    : null;
}

export function sanitizeKorlixAiGasMetadata(
  value,
  depth = 0
) {
  if (depth > 5) {
    return "[depth-limited]";
  }

  if (value === null || value === undefined) {
    return null;
  }

  if (
    typeof value === "boolean" ||
    typeof value === "number"
  ) {
    return value;
  }

  if (typeof value === "string") {
    return value.slice(0, 2000);
  }

  if (Array.isArray(value)) {
    return value
      .slice(0, 50)
      .map((item) =>
        sanitizeKorlixAiGasMetadata(
          item,
          depth + 1
        )
      );
  }

  if (typeof value === "object") {
    const safe = {};

    for (
      const [rawKey, rawValue]
      of Object.entries(value).slice(0, 100)
    ) {
      const key = cleanText(rawKey, 120);

      if (
        !key ||
        SECRET_KEY_PATTERN.test(key)
      ) {
        continue;
      }

      safe[key] =
        sanitizeKorlixAiGasMetadata(
          rawValue,
          depth + 1
        );
    }

    return safe;
  }

  return cleanText(value, 2000);
}

function normalizeCatalogRow(row) {
  const sku =
    normalizeKorlixAiGasSku(row?.sku);

  const expected =
    PACKAGE_BY_SKU.get(sku);

  const displayName = cleanText(
    row?.display_name ??
      row?.displayName ??
      expected.displayName,
    120
  );

  const seconds =
    Number(row?.seconds);

  const baseUsdCents =
    Number(
      row?.base_usd_cents ??
      row?.baseUsdCents
    );

  if (
    displayName !== expected.displayName ||
    seconds !== expected.seconds ||
    baseUsdCents !== expected.baseUsdCents
  ) {
    throw new KorlixAiGasError(
      "AI GAS catalog configuration is invalid.",
      {
        statusCode: 500,
        code: "ai_gas_catalog_mismatch",
      }
    );
  }

  return Object.freeze({
    sku,
    displayName,
    seconds,
    baseUsdCents,

    appleProductId:
      cleanText(
        row?.apple_product_id ??
        row?.appleProductId,
        200
      ) || null,

    googleProductId:
      cleanText(
        row?.google_product_id ??
        row?.googleProductId,
        200
      ) || null,

    webPriceId:
      cleanText(
        row?.web_price_id ??
        row?.webPriceId,
        200
      ) || null,
  });
}

function normalizeCatalog(data) {
  const rows =
    Array.isArray(data)
      ? data
      : data
        ? [data]
        : [];

  const normalized =
    rows.map(normalizeCatalogRow);

  const bySku =
    new Map(
      normalized.map((item) => [
        item.sku,
        item,
      ])
    );

  if (
    normalized.length !==
      KORLIX_AI_GAS_PACKAGES.length ||
    bySku.size !==
      KORLIX_AI_GAS_PACKAGES.length ||
    KORLIX_AI_GAS_PACKAGES.some(
      (item) => !bySku.has(item.sku)
    )
  ) {
    throw new KorlixAiGasError(
      "The complete AI GAS catalog is unavailable.",
      {
        statusCode: 503,
        code: "ai_gas_catalog_unavailable",
      }
    );
  }

  return Object.freeze(
    KORLIX_AI_GAS_PACKAGES.map(
      (item) => bySku.get(item.sku)
    )
  );
}

function scalar(data, keys = []) {
  if (Array.isArray(data)) {
    return data.length
      ? scalar(data[0], keys)
      : null;
  }

  if (
    data &&
    typeof data === "object"
  ) {
    for (const key of keys) {
      if (Object.hasOwn(data, key)) {
        return data[key];
      }
    }

    const values =
      Object.values(data);

    return values.length === 1
      ? values[0]
      : data;
  }

  return data;
}

function rpcJson(data) {
  return (
    Array.isArray(data) &&
    data.length === 1
  )
    ? data[0]
    : data;
}

function isoTimestamp(value, fallback) {
  const date =
    new Date(
      cleanText(value, 80) ||
      fallback
    );

  if (Number.isNaN(date.getTime())) {
    throw new KorlixAiGasError(
      "Purchase timestamp is invalid.",
      {
        code:
          "ai_gas_purchase_timestamp_invalid",
      }
    );
  }

  return date.toISOString();
}

function requireAdapter(
  adapter,
  provider
) {
  if (
    !adapter ||
    typeof adapter.verifyPurchase !==
      "function"
  ) {
    throw new KorlixAiGasError(
      `AI GAS ${provider} purchase verification is not configured.`,
      {
        statusCode: 503,
        code:
          `ai_gas_${provider}_unavailable`,
      }
    );
  }

  return adapter.verifyPurchase.bind(
    adapter
  );
}

function verifiedStatus(value) {
  const status =
    cleanText(
      value || "verified",
      32
    ).toLowerCase();

  if (TERMINAL_STATUSES.has(status)) {
    return status;
  }

  if (!VERIFIED_STATUSES.has(status)) {
    throw new KorlixAiGasError(
      "The provider did not verify this purchase.",
      {
        code:
          "ai_gas_purchase_not_verified",
      }
    );
  }

  return "verified";
}

function ensureVerifiedUser(
  verified,
  expectedUserId
) {
  const providerUserId =
    cleanText(
      verified?.userId ??
      verified?.user_id ??
      verified?.appAccountToken,
      80
    );

  if (
    providerUserId &&
    providerUserId !== expectedUserId
  ) {
    throw new KorlixAiGasError(
      "This verified purchase belongs to a different KORLIX account.",
      {
        statusCode: 403,
        code:
          "ai_gas_purchase_user_mismatch",
      }
    );
  }
}

function providerProductField(
  provider
) {
  return provider === "apple"
    ? "appleProductId"
    : provider === "google"
      ? "googleProductId"
      : "webPriceId";
}

export function createKorlixAiGasService({
  supabaseAdmin,
  appleAdapter = null,
  googleAdapter = null,
  logger = console,
  now = () => new Date(),
} = {}) {
  if (
    !supabaseAdmin ||
    typeof supabaseAdmin.rpc !==
      "function"
  ) {
    throw new KorlixAiGasError(
      "AI GAS database service is unavailable.",
      {
        statusCode: 503,
        code:
          "ai_gas_database_unavailable",
      }
    );
  }

  async function rpc(
    name,
    args = {}
  ) {
    const {
      data,
      error,
    } = await supabaseAdmin.rpc(
      name,
      args
    );

    if (error) {
      if (
        typeof logger?.error ===
        "function"
      ) {
        logger.error(
          "KORLIX_AI_GAS_RPC_FAILED",
          {
            rpc: name,
            code:
              cleanText(
                error.code,
                80
              ) || null,
          }
        );
      }

      throw new KorlixAiGasError(
        "AI GAS database operation failed.",
        {
          statusCode: 503,
          code:
            "ai_gas_database_error",
        }
      );
    }

    return data;
  }

  async function getCatalog() {
    return normalizeCatalog(
      await rpc(
        "korlix_ai_gas_get_catalog"
      )
    );
  }

  async function getBalance({
    userId,
  }) {
    const id =
      requireUserId(userId);

    const raw = scalar(
      await rpc(
        "korlix_ai_gas_get_balance",
        {
          p_user_id: id,
        }
      ),
      [
        "korlix_ai_gas_get_balance",
        "balance_seconds",
        "balanceSeconds",
      ]
    );

    const balanceSeconds =
      Number(raw ?? 0);

    if (
      !Number.isSafeInteger(
        balanceSeconds
      ) ||
      balanceSeconds < 0
    ) {
      throw new KorlixAiGasError(
        "AI GAS balance response is invalid.",
        {
          statusCode: 503,
          code:
            "ai_gas_balance_invalid",
        }
      );
    }

    return Object.freeze({
      balanceSeconds,
    });
  }

  async function resolveProduct(
    provider,
    providerProductId
  ) {
    const normalizedProvider =
      normalizeProvider(provider);

    const productId =
      cleanText(
        providerProductId,
        200
      );

    if (!productId) {
      throw new KorlixAiGasError(
        "Provider product ID is missing.",
        {
          code:
            "ai_gas_provider_product_id_required",
        }
      );
    }

    const field =
      providerProductField(
        normalizedProvider
      );

    const product =
      (await getCatalog()).find(
        (item) =>
          item[field] === productId
      );

    if (!product) {
      throw new KorlixAiGasError(
        "This provider product is not an approved AI GAS package.",
        {
          code:
            "ai_gas_provider_product_unknown",
        }
      );
    }

    return product;
  }

  async function grant({
    userId,
    provider,
    product,
    transactionId,
    originalTransactionId,
    verificationMaterial,
    purchasedAt,
    metadata,
  }) {
    const id =
      requireUserId(userId);

    const normalizedProvider =
      normalizeProvider(provider);

    const tx =
      cleanText(
        transactionId,
        240
      );

    const sku =
      normalizeKorlixAiGasSku(
        product?.sku
      );

    const expected =
      PACKAGE_BY_SKU.get(sku);

    if (!tx) {
      throw new KorlixAiGasError(
        "Verified transaction ID is missing.",
        {
          code:
            "ai_gas_transaction_id_required",
        }
      );
    }

    if (
      Number(product?.seconds) !==
        expected.seconds ||
      Number(product?.baseUsdCents) !==
        expected.baseUsdCents
    ) {
      throw new KorlixAiGasError(
        "AI GAS package configuration is invalid.",
        {
          statusCode: 500,
          code:
            "ai_gas_catalog_mismatch",
        }
      );
    }

    return rpcJson(
      await rpc(
        "korlix_ai_gas_grant_verified_purchase",
        {
          p_user_id: id,

          p_provider:
            normalizedProvider,

          p_provider_transaction_id:
            tx,

          p_provider_original_transaction_id:
            cleanText(
              originalTransactionId,
              240
            ) || null,

          p_sku: sku,

          p_receipt_or_token_hash:
            hashKorlixAiGasSensitiveValue(
              verificationMaterial
            ),

          p_purchased_at:
            isoTimestamp(
              purchasedAt,
              now()
            ),

          p_metadata:
            sanitizeKorlixAiGasMetadata(
              metadata
            ),
        }
      )
    );
  }

  async function reverse({
    provider,
    transactionId,
    reason,
    metadata = {},
  }) {
    const normalizedProvider =
      normalizeProvider(provider);

    const tx =
      cleanText(
        transactionId,
        240
      );

    const normalizedReason =
      cleanText(
        reason,
        32
      ).toLowerCase();

    if (!tx) {
      throw new KorlixAiGasError(
        "Verified transaction ID is missing.",
        {
          code:
            "ai_gas_transaction_id_required",
        }
      );
    }

    if (
      !TERMINAL_STATUSES.has(
        normalizedReason
      )
    ) {
      throw new KorlixAiGasError(
        "Purchase reversal status is invalid.",
        {
          code:
            "ai_gas_reversal_status_invalid",
        }
      );
    }

    return rpcJson(
      await rpc(
        "korlix_ai_gas_reverse_verified_purchase",
        {
          p_provider:
            normalizedProvider,

          p_provider_transaction_id:
            tx,

          p_reason:
            normalizedReason,

          p_metadata:
            sanitizeKorlixAiGasMetadata(
              metadata
            ),
        }
      )
    );
  }

  async function verifyProviderPurchase({
    provider,
    user,
    purchase = {},
  }) {
    const normalizedProvider =
      normalizeProvider(provider);

    const userId =
      requireUserId(user);

    const adapter =
      normalizedProvider === "apple"
        ? appleAdapter
        : googleAdapter;

    const verifyPurchase =
      requireAdapter(
        adapter,
        normalizedProvider
      );

    const secret =
      normalizedProvider === "apple"
        ? String(
            purchase.verificationData ??
            purchase.verification_data ??
            ""
          )
        : String(
            purchase.purchaseToken ??
            purchase.purchase_token ??
            ""
          );

    if (!secret) {
      throw new KorlixAiGasError(
        "Provider verification material is required.",
        {
          code:
            `ai_gas_${normalizedProvider}_verification_required`,
        }
      );
    }

    const verified =
      await verifyPurchase({
        userId,

        productId:
          cleanText(
            purchase.productId ??
            purchase.product_id,
            200
          ),

        purchaseId:
          cleanText(
            purchase.purchaseId ??
            purchase.purchase_id,
            240
          ),

        verificationData:
          normalizedProvider === "apple"
            ? secret
            : undefined,

        purchaseToken:
          normalizedProvider === "google"
            ? secret
            : undefined,

        source:
          cleanText(
            purchase.source,
            80
          ),

        transactionDate:
          cleanText(
            purchase.transactionDate ??
            purchase.transaction_date,
            80
          ),

        orderId:
          cleanText(
            purchase.orderId ??
            purchase.order_id,
            240
          ),

        packageName:
          cleanText(
            purchase.packageName ??
            purchase.package_name,
            240
          ),

        restored:
          purchase.restored === true,
      });

    if (
      !verified ||
      verified.verified !== true
    ) {
      throw new KorlixAiGasError(
        `${normalizedProvider} did not verify this AI GAS purchase.`,
        {
          code:
            `ai_gas_${normalizedProvider}_not_verified`,
        }
      );
    }

    ensureVerifiedUser(
      verified,
      userId
    );

    const status =
      verifiedStatus(
        verified.status
      );

    const transactionId =
      cleanText(
        verified.transactionId ??
        verified.transaction_id ??
        verified.orderId ??
        verified.order_id,
        240
      );

    if (
      TERMINAL_STATUSES.has(
        status
      )
    ) {
      return reverse({
        provider:
          normalizedProvider,

        transactionId,

        reason: status,

        metadata:
          sanitizeKorlixAiGasMetadata(
            verified.metadata
          ),
      });
    }

    const product =
      await resolveProduct(
        normalizedProvider,
        verified.productId ??
        verified.product_id
      );

    const grantResult =
      await grant({
        userId,

        provider:
          normalizedProvider,

        product,

        transactionId,

        originalTransactionId:
          verified.originalTransactionId ??
          verified.original_transaction_id,

        verificationMaterial:
          secret,

        purchasedAt:
          verified.purchasedAt ??
          verified.purchased_at,

        metadata: {
          ...sanitizeKorlixAiGasMetadata(
            verified.metadata
          ),

          restored:
            purchase.restored === true,

          source:
            cleanText(
              purchase.source,
              80
            ) || null,
        },
      });

    return Object.freeze({
      verified: true,
      provider:
        normalizedProvider,
      product,
      grant: grantResult,
    });
  }

  async function consume({
    userId,
    seconds,
    idempotencyKey,
    liveConvoSessionId = null,
    metadata = {},
  }) {
    const id =
      requireUserId(userId);

    const amount =
      Number(seconds);

    const key =
      cleanText(
        idempotencyKey,
        240
      );

    if (
      !Number.isInteger(amount) ||
      amount <= 0 ||
      amount > 86400
    ) {
      throw new KorlixAiGasError(
        "AI GAS seconds are invalid.",
        {
          code:
            "ai_gas_seconds_invalid",
        }
      );
    }

    if (!key) {
      throw new KorlixAiGasError(
        "AI GAS usage idempotency key is required.",
        {
          code:
            "ai_gas_idempotency_key_required",
        }
      );
    }

    return rpcJson(
      await rpc(
        "korlix_ai_gas_consume",
        {
          p_user_id: id,

          p_seconds:
            amount,

          p_idempotency_key:
            key,

          p_live_convo_session_id:
            cleanText(
              liveConvoSessionId,
              240
            ) || null,

          p_metadata:
            sanitizeKorlixAiGasMetadata(
              metadata
            ),
        }
      )
    );
  }

  return Object.freeze({
    getCatalog,
    getBalance,

    verifyApplePurchase: ({
      user,
      purchase,
    }) =>
      verifyProviderPurchase({
        provider: "apple",
        user,
        purchase,
      }),

    verifyGooglePurchase: ({
      user,
      purchase,
    }) =>
      verifyProviderPurchase({
        provider: "google",
        user,
        purchase,
      }),

    reverseVerifiedPurchase:
      reverse,

    consume,
  });
}
