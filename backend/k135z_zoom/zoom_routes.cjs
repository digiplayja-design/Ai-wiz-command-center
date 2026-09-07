"use strict";

const crypto = require("node:crypto");

const {
  EnvelopeCipher,
  K135zZoomError,
  MemoryZoomRepository,
  UnavailableZoomRepository,
  ZoomTokenVault,
} = require(
  "./zoom_token_vault.cjs",
);

const {
  ZoomOAuthService,
} = require(
  "./zoom_oauth_service.cjs",
);

const {
  ZoomMeetingDiscovery,
} = require(
  "./zoom_meeting_discovery.cjs",
);

const {
  ZoomWebhookVerifier,
} = require(
  "./zoom_webhook_verifier.cjs",
);

const {
  ZoomRtmsSessionManager,
} = require(
  "./zoom_rtms_session_manager.cjs",
);

const K135Z_ZOOM_ROUTE_PREFIX =
  "/api/k135z/zoom";

function jsonResponse(
  res,
  status,
  payload,
) {
  if (
    typeof res.status ===
    "function"
  ) {
    res.status(status);
  } else {
    res.statusCode = status;
  }

  if (
    typeof res.json ===
    "function"
  ) {
    return res.json(payload);
  }

  if (
    typeof res.end ===
    "function"
  ) {
    if (
      typeof res.setHeader ===
      "function"
    ) {
      res.setHeader(
        "content-type",
        "application/json; charset=utf-8",
      );
    }

    return res.end(
      JSON.stringify(payload),
    );
  }

  res.body = payload;

  return payload;
}

function errorResponse(
  res,
  error,
) {
  const known =
    error instanceof
    K135zZoomError;

  const status =
    known
      ? error.status
      : 500;

  const code =
    known
      ? error.code
      : "K135Z_ZOOM_INTERNAL_ERROR";

  const message =
    known
      ? error.message
      : "The Zoom integration request could not be completed.";

  return jsonResponse(
    res,
    status,
    {
      ok: false,
      error: {
        code,
        message,
      },
    },
  );
}

function safeHandler(handler) {
  return async function wrappedHandler(
    req,
    res,
  ) {
    try {
      return await handler(
        req,
        res,
      );
    } catch (error) {
      return errorResponse(
        res,
        error,
      );
    }
  };
}

function principalFromRequest(req) {
  const candidates = [
    req?.korlixUser,
    req?.user,
    req?.auth?.user,
    req?.auth,
    req?.session?.user,
  ];

  return (
    candidates.find(
      (candidate) =>
        candidate &&
        typeof candidate ===
          "object",
    ) || null
  );
}

function normalizedTierTokens(
  value,
) {
  return String(
    value ?? "",
  )
    .trim()
    .toLowerCase()
    .replace(
      /[^a-z0-9]+/g,
      "_",
    )
    .split("_")
    .filter(Boolean);
}

function isEnterprisePrincipal(
  principal,
  req = undefined,
) {
  const values = [
    principal?.tier,
    principal?.plan,
    principal
      ?.subscriptionTier,
    principal
      ?.subscription_tier,
    principal
      ?.app_metadata?.tier,
    principal
      ?.app_metadata?.plan,
    principal
      ?.user_metadata?.tier,
    principal
      ?.user_metadata?.plan,
    req?.korlixTier,
    req?.subscriptionTier,
  ];

  return values.some(
    (value) => {
      const tokens =
        normalizedTierTokens(
          value,
        );

      return (
        tokens.includes(
          "enterprise",
        ) &&
        !tokens.includes(
          "non",
        ) &&
        !tokens.includes(
          "not",
        )
      );
    },
  );
}

async function readFetchJson(
  response,
) {
  const text =
    await response.text();

  let body = {};

  if (text) {
    try {
      body =
        JSON.parse(text);
    } catch (error) {
      body = {
        message:
          text.slice(
            0,
            300,
          ),
      };
    }
  }

  if (!response.ok) {
    throw new K135zZoomError(
      response.status || 502,
      "ZOOM_UPSTREAM_REQUEST_FAILED",
      "Zoom rejected the requested operation.",
      {
        upstreamStatus:
          response.status,

        upstreamCode:
          body.code || null,
      },
    );
  }

  return body;
}

