'use strict';

const crypto = require('node:crypto');

const {
  createOAuthState,
  verifyOAuthState,
} = require('./oauth_state.cjs');

function text(
  value,
  label,
  max = 4096,
) {
  const normalized = String(
    value || '',
  ).trim();

  if (
    !normalized ||
    normalized.length > max
  ) {
    throw new Error(
      `Invalid ${label}`,
    );
  }

  return normalized;
}

function hashOAuthNonce(
  nonce,
) {
  return crypto
    .createHash('sha256')
    .update(
      text(
        nonce,
        'OAuth nonce',
        512,
      ),
    )
    .digest('base64url');
}

function buildZoomAuthorizationRequest(
  input,
  secret,
  options = {},
) {
  const config =
    input &&
    input.config;

  if (!config) {
    throw new Error(
      'Zoom configuration is required',
    );
  }

  const state =
    createOAuthState(
      {
        userId: text(
          input.userId,
          'userId',
          256,
        ),

        agentId: text(
          input.agentId,
          'agentId',
          256,
        ),

        returnPath:
          input.returnPath ||
          '/meeting-copilot',
      },
      secret,
      options,
    );

  const payload =
    verifyOAuthState(
      state,
      secret,
      {
        nowMs:
          options.nowMs,

        clockSkewSeconds: 0,
      },
    );

  const url =
    new URL(
      text(
        config.authorizeUrl ||
          'https://zoom.us/oauth/authorize',
        'authorizeUrl',
        2048,
      ),
    );

  url.searchParams.set(
    'response_type',
    'code',
  );

  url.searchParams.set(
    'client_id',
    text(
      config.clientId,
      'clientId',
      512,
    ),
  );

  url.searchParams.set(
    'redirect_uri',
    text(
      config.redirectUri,
      'redirectUri',
      2048,
    ),
  );

  url.searchParams.set(
    'state',
    state,
  );

  return Object.freeze({
    authorizationUrl:
      url.toString(),

    state,

    nonceHash:
      hashOAuthNonce(
        payload.nonce,
      ),

    userId:
      payload.sub,

    agentId:
      payload.agent,

    returnPath:
      payload.returnPath,

    expiresAt:
      new Date(
        payload.exp * 1000,
      ).toISOString(),
  });
}

function validateZoomOAuthCallback(
  query,
  secret,
  options = {},
) {
  if (
    !query ||
    typeof query !== 'object'
  ) {
    throw new Error(
      'OAuth callback query is required',
    );
  }

  if (query.error) {
    return Object.freeze({
      ok: false,

      error: text(
        query.error,
        'OAuth error',
        256,
      ),

      description:
        String(
          query.error_description ||
          '',
        )
          .replace(
            /[\r\n]/g,
            ' ',
          )
          .slice(
            0,
            512,
          ),
    });
  }

  const payload =
    verifyOAuthState(
      text(
        query.state,
        'OAuth state',
      ),
      secret,
      options,
    );

  return Object.freeze({
    ok: true,

    code: text(
      query.code,
      'OAuth code',
    ),

    userId:
      payload.sub,

    agentId:
      payload.agent,

    returnPath:
      payload.returnPath,

    nonceHash:
      hashOAuthNonce(
        payload.nonce,
      ),
  });
}

function key32(
  material,
) {
  if (
    Buffer.isBuffer(material) &&
    material.length === 32
  ) {
    return Buffer.from(
      material,
    );
  }

  if (
    typeof material !== 'string' ||
    Buffer.byteLength(
      material,
    ) < 32
  ) {
    throw new Error(
      'Token key must be at least 32 bytes',
    );
  }

  if (
    /^[a-f0-9]{64}$/i
      .test(material)
  ) {
    return Buffer.from(
      material,
      'hex',
    );
  }

  return crypto
    .createHash('sha256')
    .update(material)
    .digest();
}

function aad(
  context,
) {
  return Buffer.from(
    JSON.stringify({
      v: 1,

      userId: text(
        context &&
          context.userId,
        'token userId',
        256,
      ),

      connectionId: text(
        context &&
          context.connectionId,
        'connectionId',
        256,
      ),
    }),
  );
}

