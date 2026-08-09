const DEFAULT_BASE_URL =
  'https://api.openai.com/v1';

const LOCAL_HOSTS = new Set([
  '127.0.0.1',
  'localhost',
  '::1',
]);

const TRUE_VALUES = new Set([
  '1',
  'true',
  'yes',
  'on',
  'enabled',
]);

export const
  KORLIX_VAPI_NOVA_PUBLIC_BASE_INSTRUCTIONS =
  [
    (
      'You are Nova, the public telephone '
      + 'assistant for KORLIX.'
    ),
    (
      'Speak naturally, clearly, and '
      + 'concisely for a live telephone '
      + 'conversation.'
    ),
    (
      'Never claim to be a human. Identify '
      + 'yourself as Nova when asked.'
    ),
    (
      'This telephone channel is public-caller '
      + 'mode. It has no Brain Vault access, '
      + 'no private account memory, no saved '
      + 'user files, and no authority to reveal '
      + 'account-specific information.'
    ),
    (
      'Never request or repeat passwords, '
      + 'full Social Security numbers, full '
      + 'payment-card numbers, authentication '
      + 'codes, API keys, private tokens, or '
      + 'database credentials.'
    ),
    (
      'For private account actions, billing '
      + 'changes, identity verification, '
      + 'credit-report details, or Brain Vault '
      + 'content, direct the caller to the '
      + 'authenticated KORLIX app or an '
      + 'approved human support channel.'
    ),
    (
      'Do not place outbound calls, transfer '
      + 'calls, purchase phone numbers, '
      + 'schedule appointments, make payments, '
      + 'or promise actions that are not enabled.'
    ),
    (
      'When information is uncertain, say so '
      + 'plainly. Keep most responses under '
      + 'four short spoken sentences unless '
      + 'the caller asks for more detail.'
    ),
  ].join('\n');

export class KorlixVapiNovaRuntimeError
  extends Error {
  constructor(
    code,
    message = code,
  ) {
    super(message);

    this.name =
      'KorlixVapiNovaRuntimeError';

    this.code = code;
  }
}

function asText(value) {
  return String(
    value ?? '',
  ).trim();
}

function enabled(value) {
  return TRUE_VALUES.has(
    asText(value).toLowerCase(),
  );
}

function integerInRange(
  value,
  fallback,
  minimum,
  maximum,
) {
  const parsed =
    Number.parseInt(
      asText(value),
      10,
    );

  if (
    !Number.isFinite(parsed)
  ) {
    return fallback;
  }

  return Math.min(
    maximum,
    Math.max(
      minimum,
      parsed,
    ),
  );
}

function isLocalHost(
  hostname,
) {
  return LOCAL_HOSTS.has(
    asText(
      hostname,
    ).toLowerCase(),
  );
}

function validatedBaseUrl(
  environment,
) {
  const raw =
    asText(
      environment
        ?.KORLIX_VAPI_NOVA_OPENAI_BASE_URL,
    )
    || DEFAULT_BASE_URL;

  let url;

  try {
    url = new URL(raw);

  } catch {
    throw new KorlixVapiNovaRuntimeError(
      'nova_model_base_url_invalid',
      'Nova model base URL is invalid.',
    );
  }

  const localHttpAllowed =
    enabled(
      environment
        ?.KORLIX_VAPI_NOVA_ALLOW_INSECURE_LOCAL_MODEL,
    );

  if (
    url.protocol !== 'https:'
  ) {
    const permittedLocalHttp =
      url.protocol === 'http:'
      && isLocalHost(
        url.hostname,
      )
      && localHttpAllowed;

    if (!permittedLocalHttp) {
      throw new KorlixVapiNovaRuntimeError(
        'nova_model_base_url_requires_https',
        (
          'Nova model base URL '
          + 'must use HTTPS.'
        ),
      );
    }
  }

  url.pathname =
    url.pathname.replace(
      /\/+$/,
      '',
    );

  url.search = '';
  url.hash = '';

  return url;
}

function responsesEndpoint(
  environment,
) {
  const url =
    validatedBaseUrl(
      environment,
    );

  if (
    !url.pathname.endsWith(
      '/responses',
    )
  ) {
    url.pathname =
      `${url.pathname}/responses`
        .replace(
          /\/{2,}/g,
          '/',
        );
  }

  return url.toString();
}

function modelName(
  environment,
) {
  return (
    asText(
      environment
        ?.KORLIX_VAPI_NOVA_MODEL,
    )
    || asText(
      environment
        ?.OPENAI_MODEL,
    )
    || asText(
      environment
        ?.OPENAI_CHAT_MODEL,
    )
  );
}

