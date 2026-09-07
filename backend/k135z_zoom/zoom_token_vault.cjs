"use strict";

const crypto = require("node:crypto");

class K135zZoomError extends Error {
  constructor(status, code, message, details = undefined) {
    super(message);
    this.name = "K135zZoomError";
    this.status = Number.isInteger(status) ? status : 500;
    this.code = code || "K135Z_ZOOM_ERROR";
    this.details = details;
  }
}

function clone(value) {
  return value == null
    ? value
    : JSON.parse(JSON.stringify(value));
}

function identityKey(identity) {
  if (!identity || typeof identity !== "object") {
    throw new K135zZoomError(
      400,
      "ZOOM_IDENTITY_REQUIRED",
      "A KORLIX user identity is required.",
    );
  }

  const userId = String(
    identity.userId ||
      identity.user_id ||
      identity.id ||
      identity.sub ||
      "",
  ).trim();

  const tenantId = String(
    identity.tenantId ||
      identity.tenant_id ||
      identity.organizationId ||
      identity.organization_id ||
      identity.accountId ||
      identity.account_id ||
      "personal",
  ).trim();

  if (!userId) {
    throw new K135zZoomError(
      401,
      "ZOOM_USER_ID_MISSING",
      "The authenticated KORLIX user identifier is missing.",
    );
  }

  return `${tenantId}:${userId}`;
}

class EnvelopeCipher {
  constructor(keyMaterial) {
    if (
      Buffer.isBuffer(keyMaterial) &&
      keyMaterial.length === 32
    ) {
      this.key = Buffer.from(keyMaterial);
    } else if (
      typeof keyMaterial === "string" &&
      keyMaterial.trim()
    ) {
      this.key = crypto
        .createHash("sha256")
        .update(keyMaterial, "utf8")
        .digest();
    } else {
      throw new K135zZoomError(
        503,
        "ZOOM_TOKEN_ENCRYPTION_KEY_UNAVAILABLE",
        "Zoom token encryption is not configured.",
      );
    }
  }

  encrypt(value) {
    const iv = crypto.randomBytes(12);

    const cipher = crypto.createCipheriv(
      "aes-256-gcm",
      this.key,
      iv,
    );

    const plaintext = Buffer.from(
      JSON.stringify(value),
      "utf8",
    );

    const ciphertext = Buffer.concat([
      cipher.update(plaintext),
      cipher.final(),
    ]);

    const tag = cipher.getAuthTag();

    return {
      version: 1,
      algorithm: "aes-256-gcm",
      iv: iv.toString("base64url"),
      tag: tag.toString("base64url"),
      ciphertext: ciphertext.toString("base64url"),
    };
  }

  decrypt(envelope) {
    if (
      !envelope ||
      envelope.version !== 1 ||
      envelope.algorithm !== "aes-256-gcm"
    ) {
      throw new K135zZoomError(
        500,
        "ZOOM_TOKEN_ENVELOPE_INVALID",
        "Stored Zoom token material is invalid.",
      );
    }

    try {
      const decipher = crypto.createDecipheriv(
        "aes-256-gcm",
        this.key,
        Buffer.from(envelope.iv, "base64url"),
      );

      decipher.setAuthTag(
        Buffer.from(envelope.tag, "base64url"),
      );

      const plaintext = Buffer.concat([
        decipher.update(
          Buffer.from(
            envelope.ciphertext,
            "base64url",
          ),
        ),
        decipher.final(),
      ]);

      return JSON.parse(
        plaintext.toString("utf8"),
      );
    } catch (error) {
      throw new K135zZoomError(
        500,
        "ZOOM_TOKEN_DECRYPTION_FAILED",
        "Stored Zoom token material could not be decrypted.",
      );
    }
  }
}

class MemoryZoomRepository {
  constructor() {
    this.oauthStates = new Map();
    this.usedOAuthStates = new Set();
    this.connections = new Map();
    this.webhookEvents = new Map();
    this.rtmsSessions = new Map();
  }

  async saveOAuthState(stateHash, record) {
    this.oauthStates.set(
      String(stateHash),
      clone(record),
    );
  }

  async consumeOAuthState(
    stateHash,
    nowMs = Date.now(),
  ) {
    const key = String(stateHash);

    if (this.usedOAuthStates.has(key)) {
      throw new K135zZoomError(
        409,
        "ZOOM_OAUTH_STATE_REPLAYED",
        "The Zoom authorization state has already been used.",
      );
    }

    const record = this.oauthStates.get(key);

    if (!record) {
      throw new K135zZoomError(
        400,
        "ZOOM_OAUTH_STATE_INVALID",
        "The Zoom authorization state is invalid.",
      );
    }

    this.oauthStates.delete(key);
    this.usedOAuthStates.add(key);

    if (
      !Number.isFinite(record.expiresAtMs) ||
      record.expiresAtMs < nowMs
    ) {
      throw new K135zZoomError(
        410,
        "ZOOM_OAUTH_STATE_EXPIRED",
        "The Zoom authorization state has expired.",
      );
    }

    return clone(record);
  }

  async saveConnection(key, record) {
    this.connections.set(
      String(key),
      clone(record),
    );
  }

  async getConnection(key) {
    return clone(
      this.connections.get(String(key)) ||
        null,
    );
  }

  async deleteConnection(key) {
    return this.connections.delete(
      String(key),
    );
  }

  async deleteConnectionsByZoomIdentity({
    zoomAccountId,
    zoomUserId,
  }) {
    let count = 0;

    for (
      const [key, value]
      of this.connections.entries()
    ) {
      const accountMatches =
        zoomAccountId &&
        value.zoomAccountId === zoomAccountId;

      const userMatches =
        zoomUserId &&
        value.zoomUserId === zoomUserId;

      if (accountMatches || userMatches) {
        this.connections.delete(key);
        count += 1;
      }
    }

    return count;
  }

