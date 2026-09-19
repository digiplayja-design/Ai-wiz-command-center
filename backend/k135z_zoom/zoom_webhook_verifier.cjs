"use strict";

const crypto = require("node:crypto");

const {
  K135zZoomError,
} = require(
  "./zoom_token_vault.cjs",
);

function headerValue(
  headers,
  name,
) {
  if (
    !headers ||
    typeof headers !== "object"
  ) {
    return "";
  }

  const target =
    name.toLowerCase();

  for (
    const [key, value]
    of Object.entries(headers)
  ) {
    if (
      String(key)
        .toLowerCase() ===
      target
    ) {
      return Array.isArray(value)
        ? String(
            value[0] || "",
          )
        : String(
            value || "",
          );
    }
  }

  return "";
}

function getRawBody(request) {
  const candidates = [
    request?.rawBody,
    request?.rawBodyBuffer,

    Buffer.isBuffer(
      request?.body,
    )
      ? request.body
      : null,

    typeof request?.body ===
    "string"
      ? request.body
      : null,
  ];

  for (
    const candidate
    of candidates
  ) {
    if (
      Buffer.isBuffer(
        candidate,
      )
    ) {
      return candidate.toString(
        "utf8",
      );
    }

    if (
      typeof candidate ===
        "string" &&
      candidate.length > 0
    ) {
      return candidate;
    }
  }

  throw new K135zZoomError(
    400,
    "ZOOM_WEBHOOK_RAW_BODY_REQUIRED",
    "The exact Zoom webhook request body is required for signature verification.",
  );
}

function constantTimeEqual(
  left,
  right,
) {
  const leftBuffer =
    Buffer.from(
      String(left),
      "utf8",
    );

  const rightBuffer =
    Buffer.from(
      String(right),
      "utf8",
    );

  return (
    leftBuffer.length ===
      rightBuffer.length &&
    crypto.timingSafeEqual(
      leftBuffer,
      rightBuffer,
    )
  );
}

class ZoomWebhookVerifier {
  constructor({
    secret,
    toleranceSeconds = 300,
    clock = () => Date.now(),
  }) {
    this.secret =
      String(secret || "");

    this.toleranceSeconds =
      Number(toleranceSeconds);

    this.clock = clock;
  }

  assertConfigured() {
    if (!this.secret) {
      throw new K135zZoomError(
        503,
        "ZOOM_WEBHOOK_SECRET_NOT_CONFIGURED",
        "Zoom webhook verification is not configured.",
      );
    }
  }

  sign({
    timestamp,
    rawBody,
  }) {
    this.assertConfigured();

    const message =
      `v0:${timestamp}:${rawBody}`;

    const digest = crypto
      .createHmac(
        "sha256",
        this.secret,
      )
      .update(
        message,
        "utf8",
      )
      .digest("hex");

    return `v0=${digest}`;
  }

  verifyRequest(request) {
    this.assertConfigured();

    const timestampText =
      headerValue(
        request?.headers,
        "x-zm-request-timestamp",
      );

    const signature =
      headerValue(
        request?.headers,
        "x-zm-signature",
      );

    const timestamp =
      Number(timestampText);

    const rawBody =
      getRawBody(request);

    if (
      !Number.isFinite(
        timestamp,
      ) ||
      !signature
    ) {
      throw new K135zZoomError(
        401,
        "ZOOM_WEBHOOK_SIGNATURE_MISSING",
        "Zoom webhook signature headers are missing.",
      );
    }

    const nowSeconds =
      Math.floor(
        this.clock() /
          1000,
      );

    if (
      Math.abs(
        nowSeconds -
          timestamp,
      ) >
      this.toleranceSeconds
    ) {
      throw new K135zZoomError(
        401,
        "ZOOM_WEBHOOK_TIMESTAMP_REJECTED",
        "The Zoom webhook timestamp is outside the allowed window.",
      );
    }

    const expected =
      this.sign({
        timestamp:
          timestampText,
        rawBody,
      });

    if (
      !constantTimeEqual(
        expected,
        signature,
      )
    ) {
      throw new K135zZoomError(
        401,
        "ZOOM_WEBHOOK_SIGNATURE_INVALID",
        "The Zoom webhook signature is invalid.",
      );
    }

    let body;

    try {
      body =
        JSON.parse(rawBody);
    } catch (error) {
      throw new K135zZoomError(
        400,
        "ZOOM_WEBHOOK_JSON_INVALID",
        "The Zoom webhook body is not valid JSON.",
      );
    }

    return {
      body,
      rawBody,
      timestamp,
    };
  }

  createEndpointValidationResponse(
    plainToken,
  ) {
    this.assertConfigured();

    const token =
      String(
        plainToken || "",
      );

    if (!token) {
      throw new K135zZoomError(
        400,
        "ZOOM_WEBHOOK_PLAIN_TOKEN_MISSING",
        "The Zoom endpoint validation token is missing.",
      );
    }

    return {
      plainToken: token,

      encryptedToken:
        crypto
          .createHmac(
            "sha256",
            this.secret,
          )
          .update(
            token,
            "utf8",
          )
          .digest("hex"),
    };
  }
}

module.exports = {
  ZoomWebhookVerifier,
  constantTimeEqual,
  getRawBody,
  headerValue,
};
