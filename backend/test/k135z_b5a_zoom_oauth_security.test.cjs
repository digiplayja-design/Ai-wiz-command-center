"use strict";

const test = require("node:test");
const assert = require(
  "node:assert/strict",
);
const crypto = require(
  "node:crypto",
);
const fs = require(
  "node:fs",
);

const {
  EnvelopeCipher,
  MemoryZoomRepository,
  ZoomTokenVault,
} = require(
  "../k135z_zoom/zoom_token_vault.cjs",
);

const {
  ZoomOAuthService,
} = require(
  "../k135z_zoom/zoom_oauth_service.cjs",
);

const {
  ZoomMeetingDiscovery,
} = require(
  "../k135z_zoom/zoom_meeting_discovery.cjs",
);

const {
  ZoomWebhookVerifier,
} = require(
  "../k135z_zoom/zoom_webhook_verifier.cjs",
);

const {
  ZoomRtmsSessionManager,
} = require(
  "../k135z_zoom/zoom_rtms_session_manager.cjs",
);

const {
  createK135zZoomHandlers,
  isEnterprisePrincipal,
  registerK135zZoomRoutes,
} = require(
  "../k135z_zoom/zoom_routes.cjs",
);

function principal(
  tier = "enterprise",
) {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    tenantId: "tenant-1",
    agentId: "agent-1",
    app_metadata: {tier},
  };
}

function response() {
  return {
    statusCode: 200,
    body: null,
    redirectLocation: null,

    status(value) {
      this.statusCode = value;
      return this;
    },

    json(value) {
      this.body = value;
      return value;
    },

    redirect(
      status,
      value,
    ) {
      this.statusCode = status;
      this.redirectLocation =
        value;

      return value;
    },
  };
}

function makeFixture({
  nowMs =
    1800000000000,
} = {}) {
  const clock =
    () => nowMs;

  const repository =
    new MemoryZoomRepository();

  const cipher =
    new EnvelopeCipher(
      Buffer.alloc(
        32,
        7,
      ),
    );

  const tokenVault =
    new ZoomTokenVault({
      repository,
      cipher,
      clock,
    });

  const calls = [];

  const transport = {
    liveEnabled: false,

    async exchangeAuthorizationCode(
      input,
    ) {
      calls.push([
        "exchange",
        input,
      ]);

      return {
        access_token:
          "access-one",

        refresh_token:
          "refresh-one",

        token_type:
          "bearer",

        expires_in:
          3600,

        scope:
          "meeting:read:list_upcoming_meetings",

        api_url:
          "https://api.zoom.us",

        account_id:
          "zoom-account-1",

        user_id:
          "zoom-user-1",
      };
    },

    async refreshAccessToken(
      input,
    ) {
      calls.push([
        "refresh",
        input,
      ]);

      return {
        access_token:
          "access-two",

        refresh_token:
          "refresh-two",

        token_type:
          "bearer",

        expires_in:
          3600,

        scope:
          "meeting:read:list_upcoming_meetings",

        api_url:
          "https://api.zoom.us",
      };
    },

    async listUpcomingMeetings(
      input,
    ) {
      calls.push([
        "upcoming",
        input,
      ]);

      return {
        meetings: [
          {
            id:
              "9876543210123",

            uuid:
              "uuid-1",

            topic:
              "Investor meeting",

            start_time:
              "2026-09-07T15:00:00Z",

            duration:
              45,

            timezone:
              "America/New_York",

            is_host:
              true,

            join_url:
              "https://example.invalid/join",

            passcode:
              "secret-passcode",
          },
        ],
      };
    },
  };

  const oauthService =
    new ZoomOAuthService({
      repository,
      tokenVault,
      transport,
      clock,
      authorizeStoredIdentity: async () => true, // Offline fixture; real adapter is a separate integration gate.

      config: {
        clientId:
          "client-id",

        clientSecret:
          "client-secret",

        redirectUri:
          "https://api.korlix.test/api/k135z/zoom/oauth/callback",

        allowedReturnOrigins: [
          "https://app.korlix.test",
        ],

        stateTtlMs:
          600000,
      },
    });

  return {
    clock,
    repository,
    cipher,
    tokenVault,
    transport,
    oauthService,
    calls,

    setNow(value) {
      nowMs = value;
    },
  };
}

