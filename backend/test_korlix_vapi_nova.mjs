import test from 'node:test';
import assert from 'node:assert/strict';

import {
  installKorlixVapiNovaRoutes,
  KORLIX_VAPI_NOVA_ROUTES,
} from './korlix_vapi_nova.mjs';

function createApp() {
  const routes = [];

  return {
    routes,

    get(path, handler) {
      routes.push({
        method: 'GET',
        path,
        handler,
      });
    },

    post(path, handler) {
      routes.push({
        method: 'POST',
        path,
        handler,
      });
    },
  };
}

function createResponse() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    chunks: [],
    ended: false,

    get headersSent() {
      return (
        this.ended
        || this.body !== undefined
        || this.chunks.length > 0
      );
    },

    status(code) {
      this.statusCode = code;
      return this;
    },

    json(value) {
      this.body = value;
      this.ended = true;
      return this;
    },

    setHeader(name, value) {
      this.headers[
        String(name)
          .toLowerCase()
      ] = value;
    },

    write(value) {
      this.chunks.push(
        String(value),
      );

      return true;
    },

    end(value) {
      if (value != null) {
        this.write(value);
      }

      this.ended = true;
      return this;
    },

    flushHeaders() {},
  };
}

async function invoke(
  app,
  method,
  path,
  {
    headers = {},
    body = {},
  } = {},
) {
  const route =
    app.routes.find(
      (item) =>
        item.method === method
        && item.path === path,
    );

  assert.ok(
    route,
    `Route not found: ${method} ${path}`,
  );

  const normalizedHeaders =
    Object.fromEntries(
      Object.entries(
        headers,
      ).map(
        ([key, value]) => [
          key.toLowerCase(),
          value,
        ],
      ),
    );

  const request = {
    headers:
      normalizedHeaders,

    body,

    get(name) {
      return normalizedHeaders[
        String(name)
          .toLowerCase()
      ];
    },
  };

  const response =
    createResponse();

  await route.handler(
    request,
    response,
  );

  return response;
}

function bearer(secret) {
  return {
    authorization:
      `Bearer ${secret}`,
  };
}

function baseEnvironment() {
  return {
    KORLIX_VAPI_SERVER_SECRET:
      'server-secret',

    KORLIX_VAPI_ENABLED:
      'true',

    KORLIX_VAPI_DEVELOPER_UIDS:
      'developer-1',

    KORLIX_VAPI_NOVA_ASSISTANT_ID:
      'assistant-nova-1',
  };
}

test(
  'registers exactly four guarded routes',
  () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),
      },
    );

    assert.deepEqual(
      app.routes.map(
        ({
          method,
          path,
        }) =>
          `${method} ${path}`,
      ),
      [
        'GET /api/vapi/health',
        (
          'POST /api/vapi/nova/'
          + 'chat/completions'
        ),
        'POST /api/vapi/webhook',
        (
          'POST /api/vapi/'
          + 'admin/config-check'
        ),
      ],
    );
  },
);

test(
  'health fails closed when server secret is absent',
  async () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment: {},
      },
    );

    const response =
      await invoke(
        app,
        'GET',
        KORLIX_VAPI_NOVA_ROUTES
          .health,
      );

    assert.equal(
      response.statusCode,
      503,
    );

    assert.equal(
      response.body.code,
      'vapi_server_secret_not_configured',
    );
  },
);

test(
  'health rejects an incorrect credential',
  async () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),
      },
    );

    const response =
      await invoke(
        app,
        'GET',
        KORLIX_VAPI_NOVA_ROUTES
          .health,
        {
          headers:
            bearer(
              'wrong-secret',
            ),
        },
      );

    assert.equal(
      response.statusCode,
      401,
    );
  },
);

test(
  'health accepts bearer auth without exposing secrets',
  async () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),
      },
    );

    const response =
      await invoke(
        app,
        'GET',
        KORLIX_VAPI_NOVA_ROUTES
          .health,
        {
          headers:
            bearer(
              'server-secret',
            ),
        },
      );

    assert.equal(
      response.statusCode,
      200,
    );

    assert.equal(
      response
        .body
        .assistantName,
      'Nova',
    );

    assert.equal(
      JSON.stringify(
        response.body,
      ).includes(
        'server-secret',
      ),
      false,
    );
  },
);

