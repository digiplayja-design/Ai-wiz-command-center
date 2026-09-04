'use strict';

const test =
  require('node:test');

const assert =
  require('node:assert/strict');

const fs =
  require('node:fs');

const path =
  require('node:path');

const {
  buildZoomWebhookSignature,
  createMemoryZoomStore,
  createZoomHandlers,
  rejectPlaintextTokens,
} = require(
  '../k135z_zoom/index.cjs',
);

const now =
  1800000000000;

const config = {
  enabled: true,
  rtmsEnabled: true,
  clientId: 'client',

  clientSecret:
    'client-secret',

  redirectUri:
    'https://example.com/callback',

  authorizeUrl:
    'https://zoom.us/oauth/authorize',

  tokenUrl:
    'https://zoom.us/oauth/token',

  oauthStateSecret:
    's'.repeat(64),

  tokenEncryptionKey:
    'k'.repeat(64),

  webhookSecretToken:
    'webhook-secret',

  webhookMaxSkewSeconds:
    300,
};

function res() {
  return {
    statusCode: 0,
    body: null,

    status(code) {
      this.statusCode =
        code;

      return this;
    },

    json(body) {
      this.body =
        body;

      return this;
    },
  };
}

function setup(
  overrides = {},
) {
  const store =
    overrides.store ||
    createMemoryZoomStore();

  return {
    store,

    h: createZoomHandlers({
      config,

      authenticate:
        async () => ({
          userId: 'u1',
        }),

      ownsAgent:
        async ({
          userId,
          agentId,
        }) =>
          userId === 'u1' &&
          agentId === 'nova',

      exchangeCode:
        async () => ({
          account_id: 'a1',

          access_token:
            'access',

          refresh_token:
            'refresh',

          scope:
            'meeting:read:meeting_transcript',
        }),

      store,

      nowMs:
        () => now,

      newId:
        () => 'c1',

      ...overrides,
    }),
  };
}

test(
  'OAuth start requires authentication',
  async () => {
    const {
      h,
    } = setup({
      authenticate:
        async () => {
          throw new Error(
            'no',
          );
        },
    });

    const response =
      res();

    await h.start(
      {
        body: {
          agentId:
            'nova',
        },
      },
      response,
    );

    assert.equal(
      response.statusCode,
      401,
    );
  },
);

test(
  'OAuth start stores one nonce and checks agent ownership',
  async () => {
    const {
      h,
      store,
    } = setup();

    const response =
      res();

    await h.start(
      {
        body: {
          agentId:
            'nova',
        },
      },
      response,
    );

    assert.equal(
      response.statusCode,
      200,
    );

    assert.equal(
      store.nonce.size(),
      1,
    );
  },
);

test(
  'OAuth callback consumes state and stores encrypted tokens',
  async () => {
    const {
      h,
      store,
    } = setup();

    const authorizationResponse =
      res();

    await h.start(
      {
        body: {
          agentId:
            'nova',
        },
      },
      authorizationResponse,
    );

    const state =
      new URL(
        authorizationResponse
          .body
          .authorizationUrl,
      ).searchParams.get(
        'state',
      );

    const callbackResponse =
      res();

    await h.callback(
      {
        query: {
          code: 'code',
          state,
        },
      },
      callbackResponse,
    );

    assert.equal(
      callbackResponse.statusCode,
      200,
    );

    const connection =
      await store.connection.find({
        userId: 'u1',
        agentId: 'nova',
      });

    assert.equal(
      JSON.stringify(
        connection,
      ).includes(
        'access',
      ),
      false,
    );
  },
);

test(
  'OAuth callback rejects state replay',
  async () => {
    const {
      h,
    } = setup();

    const authorizationResponse =
      res();

    await h.start(
      {
        body: {
          agentId:
            'nova',
        },
      },
      authorizationResponse,
    );

    const state =
      new URL(
        authorizationResponse
          .body
          .authorizationUrl,
      ).searchParams.get(
        'state',
      );

    const first =
      res();

    const second =
      res();

    await h.callback(
      {
        query: {
          code: 'c1',
          state,
        },
      },
      first,
    );

    await h.callback(
      {
        query: {
          code: 'c2',
          state,
        },
      },
      second,
    );

    assert.equal(
      second.statusCode,
      409,
    );
  },
);

