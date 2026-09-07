"use strict";

const crypto = require("node:crypto");

const {
  K135zZoomError,
  identityKey,
} = require(
  "./zoom_token_vault.cjs",
);

function hashState(state) {
  return crypto
    .createHash("sha256")
    .update(
      String(state),
      "utf8",
    )
    .digest("hex");
}

function principalIdentity(principal) {
  if (
    !principal ||
    typeof principal !== "object"
  ) {
    throw new K135zZoomError(
      401,
      "KORLIX_AUTH_REQUIRED",
      "Authentication is required.",
    );
  }

  const userId = String(
    principal.userId ||
      principal.user_id ||
      principal.id ||
      principal.sub ||
      "",
  ).trim();

  const tenantId = String(
    principal.tenantId ||
      principal.tenant_id ||
      principal.organizationId ||
      principal.organization_id ||
      principal.accountId ||
      principal.account_id ||
      "personal",
  ).trim();

  if (!userId) {
    throw new K135zZoomError(
      401,
      "KORLIX_AUTH_SUBJECT_MISSING",
      "The authenticated KORLIX user identifier is missing.",
    );
  }

  return {
    userId,
    tenantId,
  };
}

function normalizeReturnTo(
  returnTo,
  allowedOrigins = [],
) {
  if (!returnTo) {
    return null;
  }

  let parsed;

  try {
    parsed = new URL(
      String(returnTo),
    );
  } catch (error) {
    throw new K135zZoomError(
      400,
      "ZOOM_RETURN_URL_INVALID",
      "The Zoom return URL is invalid.",
    );
  }

  if (
    parsed.protocol !== "https:" &&
    parsed.hostname !== "127.0.0.1"
  ) {
    throw new K135zZoomError(
      400,
      "ZOOM_RETURN_URL_SCHEME_REJECTED",
      "The Zoom return URL must use HTTPS.",
    );
  }

  const normalizedAllowed =
    allowedOrigins
      .map((value) => {
        try {
          return new URL(
            String(value),
          ).origin;
        } catch (error) {
          return null;
        }
      })
      .filter(Boolean);

  if (
    normalizedAllowed.length > 0 &&
    !normalizedAllowed.includes(
      parsed.origin,
    )
  ) {
    throw new K135zZoomError(
      400,
      "ZOOM_RETURN_URL_NOT_ALLOWED",
      "The Zoom return URL is not allow-listed.",
    );
  }

  return parsed.toString();
}

class ZoomOAuthService {
  constructor({
    repository,
    tokenVault,
    transport,
    config,
    clock = () => Date.now(),
  }) {
    this.repository = repository;
    this.tokenVault = tokenVault;
    this.transport = transport;

    this.config = {
      authorizeUrl:
        "https://zoom.us/oauth/authorize",
      stateTtlMs:
        10 * 60 * 1000,
      allowedReturnOrigins: [],
      ...config,
    };

    this.clock = clock;
  }

  assertConfigured() {
    if (
      !this.config.clientId ||
      !this.config.redirectUri
    ) {
      throw new K135zZoomError(
        503,
        "ZOOM_OAUTH_NOT_CONFIGURED",
        "Zoom OAuth is not configured for this environment.",
      );
    }
  }

  async startAuthorization({
    principal,
    returnTo = null,
  }) {
    this.assertConfigured();

    const identity =
      principalIdentity(principal);

    const nowMs = this.clock();

    const state = crypto
      .randomBytes(32)
      .toString("base64url");

    const stateHash =
      hashState(state);

    const expiresAtMs =
      nowMs +
      Number(
        this.config.stateTtlMs,
      );

    const safeReturnTo =
      normalizeReturnTo(
        returnTo,
        this.config
          .allowedReturnOrigins,
      );

    await this.repository
      .saveOAuthState(
        stateHash,
        {
          ...identity,
          returnTo:
            safeReturnTo,
          createdAtMs:
            nowMs,
          expiresAtMs,
        },
      );

    const authorizationUrl =
      new URL(
        this.config.authorizeUrl,
      );

    authorizationUrl.searchParams.set(
      "response_type",
      "code",
    );

    authorizationUrl.searchParams.set(
      "client_id",
      this.config.clientId,
    );

    authorizationUrl.searchParams.set(
      "redirect_uri",
      this.config.redirectUri,
    );

    authorizationUrl.searchParams.set(
      "state",
      state,
    );

    return {
      authorizationUrl:
        authorizationUrl.toString(),
      expiresAt:
        new Date(
          expiresAtMs,
        ).toISOString(),
    };
  }

