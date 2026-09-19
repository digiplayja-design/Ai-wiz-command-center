'use strict';

const crypto = require('node:crypto');

function requireSecret(
  secretToken,
) {
  if (
    typeof secretToken !== 'string' ||
    secretToken.length === 0
  ) {
    throw new Error(
      'Zoom webhook secret token is required',
    );
  }
}

function normalizeRawBody(
  rawBody,
) {
  if (
    Buffer.isBuffer(rawBody)
  ) {
    return rawBody.toString(
      'utf8',
    );
  }

  if (
    typeof rawBody === 'string'
  ) {
    return rawBody;
  }

  throw new Error(
    'Zoom webhook verification requires the exact raw request body',
  );
}

function safeEqual(
  left,
  right,
) {
  const leftBuffer = Buffer.from(
    String(left),
    'utf8',
  );

  const rightBuffer = Buffer.from(
    String(right),
    'utf8',
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

function buildZoomWebhookSignature({
  secretToken,
  timestamp,
  rawBody,
}) {
  requireSecret(
    secretToken,
  );

  const body =
    normalizeRawBody(
      rawBody,
    );

  const message =
    `v0:${String(timestamp)}:${body}`;

  const digest = crypto
    .createHmac(
      'sha256',
      secretToken,
    )
    .update(
      message,
      'utf8',
    )
    .digest('hex');

  return `v0=${digest}`;
}

function verifyZoomWebhookSignature(
  input,
) {
  const {
    secretToken,
    timestamp,
    rawBody,
    signature,
    nowMs = Date.now(),
    maxSkewSeconds = 300,
  } = input || {};

  try {
    requireSecret(
      secretToken,
    );

    const timestampNumber =
      Number(timestamp);

    if (
      !Number.isInteger(
        timestampNumber,
      ) ||
      timestampNumber <= 0
    ) {
      return {
        ok: false,
        reason:
          'invalid_timestamp',
      };
    }

    if (
      !Number.isSafeInteger(
        maxSkewSeconds,
      ) ||
      maxSkewSeconds <= 0
    ) {
      return {
        ok: false,
        reason:
          'invalid_skew_policy',
      };
    }

    const nowSeconds =
      Math.floor(nowMs / 1000);

    if (
      Math.abs(
        nowSeconds -
          timestampNumber,
      ) > maxSkewSeconds
    ) {
      return {
        ok: false,
        reason:
          'timestamp_outside_window',
      };
    }

    if (
      typeof signature !== 'string' ||
      !/^v0=[a-f0-9]{64}$/i
        .test(signature)
    ) {
      return {
        ok: false,
        reason:
          'invalid_signature_format',
      };
    }

    const expected =
      buildZoomWebhookSignature({
        secretToken,
        timestamp:
          timestampNumber,
        rawBody,
      });

    return safeEqual(
      signature,
      expected,
    )
      ? {
          ok: true,
          reason: 'verified',
        }
      : {
          ok: false,
          reason:
            'signature_mismatch',
        };
  } catch {
    return {
      ok: false,
      reason:
        'verification_error',
    };
  }
}

function buildZoomUrlValidationResponse(
  plainToken,
  secretToken,
) {
  requireSecret(
    secretToken,
  );

  if (
    typeof plainToken !== 'string' ||
    plainToken.length === 0 ||
    plainToken.length > 2048
  ) {
    throw new Error(
      'Invalid Zoom URL-validation plain token',
    );
  }

  return {
    plainToken,

    encryptedToken: crypto
      .createHmac(
        'sha256',
        secretToken,
      )
      .update(
        plainToken,
        'utf8',
      )
      .digest('hex'),
  };
}

module.exports = {
  buildZoomUrlValidationResponse,
  buildZoomWebhookSignature,
  normalizeRawBody,
  verifyZoomWebhookSignature,
};