test(
  'regular KORLIX users cannot access Vapi admin configuration',
  async () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),

        getAuthenticatedUser:
          async () => ({
            id:
              'regular-user',
          }),
      },
    );

    const response =
      await invoke(
        app,
        'POST',
        KORLIX_VAPI_NOVA_ROUTES
          .adminConfigCheck,
      );

    assert.equal(
      response.statusCode,
      403,
    );

    assert.equal(
      response.body.code,
      'developer_access_required',
    );
  },
);

test(
  'configured developer can inspect redacted Vapi status',
  async () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),

        getAuthenticatedUser:
          async () => ({
            id:
              'developer-1',
          }),

        novaResponder:
          async () =>
            'Ready.',
      },
    );

    const response =
      await invoke(
        app,
        'POST',
        KORLIX_VAPI_NOVA_ROUTES
          .adminConfigCheck,
      );

    assert.equal(
      response.statusCode,
      200,
    );

    assert.equal(
      response
        .body
        .developerOnly,
      true,
    );

    assert.equal(
      response
        .body
        .outboundCallingEnabled,
      false,
    );

    assert.equal(
      response
        .body
        .phoneNumberPurchaseEnabled,
      false,
    );

    assert.equal(
      JSON.stringify(
        response.body,
      ).includes(
        'server-secret',
      ),
      false,
    );
  },
);

test(
  'chat completion is unavailable while feature is disabled',
  async () => {
    const app =
      createApp();

    const environment =
      baseEnvironment();

    environment
      .KORLIX_VAPI_ENABLED =
        'false';

    installKorlixVapiNovaRoutes(
      app,
      {
        environment,

        novaResponder:
          async () =>
            'Unused.',
      },
    );

    const response =
      await invoke(
        app,
        'POST',
        KORLIX_VAPI_NOVA_ROUTES
          .chatCompletions,
        {
          headers:
            bearer(
              'server-secret',
            ),

          body: {
            stream: false,

            messages: [
              {
                role: 'user',
                content:
                  'Hello',
              },
            ],
          },
        },
      );

    assert.equal(
      response.statusCode,
      503,
    );

    assert.equal(
      response.body.code,
      'vapi_nova_disabled',
    );
  },
);

test(
  'chat completion fails closed until Nova responder is connected',
  async () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),
      },
    );

    const response =
      await invoke(
        app,
        'POST',
        KORLIX_VAPI_NOVA_ROUTES
          .chatCompletions,
        {
          headers:
            bearer(
              'server-secret',
            ),

          body: {
            stream: false,

            messages: [
              {
                role: 'user',
                content:
                  'Hello',
              },
            ],
          },
        },
      );

    assert.equal(
      response.statusCode,
      503,
    );

    assert.equal(
      response.body.code,
      'nova_telephone_bridge_not_connected',
    );
  },
);

test(
  'non-stream completion carries Nova identity to responder',
  async () => {
    const app =
      createApp();

    let captured;

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),

        novaResponder:
          async (request) => {
            captured =
              request;

            return (
              'This is Nova.'
            );
          },
      },
    );

    const response =
      await invoke(
        app,
        'POST',
        KORLIX_VAPI_NOVA_ROUTES
          .chatCompletions,
        {
          headers: {
            ...bearer(
              'server-secret',
            ),

            'x-vapi-call-id':
              'call-123',
          },

          body: {
            stream: false,

            model:
              'korlix-nova',

            messages: [
              {
                role: 'user',

                content:
                  'Who are you?',
              },
            ],
          },
        },
      );

    assert.equal(
      response.statusCode,
      200,
    );

    assert.equal(
      captured
        .assistantName,
      'Nova',
    );

    assert.equal(
      captured.callId,
      'call-123',
    );

    assert.equal(
      response
        .body
        .choices[0]
        .message
        .content,
      'This is Nova.',
    );
  },
);