function createFetchZoomTransport({
  enabled,
  fetchImpl = globalThis.fetch,
  tokenUrl,
  apiBaseUrl,
}) {
  const liveEnabled =
    enabled === true;

  function assertEnabled() {
    if (!liveEnabled) {
      throw new K135zZoomError(
        503,
        "ZOOM_LIVE_TRANSPORT_DISABLED",
        "Live Zoom API transport is disabled for this environment.",
      );
    }

    if (
      typeof fetchImpl !==
      "function"
    ) {
      throw new K135zZoomError(
        503,
        "ZOOM_FETCH_UNAVAILABLE",
        "The server has no HTTP transport for Zoom.",
      );
    }
  }

  async function tokenRequest({
    clientId,
    clientSecret,
    parameters,
  }) {
    assertEnabled();

    if (
      !clientId ||
      !clientSecret
    ) {
      throw new K135zZoomError(
        503,
        "ZOOM_CLIENT_CREDENTIALS_MISSING",
        "Zoom client credentials are not configured.",
      );
    }

    const response =
      await fetchImpl(
        tokenUrl,
        {
          method: "POST",

          headers: {
            authorization:
              `Basic ${
                Buffer.from(
                  `${clientId}:${clientSecret}`,
                  "utf8",
                ).toString(
                  "base64",
                )
              }`,

            "content-type":
              "application/x-www-form-urlencoded",

            accept:
              "application/json",
          },

          body:
            new URLSearchParams(
              parameters,
            ).toString(),
        },
      );

    return readFetchJson(
      response,
    );
  }

  return {
    liveEnabled,

    exchangeAuthorizationCode({
      code,
      clientId,
      clientSecret,
      redirectUri,
    }) {
      return tokenRequest({
        clientId,
        clientSecret,

        parameters: {
          grant_type:
            "authorization_code",

          code,

          redirect_uri:
            redirectUri,
        },
      });
    },

    refreshAccessToken({
      refreshToken,
      clientId,
      clientSecret,
    }) {
      return tokenRequest({
        clientId,
        clientSecret,

        parameters: {
          grant_type:
            "refresh_token",

          refresh_token:
            refreshToken,
        },
      });
    },

    async listUpcomingMeetings({
      accessToken,
      userId = "me",
    }) {
      assertEnabled();

      const encodedUser =
        encodeURIComponent(
          String(
            userId || "me",
          ),
        );

      const response =
        await fetchImpl(
          `${apiBaseUrl}/users/${encodedUser}/upcoming_meetings`,
          {
            method: "GET",

            headers: {
              authorization:
                `Bearer ${accessToken}`,

              accept:
                "application/json",
            },
          },
        );

      return readFetchJson(
        response,
      );
    },
  };
}

function unavailableVault(
  repository,
) {
  const fail = async () => {
    throw new K135zZoomError(
      503,
      "ZOOM_PERSISTENT_STORAGE_NOT_CONFIGURED",
      "Persistent Zoom connection storage is not configured.",
    );
  };

  return {
    storeConnection: fail,
    getTokenBundle: fail,
    getPublicStatus: fail,
    deleteConnection: fail,
    deleteByZoomIdentity: fail,
    repository,
  };
}

