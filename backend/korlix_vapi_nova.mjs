import {
  randomUUID,
  timingSafeEqual,
} from 'node:crypto';

export const KORLIX_VAPI_NOVA_ROUTES =
  Object.freeze({
    health:
      '/api/vapi/health',

    chatCompletions:
      '/api/vapi/nova/chat/completions',

    webhook:
      '/api/vapi/webhook',

    adminConfigCheck:
      '/api/vapi/admin/config-check',
  });

const TRUE_VALUES = new Set([
  '1',
  'true',
  'yes',
  'on',
  'enabled',
]);

function text(value) {
  return String(
    value ?? '',
  ).trim();
}

function envText(
  environment,
  name,
) {
  return text(
    environment?.[name],
  );
}

function envEnabled(
  environment,
  name,
) {
  return TRUE_VALUES.has(
    envText(
      environment,
      name,
    ).toLowerCase(),
  );
}

function csvSet(value) {
  return new Set(
    text(value)
      .split(',')
      .map(
        (item) =>
          item.trim(),
      )
      .filter(Boolean),
  );
}

function header(
  request,
  name,
) {
  const lower =
    name.toLowerCase();

  const headers =
    request?.headers
    ?? {};

  const key =
    Object.keys(headers)
      .find(
        (item) =>
          item.toLowerCase()
          === lower,
      );

  let value =
    headers[lower]
    ?? headers[name]
    ?? (
      key
        ? headers[key]
        : undefined
    );

  if (
    value == null
    && typeof request?.get
      === 'function'
  ) {
    value =
      request.get(name);
  }

  if (
    Array.isArray(value)
  ) {
    value = value[0];
  }

  return text(value);
}

function suppliedSecret(
  request,
) {
  const authorization =
    header(
      request,
      'authorization',
    );

  if (
    authorization
      .toLowerCase()
      .startsWith(
        'bearer ',
      )
  ) {
    return authorization
      .slice(7)
      .trim();
  }

  return (
    header(
      request,
      'x-vapi-secret',
    )
    || header(
      request,
      'x-korlix-vapi-secret',
    )
  );
}

function constantTimeEqual(
  leftValue,
  rightValue,
) {
  const left =
    Buffer.from(
      text(leftValue),
      'utf8',
    );

  const right =
    Buffer.from(
      text(rightValue),
      'utf8',
    );

  if (
    !left.length
    || !right.length
    || left.length
      !== right.length
  ) {
    return false;
  }

  return timingSafeEqual(
    left,
    right,
  );
}

function authorizeVapi(
  request,
  environment,
) {
  const configured =
    envText(
      environment,
      'KORLIX_VAPI_SERVER_SECRET',
    );

  if (!configured) {
    return {
      ok: false,
      status: 503,
      code:
        'vapi_server_secret_not_configured',
    };
  }

  if (
    !constantTimeEqual(
      suppliedSecret(request),
      configured,
    )
  ) {
    return {
      ok: false,
      status: 401,
      code:
        'vapi_authentication_required',
    };
  }

  return {
    ok: true,
    status: 200,
    code: 'authorized',
  };
}

function sendJson(
  response,
  status,
  payload,
) {
  return response
    .status(status)
    .json(payload);
}

function normalizeUser(
  value,
) {
  if (!value) {
    return null;
  }

  if (value.user) {
    return value.user;
  }

  if (value.data?.user) {
    return value.data.user;
  }

  return value;
}

function developerIds(
  environment,
) {
  return csvSet(
    envText(
      environment,
      'KORLIX_VAPI_DEVELOPER_UIDS',
    )
    || envText(
      environment,
      'KORLIX_VAPI_DEVELOPER_UID',
    ),
  );
}

function configuredAssistantId(
  environment,
) {
  return (
    envText(
      environment,
      'KORLIX_VAPI_NOVA_ASSISTANT_ID',
    )
    || envText(
      environment,
      'VAPI_NOVA_ASSISTANT_ID',
    )
  );
}