async function connect(
  fixture,
) {
  const start =
    await fixture
      .oauthService
      .startAuthorization({
        principal:
          principal(),

        returnTo:
          "https://app.korlix.test/#/meeting-copilot",
      });

  const state =
    new URL(
      start.authorizationUrl,
    ).searchParams.get(
      "state",
    );

  await fixture
    .oauthService
    .completeAuthorization({
      code: "code-1",
      state,
    });

  return state;
}

test(
  "OAuth start creates a backend-owned one-time state and exact authorization URL",
  async () => {
    const fixture =
      makeFixture();

    const result =
      await fixture
        .oauthService
        .startAuthorization({
          principal:
            principal(),

          returnTo:
            "https://app.korlix.test/#/meeting-copilot",
        });

    const url =
      new URL(
        result.authorizationUrl,
      );

    assert.equal(
      url.origin,
      "https://zoom.us",
    );

    assert.equal(
      url.pathname,
      "/oauth/authorize",
    );

    assert.equal(
      url.searchParams.get(
        "response_type",
      ),
      "code",
    );

    assert.equal(
      url.searchParams.get(
        "client_id",
      ),
      "client-id",
    );

    assert.ok(
      url.searchParams
        .get("state")
        .length >= 40,
    );
  },
);

test(
  "OAuth state cannot be replayed",
  async () => {
    const fixture =
      makeFixture();

    const state =
      await connect(
        fixture,
      );

    await assert.rejects(
      fixture
        .oauthService
        .completeAuthorization({
          code: "code-2",
          state,
        }),

      (error) =>
        error.code ===
        "ZOOM_OAUTH_STATE_REPLAYED",
    );
  },
);

test(
  "OAuth state expires fail closed",
  async () => {
    const fixture =
      makeFixture();

    const result =
      await fixture
        .oauthService
        .startAuthorization({
          principal:
            principal(),
        });

    const state =
      new URL(
        result.authorizationUrl,
      ).searchParams.get(
        "state",
      );

    fixture.setNow(
      1800000700001,
    );

    await assert.rejects(
      fixture
        .oauthService
        .completeAuthorization({
          code: "code-1",
          state,
        }),

      (error) =>
        error.code ===
        "ZOOM_OAUTH_STATE_EXPIRED",
    );
  },
);

test(
  "token vault stores ciphertext rather than plaintext",
  async () => {
    const fixture =
      makeFixture();

    await connect(fixture);

    const record =
      await fixture
        .repository
        .getConnection(
          JSON.stringify(["tenant-1", "11111111-1111-4111-8111-111111111111", "agent-1"]),
        );

    const serialized =
      JSON.stringify(record);

    assert.equal(
      serialized.includes(
        "access-one",
      ),
      false,
    );

    assert.equal(
      serialized.includes(
        "refresh-one",
      ),
      false,
    );

    const decrypted =
      fixture.cipher.decrypt(
        record.encryptedTokens, record.key,
      );

    assert.equal(
      decrypted.accessToken,
      "access-one",
    );
  },
);

test(
  "public status never returns token material",
  async () => {
    const fixture =
      makeFixture();

    await connect(fixture);

    const status =
      await fixture
        .oauthService
        .getStatus(
          principal(),
        );

    const serialized =
      JSON.stringify(status);

    assert.equal(
      status.connected,
      true,
    );

    assert.equal(
      serialized.includes(
        "access-one",
      ),
      false,
    );

    assert.equal(
      serialized.includes(
        "refresh-one",
      ),
      false,
    );
  },
);

test(
  "expired access token rotates through the latest refresh token",
  async () => {
    const fixture =
      makeFixture();

    await connect(fixture);

    fixture.setNow(
      1800003700000,
    );

    const authorized =
      await fixture
        .oauthService
        .getAuthorizedAccess(
          principal(),
        );

    assert.equal(
      authorized.accessToken,
      "access-two",
    );

    assert.equal(
      fixture.calls.some(
        ([kind]) =>
          kind === "refresh",
      ),
      true,
    );
  },
);

test(
  "meeting discovery strips join URL and passcode",
  async () => {
    const fixture =
      makeFixture();

    await connect(fixture);

    const discovery =
      new ZoomMeetingDiscovery({
        oauthService:
          fixture.oauthService,

        transport:
          fixture.transport,
      });

    const result =
      await discovery
        .listUpcoming(
          principal(),
        );

    assert.equal(
      result.count,
      1,
    );

    assert.equal(
      result.meetings[0].id,
      "9876543210123",
    );

    assert.equal(
      Object.hasOwn(
        result.meetings[0],
        "join_url",
      ),
      false,
    );

    assert.equal(
      Object.hasOwn(
        result.meetings[0],
        "passcode",
      ),
      false,
    );
  },
);

