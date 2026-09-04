'use strict';

const crypto = require('node:crypto');

function assertSecret(secret) {
  if (
    typeof secret !== 'string' ||
    Buffer.byteLength(
      secret,
      'utf8',
    ) < 32
  ) {
    throw new Error(
      'OAuth state secret must be at least 32 bytes',
    );
  }
}

function safeEqual(left, right) {
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

function isSafeReturnPath(value) {
  return (
    typeof value === 'string' &&
    value.startsWith('/') &&
    !value.startsWith('//') &&
    !/[\r\n]/.test(value) &&
    value.length <= 512
  );
}

function signPayload(
  encodedPayload,
  secret,
) {
  return crypto
    .createHmac(
      'sha256',
      secret,
    )
    .update(
      encodedPayload,
      'utf8',
    )
    .digest('base64url');
}

function createOAuthState(
  input,
  secret,
  options = {},
) {
  assertSecret(secret);

  const nowMs =
    options.nowMs === undefined
      ? Date.now()
      : options.nowMs;

  const ttlSeconds =
    options.ttlSeconds === undefined
      ? 600
      : options.ttlSeconds;

  const nowSeconds =
    Math.floor(nowMs / 1000);

  if (
    !Number.isSafeInteger(
      ttlSeconds,
    ) ||
    ttlSeconds < 60 ||
    ttlSeconds > 900
  ) {
    throw new Error(
      'OAuth state TTL must be between 60 and 900 seconds',
    );
  }

  const userId = String(
    (input && input.userId) || '',
  ).trim();

  const agentId = String(
    (input && input.agentId) || '',
  ).trim();

  const returnPath = String(
    (input && input.returnPath) ||
      '/meeting-copilot',
  );

  if (
    !userId ||
    userId.length > 256
  ) {
    throw new Error(
      'Invalid OAuth state userId',
    );
  }

  if (
    !agentId ||
    agentId.length > 256
  ) {
    throw new Error(
      'Invalid OAuth state agentId',
    );
  }

  if (
    !isSafeReturnPath(returnPath)
  ) {
    throw new Error(
      'Invalid OAuth state returnPath',
    );
  }

  const payload = {
    v: 1,
    sub: userId,
    agent: agentId,
    returnPath,

    nonce:
      options.nonce ||
      crypto
        .randomBytes(18)
        .toString('base64url'),

    iat: nowSeconds,
    exp:
      nowSeconds +
      ttlSeconds,
  };

  const encodedPayload = Buffer
    .from(
      JSON.stringify(payload),
      'utf8',
    )
    .toString('base64url');

  const signature = signPayload(
    encodedPayload,
    secret,
  );

  return (
    `${encodedPayload}.${signature}`
  );
}

function verifyOAuthState(
  token,
  secret,
  options = {},
) {
  assertSecret(secret);

  if (
    typeof token !== 'string' ||
    token.length > 4096
  ) {
    throw new Error(
      'Invalid OAuth state token',
    );
  }

  const pieces =
    token.split('.');

  if (
    pieces.length !== 2 ||
    !pieces[0] ||
    !pieces[1]
  ) {
    throw new Error(
      'Malformed OAuth state token',
    );
  }

  const [
    encodedPayload,
    suppliedSignature,
  ] = pieces;

  const expectedSignature =
    signPayload(
      encodedPayload,
      secret,
    );

  if (
    !safeEqual(
      suppliedSignature,
      expectedSignature,
    )
  ) {
    throw new Error(
      'OAuth state signature mismatch',
    );
  }

  let payload;

  try {
    payload = JSON.parse(
      Buffer
        .from(
          encodedPayload,
          'base64url',
        )
        .toString('utf8'),
    );
  } catch {
    throw new Error(
      'OAuth state payload is invalid',
    );
  }

  const nowMs =
    options.nowMs === undefined
      ? Date.now()
      : options.nowMs;

  const clockSkewSeconds =
    options.clockSkewSeconds === undefined
      ? 30
      : options.clockSkewSeconds;

  const nowSeconds =
    Math.floor(nowMs / 1000);

  if (
    !payload ||
    payload.v !== 1 ||
    typeof payload.sub !== 'string' ||
    typeof payload.agent !== 'string' ||
    typeof payload.nonce !== 'string' ||
    !Number.isSafeInteger(payload.iat) ||
    !Number.isSafeInteger(payload.exp) ||
    !isSafeReturnPath(
      payload.returnPath,
    )
  ) {
    throw new Error(
      'OAuth state payload failed validation',
    );
  }

  if (
    payload.iat >
    nowSeconds +
      clockSkewSeconds
  ) {
    throw new Error(
      'OAuth state issued in the future',
    );
  }

  if (
    payload.exp <
    nowSeconds -
      clockSkewSeconds
  ) {
    throw new Error(
      'OAuth state expired',
    );
  }

  return Object.freeze({
    ...payload,
  });
}

module.exports = {
  createOAuthState,
  isSafeReturnPath,
  verifyOAuthState,
};
