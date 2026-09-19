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

const { identity: principalIdentity, normalizeReturnTo, need, time } = require("./b5b_contract.cjs");

class ZoomOAuthService {
  constructor({
    repository,
    tokenVault,
    transport,
    config,
    clock = () => Date.now(),
    authorizeStoredIdentity = async () => false,
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
    this.authorizeStoredIdentity = authorizeStoredIdentity;
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

    const nowMs = time(this.clock());
    need(Number.isSafeInteger(this.config.stateTtlMs) && this.config.stateTtlMs > 0 && this.config.stateTtlMs <= 600000, "ZOOM_STATE_TTL_INVALID");

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

    const identity = principalIdentity(stateRecord);
    need(await this.authorizeStoredIdentity(identity) === true, "ZOOM_STORED_AUTHORIZATION_DENIED", 403);
    const safeReturnTo = normalizeReturnTo(stateRecord.returnTo, this.config.allowedReturnOrigins);

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
        safeReturnTo,
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