test(
  'status never returns encrypted or plaintext tokens',
  async () => {
    const {
      h,
    } = setup();

    const authorizationResponse =
      res();

    await h.start(
      {
        body: {
          agentId:
            'nova',
        },
      },
      authorizationResponse,
    );

    const state =
      new URL(
        authorizationResponse
          .body
          .authorizationUrl,
      ).searchParams.get(
        'state',
      );

    await h.callback(
      {
        query: {
          code: 'c',
          state,
        },
      },
      res(),
    );

    const statusResponse =
      res();

    await h.status(
      {
        query: {
          agentId:
            'nova',
        },
      },
      statusResponse,
    );

    assert.equal(
      JSON.stringify(
        statusResponse.body,
      ).includes(
        'token',
      ),
      false,
    );
  },
);

test(
  'Zoom URL validation requires HMAC and returns challenge',
  async () => {
    const {
      h,
    } = setup();

    const rawBody =
      JSON.stringify({
        event:
          'endpoint.url_validation',

        payload: {
          plainToken:
            'p1',
        },
      });

    const timestamp =
      Math.floor(
        now / 1000,
      );

    const signature =
      buildZoomWebhookSignature({
        secretToken:
          config.webhookSecretToken,

        timestamp,
        rawBody,
      });

    const response =
      res();

    await h.webhook(
      {
        rawBody,

        headers: {
          'x-zm-request-timestamp':
            String(timestamp),

          'x-zm-signature':
            signature,
        },
      },
      response,
    );

    assert.equal(
      response.statusCode,
      200,
    );

    assert.equal(
      response.body.plainToken,
      'p1',
    );
  },
);

test(
  'RTMS webhook ledger is replay-safe',
  async () => {
    const {
      h,
      store,
    } = setup();

    const rawBody =
      JSON.stringify({
        event:
          'meeting.rtms_started',

        event_id:
          'e1',

        payload: {
          object: {
            uuid: 'm1',

            rtms_stream_id:
              's1',
          },
        },
      });

    const timestamp =
      Math.floor(
        now / 1000,
      );

    const signature =
      buildZoomWebhookSignature({
        secretToken:
          config.webhookSecretToken,

        timestamp,
        rawBody,
      });

    const request = {
      rawBody,

      headers: {
        'x-zm-request-timestamp':
          String(timestamp),

        'x-zm-signature':
          signature,
      },
    };

    const first =
      res();

    const second =
      res();

    await h.webhook(
      request,
      first,
    );

    await h.webhook(
      request,
      second,
    );

    assert.equal(
      first.body.accepted,
      true,
    );

    assert.equal(
      second.body.duplicate,
      true,
    );

    assert.equal(
      store.event.size(),
      1,
    );
  },
);

test(
  'invalid webhook signature is rejected before storage',
  async () => {
    const {
      h,
      store,
    } = setup();

    const response =
      res();

    await h.webhook(
      {
        rawBody: '{}',

        headers: {
          'x-zm-request-timestamp':
            String(
              Math.floor(
                now / 1000,
              ),
            ),

          'x-zm-signature':
            `v0=${'0'.repeat(
              64,
            )}`,
        },
      },
      response,
    );

    assert.equal(
      response.statusCode,
      401,
    );

    assert.equal(
      store.event.size(),
      0,
    );
  },
);

test(
  'storage and migration forbid plaintext token columns',
  () => {
    assert.throws(
      () =>
        rejectPlaintextTokens({
          accessToken: 'x',
        }),
      /Plaintext/,
    );

    const sql =
      fs
        .readFileSync(
          path.resolve(
            __dirname,
            '../../supabase/migrations/202609040001_k135z_zoom_b1_foundation.sql',
          ),
          'utf8',
        )
        .toLowerCase();

    assert.match(
      sql,
      /enable row level security/,
    );

    assert.match(
      sql,
      /token_envelope jsonb not null/,
    );

    assert.doesNotMatch(
      sql,
      /drop table|truncate|delete from|access_token\s+text|refresh_token\s+text/,
    );
  },
);
