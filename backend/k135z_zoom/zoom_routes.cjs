"use strict";

const crypto = require("node:crypto");
const { identity, eventPlan } = require("./b5b_contract.cjs");
const {createZoomRtmsStarter} = require('./zoom_rtms_start.cjs');

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
  K135zWorkspaceCommandService,
  K135zAtomicWorkspaceAdapter,
  K135zSupabaseWorkspaceStore,
  createK135zRtmsGrantResolver,
  createK135zRtmsCommandTransport,
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

// Browser callbacks must render once: downloading JSON can repeat a one-use URL.
function oauthCallbackPage(req, res, status, code = null) {
  if (typeof res.setHeader === 'function') {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Referrer-Policy', 'no-referrer');
  }
  const browser = /\btext\/html\b/i.test(String(req?.headers?.accept || ''));
  if (!browser || typeof res.end !== 'function') return false;
  const title = code ? 'Zoom connection did not complete' : 'Zoom is connected';
  const message = code
    ? 'Return to your original KORLIX tab. Share the error code below before trying again.'
    : 'Return to your original KORLIX tab and tap Refresh status. You can close this tab.';
  res.statusCode = status;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Content-Disposition', 'inline');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");
  res.end(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>body{font:18px system-ui,sans-serif;background:#061725;color:#eefaff;margin:0;padding:32px}main{max-width:640px;margin:10vh auto;padding:28px;border:1px solid #21d4f4;border-radius:18px}h1{font-size:28px}p{line-height:1.6}code{display:block;overflow-wrap:anywhere;color:#63e5ff}</style></head><body><main><p>KORLIX AI</p><h1>${title}</h1><p>${message}</p>${code ? `<code>${code}</code>` : ''}</main></body></html>`);
  return true;
}

function oauthCallbackAudit(status, code) {
  // Never log the request URL, authorization code, state, tokens, or error text.
  try { console.info('K135Z_ZOOM_OAUTH_CALLBACK', JSON.stringify({status, code})); }
  catch (_) { /* Logging must not change the callback outcome. */ }
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

// Classification of SERVER-VERIFIED app metadata only; not an authentication mechanism.
function isEnterprisePrincipal(principal) {
  const tier = principal?.app_metadata?.tier;
  return tier === "enterprise" || tier === "enterprise_plus";
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
  const liveEnabled = false; // B5B local checkpoint: live transport remains disabled.

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

  const allowEphemeral = !production &&
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
      authorizeStoredIdentity: options.authorizeStoredIdentity || (async () => false),

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

  const workspaceStore=options.workspaceCommandAdapter ? null : options.workspaceCommandStore || (options.workspaceCommandClient
    ? new K135zSupabaseWorkspaceStore({client:options.workspaceCommandClient}) : null);
  let workspaceTransport=options.workspaceCommandTransport || null;
  if(!options.workspaceCommandAdapter && !workspaceTransport && options.rtmsSdk) {
    const resolveGrant=createK135zRtmsGrantResolver({store:workspaceStore,repository,
      clientId:env.KORLIX_ZOOM_CLIENT_ID,clientSecret:env.KORLIX_ZOOM_CLIENT_SECRET});
    workspaceTransport=createK135zRtmsCommandTransport({sdk:options.rtmsSdk,resolveGrant,
      onTranscript:options.onRtmsTranscript,audioLevels:options.audioLevels===true});
  }
  return {
    workspaceStore,
    workspaceStartRtms:options.rtmsStartEnabled===true && workspaceStore
      ? createZoomRtmsStarter({store:workspaceStore,repository,oauthService,transport,
        clientId:env.KORLIX_ZOOM_CLIENT_ID,fetchImpl:options.fetchImpl||globalThis.fetch}) : null,
    workspaceTranscriptPreview:options.workspaceTranscriptPreview,
    workspaceHttpEnabled: options.workspaceHttpEnabled===true,
    workspaceTransport,
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

    // Real integration must inject verified authentication, entitlement and agent ownership.
    // HTTP registration requires explicit opt-in; the default production SDK remains disabled.
    workspaceCommands: new K135zWorkspaceCommandService({
      authenticateRequest: options.authenticateRequest,
      resolveEnterprise: options.resolveEnterprise,
      authorizeAgent: options.authorizeAgent,
      adapter: options.workspaceCommandAdapter ||
        (workspaceStore && workspaceTransport
          ? new K135zAtomicWorkspaceAdapter({store:workspaceStore,transport:workspaceTransport}) : null),
    }),
    authenticateRequest: options.authenticateRequest || (async () => null),
    resolveEnterprise: options.resolveEnterprise || (async () => false),
    authorizeAgent: options.authorizeAgent || (async () => false),
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

    if (enterprise !== true) {
      throw new K135zZoomError(
        403,
        "KORLIX_ENTERPRISE_REQUIRED",
        "Nova Meeting Copilot requires an Enterprise account.",
      );
    }

    const bound = identity(principal);
    if (typeof deps.authorizeAgent !== "function" || await deps.authorizeAgent(bound, req) !== true) {
      throw new K135zZoomError(403, "KORLIX_AGENT_AUTHORIZATION_REQUIRED", "Agent authorization is required.");
    }
    return bound;
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

  const callback = async (req, res) => {
    try {
        const result =
          await deps
            .oauthService
            .completeAuthorization({
              code:
                req?.query?.code,

              state:
                req?.query?.state,
            });

        oauthCallbackAudit(200, 'CONNECTED');
        if (typeof res.setHeader === 'function') {
          res.setHeader('Cache-Control', 'no-store');
          res.setHeader('Referrer-Policy', 'no-referrer');
        }
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

        if (oauthCallbackPage(req, res, 200)) return;
        return jsonResponse(
          res,
          200,
          {
            ok: true,
            connected: true,
          },
        );
    } catch (error) {
      const known = error instanceof K135zZoomError;
      const status = known && Number.isInteger(error.status) && error.status >= 400 && error.status <= 599
        ? error.status : 500;
      const code = known && /^(?:ZOOM|K135Z)_[A-Z0-9_]{1,80}$/.test(error.code)
        ? error.code : 'K135Z_ZOOM_INTERNAL_ERROR';
      oauthCallbackAudit(status, code);
      if (oauthCallbackPage(req, res, status, code)) return;
      return errorResponse(res, error);
    }
  };

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

        const result = await deps.repository.applyWebhookEvent(eventPlan(verified));
        return jsonResponse(res, 200, {ok: true, ...result});
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

        const result = await deps.repository.applyWebhookEvent(eventPlan(verified));
        return jsonResponse(res, 200, {ok: true, duplicate: result.duplicate,
          deleted_connections: result.deletedConnections});
      },
    );

  // Explicitly enabled by server wiring. The browser supplies neither provider
  // credentials nor a trusted identity, host decision or permission duration.
  function workspaceHandler(kind) {
    return async(req,res)=>{
      const C=require('../k135z_copilot_notes/contract.cjs');
      const abort=new AbortController();let timer,fail,finished=false;
      const cancel=()=>{abort.abort();fail?.(new K135zZoomError(499,'K135Z_WORKSPACE_CANCELLED'));};
      const check=()=>{if(abort.signal.aborted)throw new K135zZoomError(499,'K135Z_WORKSPACE_CANCELLED');};
      const cancellation={isCancelled:()=>abort.signal.aborted,subscribe(listener){
        if(abort.signal.aborted){listener();return()=>{};}
        abort.signal.addEventListener('abort',listener,{once:true});return()=>abort.signal.removeEventListener('abort',listener);
      }};
      try {
        res.setHeader?.('Cache-Control','no-store');
        if(deps.workspaceHttpEnabled!==true)throw new K135zZoomError(503,'K135Z_WORKSPACE_UNAVAILABLE');
        if(!/^Bearer [^\s,]{1,8192}$/.test(req?.headers?.authorization||''))throw new K135zZoomError(401,'KORLIX_AUTH_REQUIRED');
        if(!/^application\/json(?:\s*;|$)/i.test(req?.headers?.['content-type']||''))throw new K135zZoomError(415,'K135Z_JSON_REQUIRED');
        let body;
        try {
          C.checkSize(req.body,C.LIMITS.envelope,'control');body=C.clone(req.body);
          if(kind==='command')C.control(body,'request');
          else if(kind==='bind'){C.object(body,['meetingUuid','expectedBindingRevision']);C.text(body.meetingUuid);C.uint(body.expectedBindingRevision);}
          else if(kind==='status')C.object(body,[]);
          else if(kind==='transcript'||kind==='audio-level'){C.object(body,['context']);C.context(body.context);}
          else {
            C.object(body,['action','context','bindingRevision','authorityRevision'],body.action==='consent'?['listeningConsent']:[]);
            C.oneOf(body.action,['consent','renew','revoke']);C.context(body.context);
            C.uint(body.bindingRevision);C.uint(body.authorityRevision);C.requireValue(body.action!=='consent'||body.listeningConsent===true);
          }
        }catch{throw new K135zZoomError(400,'K135Z_WORKSPACE_REQUEST_INVALID');}
        const ended=new Promise((_,reject)=>{fail=reject;});
        req.once?.('aborted',cancel);res.once?.('close',cancel);
        timer=setTimeout(()=>{fail(new K135zZoomError(504,'K135Z_WORKSPACE_TIMEOUT'));abort.abort();},
          kind==='consent'&&body.action==='consent'?25000:10000);
        if(req.aborted || res.destroyed)cancel();
        const run=async()=>{
          check();
          if(kind==='command')return {reply:await deps.workspaceCommands.request(req,body,cancellation)};
          const principal=await authorize(req);check();
          const store=deps.workspaceStore;
          if(!store)throw new K135zZoomError(503,'K135Z_WORKSPACE_UNAVAILABLE');
          let row;
          if(kind==='bind')row=await store.bindWorkspace({principal,...body,signal:abort.signal});
          else if(kind==='consent') {
            if(body.action==='consent'&&deps.workspaceStartRtms) {
              await deps.workspaceStartRtms({principal,request:body,signal:abort.signal});check();
            }
            row=await store.changeConsent({principal,request:body,signal:abort.signal});
          }
          else row=await store.readCaptureLease({principal,...(['transcript','audio-level'].includes(kind)?{context:body.context}:{}),signal:abort.signal});
          check();
          if(kind==='audio-level') {
            if(!C.sameContext(body.context,row.record.snapshot.context)||
              !['tenantId','userId','agentId'].every(k=>body.context[k]===principal[k]))
              throw new K135zZoomError(409,'K135Z_WORKSPACE_BINDING_MISMATCH');
            if(row.authority.viewerAuthorized!==true)throw new K135zZoomError(403,'K135Z_WORKSPACE_DENIED');
            const active=row.validForMs>0&&row.authority.hostAuthorized&&row.authority.listeningAuthorized&&
              row.record.snapshot.state==='listening'&&!row.record.pending&&!row.record.uncertain;
            const level=active?deps.workspaceTransport?.audioLevel?.({principal,context:body.context}):null;
            return {audioLevel:level||{schemaVersion:1,context:body.context,active:false,available:true,
              received:false,packets:0,ageMs:null,level:0,peak:0}};
          }
          if(kind==='transcript') {
            if(!C.sameContext(body.context,row.record.snapshot.context)||
              !['tenantId','userId','agentId'].every(k=>body.context[k]===principal[k]))
              throw new K135zZoomError(409,'K135Z_WORKSPACE_BINDING_MISMATCH');
            if(row.authority.viewerAuthorized!==true)throw new K135zZoomError(403,'K135Z_WORKSPACE_DENIED');
            if(typeof deps.workspaceTranscriptPreview!=='function')throw new K135zZoomError(503,'K135Z_TRANSCRIPT_UNAVAILABLE');
            return {transcript:deps.workspaceTranscriptPreview(body.context)};
          }
          return {workspace:{snapshot:row.record.snapshot,authority:row.authority,
            bindingRevision:row.bindingRevision,authorityRevision:row.authorityRevision,
            validForMs:row.validForMs,pending:row.record.pending!==null,uncertain:row.record.uncertain,
            captureActive:deps.workspaceTransport?.captureActive?.({principal,context:row.record.snapshot.context})===true}};
        };
        const result=await Promise.race([run(),ended]);check();finished=true;
        return jsonResponse(res,200,{ok:true,...result});
      }catch(error){
        if(res.destroyed || res.writableEnded)return;
        const mapped={DENIED:403,CONFLICT:409,BINDING_MISMATCH:409,CANCELLED:499,TIMEOUT:504,UNAVAILABLE:503,PROTOCOL_ERROR:502};
        const known=error instanceof K135zZoomError,status=known?error.status:(mapped[error?.code]||500);
        return jsonResponse(res,status,{ok:false,error:{code:known?error.code:
          'K135Z_WORKSPACE_'+(mapped[error?.code]?error.code:'UNAVAILABLE'),
          message:'The workspace request could not be confirmed.',automaticRetry:false}});
      }finally{
        clearTimeout(timer);req.removeListener?.('aborted',cancel);res.removeListener?.('close',cancel);
        if(!finished)abort.abort();
      }
    };
  }

  return {
    workspaceBind:workspaceHandler('bind'),workspaceStatus:workspaceHandler('status'),
    workspaceConsent:workspaceHandler('consent'),workspaceCommand:workspaceHandler('command'),
    workspaceTranscript:workspaceHandler('transcript'),
    workspaceAudioLevel:workspaceHandler('audio-level'),
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
  if(dependencies.workspaceHttpEnabled) {
    for(const [path,handler] of [['bind','workspaceBind'],['status','workspaceStatus'],
      ['consent','workspaceConsent'],['command','workspaceCommand']])
      app.post(`${K135Z_ZOOM_ROUTE_PREFIX}/workspace/${path}`,handlers[handler]);
    if(typeof dependencies.workspaceTranscriptPreview==='function')
      app.post(`${K135Z_ZOOM_ROUTE_PREFIX}/workspace/transcript`,handlers.workspaceTranscript);
    if(typeof dependencies.workspaceTransport?.audioLevel==='function')
      app.post(`${K135Z_ZOOM_ROUTE_PREFIX}/workspace/audio-level`,handlers.workspaceAudioLevel);
  }

  return {
    dependencies,
    handlers,
  };
}

// K135Z_GATE6O_SERVER_RUNTIME_BEGIN
// Server-owned, bounded, volatile inbox. Packets are not persisted or exposed
// through HTTP here. A subsequent transcript consumer must authorize its reads.
function createK135zTranscriptInbox({maxPackets=256,maxBytes=524288}={}) {
  const C=require('../k135z_copilot_notes/contract.cjs');
  if(!Number.isSafeInteger(maxPackets)||maxPackets<1||maxPackets>256||
     !Number.isSafeInteger(maxBytes)||maxBytes<1||maxBytes>524288)
    throw new TypeError('K135Z_INBOX_LIMIT_INVALID');
  let packets=[],bytes=0,closed=false;const previews=new Map();
  return Object.freeze({
    accept(raw) {
      if(closed)return false;
      try {
        C.object(raw,['context','text','providerTimestamp','userId','userName','startTs','endTs']);
        C.context(raw.context);if(raw.context.streamId===null)return false;
        C.nonblank(raw.text);C.text(raw.userName);
        for(const key of ['providerTimestamp','userId','startTs','endTs'])C.uint(raw[key]);
        if(raw.endTs<raw.startTs||Buffer.byteLength(raw.text,'utf8')>C.LIMITS.text||
           Buffer.byteLength(raw.userName,'utf8')>256)return false;
        C.checkSize(raw,C.LIMITS.envelope);
        const packet=C.freeze(C.clone(raw)),size=C.bytes(packet);
        if(packets.length>=maxPackets||bytes+size>maxBytes)return false;
        packets.push({packet,size});bytes+=size;return true;
      } catch {return false;}
    },
    preview(trustedContext) {
      if(closed)throw new K135zZoomError(503,'K135Z_TRANSCRIPT_UNAVAILABLE');
      const ctx=C.context(trustedContext),owner=C.canonical([ctx.tenantId,ctx.userId,ctx.agentId]);
      let view=previews.get(owner);
      if(!view||!C.sameContext(view.context,ctx))view={context:ctx,windowId:crypto.randomBytes(16).toString('hex'),revision:0,rows:[],truncated:false};
      const remaining=[];
      for(const row of packets) {
        const p=row.packet,c=p.context;
        if(c.tenantId!==ctx.tenantId||c.userId!==ctx.userId||c.agentId!==ctx.agentId){remaining.push(row);continue;}
        bytes-=row.size;
        if(!C.sameContext(c,ctx))continue;
        if(view.revision>=Number.MAX_SAFE_INTEGER)throw new K135zZoomError(503,'K135Z_TRANSCRIPT_UNAVAILABLE');
        view.rows.push({sequence:++view.revision,packet:p});
        while(view.rows.length>50||C.bytes(view.rows)>49152){view.rows.shift();view.truncated=true;}
      }
      packets=remaining;previews.delete(owner);previews.set(owner,view);
      if(previews.size>64)previews.delete(previews.keys().next().value);
      return C.freeze({schemaVersion:1,context:ctx,windowId:view.windowId,revision:view.revision,
        lines:view.rows.map(({sequence,packet:p})=>({sequence,text:p.text,speaker:p.userName,
          providerTimestamp:p.providerTimestamp,startTs:p.startTs,endTs:p.endTs})),
        truncated:view.truncated,persisted:false,coverage:'partial'});
    },
    take(trustedContext) {
      const ctx=C.context(trustedContext),selected=[],remaining=[];
      for(const row of packets) {
        if(C.sameContext(row.packet.context,ctx)){selected.push(row.packet);bytes-=row.size;}
        else remaining.push(row);
      }
      packets=remaining;return Object.freeze(selected);
    },
    status:()=>Object.freeze({queued:packets.length,bytes,closed,persisted:false}),
    close(){closed=true;packets=[];bytes=0;previews.clear();}
  });
}

async function createK135zServerRuntime({env=process.env,database,fetchImpl=globalThis.fetch,
  loadSdk=async()=>{
    if(require('@zoom/rtms/package.json').version!=='1.1.0')throw Error('SDK_VERSION');
    return (await import('@zoom/rtms')).default;
  }}={}) {
  const fail=code=>{throw new K135zZoomError(503,code);};
  const flag=env.KORLIX_K135Z_WORKSPACE_ENABLED;
  if(![undefined,'','false','true'].includes(flag))fail('K135Z_WORKSPACE_FLAG_INVALID');
  env=Object.freeze({...env});
  const enabled=flag==='true',inbox=createK135zTranscriptInbox();
  const oauthFlag=env.KORLIX_K135Z_OAUTH_HTTP_ENABLED;
  if(![undefined,'','false','true'].includes(oauthFlag))fail('K135Z_OAUTH_FLAG_INVALID');
  const oauthEnabled=oauthFlag==='true';
  let dependencies=null,closed=false,released=true,bound=false,oauthCipher=null,returnOrigins=[];
  const options={};
  if(oauthEnabled) {
    if(typeof database?.rpc!=='function'||typeof database?.from!=='function')fail('K135Z_OAUTH_DATABASE_REQUIRED');
    for(const name of ['KORLIX_ZOOM_CLIENT_ID','KORLIX_ZOOM_CLIENT_SECRET']) {
      const value=env[name];
      if(typeof value!=='string'||!value||value.length>1024||/[^\x21-\x7e]/.test(value)||
        (name==='KORLIX_ZOOM_CLIENT_ID'&&value.includes(':')))fail('K135Z_OAUTH_CREDENTIALS_REQUIRED');
    }
    const key=env.KORLIX_K135Z_ZOOM_TOKEN_ENCRYPTION_KEY;
    if(typeof key!=='string'||key!==key.trim()||Buffer.byteLength(key)<32||Buffer.byteLength(key)>4096||
      /[\x00-\x1f\x7f]/.test(key))fail('K135Z_OAUTH_ENCRYPTION_REQUIRED');
    oauthCipher=new EnvelopeCipher(key);
    if(![undefined,'','false'].includes(env.KORLIX_K135Z_ZOOM_ALLOW_EPHEMERAL_STORE))fail('K135Z_OAUTH_DURABLE_STORE_REQUIRED');
    function https(value,originOnly=false) {
      let u;try{u=new URL(value);}catch{fail('K135Z_OAUTH_URL_INVALID');}
      if(typeof value!=='string'||value.length>2048||u.protocol!=='https:'||u.hostname.includes('*')||u.username||u.password||u.search||u.hash||
        (originOnly?u.origin!==value:u.href!==value))fail('K135Z_OAUTH_URL_INVALID');
      return u;
    }
    if(https(env.KORLIX_ZOOM_REDIRECT_URI).pathname!==K135Z_ZOOM_ROUTE_PREFIX+'/oauth/callback')
      fail('K135Z_OAUTH_CALLBACK_PATH_INVALID');
    const origins=env.KORLIX_K135Z_ZOOM_ALLOWED_RETURN_ORIGINS;
    if(typeof origins!=='string'||!origins||origins.length>8192)fail('K135Z_OAUTH_RETURN_ORIGINS_REQUIRED');
    returnOrigins=origins.split(',').map(v=>v.trim());
    if(returnOrigins.length>10||new Set(returnOrigins).size!==returnOrigins.length)fail('K135Z_OAUTH_URL_INVALID');
    for(const origin of returnOrigins)https(origin,true);
    for(const [name,value] of Object.entries({KORLIX_ZOOM_AUTHORIZE_URL:'https://zoom.us/oauth/authorize',
      KORLIX_ZOOM_TOKEN_URL:'https://zoom.us/oauth/token',KORLIX_ZOOM_API_BASE_URL:'https://api.zoom.us/v2'}))
      if(![undefined,'',value].includes(env[name]))fail('K135Z_OAUTH_PROVIDER_URL_INVALID');
    if(typeof fetchImpl!=='function')fail('ZOOM_FETCH_UNAVAILABLE');
    const provider=createK135zOAuthHttpTransport({enabled:true,fetchImpl});
    const transport={liveEnabled:true};
    for(const name of ['exchangeAuthorizationCode','refreshAccessToken','listUpcomingMeetings','revokeAccessToken'])
      transport[name]=async input=>{
        if(closed||!dependencies)fail('K135Z_OAUTH_RUNTIME_UNAVAILABLE');
        return provider[name](input);
      };
    Object.assign(options,{env,transport:Object.freeze(transport),fetchImpl,rtmsStartEnabled:enabled});
  }
  if(enabled) {
    if(typeof database?.rpc!=='function'||typeof database?.from!=='function')
      fail('K135Z_WORKSPACE_DATABASE_REQUIRED');
    for(const name of ['KORLIX_ZOOM_CLIENT_ID','KORLIX_ZOOM_CLIENT_SECRET']) {
      const value=env[name];
      if(typeof value!=='string'||!value.trim()||value!==value.trim()||value.length>1024)
        fail('K135Z_WORKSPACE_CREDENTIALS_REQUIRED');
    }
    let sdk;try {sdk=await loadSdk();}catch {fail('K135Z_RTMS_SDK_UNAVAILABLE');}
    if(typeof sdk?.Client!=='function'||sdk.RTMS_SDK_OK!==0||typeof sdk.configureLogger!=='function'||
       !['join','leave','onJoinConfirm','onTranscriptData','onLeave','setAudioParams','onAudioData'].every(k=>typeof sdk.Client.prototype?.[k]==='function'))
      fail('K135Z_RTMS_SDK_INVALID');
    Object.assign(options,{workspaceHttpEnabled:true,workspaceCommandClient:database,rtmsSdk:sdk,audioLevels:true,
      workspaceTranscriptPreview:context=>inbox.preview(context),
      onRtmsTranscript(packet) {
        if(closed||!dependencies)return false;
        const context=packet?.context;
        const principal=context&&{tenantId:context.tenantId,userId:context.userId,agentId:context.agentId};
        return dependencies.workspaceTransport.captureActive({principal,context})===true&&inbox.accept(packet);
      }});
  }
  function close() {
    if(closed)return released;
    closed=true;inbox.close();
    try {if(dependencies?.workspaceTransport)released=dependencies.workspaceTransport.close()===true;}
    catch {released=false;}
    return released;
  }
  return Object.freeze({enabled,oauthEnabled,options:Object.freeze(options),inbox,close,
    attach(value) {
      if(closed||dependencies)fail('K135Z_RUNTIME_ALREADY_ATTACHED_OR_CLOSED');
      if(!value||value.workspaceHttpEnabled!==enabled||
        (enabled&&(!value.workspaceStore||typeof value.workspaceTransport?.close!=='function'||
          typeof value.workspaceTransport?.captureActive!=='function')))fail('K135Z_RUNTIME_BINDING_INVALID');
      if(oauthEnabled) {
        const {SupabaseZoomRepository}=require('./b5b_repository.cjs');
        const vault=value.tokenVault,service=value.oauthService,config=service?.config;
        if(!(value.repository instanceof SupabaseZoomRepository)||value.repository.client!==database||
          !(vault instanceof ZoomTokenVault)||vault.repository!==value.repository||
          !(vault.cipher instanceof EnvelopeCipher)||!Buffer.isBuffer(vault.cipher.key)||!vault.cipher.key.equals(oauthCipher.key)||
          value.transport!==options.transport||!(service instanceof ZoomOAuthService)||
          service.repository!==value.repository||service.tokenVault!==vault||service.transport!==options.transport||
          !config||config.clientId!==env.KORLIX_ZOOM_CLIENT_ID||config.clientSecret!==env.KORLIX_ZOOM_CLIENT_SECRET||
          config.redirectUri!==env.KORLIX_ZOOM_REDIRECT_URI||config.authorizeUrl!=='https://zoom.us/oauth/authorize'||
          JSON.stringify(config.allowedReturnOrigins)!==JSON.stringify(returnOrigins))fail('K135Z_OAUTH_BINDING_INVALID');
      }
      dependencies=value;
    },
    bindServer(server,{lifecycle=process,shutdownMs=8000}={}) {
      if(!enabled&&!oauthEnabled)return;
      if(closed||bound||!dependencies||typeof server?.close!=='function'||typeof server?.once!=='function'||
        typeof lifecycle?.once!=='function'||typeof lifecycle?.removeListener!=='function'||
        typeof lifecycle?.exit!=='function'||!Number.isSafeInteger(shutdownMs)||shutdownMs<1||shutdownMs>30000)
        fail('K135Z_SHUTDOWN_BINDING_INVALID');
      bound=true;let stopping=false,finished=false,timer;
      const cleanup=()=>{lifecycle.removeListener('SIGTERM',stop);lifecycle.removeListener('SIGINT',stop);};
      const finish=code=>{if(finished)return;finished=true;clearTimeout(timer);cleanup();lifecycle.exit(code);};
      const stop=()=>{
        if(stopping)return;stopping=true;
        const ok=close();
        timer=setTimeout(()=>{try{server.closeAllConnections?.();}catch{}finish(1);},shutdownMs);
        try {server.close(error=>finish(!error&&ok?0:1));}catch {finish(1);}
      };
      lifecycle.once('SIGTERM',stop);lifecycle.once('SIGINT',stop);
      server.once('close',()=>{close();if(!stopping)cleanup();});
    }
  });
}
// K135Z_GATE6O_SERVER_RUNTIME_END

// Gate6R adapter; Gate6S runtime wiring requires an explicit default-off flag.
function createK135zOAuthHttpTransport({enabled=false,fetchImpl=globalThis.fetch,
  timeoutMs=8000,maxResponseBytes=262144}={}) {
  const fail=(code,status=502)=>{throw new K135zZoomError(status,code,'The Zoom request could not be completed.');};
  if(typeof enabled!=='boolean'||!Number.isInteger(timeoutMs)||timeoutMs<25||timeoutMs>10000||
     !Number.isInteger(maxResponseBytes)||maxResponseBytes<1024||maxResponseBytes>1048576)
    fail('ZOOM_HTTP_OPTIONS_INVALID',503);
  const text=(value,max=16384)=>typeof value==='string'&&value.length>0&&value.length<=max&&
    value===value.trim()&&!/[\x00-\x20\x7f]/.test(value);
  const requireText=(value,max)=>{if(!text(value,max))fail('ZOOM_HTTP_INPUT_INVALID',400);return value;};
  function active(){if(!enabled)fail('ZOOM_LIVE_TRANSPORT_DISABLED',503);
    if(typeof fetchImpl!=='function')fail('ZOOM_FETCH_UNAVAILABLE',503);}
  async function request(url,options,budgetMs=timeoutMs) {
    active();if(budgetMs<1)fail('ZOOM_HTTP_TIMEOUT',504);
    const abort=new AbortController();let timer,reader;
    const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>{
      reject(new K135zZoomError(504,'ZOOM_HTTP_TIMEOUT','The Zoom request timed out.'));
      abort.abort();if(reader)void reader.cancel().catch(()=>{});
    },budgetMs);});
    try {
      return await Promise.race([timeout,(async()=>{
        const res=await fetchImpl(url,{...options,redirect:'error',signal:abort.signal});
        if(abort.signal.aborted)fail('ZOOM_HTTP_TIMEOUT',504);
        if(!res||res.redirected||(res.url&&res.url!==url))fail('ZOOM_HTTP_REDIRECT_REJECTED');
        if(res.status!==200){abort.abort();fail('ZOOM_UPSTREAM_REQUEST_FAILED',res.status===429?429:502);}
        if(!/^application\/json(?:\s*;|$)/i.test(res.headers?.get('content-type')||''))fail('ZOOM_HTTP_RESPONSE_INVALID');
        const length=res.headers.get('content-length');
        if(length!==null&&(!/^\d+$/.test(length)||Number(length)>maxResponseBytes))fail('ZOOM_HTTP_RESPONSE_TOO_LARGE');
        if(typeof res.body?.getReader!=='function')fail('ZOOM_HTTP_RESPONSE_INVALID');
        reader=res.body.getReader();let size=0;const chunks=[];
        while(true){const next=await reader.read();if(abort.signal.aborted)fail('ZOOM_HTTP_TIMEOUT',504);
          if(next.done)break;size+=next.value.byteLength;
          if(size>maxResponseBytes)fail('ZOOM_HTTP_RESPONSE_TOO_LARGE');chunks.push(Buffer.from(next.value));}
        const body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));
        if(!body||typeof body!=='object'||Array.isArray(body))fail('ZOOM_HTTP_RESPONSE_INVALID');
        return body;
      })()]);
    }catch(error){if(error instanceof K135zZoomError)throw error;fail('ZOOM_HTTP_REQUEST_FAILED');}
    finally{clearTimeout(timer);abort.abort();if(reader)void reader.cancel().catch(()=>{});}
  }
  function form(clientId,clientSecret,values) {
    active();requireText(clientId,1024);requireText(clientSecret,4096);
    if(clientId.includes(':'))fail('ZOOM_HTTP_INPUT_INVALID',400);
    return {method:'POST',headers:{authorization:'Basic '+Buffer.from(clientId+':'+clientSecret).toString('base64'),
      'content-type':'application/x-www-form-urlencoded',accept:'application/json'},body:new URLSearchParams(values).toString()};
  }
  function token(raw) {
    if(!text(raw.access_token)||!text(raw.refresh_token)||typeof raw.token_type!=='string'||
       raw.token_type.toLowerCase()!=='bearer'||!Number.isSafeInteger(raw.expires_in)||raw.expires_in<1||raw.expires_in>2678400||
       typeof raw.scope!=='string'||raw.scope.length>4096||/[\x00-\x1f\x7f]/.test(raw.scope))fail('ZOOM_TOKEN_RESPONSE_INVALID');
    // Zoom documents regional and vanity hosts; its global API supports every region.
    // Treat api_url as metadata only. All outbound request targets remain fixed.
    // https://developers.zoom.us/docs/api/using-zoom-apis/#regional-base-urls
    if(raw.api_url!==undefined&&(!text(raw.api_url,253)||
       !/^https:\/\/[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.zoom\.us\/?$/i.test(raw.api_url)))
      fail('ZOOM_API_REGION_UNSUPPORTED');
    return {access_token:raw.access_token,refresh_token:raw.refresh_token,token_type:'bearer',
      expires_in:raw.expires_in,scope:raw.scope,api_url:'https://api.zoom.us'};
  }
  const bearer=accessToken=>({method:'GET',headers:{authorization:'Bearer '+requireText(accessToken),accept:'application/json'}});
  return Object.freeze({liveEnabled:enabled,
    async exchangeAuthorizationCode({code,clientId,clientSecret,redirectUri}) {
      active();requireText(code,4096);requireText(redirectUri,2048);
      let uri;try{uri=new URL(redirectUri);}catch{fail('ZOOM_REDIRECT_URI_INVALID',400);}
      if(uri.protocol!=='https:'||uri.username||uri.password||uri.hash||uri.search)fail('ZOOM_REDIRECT_URI_INVALID',400);
      const value=token(await request('https://zoom.us/oauth/token',form(clientId,clientSecret,
        {grant_type:'authorization_code',code,redirect_uri:redirectUri})));
      const profile=await request('https://api.zoom.us/v2/users/me',bearer(value.access_token));
      if(!text(profile.id,256)||!text(profile.account_id,256))fail('ZOOM_PROFILE_RESPONSE_INVALID');
      return {...value,account_id:profile.account_id,user_id:profile.id};
    },
    async refreshAccessToken({refreshToken,clientId,clientSecret}) {
      active();requireText(refreshToken);
      return token(await request('https://zoom.us/oauth/token',form(clientId,clientSecret,
        {grant_type:'refresh_token',refresh_token:refreshToken})));
    },
    async listUpcomingMeetings({accessToken,userId='me',apiUrl='https://api.zoom.us'}) {
      active();if(userId!=='me'||apiUrl!=='https://api.zoom.us')fail('ZOOM_HTTP_TARGET_REJECTED',400);
      const deadline=Date.now()+timeoutMs;
      const read=async url=>{
        const page=await request(url,bearer(accessToken),deadline-Date.now());
        if(!Array.isArray(page.meetings)||page.meetings.length>300||
          (page.next_page_token!==undefined&&(typeof page.next_page_token!=='string'||page.next_page_token.length>300)))
          fail('ZOOM_MEETINGS_RESPONSE_INVALID');
        return page;
      };
      const value=await read('https://api.zoom.us/v2/users/me/upcoming_meetings');
      // upcoming_meetings omits uuid. Resolve only the current user's hosted meetings
      // through the scheduled-meetings API (meeting:read:list_meetings scope).
      // A numeric meeting ID must never substitute for an instance UUID.
      const meetingId=value=>((typeof value==='number'&&Number.isSafeInteger(value))||typeof value==='string')&&
        /^[1-9]\d{0,14}$/.test(String(value))?String(value):null;
      const needsUuid=meeting=>meeting?.is_host===true&&!text(meeting.uuid,180);
      const needed=new Set();
      for(const meeting of value.meetings)if(needsUuid(meeting)){
        const id=meetingId(meeting.id);if(!id)fail('ZOOM_MEETINGS_RESPONSE_INVALID');needed.add(id);
      }
      const hosted=new Map();
      if(needed.size){
        const seenTokens=new Set();let next='';
        for(let page=0;page<3;page++){
          const url=new URL('https://api.zoom.us/v2/users/me/meetings');
          url.searchParams.set('page_size','100');
          if(next)url.searchParams.set('next_page_token',next);
          const result=await read(url.href);
          for(const meeting of result.meetings){
            const id=meetingId(meeting?.id);if(!id)fail('ZOOM_MEETINGS_RESPONSE_INVALID');
            if(!needed.has(id))continue;
            if(!text(meeting.uuid,180))fail('ZOOM_MEETINGS_RESPONSE_INVALID');
            if(hosted.has(id)&&hosted.get(id)!==meeting.uuid)fail('ZOOM_MEETING_UUID_AMBIGUOUS');
            hosted.set(id,meeting.uuid);
          }
          next=result.next_page_token||'';if(!next)break;
          if(seenTokens.has(next)||page===2)fail('ZOOM_MEETINGS_LOOKUP_LIMIT');
          seenTokens.add(next);
        }
      }
      return {meetings:value.meetings.map(meeting=>{
        const uuid=needsUuid(meeting)?hosted.get(meetingId(meeting.id)):null;
        return uuid?{...meeting,uuid}:meeting;
      }),next_page_token:value.next_page_token||''};
    },
    async revokeAccessToken({accessToken,clientId,clientSecret}) {
      active();requireText(accessToken);
      const value=await request('https://zoom.us/oauth/revoke',form(clientId,clientSecret,{token:accessToken}));
      if(value.status!=='success')fail('ZOOM_REVOCATION_RESPONSE_INVALID');
      return {status:'success'};
    }
  });
}

module.exports = {
  createK135zOAuthHttpTransport,
  createK135zTranscriptInbox,
  createK135zServerRuntime,
  K135Z_ZOOM_ROUTE_PREFIX,
  createFetchZoomTransport,
  createK135zZoomDependencies,
  createK135zZoomHandlers,
  errorResponse,
  isEnterprisePrincipal,
  principalFromRequest,
  registerK135zZoomRoutes,
};