  async recordWebhookEvent(
    eventId,
    record,
  ) {
    const key = String(eventId);

    if (this.webhookEvents.has(key)) {
      return false;
    }

    this.webhookEvents.set(
      key,
      clone(record),
    );

    return true;
  }

  async upsertRtmsSession(
    sessionKey,
    record,
  ) {
    const previous =
      this.rtmsSessions.get(
        String(sessionKey),
      ) || {};

    const next = {
      ...previous,
      ...clone(record),
    };

    this.rtmsSessions.set(
      String(sessionKey),
      next,
    );

    return clone(next);
  }

  async getRtmsSession(sessionKey) {
    return clone(
      this.rtmsSessions.get(
        String(sessionKey),
      ) || null,
    );
  }
}

class UnavailableZoomRepository {
  async _fail() {
    throw new K135zZoomError(
      503,
      "ZOOM_PERSISTENT_STORAGE_NOT_CONFIGURED",
      "Persistent Zoom connection storage is not configured.",
    );
  }

  async saveOAuthState() {
    return this._fail();
  }

  async consumeOAuthState() {
    return this._fail();
  }

  async saveConnection() {
    return this._fail();
  }

  async getConnection() {
    return this._fail();
  }

  async deleteConnection() {
    return this._fail();
  }

  async deleteConnectionsByZoomIdentity() {
    return this._fail();
  }

  async recordWebhookEvent() {
    return this._fail();
  }

  async upsertRtmsSession() {
    return this._fail();
  }
}

class ZoomTokenVault {
  constructor({
    repository,
    cipher,
    clock = () => Date.now(),
  }) {
    this.repository = repository;
    this.cipher = cipher;
    this.clock = clock;
  }

  async storeConnection(
    identity,
    tokenResponse,
    metadata = {},
  ) {
    const key = identityKey(identity);
    const nowMs = this.clock();

    const expiresInSeconds = Number(
      tokenResponse?.expires_in || 0,
    );

    if (
      !tokenResponse?.access_token ||
      !tokenResponse?.refresh_token
    ) {
      throw new K135zZoomError(
        502,
        "ZOOM_TOKEN_RESPONSE_INVALID",
        "Zoom did not return the required token fields.",
      );
    }

    const tokenBundle = {
      accessToken: String(
        tokenResponse.access_token,
      ),
      refreshToken: String(
        tokenResponse.refresh_token,
      ),
      tokenType: String(
        tokenResponse.token_type ||
          "bearer",
      ),
      scope: String(
        tokenResponse.scope || "",
      ),
      apiUrl: String(
        tokenResponse.api_url ||
          "https://api.zoom.us",
      ),
      issuedAtMs: nowMs,
      expiresAtMs:
        nowMs +
        Math.max(
          0,
          expiresInSeconds,
        ) *
          1000,
    };

    const record = {
      key,
      tenantId: String(
        identity.tenantId ||
          identity.tenant_id ||
          "personal",
      ),
      userId: String(
        identity.userId ||
          identity.user_id ||
          identity.id ||
          identity.sub,
      ),
      zoomAccountId: String(
        metadata.zoomAccountId ||
          tokenResponse.account_id ||
          tokenResponse.zoom_account_id ||
          "",
      ),
      zoomUserId: String(
        metadata.zoomUserId ||
          tokenResponse.user_id ||
          tokenResponse.zoom_user_id ||
          "",
      ),
      scope: tokenBundle.scope,
      expiresAtMs:
        tokenBundle.expiresAtMs,
      connectedAtMs: Number(
        metadata.connectedAtMs ||
          nowMs,
      ),
      updatedAtMs: nowMs,
      encryptedTokens:
        this.cipher.encrypt(
          tokenBundle,
        ),
    };

    await this.repository.saveConnection(
      key,
      record,
    );

    return this.getPublicStatus(
      identity,
    );
  }

  async getTokenBundle(identity) {
    const record =
      await this.repository.getConnection(
        identityKey(identity),
      );

    if (!record) {
      return null;
    }

    return {
      record,
      tokens: this.cipher.decrypt(
        record.encryptedTokens,
      ),
    };
  }

  async getPublicStatus(identity) {
    const result =
      await this.getTokenBundle(identity);

    if (!result) {
      return {
        connected: false,
        requiresReauthorization: false,
      };
    }

    const nowMs = this.clock();

    return {
      connected: true,
      requiresReauthorization:
        !result.tokens.refreshToken,
      accessTokenExpired:
        result.tokens.expiresAtMs <=
        nowMs,
      scope: result.record.scope,
      expiresAt: new Date(
        result.tokens.expiresAtMs,
      ).toISOString(),
      connectedAt: new Date(
        result.record.connectedAtMs,
      ).toISOString(),
      zoomAccountId:
        result.record.zoomAccountId ||
        null,
      zoomUserId:
        result.record.zoomUserId ||
        null,
    };
  }

  async deleteConnection(identity) {
    return this.repository.deleteConnection(
      identityKey(identity),
    );
  }

  async deleteByZoomIdentity(
    zoomIdentity,
  ) {
    return this.repository
      .deleteConnectionsByZoomIdentity(
        zoomIdentity || {},
      );
  }
}

module.exports = {
  EnvelopeCipher,
  K135zZoomError,
  MemoryZoomRepository,
  UnavailableZoomRepository,
  ZoomTokenVault,
  identityKey,
};