function apiKey(
  environment,
) {
  return (
    asText(
      environment
        ?.KORLIX_VAPI_NOVA_OPENAI_API_KEY,
    )
    || asText(
      environment
        ?.OPENAI_API_KEY,
    )
  );
}

function publicInstructions(
  environment,
) {
  const approved =
    asText(
      environment
        ?.KORLIX_VAPI_NOVA_PUBLIC_INSTRUCTIONS,
    ).slice(
      0,
      12000,
    );

  if (!approved) {
    return (
      KORLIX_VAPI_NOVA_PUBLIC_BASE_INSTRUCTIONS
    );
  }

  return (
    KORLIX_VAPI_NOVA_PUBLIC_BASE_INSTRUCTIONS
    + '\n\nApproved public KORLIX '
    + 'telephone instructions:\n'
    + approved
  );
}

function conversationInput(
  messages,
) {
  if (
    !Array.isArray(messages)
  ) {
    return [];
  }

  return messages
    .slice(-48)
    .map(
      (message) => ({
        role:
          asText(
            message?.role,
          ).toLowerCase(),

        content:
          asText(
            message?.content,
          ).slice(
            0,
            12000,
          ),
      }),
    )
    .filter(
      (message) => (
        (
          message.role === 'user'
          || message.role === 'assistant'
        )
        && message.content
      ),
    );
}

function extractOutputText(
  payload,
) {
  if (
    typeof payload?.output_text
      === 'string'
    && payload.output_text.trim()
  ) {
    return payload
      .output_text
      .trim();
  }

  const pieces = [];

  for (
    const item
    of (
      Array.isArray(
        payload?.output,
      )
        ? payload.output
        : []
    )
  ) {
    for (
      const part
      of (
        Array.isArray(
          item?.content,
        )
          ? item.content
          : []
      )
    ) {
      if (
        typeof part?.text
          === 'string'
      ) {
        pieces.push(
          part.text,
        );
      }

      if (
        typeof part?.output_text
          === 'string'
      ) {
        pieces.push(
          part.output_text,
        );
      }
    }
  }

  const joined =
    pieces.join('').trim();

  if (joined) {
    return joined;
  }

  const chatText =
    payload
      ?.choices
      ?.[0]
      ?.message
      ?.content;

  return (
    typeof chatText
      === 'string'
      ? chatText.trim()
      : ''
  );
}