test(
  'stream completion returns OpenAI-compatible SSE and DONE',
  async () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),

        novaResponder:
          async () =>
            'Nova telephone response.',
      },
    );

    const response =
      await invoke(
        app,
        'POST',
        KORLIX_VAPI_NOVA_ROUTES
          .chatCompletions,
        {
          headers:
            bearer(
              'server-secret',
            ),

          body: {
            stream: true,

            messages: [
              {
                role: 'user',
                content:
                  'Hello',
              },
            ],
          },
        },
      );

    const stream =
      response
        .chunks
        .join('');

    assert.equal(
      response.statusCode,
      200,
    );

    assert.match(
      response.headers[
        'content-type'
      ],
      /text\/event-stream/,
    );

    assert.match(
      stream,
      /chat\.completion\.chunk/,
    );

    assert.match(
      stream,
      /data: \[DONE\]/,
    );
  },
);

test(
  'assistant-request returns only the configured Nova assistant ID',
  async () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),
      },
    );

    const response =
      await invoke(
        app,
        'POST',
        KORLIX_VAPI_NOVA_ROUTES
          .webhook,
        {
          headers:
            bearer(
              'server-secret',
            ),

          body: {
            message: {
              type:
                'assistant-request',
            },
          },
        },
      );

    assert.equal(
      response.statusCode,
      200,
    );

    assert.deepEqual(
      response.body,
      {
        assistantId:
          'assistant-nova-1',
      },
    );
  },
);

test(
  'tool calls return fail-closed Vapi results',
  async () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),
      },
    );

    const response =
      await invoke(
        app,
        'POST',
        KORLIX_VAPI_NOVA_ROUTES
          .webhook,
        {
          headers:
            bearer(
              'server-secret',
            ),

          body: {
            message: {
              type:
                'tool-calls',

              toolCallList: [
                {
                  id:
                    'tool-1',

                  name:
                    'placeOutboundCall',

                  parameters: {},
                },
              ],
            },
          },
        },
      );

    assert.equal(
      response.statusCode,
      200,
    );

    assert.equal(
      response
        .body
        .results[0]
        .toolCallId,
      'tool-1',
    );

    assert.match(
      response
        .body
        .results[0]
        .result,
      /vapi_tool_not_enabled/,
    );
  },
);

test(
  'informational events are accepted by the event sink',
  async () => {
    const app =
      createApp();

    const events = [];

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),

        eventSink:
          async (event) =>
            events.push(
              event,
            ),
      },
    );

    const response =
      await invoke(
        app,
        'POST',
        KORLIX_VAPI_NOVA_ROUTES
          .webhook,
        {
          headers:
            bearer(
              'server-secret',
            ),

          body: {
            message: {
              type:
                'end-of-call-report',

              call: {
                id:
                  'call-1',
              },
            },
          },
        },
      );

    assert.equal(
      response.statusCode,
      202,
    );

    assert.equal(
      events.length,
      1,
    );

    assert.equal(
      events[0]
        .assistantName,
      'Nova',
    );
  },
);

test(
  'transfer destination requests are denied',
  async () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),
      },
    );

    const response =
      await invoke(
        app,
        'POST',
        KORLIX_VAPI_NOVA_ROUTES
          .webhook,
        {
          headers:
            bearer(
              'server-secret',
            ),

          body: {
            message: {
              type:
                'transfer-destination-request',
            },
          },
        },
      );

    assert.equal(
      response.statusCode,
      403,
    );
  },
);

test(
  'no outbound-call or phone-purchase route is registered',
  () => {
    const app =
      createApp();

    installKorlixVapiNovaRoutes(
      app,
      {
        environment:
          baseEnvironment(),
      },
    );

    const paths =
      app.routes.map(
        (route) =>
          route.path
            .toLowerCase(),
      );

    assert.equal(
      paths.some(
        (path) =>
          path.includes(
            'outbound',
          ),
      ),
      false,
    );

    assert.equal(
      paths.some(
        (path) =>
          path.includes(
            'purchase',
          ),
      ),
      false,
    );

    assert.equal(
      paths.some(
        (path) =>
          path.includes(
            'phone-number',
          ),
      ),
      false,
    );
  },
);
