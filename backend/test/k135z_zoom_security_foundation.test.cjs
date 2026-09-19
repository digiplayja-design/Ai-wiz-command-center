'use strict';

const test =
  require('node:test');

const assert =
  require('node:assert/strict');

const crypto =
  require('node:crypto');

const {
  buildZoomUrlValidationResponse,
  buildZoomWebhookSignature,
  createOAuthState,
  readZoomConfig,
  summarizeZoomConfig,
  validateZoomConfig,
  verifyOAuthState,
  verifyZoomWebhookSignature,
} = require(
  '../k135z_zoom/index.cjs',
);

test(
  'disabled Zoom configuration remains fail-closed without credentials',
  () => {
    const config =
      readZoomConfig({});

    assert.equal(
      config.enabled,
      false,
    );

    assert.equal(
      config.rtmsEnabled,
      false,
    );

    assert.deepEqual(
      validateZoomConfig(
        config,
      ),
      {
        ok: true,
        missing: [],
        invalid: [],
      },
    );
  },
);

test(
  'enabled configuration reports variable names without secret values',
  () => {
    const config =
      readZoomConfig({
        KORLIX_ZOOM_ENABLED:
          'true',
      });

    const summary =
      summarizeZoomConfig(
        config,
      );

    assert.equal(
      summary.enabled,
      true,
    );

    assert.equal(
      summary.validation.ok,
      false,
    );

    assert.ok(
      summary.validation.missing
        .includes(
          'KORLIX_ZOOM_CLIENT_SECRET',
        ),
    );

    assert.equal(
      JSON.stringify(summary)
        .includes(
          'secret-value',
        ),
      false,
    );
  },
);

test(
  'OAuth state is user/agent-bound, short-lived and tamper-evident',
  () => {
    const secret =
      's'.repeat(64);

    const nowMs =
      1_800_000_000_000;

    const state =
      createOAuthState(
        {
          userId: 'user-1',
          agentId: 'nova-1',
          returnPath:
            '/meeting-copilot',
        },
        secret,
        {
          nowMs,
          ttlSeconds: 600,
          nonce:
            'fixed-nonce',
        },
      );

    const payload =
      verifyOAuthState(
        state,
        secret,
        {
          nowMs:
            nowMs + 5_000,
        },
      );

    assert.equal(
      payload.sub,
      'user-1',
    );

    assert.equal(
      payload.agent,
      'nova-1',
    );

    assert.equal(
      payload.returnPath,
      '/meeting-copilot',
    );

    assert.throws(
      () =>
        verifyOAuthState(
          `${state}x`,
          secret,
          { nowMs },
        ),
      /signature|Malformed/,
    );

    assert.throws(
      () =>
        verifyOAuthState(
          state,
          secret,
          {
            nowMs:
              nowMs + 700_000,
            clockSkewSeconds:
              0,
          },
        ),
      /expired/,
    );
  },
);

test(
  'Zoom webhook verification accepts current signatures and rejects stale ones',
  () => {
    const secretToken =
      'webhook-secret';

    const timestamp =
      1_800_000_000;

    const rawBody =
      JSON.stringify({
        event:
          'meeting.rtms_started',

        payload: {
          account_id:
            'account-1',
        },
      });

    const signature =
      buildZoomWebhookSignature({
        secretToken,
        timestamp,
        rawBody,
      });

    assert.deepEqual(
      verifyZoomWebhookSignature({
        secretToken,
        timestamp,
        rawBody,
        signature,
        nowMs:
          timestamp * 1000,
      }),
      {
        ok: true,
        reason: 'verified',
      },
    );

    assert.deepEqual(
      verifyZoomWebhookSignature({
        secretToken,
        timestamp,
        rawBody,
        signature,
        nowMs:
          (
            timestamp +
            301
          ) * 1000,
      }),
      {
        ok: false,
        reason:
          'timestamp_outside_window',
      },
    );
  },
);

test(
  'Zoom URL-validation response uses HMAC SHA-256',
  () => {
    const plainToken =
      'plain-token';

    const secretToken =
      'webhook-secret';

    const response =
      buildZoomUrlValidationResponse(
        plainToken,
        secretToken,
      );

    const expected =
      crypto
        .createHmac(
          'sha256',
          secretToken,
        )
        .update(
          plainToken,
        )
        .digest('hex');

    assert.deepEqual(
      response,
      {
        plainToken,
        encryptedToken:
          expected,
      },
    );
  },
);