function createK135zZoomDependencies(
  options = {},
) {
  const env =
    options.env ||
    process.env;

  const production =
    String(
      env.NODE_ENV || "",
    ).toLowerCase() ===
    "production";

  const allowEphemeral =
    String(
      env.KORLIX_K135Z_ZOOM_ALLOW_EPHEMERAL_STORE ||
        "",
    ).toLowerCase() ===
    "true";

  const encryptionKey =
    env.KORLIX_K135Z_ZOOM_TOKEN_ENCRYPTION_KEY ||
    "";

  const repository =
    options.repository ||
    (
      production &&
      !allowEphemeral
        ? new UnavailableZoomRepository()
        : new MemoryZoomRepository()
    );

  let tokenVault =
    options.tokenVault;

  if (!tokenVault) {
    if (encryptionKey) {
      tokenVault =
        new ZoomTokenVault({
          repository,

          cipher:
            new EnvelopeCipher(
              encryptionKey,
            ),
        });
    } else if (
      !production ||
      allowEphemeral
    ) {
      tokenVault =
        new ZoomTokenVault({
          repository,

          cipher:
            new EnvelopeCipher(
              crypto.randomBytes(
                32,
              ),
            ),
        });
    } else {
      tokenVault =
        unavailableVault(
          repository,
        );
    }
  }

  const transport =
    options.transport ||
    createFetchZoomTransport({
      enabled:
        String(
          env.KORLIX_K135Z_ZOOM_LIVE_TRANSPORT_ENABLED ||
            "",
        ).toLowerCase() ===
        "true",

      fetchImpl:
        options.fetchImpl ||
        globalThis.fetch,

      tokenUrl:
        env.KORLIX_ZOOM_TOKEN_URL ||
        "https://zoom.us/oauth/token",

      apiBaseUrl:
        env.KORLIX_ZOOM_API_BASE_URL ||
        "https://api.zoom.us/v2",
    });

  const allowedReturnOrigins =
    String(
      env.KORLIX_K135Z_ZOOM_ALLOWED_RETURN_ORIGINS ||
        "",
    )
      .split(",")
      .map(
        (value) =>
          value.trim(),
      )
      .filter(Boolean);

  const oauthService =
    options.oauthService ||
    new ZoomOAuthService({
      repository,
      tokenVault,
      transport,

      config: {
        clientId:
          env.KORLIX_ZOOM_CLIENT_ID ||
          "",

        clientSecret:
          env.KORLIX_ZOOM_CLIENT_SECRET ||
          "",

        redirectUri:
          env.KORLIX_ZOOM_REDIRECT_URI ||
          "",

        authorizeUrl:
          env.KORLIX_ZOOM_AUTHORIZE_URL ||
          "https://zoom.us/oauth/authorize",

        allowedReturnOrigins,
      },
    });

  const webhookVerifier =
    options.webhookVerifier ||
    new ZoomWebhookVerifier({
      secret:
        env.KORLIX_ZOOM_WEBHOOK_SECRET ||
        "",
    });

  return {
    repository,
    tokenVault,
    transport,
    oauthService,

    meetingDiscovery:
      options.meetingDiscovery ||
      new ZoomMeetingDiscovery({
        oauthService,
        transport,
      }),

    webhookVerifier,

    rtmsSessionManager:
      options.rtmsSessionManager ||
      new ZoomRtmsSessionManager({
        repository,
      }),

    authenticateRequest:
      options.authenticateRequest ||
      (
        async (req) =>
          principalFromRequest(
            req,
          )
      ),

    resolveEnterprise:
      options.resolveEnterprise ||
      (
        async (
          principal,
          req,
        ) =>
          isEnterprisePrincipal(
            principal,
            req,
          )
      ),
  };
}