function encryptZoomTokens(
  tokens,
  material,
  context,
  options = {},
) {
  if (
    !tokens ||
    typeof tokens.access_token !==
      'string' ||
    !tokens.access_token
  ) {
    throw new Error(
      'access_token is required',
    );
  }

  const iv =
    options.iv
      ? Buffer.from(
          options.iv,
        )
      : crypto.randomBytes(12);

  if (iv.length !== 12) {
    throw new Error(
      'AES-GCM IV must be 12 bytes',
    );
  }

  const cipher =
    crypto.createCipheriv(
      'aes-256-gcm',
      key32(material),
      iv,
    );

  cipher.setAAD(
    aad(context),
  );

  const ciphertext =
    Buffer.concat([
      cipher.update(
        JSON.stringify(tokens),
        'utf8',
      ),

      cipher.final(),
    ]);

  return Object.freeze({
    v: 1,
    alg: 'A256GCM',

    iv:
      iv.toString(
        'base64url',
      ),

    tag:
      cipher
        .getAuthTag()
        .toString(
          'base64url',
        ),

    ciphertext:
      ciphertext.toString(
        'base64url',
      ),
  });
}

function decryptZoomTokens(
  envelope,
  material,
  context,
) {
  try {
    if (
      !envelope ||
      envelope.v !== 1 ||
      envelope.alg !==
        'A256GCM'
    ) {
      throw new Error();
    }

    const decipher =
      crypto.createDecipheriv(
        'aes-256-gcm',
        key32(material),
        Buffer.from(
          envelope.iv,
          'base64url',
        ),
      );

    decipher.setAAD(
      aad(context),
    );

    decipher.setAuthTag(
      Buffer.from(
        envelope.tag,
        'base64url',
      ),
    );

    return JSON.parse(
      Buffer.concat([
        decipher.update(
          Buffer.from(
            envelope.ciphertext,
            'base64url',
          ),
        ),

        decipher.final(),
      ]).toString('utf8'),
    );
  } catch {
    throw new Error(
      'Token envelope authentication failed',
    );
  }
}

class ActiveUsageMeter {
  constructor() {
    this.status = 'idle';
    this.activeMs = 0;
    this.activeSince = null;
    this.lastAt = null;
    this.seen = new Set();
  }

  apply(
    action,
    eventId,
    atMs,
  ) {
    const id = text(
      eventId,
      'usage eventId',
      512,
    );

    if (
      !Number.isSafeInteger(atMs) ||
      atMs < 0 ||
      (
        this.lastAt !== null &&
        atMs < this.lastAt
      )
    ) {
      throw new Error(
        'Invalid usage event time',
      );
    }

    if (this.seen.has(id)) {
      return {
        ...this.snapshot(atMs),
        duplicate: true,
      };
    }

    if (
      action === 'start' &&
      this.status === 'idle'
    ) {
      this.status = 'active';
      this.activeSince = atMs;
    } else if (
      action === 'pause' &&
      this.status === 'active'
    ) {
      this.activeMs +=
        atMs -
        this.activeSince;

      this.activeSince = null;
      this.status = 'paused';
    } else if (
      action === 'resume' &&
      this.status === 'paused'
    ) {
      this.activeSince = atMs;
      this.status = 'active';
    } else if (
      action === 'stop' &&
      [
        'active',
        'paused',
      ].includes(
        this.status,
      )
    ) {
      if (
        this.status === 'active'
      ) {
        this.activeMs +=
          atMs -
          this.activeSince;
      }

      this.activeSince = null;
      this.status = 'stopped';
    } else {
      throw new Error(
        'Invalid usage transition',
      );
    }

    this.seen.add(id);
    this.lastAt = atMs;

    return {
      ...this.snapshot(atMs),
      duplicate: false,
    };
  }

  snapshot(
    nowMs = Date.now(),
  ) {
    const activeMs =
      this.activeMs +
      (
        this.status === 'active'
          ? nowMs -
            this.activeSince
          : 0
      );

    return {
      status:
        this.status,

      activeMs,

      activeSeconds:
        Math.floor(
          activeMs / 1000,
        ),

      processedEventCount:
        this.seen.size,
    };
  }
}

class RtmsSession {
  constructor(
    input = {},
  ) {
    this.sessionId = text(
      input.sessionId,
      'sessionId',
      256,
    );

    this.meetingUuid = text(
      input.meetingUuid,
      'meetingUuid',
      512,
    );

    this.streamId =
      String(
        input.streamId ||
        '',
      ).trim();

    this.state = 'inactive';
    this.seen = new Set();
    this.usage =
      new ActiveUsageMeter();
  }