function configSnapshot(
  environment,
  novaResponder,
) {
  return {
    feature:
      'vapi_nova_telephone',

    assistantName:
      'Nova',

    developerOnly:
      true,

    enabled:
      envEnabled(
        environment,
        'KORLIX_VAPI_ENABLED',
      ),

    serverSecretConfigured:
      Boolean(
        envText(
          environment,
          'KORLIX_VAPI_SERVER_SECRET',
        ),
      ),

    developerUidConfigured:
      developerIds(
        environment,
      ).size > 0,

    assistantIdConfigured:
      Boolean(
        configuredAssistantId(
          environment,
        ),
      ),

    novaResponderConnected:
      typeof novaResponder
        === 'function',

    outboundCallingEnabled:
      false,

    phoneNumberPurchaseEnabled:
      false,

    publicAdminAccess:
      false,

    regularUserAdminAccess:
      false,
  };
}

function normalizedMessages(
  body,
) {
  if (
    !Array.isArray(
      body?.messages,
    )
  ) {
    return null;
  }

  const messages =
    body.messages
      .slice(-64)
      .map(
        (message) => ({
          role:
            text(
              message?.role,
            ),

          content:
            text(
              message?.content,
            ),
        }),
      )
      .filter(
        (message) =>
          message.role
          && message.content,
      );

  return messages.length
    ? messages
    : null;
}

function replyText(value) {
  if (
    typeof value
    === 'string'
  ) {
    return value.trim();
  }

  if (
    typeof value?.text
    === 'string'
  ) {
    return value.text.trim();
  }

  if (
    typeof value?.content
    === 'string'
  ) {
    return value.content.trim();
  }

  if (
    typeof value
      ?.message
      ?.content
    === 'string'
  ) {
    return value
      .message
      .content
      .trim();
  }

  return '';
}

function completionId() {
  return (
    'chatcmpl-korlix-nova-'
    + randomUUID()
      .replaceAll(
        '-',
        '',
      )
  );
}

function streamCompletion(
  response,
  {
    id,
    model,
    created,
    content,
  },
) {
  response.setHeader(
    'Content-Type',
    'text/event-stream',
  );

  response.setHeader(
    'Cache-Control',
    'no-cache',
  );

  response.setHeader(
    'Connection',
    'keep-alive',
  );

  if (
    typeof response
      .flushHeaders
    === 'function'
  ) {
    response.flushHeaders();
  }

  const emit = (
    delta,
    finishReason = null,
  ) => {
    response.write(
      `data: ${
        JSON.stringify({
          id,
          object:
            'chat.completion.chunk',
          created,
          model,
          choices: [
            {
              index: 0,
              delta,
              finish_reason:
                finishReason,
            },
          ],
        })
      }\n\n`,
    );
  };

  emit({
    role: 'assistant',
  });

  for (
    let index = 0;
    index < content.length;
    index += 80
  ) {
    emit({
      content:
        content.slice(
          index,
          index + 80,
        ),
    });
  }

  emit(
    {},
    'stop',
  );

  response.write(
    'data: [DONE]\n\n',
  );

  response.end();
}

function webhookToolCalls(
  message,
) {
  if (
    Array.isArray(
      message?.toolCallList,
    )
  ) {
    return message.toolCallList;
  }

  if (
    Array.isArray(
      message
        ?.toolWithToolCallList,
    )
  ) {
    return message
      .toolWithToolCallList
      .map(
        (entry) => ({
          ...entry?.toolCall,

          name:
            entry
              ?.toolCall
              ?.name
            || entry?.name,
        }),
      )
      .filter(Boolean);
  }

  return [];
}

function failClosedToolResults(
  message,
) {
  return webhookToolCalls(
    message,
  ).map(
    (toolCall) => ({
      name:
        text(
          toolCall?.name,
        )
        || 'unknown_tool',

      toolCallId:
        text(
          toolCall?.id,
        )
        || 'unknown',

      result:
        JSON.stringify({
          ok: false,

          code:
            'vapi_tool_not_enabled',

          message:
            'Telephone tools are not enabled.',
        }),
    }),
  );
}

