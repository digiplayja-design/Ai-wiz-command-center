'use strict';

const test =
  require('node:test');

const assert =
  require('node:assert/strict');

const {
  RtmsSession,
  buildZoomAuthorizationRequest,
  decryptZoomTokens,
  encryptZoomTokens,
  normalizeZoomEvent,
  validateZoomOAuthCallback,
} = require(
  '../k135z_zoom/index.cjs',
);

const secret =
  's'.repeat(64);

const now =
  1800000000000;

const config = {
  clientId: 'client',

  redirectUri:
    'https://example.com/callback',

  authorizeUrl:
    'https://zoom.us/oauth/authorize',
};

test(
  'OAuth request binds KORLIX user and Nova agent',
  () => {
    const request =
      buildZoomAuthorizationRequest(
        {
          config,
          userId: 'u1',
          agentId: 'nova',

          returnPath:
            '/meeting-copilot',
        },
        secret,
        {
          nowMs: now,
          nonce: 'n1',
        },
      );

    const callback =
      validateZoomOAuthCallback(
        {
          code: 'c1',
          state:
            request.state,
        },
        secret,
        {
          nowMs:
            now + 1000,
        },
      );

    assert.equal(
      callback.userId,
      'u1',
    );

    assert.equal(
      callback.agentId,
      'nova',
    );

    assert.equal(
      callback.nonceHash,
      request.nonceHash,
    );
  },
);

test(
  'OAuth denial remains fail-closed',
  () => {
    assert.deepEqual(
      validateZoomOAuthCallback(
        {
          error:
            'access_denied',

          error_description:
            'declined',
        },
        secret,
      ),
      {
        ok: false,
        error:
          'access_denied',
        description:
          'declined',
      },
    );
  },
);

test(
  'token envelope encrypts and authenticates Zoom tokens',
  () => {
    const context = {
      userId: 'u1',
      connectionId: 'c1',
    };

    const key =
      'k'.repeat(64);

    const envelope =
      encryptZoomTokens(
        {
          access_token:
            'access',

          refresh_token:
            'refresh',
        },
        key,
        context,
        {
          iv:
            Buffer.alloc(
              12,
              4,
            ),
        },
      );

    assert.equal(
      JSON.stringify(
        envelope,
      ).includes(
        'access',
      ),
      false,
    );

    assert.equal(
      decryptZoomTokens(
        envelope,
        key,
        context,
      ).refresh_token,
      'refresh',
    );

    const bad = {
      ...envelope,

      tag:
        `${envelope.tag.slice(
          0,
          -1,
        )}A`,
    };

    assert.throws(
      () =>
        decryptZoomTokens(
          bad,
          key,
          context,
        ),
      /authentication failed/,
    );
  },
);

test(
  'RTMS lifecycle bills active time only',
  () => {
    const session =
      new RtmsSession({
        sessionId: 's1',
        meetingUuid: 'm1',
        streamId: 'r1',
      });

    session.apply({
      type: 'started',
      eventId: 'e1',
      atMs: 1000,
    });

    session.apply({
      type: 'paused',
      eventId: 'e2',
      atMs: 6000,
    });

    session.apply({
      type: 'resumed',
      eventId: 'e3',
      atMs: 10000,
    });

    const end =
      session.apply({
        type: 'stopped',
        eventId: 'e4',
        atMs: 13000,
      });

    assert.equal(
      end.usage.activeMs,
      8000,
    );
  },
);

test(
  'RTMS lifecycle ignores replayed event IDs',
  () => {
    const session =
      new RtmsSession({
        sessionId: 's2',
        meetingUuid: 'm2',
      });

    session.apply({
      type: 'started',
      eventId: 'e1',
      atMs: 1000,
    });

    assert.equal(
      session.apply({
        type: 'started',
        eventId: 'e1',
        atMs: 1000,
      }).duplicate,
      true,
    );
  },
);

test(
  'Zoom RTMS events normalize meeting and stream identifiers',
  () => {
    const event =
      normalizeZoomEvent(
        JSON.stringify({
          event:
            'meeting.rtms_started',

          event_id:
            'z1',

          payload: {
            account_id:
              'a1',

            object: {
              uuid: 'm1',
              id: 7,

              rtms_stream_id:
                'r1',
            },
          },
        }),
      );

    assert.equal(
      event.kind,
      'rtms_started',
    );

    assert.equal(
      event.meetingUuid,
      'm1',
    );

    assert.equal(
      event.streamId,
      'r1',
    );
  },
);
