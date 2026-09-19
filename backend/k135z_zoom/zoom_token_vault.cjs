"use strict";

const crypto = require("node:crypto");

const { K135zZoomError, identity, identityKey, need, envelope } = require("./b5b_contract.cjs");

function clone(value) {
  return value == null
    ? value
    : JSON.parse(JSON.stringify(value));
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
      Buffer.byteLength(keyMaterial, "utf8") >= 32
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

  encrypt(value, binding) {
    need(typeof binding === "string" && binding.length > 0, "ZOOM_TOKEN_BINDING_REQUIRED");
    const iv = crypto.randomBytes(12);

    const cipher = crypto.createCipheriv(
      "aes-256-gcm",
      this.key,
      iv,
    );

    cipher.setAAD(Buffer.from("K135Z-B5B-v1:" + binding, "utf8"));

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
      version: 2,
      algorithm: "aes-256-gcm",
      iv: iv.toString("base64url"),
      tag: tag.toString("base64url"),
      ciphertext: ciphertext.toString("base64url"),
    };
  }

  decrypt(envelopeValue, binding) {
    need(typeof binding === "string" && binding.length > 0, "ZOOM_TOKEN_BINDING_REQUIRED");
    const envelope = require("./b5b_contract.cjs").envelope(envelopeValue);
    if (
      !envelope ||
      envelope.version !== 2 ||
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

      decipher.setAAD(Buffer.from("K135Z-B5B-v1:" + binding, "utf8"));

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

const { MemoryZoomRepository } = require("./b5b_repository.cjs");

class UnavailableZoomRepository {
  async applyWebhookEvent() { return this._fail(); }
  async getRtmsSession() { return this._fail(); }
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
    identity = require("./b5b_contract.cjs").identity(identity);
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

    need(Number.isSafeInteger(expiresInSeconds) && expiresInSeconds > 0 && expiresInSeconds <= 2678400, "ZOOM_TOKEN_EXPIRY_INVALID", 502);

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
      agentId: identity.agentId,
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
          tokenBundle, key,
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
        record.encryptedTokens, identityKey(identity),
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
