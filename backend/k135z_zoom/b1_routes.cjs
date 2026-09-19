'use strict';

const crypto =
  require('node:crypto');

const {
  buildZoomAuthorizationRequest,
  encryptZoomTokens,
  normalizeZoomEvent,
  validateZoomOAuthCallback,
} = require(
  './b1_core.cjs',
);

const {
  buildZoomUrlValidationResponse,
  verifyZoomWebhookSignature,
} = require(
  './zoom_webhook.cjs',
);

const ROUTES =
  Object.freeze([
    {
      method: 'POST',

      path:
        '/api/k135z/zoom/oauth/start',

      auth:
        'korlix_user',
    },

    {
      method: 'GET',

      path:
        '/api/k135z/zoom/oauth/callback',

      auth:
        'signed_state',
    },

    {
      method: 'GET',

      path:
        '/api/k135z/zoom/status',

      auth:
        'korlix_user',
    },

    {
      method: 'POST',

      path:
        '/api/k135z/zoom/webhook',

      auth:
        'zoom_hmac',

      rawBody: true,
    },
  ]);

function text(
  value,
  label,
  max = 4096,
) {
  const normalized =
    String(
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

function rejectPlaintextTokens(
  value,
  path = 'record',
) {
  if (
    !value ||
    typeof value !== 'object'
  ) {
    return true;
  }

  for (
    const [
      key,
      child,
    ] of Object.entries(value)
  ) {
    const normalizedKey =
      key
        .toLowerCase()
        .replace(
          /[^a-z0-9]/g,
          '',
        );

    if (
      [
        'accesstoken',
        'refreshtoken',
        'idtoken',
        'clientsecret',
      ].includes(
        normalizedKey,
      )
    ) {
      throw new Error(
        `Plaintext token field forbidden at ${path}.${key}`,
      );
    }

    rejectPlaintextTokens(
      child,
      `${path}.${key}`,
    );
  }

  return true;
}

function createMemoryZoomStore() {
  const nonces =
    new Map();

  const connections =
    new Map();

  const events =
    new Map();

  const audits = [];

  return Object.freeze({
    nonce: {
      async create(record) {
        if (
          nonces.has(
            record.nonceHash,
          )
        ) {
          throw new Error(
            'nonce exists',
          );
        }

        nonces.set(
          record.nonceHash,
          {
            ...record,
          },
        );
      },

      async consume(query) {
        const record =
          nonces.get(
            query.nonceHash,
          );

        if (
          !record ||
          record.consumedAt ||
          record.userId !==
            query.userId ||
          record.agentId !==
            query.agentId ||
          Date.parse(
            record.expiresAt,
          ) <
            Date.parse(
              query.nowIso,
            )
        ) {
          return null;
        }

        record.consumedAt =
          query.nowIso;

        return {
          ...record,
        };
      },

      size: () =>
        nonces.size,
    },

    connection: {
      async upsert(record) {
        rejectPlaintextTokens(
          record,
        );

        if (
          !record.tokenEnvelope ||
          record.tokenEnvelope.alg !==
            'A256GCM'
        ) {
          throw new Error(
            'encrypted token envelope required',
          );
        }

        connections.set(
          `${record.userId}:${record.agentId}`,
          {
            ...record,
          },
        );
      },

      async find(query) {
        return (
          connections.get(
            `${query.userId}:${query.agentId}`,
          ) ||
          null
        );
      },

      size: () =>
        connections.size,
    },

    event: {
      async accept(record) {
        if (
          events.has(
            record.eventId,
          )
        ) {
          return {
            accepted: false,
            duplicate: true,
          };
        }

        events.set(
          record.eventId,
          {
            ...record,
          },
        );

        return {
          accepted: true,
          duplicate: false,
        };
      },

      size: () =>
        events.size,
    },

    audit: {
      async record(record) {
        rejectPlaintextTokens(
          record,
        );

        audits.push({
          id:
            crypto.randomUUID(),

          ...record,
        });
      },

      list: () =>
        audits.map(
          (record) => ({
            ...record,
          }),
        ),
    },
  });
}

function header(
  req,
  name,
) {
  if (
    req &&
    typeof req.get ===
      'function'
  ) {
    return (
      req.get(name) ||
      ''
    );
  }

  const headers =
    (
      req &&
      req.headers
    ) || {};

  return (
    headers[name] ||
    headers[
      name.toLowerCase()
    ] ||
    ''
  );
}

function send(
  res,
  status,
  body,
) {
  if (
    res &&
    typeof res.status ===
      'function' &&
    typeof res.json ===
      'function'
  ) {
    return res
      .status(status)
      .json(body);
  }

  if (res) {
    res.statusCode =
      status;

    res.body =
      body;
  }

  return (
    res || {
      statusCode:
        status,

      body,
    }
  );
}

function createZoomHandlers(
  deps = {},
) {
  const {
    config,
    authenticate,
    ownsAgent,
    exchangeCode,
    store,
  } = deps;

  if (
    !config ||
    !store ||
    ![
      'authenticate',
      'ownsAgent',
      'exchangeCode',
    ].every(
      (key) =>
        typeof deps[key] ===
        'function',
    )
  ) {
    throw new Error(
      'Zoom handler dependencies are incomplete',
    );
  }

  const now =
    typeof deps.nowMs ===
      'function'
      ? deps.nowMs
      : () => Date.now();

  const newId =
    typeof deps.newId ===
      'function'
      ? deps.newId
      : () =>
          crypto.randomUUID();

  async function start(
    req,
    res,
  ) {
    try {
      if (!config.enabled) {
        return send(
          res,
          503,
          {
            ok: false,
            code:
              'ZOOM_DISABLED',
          },
        );
      }

      const userId =
        text(
          (
            await authenticate(
              req,
            )
          ).userId,
          'userId',
          256,
        );

      const agentId =
        text(
          req &&
            req.body &&
            req.body.agentId,
          'agentId',
          256,
        );

      if (
        !(
          await ownsAgent({
            userId,
            agentId,
          })
        )
      ) {
        return send(
          res,
          403,
          {
            ok: false,
            code:
              'AGENT_NOT_OWNED',
          },
        );
      }

      const request =
        buildZoomAuthorizationRequest(
          {
            config,
            userId,
            agentId,

            returnPath:
              req.body
                .returnPath ||
              '/meeting-copilot',
          },
          config.oauthStateSecret,
          {
            nowMs: now(),
            ttlSeconds: 600,
          },
        );

      await store.nonce.create({
        nonceHash:
          request.nonceHash,

        userId,
        agentId,

        expiresAt:
          request.expiresAt,

        createdAt:
          new Date(
            now(),
          ).toISOString(),

        consumedAt: null,
      });

      await store.audit.record({
        type:
          'zoom.oauth.started',

        userId,
        agentId,

        createdAt:
          new Date(
            now(),
          ).toISOString(),
      });

      return send(
        res,
        200,
        {
          ok: true,

          authorizationUrl:
            request.authorizationUrl,

          expiresAt:
            request.expiresAt,

          agentId,
        },
      );
    } catch {
      return send(
        res,
        401,
        {
          ok: false,

          code:
            'AUTHENTICATION_OR_STATE_FAILED',
        },
      );
    }
  }

  async function callback(
    req,
    res,
  ) {
    const at =
      now();

    const nowIso =
      new Date(
        at,
      ).toISOString();

    try {
      const callbackResult =
        validateZoomOAuthCallback(
          (
            req &&
            req.query
          ) || {},
          config.oauthStateSecret,
          {
            nowMs: at,
          },
        );

      if (!callbackResult.ok) {
        return send(
          res,
          400,
          {
            ok: false,
            code:
              'ZOOM_OAUTH_DENIED',

            error:
              callbackResult.error,
          },
        );
      }

      if (
        !(
          await ownsAgent({
            userId:
              callbackResult.userId,

            agentId:
              callbackResult.agentId,
          })
        )
      ) {
        return send(
          res,
          403,
          {
            ok: false,
            code:
              'AGENT_NOT_OWNED',
          },
        );
      }

      const consumedNonce =
        await store.nonce.consume({
          nonceHash:
            callbackResult.nonceHash,

          userId:
            callbackResult.userId,

          agentId:
            callbackResult.agentId,

          nowIso,
        });

      if (!consumedNonce) {
        return send(
          res,
          409,
          {
            ok: false,

            code:
              'OAUTH_STATE_REPLAY_OR_EXPIRED',
          },
        );
      }

      const tokens =
        await exchangeCode({
          code:
            callbackResult.code,

          redirectUri:
            config.redirectUri,

          clientId:
            config.clientId,

          clientSecret:
            config.clientSecret,

          tokenUrl:
            config.tokenUrl,
        });

      const connectionId =
        newId();

      const accountId =
        text(
          tokens.account_id ||
          tokens.accountId,
          'accountId',
          512,
        );

      const tokenEnvelope =
        encryptZoomTokens(
          tokens,
          config.tokenEncryptionKey,
          {
            userId:
              callbackResult.userId,

            connectionId,
          },
        );

      const scopes =
        Array.isArray(
          tokens.scope,
        )
          ? tokens.scope
          : String(
              tokens.scope ||
              '',
            )
              .split(
                /[ ,]+/,
              )
              .filter(Boolean);

      await store.connection.upsert({
        id:
          connectionId,

        userId:
          callbackResult.userId,

        agentId:
          callbackResult.agentId,

        accountId,
        tokenEnvelope,
        scopes,

        status:
          'connected',

        connectedAt:
          nowIso,
      });

      await store.audit.record({
        type:
          'zoom.oauth.connected',

        userId:
          callbackResult.userId,

        agentId:
          callbackResult.agentId,

        connectionId,

        createdAt:
          nowIso,

        metadata: {
          accountId,
          scopes,
        },
      });

      return send(
        res,
        200,
        {
          ok: true,
          connected: true,
          connectionId,

          agentId:
            callbackResult.agentId,

          returnPath:
            callbackResult.returnPath,
        },
      );
    } catch {
      return send(
        res,
        400,
        {
          ok: false,

          code:
            'OAUTH_CALLBACK_FAILED',
        },
      );
    }
  }

  async function status(
    req,
    res,
  ) {
    try {
      const userId =
        text(
          (
            await authenticate(
              req,
            )
          ).userId,
          'userId',
          256,
        );

      const agentId =
        text(
          req.query.agentId,
          'agentId',
          256,
        );

      if (
        !(
          await ownsAgent({
            userId,
            agentId,
          })
        )
      ) {
        return send(
          res,
          403,
          {
            ok: false,
            code:
              'AGENT_NOT_OWNED',
          },
        );
      }

      const connection =
        await store.connection.find({
          userId,
          agentId,
        });

      return send(
        res,
        200,
        {
          ok: true,

          enabled:
            Boolean(
              config.enabled,
            ),

          connected:
            Boolean(
              connection,
            ),

          agentId,

          accountId:
            connection
              ? connection.accountId
              : null,

          scopes:
            connection
              ? connection.scopes
              : [],
        },
      );
    } catch {
      return send(
        res,
        401,
        {
          ok: false,

          code:
            'AUTHENTICATION_FAILED',
        },
      );
    }
  }

  async function webhook(
    req,
    res,
  ) {
    const at =
      now();

    const rawBody =
      req &&
      req.rawBody;

    const verified =
      verifyZoomWebhookSignature({
        secretToken:
          config.webhookSecretToken,

        timestamp:
          header(
            req,
            'x-zm-request-timestamp',
          ),

        signature:
          header(
            req,
            'x-zm-signature',
          ),

        rawBody,
        nowMs: at,

        maxSkewSeconds:
          config.webhookMaxSkewSeconds ||
          300,
      });

    if (
      !config.enabled ||
      !config.rtmsEnabled
    ) {
      return send(
        res,
        503,
        {
          ok: false,

          code:
            'ZOOM_RTMS_DISABLED',
        },
      );
    }

    if (!verified.ok) {
      return send(
        res,
        401,
        {
          ok: false,

          code:
            'INVALID_ZOOM_SIGNATURE',
        },
      );
    }

    try {
      const event =
        normalizeZoomEvent(
          rawBody,
        );

      if (
        event.kind ===
        'url_validation'
      ) {
        return send(
          res,
          200,
          buildZoomUrlValidationResponse(
            event.plainToken,
            config.webhookSecretToken,
          ),
        );
      }

      if (
        ![
          'rtms_started',
          'rtms_stopped',
        ].includes(
          event.kind,
        )
      ) {
        return send(
          res,
          202,
          {
            ok: true,
            accepted: false,
          },
        );
      }

      const result =
        await store.event.accept({
          ...event,

          receivedAt:
            new Date(
              at,
            ).toISOString(),
        });

      if (result.accepted) {
        await store.audit.record({
          type:
            `zoom.${event.kind}`,

          createdAt:
            new Date(
              at,
            ).toISOString(),

          metadata: {
            eventId:
              event.eventId,

            meetingUuid:
              event.meetingUuid,

            streamId:
              event.streamId,
          },
        });
      }

      return send(
        res,
        200,
        {
          ok: true,
          ...result,
        },
      );
    } catch {
      return send(
        res,
        400,
        {
          ok: false,

          code:
            'ZOOM_EVENT_INVALID',
        },
      );
    }
  }

  return Object.freeze({
    start,
    callback,
    status,
    webhook,
  });
}

module.exports = {
  ROUTES,
  createMemoryZoomStore,
  createZoomHandlers,
  rejectPlaintextTokens,
};