function createK135zZoomHandlers(
  dependencies,
) {
  const deps =
    dependencies;

  async function authorize(req) {
    const principal =
      await deps
        .authenticateRequest(
          req,
        );

    if (!principal) {
      throw new K135zZoomError(
        401,
        "KORLIX_AUTH_REQUIRED",
        "Authentication is required.",
      );
    }

    const enterprise =
      await deps
        .resolveEnterprise(
          principal,
          req,
        );

    if (!enterprise) {
      throw new K135zZoomError(
        403,
        "KORLIX_ENTERPRISE_REQUIRED",
        "Nova Meeting Copilot requires an Enterprise account.",
      );
    }

    return principal;
  }

  const start =
    safeHandler(
      async (
        req,
        res,
      ) => {
        const principal =
          await authorize(req);

        const result =
          await deps
            .oauthService
            .startAuthorization({
              principal,

              returnTo:
                req?.query
                  ?.return_to ||
                req?.query
                  ?.returnTo ||
                null,
            });

        return jsonResponse(
          res,
          200,
          {
            ok: true,

            authorization_url:
              result
                .authorizationUrl,

            expires_at:
              result.expiresAt,

            live_transport_enabled:
              Boolean(
                deps.transport
                  .liveEnabled,
              ),
          },
        );
      },
    );

  const callback =
    safeHandler(
      async (
        req,
        res,
      ) => {
        const result =
          await deps
            .oauthService
            .completeAuthorization({
              code:
                req?.query?.code,

              state:
                req?.query?.state,
            });

        if (
          result.returnTo &&
          typeof res.redirect ===
            "function"
        ) {
          const returnUrl =
            new URL(
              result.returnTo,
            );

          returnUrl
            .searchParams
            .set(
              "zoom",
              "connected",
            );

          return res.redirect(
            302,
            returnUrl.toString(),
          );
        }

        return jsonResponse(
          res,
          200,
          {
            ok: true,
            connected: true,
          },
        );
      },
    );

  const status =
    safeHandler(
      async (
        req,
        res,
      ) => {
        const principal =
          await authorize(req);

        return jsonResponse(
          res,
          200,
          {
            ok: true,

            status:
              await deps
                .oauthService
                .getStatus(
                  principal,
                ),
          },
        );
      },
    );

  const disconnect =
    safeHandler(
      async (
        req,
        res,
      ) => {
        const principal =
          await authorize(req);

        return jsonResponse(
          res,
          200,
          {
            ok: true,

            result:
              await deps
                .oauthService
                .disconnect(
                  principal,
                ),
          },
        );
      },
    );

  const upcoming =
    safeHandler(
      async (
        req,
        res,
      ) => {
        const principal =
          await authorize(req);

        const result =
          await deps
            .meetingDiscovery
            .listUpcoming(
              principal,
            );

        return jsonResponse(
          res,
          200,
          {
            ok: true,
            ...result,
          },
        );
      },
    );

  const webhook =
    safeHandler(
      async (
        req,
        res,
      ) => {
        const verified =
          deps.webhookVerifier
            .verifyRequest(req);

        const body =
          verified.body;

        if (
          body?.event ===
          "endpoint.url_validation"
        ) {
          const response =
            deps.webhookVerifier
              .createEndpointValidationResponse(
                body?.payload
                  ?.plainToken,
              );

          return jsonResponse(
            res,
            200,
            response,
          );
        }

        const eventId =
          crypto
            .createHash(
              "sha256",
            )
            .update(
              `${
                body?.event ||
                "unknown"
              }:${
                body?.event_ts ||
                "0"
              }:${
                verified.rawBody
              }`,
              "utf8",
            )
            .digest("hex");

        await deps.repository
          .recordWebhookEvent(
            eventId,
            {
              event:
                String(
                  body?.event ||
                    "",
                ),

              eventTs:
                Number(
                  body?.event_ts ||
                    0,
                ),

              receivedAt:
                new Date()
                  .toISOString(),

              rawBodyStored:
                false,
            },
          );

        await deps
          .rtmsSessionManager
          .handleVerifiedEvent(
            body,
          );

        return jsonResponse(
          res,
          200,
          {
            ok: true,
            accepted: true,
          },
        );
      },
    );

  const deauthorization =
    safeHandler(
      async (
        req,
        res,
      ) => {
        const verified =
          deps.webhookVerifier
            .verifyRequest(req);

        const body =
          verified.body;

        if (
          body?.event !==
          "app_deauthorized"
        ) {
          throw new K135zZoomError(
            400,
            "ZOOM_DEAUTH_EVENT_REQUIRED",
            "The request is not a Zoom deauthorization event.",
          );
        }

        const deleted =
          await deps
            .tokenVault
            .deleteByZoomIdentity({
              zoomAccountId:
                String(
                  body?.payload
                    ?.account_id ||
                    "",
                ),

              zoomUserId:
                String(
                  body?.payload
                    ?.user_id ||
                    "",
                ),
            });

        return jsonResponse(
          res,
          200,
          {
            ok: true,

            deleted_connections:
              Number(
                deleted || 0,
              ),
          },
        );
      },
    );

  return {
    start,
    callback,
    status,
    disconnect,
    upcoming,
    webhook,
    deauthorization,
  };
}

function registerK135zZoomRoutes(
  app,
  options = {},
) {
  if (
    !app ||
    typeof app.get !==
      "function" ||
    typeof app.post !==
      "function"
  ) {
    throw new Error(
      "K135Z_ZOOM_EXPRESS_APP_REQUIRED",
    );
  }

  const dependencies =
    createK135zZoomDependencies(
      options,
    );

  const handlers =
    createK135zZoomHandlers(
      dependencies,
    );

  // K135Z_B5A_ZOOM_ROUTE_REGISTRATION_BEGIN
  app.get(
    `${K135Z_ZOOM_ROUTE_PREFIX}/oauth/start`,
    handlers.start,
  );

  app.get(
    `${K135Z_ZOOM_ROUTE_PREFIX}/oauth/callback`,
    handlers.callback,
  );

  app.get(
    `${K135Z_ZOOM_ROUTE_PREFIX}/status`,
    handlers.status,
  );

  app.delete(
    `${K135Z_ZOOM_ROUTE_PREFIX}/connection`,
    handlers.disconnect,
  );

  app.get(
    `${K135Z_ZOOM_ROUTE_PREFIX}/meetings/upcoming`,
    handlers.upcoming,
  );

  app.post(
    `${K135Z_ZOOM_ROUTE_PREFIX}/webhook`,
    handlers.webhook,
  );

  app.post(
    `${K135Z_ZOOM_ROUTE_PREFIX}/deauthorization`,
    handlers.deauthorization,
  );
  // K135Z_B5A_ZOOM_ROUTE_REGISTRATION_END

  return {
    dependencies,
    handlers,
  };
}

module.exports = {
  K135Z_ZOOM_ROUTE_PREFIX,
  createFetchZoomTransport,
  createK135zZoomDependencies,
  createK135zZoomHandlers,
  errorResponse,
  isEnterprisePrincipal,
  principalFromRequest,
  registerK135zZoomRoutes,
};