  apply(
    event = {},
  ) {
    const id = text(
      event.eventId,
      'RTMS eventId',
      512,
    );

    const at =
      event.atMs;

    const type =
      event.type;

    if (this.seen.has(id)) {
      return {
        ...this.snapshot(at),
        duplicate: true,
      };
    }

    if (
      type === 'initialize' &&
      this.state === 'inactive'
    ) {
      this.state =
        'initializing';
    } else if (
      type === 'started' &&
      [
        'inactive',
        'initializing',
      ].includes(
        this.state,
      )
    ) {
      this.state = 'started';

      this.usage.apply(
        'start',
        id,
        at,
      );
    } else if (
      type === 'paused' &&
      this.state === 'started'
    ) {
      this.state = 'paused';

      this.usage.apply(
        'pause',
        id,
        at,
      );
    } else if (
      type === 'resumed' &&
      this.state === 'paused'
    ) {
      this.state = 'started';

      this.usage.apply(
        'resume',
        id,
        at,
      );
    } else if (
      type === 'stopped' &&
      [
        'started',
        'paused',
      ].includes(
        this.state,
      )
    ) {
      this.usage.apply(
        'stop',
        id,
        at,
      );

      this.state =
        'stopped';
    } else {
      throw new Error(
        'Invalid RTMS transition',
      );
    }

    this.seen.add(id);

    return {
      ...this.snapshot(at),
      duplicate: false,
    };
  }

  snapshot(
    nowMs = Date.now(),
  ) {
    return {
      sessionId:
        this.sessionId,

      meetingUuid:
        this.meetingUuid,

      streamId:
        this.streamId,

      state:
        this.state,

      usage:
        this.usage.snapshot(
          nowMs,
        ),

      processedEventCount:
        this.seen.size,
    };
  }
}

function normalizeZoomEvent(
  rawBody,
) {
  const body =
    JSON.parse(
      Buffer.isBuffer(rawBody)
        ? rawBody.toString(
            'utf8',
          )
        : text(
            rawBody,
            'raw webhook body',
            1000000,
          ),
    );

  const payload =
    body.payload || {};

  const object =
    payload.object || {};

  const event = text(
    body.event,
    'Zoom event',
    256,
  );

  if (
    event ===
    'endpoint.url_validation'
  ) {
    return Object.freeze({
      kind:
        'url_validation',

      plainToken: text(
        payload.plainToken ||
          payload.plain_token,
        'plainToken',
        2048,
      ),
    });
  }

  const meetingUuid =
    String(
      object.uuid ||
      object.meeting_uuid ||
      payload.meeting_uuid ||
      '',
    ).trim();

  const streamId =
    String(
      object.rtms_stream_id ||
      object.stream_id ||
      payload.rtms_stream_id ||
      '',
    ).trim();

  const kind =
    event ===
    'meeting.rtms_started'
      ? 'rtms_started'
      : event ===
        'meeting.rtms_stopped'
        ? 'rtms_stopped'
        : 'other';

  if (
    kind !== 'other' &&
    (
      !meetingUuid ||
      !streamId
    )
  ) {
    throw new Error(
      'RTMS identifiers are required',
    );
  }

  const eventId =
    String(
      body.event_id ||
      payload.event_id ||
      '',
    ).trim() ||
    crypto
      .createHash('sha256')
      .update(
        JSON.stringify({
          event,
          ts:
            body.event_ts ||
            null,
          meetingUuid,
          streamId,
        }),
      )
      .digest('base64url');

  return Object.freeze({
    kind,
    event,
    eventId,

    accountId:
      String(
        payload.account_id ||
        object.account_id ||
        '',
      ).trim(),

    meetingUuid,

    meetingId:
      String(
        object.id ||
        object.meeting_id ||
        '',
      ).trim(),

    streamId,
  });
}

module.exports = {
  ActiveUsageMeter,
  RtmsSession,
  buildZoomAuthorizationRequest,
  decryptZoomTokens,
  encryptZoomTokens,
  hashOAuthNonce,
  normalizeZoomEvent,
  validateZoomOAuthCallback,
};