test(
  "webhook verifier accepts a correct x-zm-signature",
  () => {
    const nowMs =
      1800000000000;

    const verifier =
      new ZoomWebhookVerifier({
        secret:
          "webhook-secret",

        clock:
          () => nowMs,
      });

    const rawBody =
      JSON.stringify({
        event:
          "meeting.rtms_started",

        event_ts:
          nowMs,
      });

    const timestamp =
      String(
        Math.floor(
          nowMs / 1000,
        ),
      );

    const signature =
      verifier.sign({
        timestamp,
        rawBody,
      });

    const verified =
      verifier.verifyRequest({
        headers: {
          "x-zm-request-timestamp":
            timestamp,

          "x-zm-signature":
            signature,
        },

        rawBody,
      });

    assert.equal(
      verified.body.event,
      "meeting.rtms_started",
    );
  },
);

test(
  "webhook verifier rejects an invalid signature",
  () => {
    const nowMs =
      1800000000000;

    const verifier =
      new ZoomWebhookVerifier({
        secret:
          "webhook-secret",

        clock:
          () => nowMs,
      });

    assert.throws(
      () =>
        verifier.verifyRequest({
          headers: {
            "x-zm-request-timestamp":
              String(
                Math.floor(
                  nowMs / 1000,
                ),
              ),

            "x-zm-signature":
              "v0=invalid",
          },

          rawBody:
            JSON.stringify({
              event:
                "endpoint.url_validation",
            }),
        }),

      (error) =>
        error.code ===
        "ZOOM_WEBHOOK_SIGNATURE_INVALID",
    );
  },
);

test(
  "endpoint validation response hashes the plain token",
  () => {
    const verifier =
      new ZoomWebhookVerifier({
        secret:
          "webhook-secret",
      });

    const responseValue =
      verifier
        .createEndpointValidationResponse(
          "plain-token",
        );

    const expected =
      crypto
        .createHmac(
          "sha256",
          "webhook-secret",
        )
        .update(
          "plain-token",
        )
        .digest("hex");

    assert.deepEqual(
      responseValue,
      {
        plainToken:
          "plain-token",

        encryptedToken:
          expected,
      },
    );
  },
);

test(
  "Enterprise detection is exact and fail closed",
  () => {
    assert.equal(
      isEnterprisePrincipal(
        principal(
          "enterprise",
        ),
      ),
      true,
    );

    assert.equal(
      isEnterprisePrincipal(
        principal(
          "enterprise_plus",
        ),
      ),
      true,
    );

    assert.equal(
      isEnterprisePrincipal(
        principal(
          "non_enterprise",
        ),
      ),
      false,
    );

    assert.equal(
      isEnterprisePrincipal(
        principal("pro"),
      ),
      false,
    );
  },
);

test(
  "protected handler blocks non-Enterprise users before OAuth state creation",
  async () => {
    const fixture =
      makeFixture();

    const handlers =
      createK135zZoomHandlers({
        ...fixture,

        meetingDiscovery:
          new ZoomMeetingDiscovery({
            oauthService:
              fixture.oauthService,

            transport:
              fixture.transport,
          }),

        webhookVerifier:
          new ZoomWebhookVerifier({
            secret:
              "webhook-secret",

            clock:
              fixture.clock,
          }),

        rtmsSessionManager:
          new ZoomRtmsSessionManager({
            repository:
              fixture.repository,

            clock:
              fixture.clock,
          }),

        authenticateRequest:
          async (req) =>
            req.user,

        resolveEnterprise:
          async (user) =>
            isEnterprisePrincipal(
              user,
            ),
      });

    const res =
      response();

    await handlers.start(
      {
        user:
          principal("pro"),

        query: {},
      },
      res,
    );

    assert.equal(
      res.statusCode,
      403,
    );

    assert.equal(
      res.body.error.code,
      "KORLIX_ENTERPRISE_REQUIRED",
    );
  },
);

