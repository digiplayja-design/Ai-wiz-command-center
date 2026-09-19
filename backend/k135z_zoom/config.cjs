'use strict';

const ZOOM_ENV = Object.freeze({
  enabled: 'KORLIX_ZOOM_ENABLED',
  rtmsEnabled: 'KORLIX_ZOOM_RTMS_ENABLED',
  clientId: 'KORLIX_ZOOM_CLIENT_ID',
  clientSecret: 'KORLIX_ZOOM_CLIENT_SECRET',
  redirectUri: 'KORLIX_ZOOM_REDIRECT_URI',
  webhookSecretToken: 'KORLIX_ZOOM_WEBHOOK_SECRET_TOKEN',
  oauthStateSecret: 'KORLIX_ZOOM_OAUTH_STATE_SECRET',
  tokenEncryptionKey: 'KORLIX_ZOOM_TOKEN_ENCRYPTION_KEY',
  authorizeUrl: 'KORLIX_ZOOM_OAUTH_AUTHORIZE_URL',
  tokenUrl: 'KORLIX_ZOOM_OAUTH_TOKEN_URL',
  webhookMaxSkewSeconds:
    'KORLIX_ZOOM_WEBHOOK_MAX_SKEW_SECONDS',
});

function parseBoolean(value, fallback = false) {
  if (
    value === undefined ||
    value === null ||
    value === ''
  ) {
    return fallback;
  }

  const normalized = String(value)
    .trim()
    .toLowerCase();

  if (
    ['1', 'true', 'yes', 'on']
      .includes(normalized)
  ) {
    return true;
  }

  if (
    ['0', 'false', 'no', 'off']
      .includes(normalized)
  ) {
    return false;
  }

  throw new Error(
    'Invalid boolean configuration value',
  );
}

function parsePositiveInteger(value, fallback) {
  if (
    value === undefined ||
    value === null ||
    value === ''
  ) {
    return fallback;
  }

  const parsed = Number.parseInt(
    String(value),
    10,
  );

  if (
    !Number.isSafeInteger(parsed) ||
    parsed <= 0
  ) {
    throw new Error(
      'Invalid positive integer configuration value',
    );
  }

  return parsed;
}

function readZoomConfig(env = process.env) {
  return {
    enabled: parseBoolean(
      env[ZOOM_ENV.enabled],
      false,
    ),

    rtmsEnabled: parseBoolean(
      env[ZOOM_ENV.rtmsEnabled],
      false,
    ),

    clientId: String(
      env[ZOOM_ENV.clientId] || '',
    ).trim(),

    clientSecret: String(
      env[ZOOM_ENV.clientSecret] || '',
    ),

    redirectUri: String(
      env[ZOOM_ENV.redirectUri] || '',
    ).trim(),

    webhookSecretToken: String(
      env[ZOOM_ENV.webhookSecretToken] || '',
    ),

    oauthStateSecret: String(
      env[ZOOM_ENV.oauthStateSecret] || '',
    ),

    tokenEncryptionKey: String(
      env[ZOOM_ENV.tokenEncryptionKey] || '',
    ),

    authorizeUrl: String(
      env[ZOOM_ENV.authorizeUrl] ||
        'https://zoom.us/oauth/authorize',
    ).trim(),

    tokenUrl: String(
      env[ZOOM_ENV.tokenUrl] ||
        'https://zoom.us/oauth/token',
    ).trim(),

    webhookMaxSkewSeconds:
      parsePositiveInteger(
        env[
          ZOOM_ENV.webhookMaxSkewSeconds
        ],
        300,
      ),
  };
}

function validateZoomConfig(config) {
  const missing = [];
  const invalid = [];

  if (
    !config ||
    typeof config !== 'object'
  ) {
    return {
      ok: false,
      missing: [],
      invalid: ['config'],
    };
  }

  if (
    config.rtmsEnabled &&
    !config.enabled
  ) {
    invalid.push(
      `${ZOOM_ENV.rtmsEnabled}:requires_${ZOOM_ENV.enabled}`,
    );
  }

  if (config.enabled) {
    for (const [field, envName] of [
      ['clientId', ZOOM_ENV.clientId],
      ['clientSecret', ZOOM_ENV.clientSecret],
      ['redirectUri', ZOOM_ENV.redirectUri],
      [
        'oauthStateSecret',
        ZOOM_ENV.oauthStateSecret,
      ],
      [
        'tokenEncryptionKey',
        ZOOM_ENV.tokenEncryptionKey,
      ],
    ]) {
      if (!config[field]) {
        missing.push(envName);
      }
    }

    if (
      config.oauthStateSecret &&
      Buffer.byteLength(
        config.oauthStateSecret,
        'utf8',
      ) < 32
    ) {
      invalid.push(
        `${ZOOM_ENV.oauthStateSecret}:minimum_32_bytes`,
      );
    }

    if (
      config.tokenEncryptionKey &&
      Buffer.byteLength(
        config.tokenEncryptionKey,
        'utf8',
      ) < 32
    ) {
      invalid.push(
        `${ZOOM_ENV.tokenEncryptionKey}:minimum_32_bytes`,
      );
    }

    if (config.redirectUri) {
      try {
        const url = new URL(
          config.redirectUri,
        );

        const localHostnames = new Set([
          'localhost',
          '127.0.0.1',
          '[::1]',
        ]);

        if (
          url.protocol !== 'https:' &&
          !localHostnames.has(url.hostname)
        ) {
          invalid.push(
            `${ZOOM_ENV.redirectUri}:https_required`,
          );
        }
      } catch {
        invalid.push(
          `${ZOOM_ENV.redirectUri}:invalid_url`,
        );
      }
    }
  }

  if (
    config.rtmsEnabled &&
    !config.webhookSecretToken
  ) {
    missing.push(
      ZOOM_ENV.webhookSecretToken,
    );
  }

  return {
    ok:
      missing.length === 0 &&
      invalid.length === 0,

    missing: [
      ...new Set(missing),
    ].sort(),

    invalid: [
      ...new Set(invalid),
    ].sort(),
  };
}

function summarizeZoomConfig(config) {
  return {
    enabled: Boolean(
      config &&
      config.enabled,
    ),

    rtmsEnabled: Boolean(
      config &&
      config.rtmsEnabled,
    ),

    clientIdConfigured: Boolean(
      config &&
      config.clientId,
    ),

    clientSecretConfigured: Boolean(
      config &&
      config.clientSecret,
    ),

    redirectUriConfigured: Boolean(
      config &&
      config.redirectUri,
    ),

    webhookSecretConfigured: Boolean(
      config &&
      config.webhookSecretToken,
    ),

    oauthStateSecretConfigured: Boolean(
      config &&
      config.oauthStateSecret,
    ),

    tokenEncryptionKeyConfigured: Boolean(
      config &&
      config.tokenEncryptionKey,
    ),

    validation:
      validateZoomConfig(config),
  };
}

module.exports = {
  ZOOM_ENV,
  parseBoolean,
  readZoomConfig,
  summarizeZoomConfig,
  validateZoomConfig,
};