  async completeAuthorization({
    code,
    state,
  }) {
    this.assertConfigured();

    if (!code || !state) {
      throw new K135zZoomError(
        400,
        "ZOOM_OAUTH_CALLBACK_INCOMPLETE",
        "The Zoom callback is missing code or state.",
      );
    }

    const stateRecord =
      await this.repository
        .consumeOAuthState(
          hashState(state),
          this.clock(),
        );

    const identity = {
      userId:
        stateRecord.userId,
      tenantId:
        stateRecord.tenantId,
    };

    const tokenResponse =
      await this.transport
        .exchangeAuthorizationCode({
          code: String(code),
          clientId:
            this.config.clientId,
          clientSecret:
            this.config.clientSecret,
          redirectUri:
            this.config.redirectUri,
        });

    await this.tokenVault
      .storeConnection(
        identity,
        tokenResponse,
        {
          connectedAtMs:
            this.clock(),
        },
      );

    return {
      connected: true,
      returnTo:
        stateRecord.returnTo ||
        null,
      identityKey:
        identityKey(identity),
    };
  }

  async getStatus(principal) {
    return this.tokenVault
      .getPublicStatus(
        principalIdentity(
          principal,
        ),
      );
  }

  async getAuthorizedAccess(
    principal,
  ) {
    const identity =
      principalIdentity(principal);

    const current =
      await this.tokenVault
        .getTokenBundle(
          identity,
        );

    if (!current) {
      throw new K135zZoomError(
        409,
        "ZOOM_NOT_CONNECTED",
        "A Zoom account is not connected.",
      );
    }

    const nowMs = this.clock();

    if (
      current.tokens.expiresAtMs >
      nowMs + 30000
    ) {
      return {
        identity,
        accessToken:
          current.tokens.accessToken,
        apiUrl:
          current.tokens.apiUrl,
      };
    }

    if (
      !current.tokens.refreshToken ||
      typeof this.transport
        .refreshAccessToken !==
        "function"
    ) {
      throw new K135zZoomError(
        401,
        "ZOOM_REAUTHORIZATION_REQUIRED",
        "Zoom authorization must be renewed.",
      );
    }

    const refreshed =
      await this.transport
        .refreshAccessToken({
          refreshToken:
            current.tokens
              .refreshToken,
          clientId:
            this.config.clientId,
          clientSecret:
            this.config.clientSecret,
        });

    await this.tokenVault
      .storeConnection(
        identity,
        refreshed,
        {
          connectedAtMs:
            current.record
              .connectedAtMs,
          zoomAccountId:
            current.record
              .zoomAccountId,
          zoomUserId:
            current.record
              .zoomUserId,
        },
      );

    const rotated =
      await this.tokenVault
        .getTokenBundle(
          identity,
        );

    return {
      identity,
      accessToken:
        rotated.tokens
          .accessToken,
      apiUrl:
        rotated.tokens.apiUrl,
    };
  }

  async disconnect(principal) {
    const identity =
      principalIdentity(principal);

    const current =
      await this.tokenVault
        .getTokenBundle(
          identity,
        );

    let revocationAttempted =
      false;

    let revocationSucceeded =
      false;

    if (
      current &&
      typeof this.transport
        .revokeAccessToken ===
        "function"
    ) {
      revocationAttempted = true;

      try {
        await this.transport
          .revokeAccessToken({
            accessToken:
              current.tokens
                .accessToken,
            clientId:
              this.config.clientId,
            clientSecret:
              this.config.clientSecret,
          });

        revocationSucceeded =
          true;
      } catch (error) {
        revocationSucceeded =
          false;
      }
    }

    const deleted =
      await this.tokenVault
        .deleteConnection(
          identity,
        );

    return {
      disconnected: true,
      localConnectionDeleted:
        Boolean(deleted),
      revocationAttempted,
      revocationSucceeded,
    };
  }
}

module.exports = {
  ZoomOAuthService,
  hashState,
  normalizeReturnTo,
  principalIdentity,
};