test(
  "verified deauthorization deletes matching encrypted connections",
  async () => {
    const fixture =
      makeFixture();

    await connect(fixture);

    const verifier =
      new ZoomWebhookVerifier({
        secret:
          "webhook-secret",

        clock:
          fixture.clock,
      });

    const handlers =
      createK135zZoomHandlers({
        ...fixture,

        meetingDiscovery:
          new ZoomMeetingDiscovery({
            oauthService:
              fixture.oauthService,

            transport:
              fixture.transport,
          }),

        webhookVerifier:
          verifier,

        rtmsSessionManager:
          new ZoomRtmsSessionManager({
            repository:
              fixture.repository,

            clock:
              fixture.clock,
          }),

        authenticateRequest:
          async (req) =>
            req.user,

        resolveEnterprise:
          async (user) =>
            isEnterprisePrincipal(
              user,
            ),
      });

    const body = {
      event:
        "app_deauthorized",

      event_ts:
        fixture.clock(),

      payload: {
        account_id:
          "zoom-account-1",

        user_id:
          "zoom-user-1",
      },
    };

    const rawBody =
      JSON.stringify(body);

    const timestamp =
      String(
        Math.floor(
          fixture.clock() /
            1000,
        ),
      );

    const res =
      response();

    await handlers
      .deauthorization(
        {
          headers: {
            "x-zm-request-timestamp":
              timestamp,

            "x-zm-signature":
              verifier.sign({
                timestamp,
                rawBody,
              }),
          },

          rawBody,
        },
        res,
      );

    assert.equal(
      res.statusCode,
      200,
    );

    assert.equal(
      res.body
        .deleted_connections,
      1,
    );

    assert.equal(
      (
        await fixture
          .oauthService
          .getStatus(
            principal(),
          )
      ).connected,
      false,
    );
  },
);

test(
  "RTMS lifecycle manager stores metadata only and never marks media collected",
  async () => {
    const fixture =
      makeFixture();

    const manager =
      new ZoomRtmsSessionManager({
        repository:
          fixture.repository,

        clock:
          fixture.clock,
      });

    const result =
      await manager
        .handleVerifiedEvent({
          event:
            "meeting.rtms_started",

          event_ts:
            fixture.clock(),

          payload: {
            object: {
              id:
                "123456789",

              uuid:
                "uuid-rtms",

              rtms_stream_id:
                "stream-1",

              server_urls: [
                "wss://sensitive.example.invalid",
              ],
            },
          },
        });

    assert.equal(
      result.handled,
      true,
    );

    assert.equal(
      result.record
        .mediaConnected,
      false,
    );

    assert.equal(
      result.record
        .transcriptCollected,
      false,
    );

    assert.equal(
      JSON.stringify(
        result.record,
      ).includes(
        "server_urls",
      ),
      false,
    );
  },
);

test(
  "route registrar exposes all seven B5A routes",
  () => {
    const calls = [];

    const app = {
      get(path) {
        calls.push([
          "GET",
          path,
        ]);
      },

      post(path) {
        calls.push([
          "POST",
          path,
        ]);
      },

      delete(path) {
        calls.push([
          "DELETE",
          path,
        ]);
      },
    };

    const fixture =
      makeFixture();

    registerK135zZoomRoutes(
      app,
      {
        ...fixture,

        webhookVerifier:
          new ZoomWebhookVerifier({
            secret:
              "webhook-secret",

            clock:
              fixture.clock,
          }),

        authenticateRequest:
          async (req) =>
            req.user,

        resolveEnterprise:
          async (user) =>
            isEnterprisePrincipal(
              user,
            ),
      },
    );

    assert.equal(
      calls.length,
      7,
    );

    assert.deepEqual(
      calls.map(
        ([method, path]) =>
          `${method} ${path}`,
      ),
      [
        "GET /api/k135z/zoom/oauth/start",
        "GET /api/k135z/zoom/oauth/callback",
        "GET /api/k135z/zoom/status",
        "DELETE /api/k135z/zoom/connection",
        "GET /api/k135z/zoom/meetings/upcoming",
        "POST /api/k135z/zoom/webhook",
        "POST /api/k135z/zoom/deauthorization",
      ],
    );
  },
);

test(
  "backend startup registers the B5A route module once",
  () => {
    const source =
      fs.readFileSync(
        "backend/server.js",
        "utf8",
      );

    assert.equal(
      (
        source.match(
          /K135Z_B5A_ZOOM_SERVER_REGISTRATION_BEGIN/g,
        ) || []
      ).length,
      1,
    );

    assert.equal(
      (
        source.match(
          /registerK135zZoomRoutes\(app,/g,
        ) || []
      ).length,
      1,
    );
  },
);