function speechText(value) {
  return asText(value)
    .replace(
      /```[\s\S]*?```/g,
      ' ',
    )
    .replace(
      /`([^`]+)`/g,
      '$1',
    )
    .replace(
      /^#{1,6}\s+/gm,
      '',
    )
    .replace(
      /\[([^\]]+)\]\([^\)]+\)/g,
      '$1',
    )
    .replace(
      /[*_~]+/g,
      '',
    )
    .replace(
      /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g,
      ' ',
    )
    .replace(
      /\s+/g,
      ' ',
    )
    .trim()
    .slice(
      0,
      5000,
    );
}

function safeProviderMessage(
  value,
) {
  return asText(value)
    .replace(
      /sbp_[A-Za-z0-9_-]+/g,
      '<REDACTED>',
    )
    .replace(
      /sk-[A-Za-z0-9_-]+/g,
      '<REDACTED>',
    )
    .replace(
      /Bearer\s+\S+/gi,
      'Bearer <REDACTED>',
    )
    .slice(
      0,
      300,
    );
}

function callIdFromEvent(
  event,
) {
  return asText(
    event
      ?.message
      ?.call
      ?.id
    ?? event
      ?.message
      ?.callId
    ?? event
      ?.callId,
  ).slice(
    0,
    120,
  );
}

export function createKorlixVapiNovaRuntime(
  options = {},
) {
  const environment =
    options.environment
    ?? process.env;

  const fetchImpl =
    options.fetchImpl
    ?? globalThis.fetch;

  const logger =
    options.logger
    ?? console;

  const status = () => ({
    assistantName:
      'Nova',

    publicCallerMode:
      true,

    brainVaultAccessEnabled:
      false,

    privateAccountMemoryEnabled:
      false,

    transcriptPersistenceEnabled:
      false,

    eventPayloadLoggingEnabled:
      false,

    eventMetadataLoggingEnabled:
      enabled(
        environment
          ?.KORLIX_VAPI_EVENT_METADATA_LOGGING_ENABLED,
      ),

    apiKeyConfigured:
      Boolean(
        apiKey(
          environment,
        ),
      ),

    modelConfigured:
      Boolean(
        modelName(
          environment,
        ),
      ),

    publicInstructionsConfigured:
      Boolean(
        asText(
          environment
            ?.KORLIX_VAPI_NOVA_PUBLIC_INSTRUCTIONS,
        ),
      ),
  });

  const respond = async (
    request = {},
  ) => {
    if (
      typeof fetchImpl
        !== 'function'
    ) {
      throw new KorlixVapiNovaRuntimeError(
        'nova_model_fetch_unavailable',
        (
          'Nova model transport '
          + 'is unavailable.'
        ),
      );
    }

    const key =
      apiKey(
        environment,
      );

    if (!key) {
      throw new KorlixVapiNovaRuntimeError(
        'nova_model_api_key_not_configured',
        (
          'Nova model API key '
          + 'is not configured.'
        ),
      );
    }

    const model =
      modelName(
        environment,
      );

    if (!model) {
      throw new KorlixVapiNovaRuntimeError(
        'nova_model_not_configured',
        (
          'Nova model is '
          + 'not configured.'
        ),
      );
    }

    const input =
      conversationInput(
        request?.messages,
      );

    if (!input.length) {
      throw new KorlixVapiNovaRuntimeError(
        'nova_model_messages_required',
        (
          'Nova requires at least '
          + 'one caller message.'
        ),
      );
    }

    const controller =
      new AbortController();

    const timeoutMs =
      integerInRange(
        environment
          ?.KORLIX_VAPI_NOVA_MODEL_TIMEOUT_MS,

        25000,
        3000,
        60000,
      );

    const timeout =
      setTimeout(
        () =>
          controller.abort(),

        timeoutMs,
      );

    try {
      const response =
        await fetchImpl(
          responsesEndpoint(
            environment,
          ),

          {
            method:
              'POST',

            headers: {
              authorization:
                `Bearer ${key}`,

              'content-type':
                'application/json',
            },

            body:
              JSON.stringify({
                model,

                instructions:
                  publicInstructions(
                    environment,
                  ),

                input,

                max_output_tokens:
                  integerInRange(
                    environment
                      ?.KORLIX_VAPI_NOVA_MAX_OUTPUT_TOKENS,

                    220,
                    48,
                    800,
                  ),

                store:
                  false,
              }),

            signal:
              controller.signal,
          },
        );

      let payload = null;

      try {
        payload =
          await response.json();

      } catch {
        payload = null;
      }

      if (!response.ok) {
        const providerMessage =
          safeProviderMessage(
            payload
              ?.error
              ?.message
            ?? payload
              ?.message
            ?? `HTTP ${response.status}`,
          );

        throw new KorlixVapiNovaRuntimeError(
          'nova_model_request_failed',
          (
            'Nova model request failed: '
            + (
              providerMessage
              || 'provider error'
            )
          ),
        );
      }

      const content =
        speechText(
          extractOutputText(
            payload,
          ),
        );

      if (!content) {
        throw new KorlixVapiNovaRuntimeError(
          'nova_model_empty_response',
          (
            'Nova model returned '
            + 'an empty response.'
          ),
        );
      }

      return {
        text:
          content,

        assistantName:
          'Nova',

        publicCallerMode:
          true,
      };

    } catch (error) {
      if (
        error?.name
        === 'AbortError'
      ) {
        throw new KorlixVapiNovaRuntimeError(
          'nova_model_timeout',
          (
            'Nova model request '
            + 'timed out.'
          ),
        );
      }

      throw error;

    } finally {
      clearTimeout(
        timeout,
      );
    }
  };

  const acceptEvent = async (
    event = {},
  ) => {
    const type =
      asText(
        event?.type
        ?? event
          ?.message
          ?.type,
      ).slice(
        0,
        120,
      );

    const callId =
      callIdFromEvent(
        event,
      );

    if (
      enabled(
        environment
          ?.KORLIX_VAPI_EVENT_METADATA_LOGGING_ENABLED,
      )
    ) {
      logger?.info?.(
        'KORLIX_VAPI_EVENT_METADATA',

        {
          assistantName:
            'Nova',

          type,

          callId,

          payloadStored:
            false,

          transcriptStored:
            false,
        },
      );
    }

    return {
      accepted:
        true,

      type,

      callId,

      payloadStored:
        false,

      transcriptStored:
        false,
    };
  };

  return Object.freeze({
    respond,
    acceptEvent,
    status,
  });
}