export function installKorlixVapiNovaRoutes(
  app,
  options = {},
) {
  if (
    !app
    || typeof app.get
      !== 'function'
    || typeof app.post
      !== 'function'
  ) {
    throw new TypeError(
      'An Express-compatible app is required.',
    );
  }

  const environment =
    options.environment
    ?? process.env;

  const getAuthenticatedUser =
    options.getAuthenticatedUser;

  const novaResponder =
    options.novaResponder;

  const eventSink =
    options.eventSink;

  const now =
    options.now
    ?? Date.now;

  app.get(
    KORLIX_VAPI_NOVA_ROUTES
      .health,

    (
      request,
      response,
    ) => {
      const authorization =
        authorizeVapi(
          request,
          environment,
        );

      if (
        !authorization.ok
      ) {
        return sendJson(
          response,
          authorization.status,
          {
            ok: false,
            code:
              authorization.code,
          },
        );
      }

      return sendJson(
        response,
        200,
        {
          ok: true,

          service:
            'korlix-vapi-nova',

          assistantName:
            'Nova',

          developerOnly:
            true,

          enabled:
            envEnabled(
              environment,
              'KORLIX_VAPI_ENABLED',
            ),

          outboundCallingEnabled:
            false,

          phoneNumberPurchaseEnabled:
            false,
        },
      );
    },
  );

  app.post(
    KORLIX_VAPI_NOVA_ROUTES
      .chatCompletions,

    async (
      request,
      response,
    ) => {
      const authorization =
        authorizeVapi(
          request,
          environment,
        );

      if (
        !authorization.ok
      ) {
        return sendJson(
          response,
          authorization.status,
          {
            ok: false,
            code:
              authorization.code,
          },
        );
      }

      if (
        !envEnabled(
          environment,
          'KORLIX_VAPI_ENABLED',
        )
      ) {
        return sendJson(
          response,
          503,
          {
            ok: false,
            code:
              'vapi_nova_disabled',
          },
        );
      }

      if (
        typeof novaResponder
        !== 'function'
      ) {
        return sendJson(
          response,
          503,
          {
            ok: false,

            code:
              'nova_telephone_bridge_not_connected',
          },
        );
      }

      const body =
        request.body
        && typeof request.body
          === 'object'
          ? request.body
          : {};

      const messages =
        normalizedMessages(
          body,
        );

      if (!messages) {
        return sendJson(
          response,
          400,
          {
            ok: false,
            code:
              'messages_required',
          },
        );
      }

      try {
        const result =
          await novaResponder({
            assistantName:
              'Nova',

            source:
              'vapi-telephone',

            accessScope:
              'public-caller-no-admin',

            messages,

            model:
              text(body.model)
              || 'korlix-nova',

            temperature:
              Number.isFinite(
                Number(
                  body.temperature,
                ),
              )
                ? Number(
                    body.temperature,
                  )
                : 0.7,

            callId:
              header(
                request,
                'x-vapi-call-id',
              )
              || text(
                body?.call?.id,
              )
              || text(
                body
                  ?.metadata
                  ?.callId,
              ),
          });

        const content =
          replyText(result);

        if (!content) {
          return sendJson(
            response,
            503,
            {
              ok: false,

              code:
                'nova_telephone_empty_response',
            },
          );
        }

        const id =
          completionId();

        const model =
          text(body.model)
          || 'korlix-nova';

        const created =
          Math.floor(
            Number(now())
            / 1000,
          );

        if (
          body.stream === false
        ) {
          return sendJson(
            response,
            200,
            {
              id,

              object:
                'chat.completion',

              created,

              model,

              choices: [
                {
                  index: 0,

                  message: {
                    role:
                      'assistant',

                    content,
                  },

                  finish_reason:
                    'stop',
                },
              ],
            },
          );
        }

        return streamCompletion(
          response,
          {
            id,
            model,
            created,
            content,
          },
        );

      } catch {
        return sendJson(
          response,
          503,
          {
            ok: false,

            code:
              'nova_telephone_bridge_unavailable',
          },
        );
      }
    },
  );

  app.post(
    KORLIX_VAPI_NOVA_ROUTES
      .webhook,

    async (
      request,
      response,
    ) => {
      const authorization =
        authorizeVapi(
          request,
          environment,
        );

      if (
        !authorization.ok
      ) {
        return sendJson(
          response,
          authorization.status,
          {
            ok: false,
            code:
              authorization.code,
          },
        );
      }

      const message =
        request.body
          ?.message;

      const type =
        text(
          message?.type,
        );

      if (!type) {
        return sendJson(
          response,
          400,
          {
            ok: false,

            code:
              'vapi_message_type_required',
          },
        );
      }

      if (
        type
        === 'assistant-request'
      ) {
        if (
          !envEnabled(
            environment,
            'KORLIX_VAPI_ENABLED',
          )
        ) {
          return sendJson(
            response,
            503,
            {
              error:
                'Nova telephone service is disabled.',
            },
          );
        }

        const assistantId =
          configuredAssistantId(
            environment,
          );

        if (!assistantId) {
          return sendJson(
            response,
            503,
            {
              error:
                'Nova telephone assistant is not configured.',
            },
          );
        }

        return sendJson(
          response,
          200,
          {
            assistantId,
          },
        );
      }

      if (
        type === 'tool-calls'
      ) {
        return sendJson(
          response,
          200,
          {
            results:
              failClosedToolResults(
                message,
              ),
          },
        );
      }

      if (
        type
        === 'transfer-destination-request'
      ) {
        return sendJson(
          response,
          403,
          {
            error:
              'Call transfer is not enabled.',
          },
        );
      }

      if (
        type
        === 'knowledge-base-request'
      ) {
        return sendJson(
          response,
          503,
          {
            error:
              'Telephone knowledge base is not connected.',
          },
        );
      }

      if (
        typeof eventSink
        === 'function'
      ) {
        try {
          await eventSink({
            assistantName:
              'Nova',

            source:
              'vapi-telephone',

            type,
            message,
          });

        } catch {
          return sendJson(
            response,
            503,
            {
              ok: false,

              code:
                'vapi_event_sink_unavailable',
            },
          );
        }
      }

      return sendJson(
        response,
        202,
        {
          ok: true,
          accepted: true,
          type,
        },
      );
    },
  );

  app.post(
    KORLIX_VAPI_NOVA_ROUTES
      .adminConfigCheck,

    async (
      request,
      response,
    ) => {
      if (
        typeof getAuthenticatedUser
        !== 'function'
      ) {
        return sendJson(
          response,
          503,
          {
            ok: false,

            code:
              'korlix_authentication_not_connected',
          },
        );
      }

      let authenticated;

      try {
        authenticated =
          await getAuthenticatedUser(
            request,
            response,
          );

      } catch {
        return sendJson(
          response,
          401,
          {
            ok: false,

            code:
              'authentication_required',
          },
        );
      }

      if (
        response.headersSent
      ) {
        return undefined;
      }

      const user =
        normalizeUser(
          authenticated,
        );

      const userId =
        text(
          user?.id
          ?? user?.user_id
          ?? user?.uid,
        );

      if (!userId) {
        return sendJson(
          response,
          401,
          {
            ok: false,

            code:
              'authentication_required',
          },
        );
      }

      const allowed =
        developerIds(
          environment,
        );

      if (!allowed.size) {
        return sendJson(
          response,
          503,
          {
            ok: false,

            code:
              'vapi_developer_uid_not_configured',
          },
        );
      }

      if (
        !allowed.has(userId)
      ) {
        return sendJson(
          response,
          403,
          {
            ok: false,

            code:
              'developer_access_required',
          },
        );
      }

      return sendJson(
        response,
        200,
        {
          ok: true,

          ...configSnapshot(
            environment,
            novaResponder,
          ),
        },
      );
    },
  );

  return Object.freeze({
    assistantName:
      'Nova',

    routes:
      KORLIX_VAPI_NOVA_ROUTES,

    developerOnly:
      true,

    outboundCallingEnabled:
      false,

    phoneNumberPurchaseEnabled:
      false,
  });
}
