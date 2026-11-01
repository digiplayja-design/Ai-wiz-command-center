# KORLIX Brain+Voice: Astra Max and spoken memory

The standalone `com.korlix.brain` app opts into `astra-max-v1` with
`x-korlix-brain-voice` on the existing authenticated, metered voice-session route.
Other KORLIX voice workspaces keep their existing model configuration.

The server disables Realtime automatic answers and tools. `gpt-transcribe`
transcribes committed microphone turns with Rici/KORLIX keyword guidance. The
native client submits completed user transcripts to `/api/brain-voice/turn`.
Ordinary answers use Responses `gpt-6-astra`, `reasoning.effort: max`, `store: false`.
There is no lower-model fallback. Realtime speaks the supplied answer through an
out-of-band response with no microphone-conversation context. The native app
checks the protocol and model/effort headers before enabling the microphone.

`Rici, remember this: <content>` authorizes an exact-content memory save under the
authenticated user's general agent. `Rici, remember this instruction: <content>`
saves a tagged style memory, available on the next reasoning turn and removable
in My Brain. No extra Brain Vault password or confirmation screen is required.
The bare command asks for the next utterance, expires after 60 seconds, and
accepts `cancel`/`never mind`. Quoted commands, negatives, and ordinary conversation
do not trigger writes. The assistant cannot call a memory-writing tool.

The existing persistence helper enforces account/agent ownership, memory-enabled
state, and confirmation. Source event IDs and deterministic memory keys make
duplicate transcript delivery idempotent. Success requires a returned persisted
memory ID. Fresh runtime memory/training is loaded before every reasoning turn
(100 memories / 48,000 characters, subject to the shared loader's limits).

Ephemeral session state is bound to a server-issued usage session and user ID.
Turns are serialized and bounded by existing session time/response limits.
Backend restarts require reconnect. Astra usage is recorded server-side even if
the phone disconnects, then combined with cumulative speech usage. The existing
database usage RPC and developer entitlement remain authoritative. No database
schema, secret, price, or general account password policy is changed.

Validation:

```sh
node --check backend/server.js
node --test backend/test/brain_voice.test.mjs backend/test/rici_pronunciation.test.cjs backend/test/k135z_agent_memory.test.cjs
node backend/test_korlix_live_convo_agents.mjs
```

The isolated tests use fixture provider/database responses. An authenticated
physical-device conversation remains necessary to verify provider access,
microphone/transcript accuracy, spoken readback, interruptions, and real saved
memory. Public health reports configuration, not a successful live model call.

## Rici identity and responsiveness (build 7)

Brain+Voice constructs a dedicated, stable Rici system prompt. Shared agent
training and approved memories arrive as lower-priority JSON account context;
custom names in another workspace no longer become a protected spoken alias in
this app. The shared profile and stored records are not modified.

Exact standalone connection/name checks (for example, “Rici, are you there?”)
return a fixed app phrase after session and allowance validation, with no
reasoning request. These replies identify `source: app_phrase`; they are not
represented as model output. Compound or substantive questions continue to use
`gpt-6-astra` with `reasoning.effort: max`. Pending voice-memory capture takes
precedence over quick replies. Usage, deduplication and ownership checks apply.

Observed pre-update build-6 first-text times were 2,234, 5,363 and 7,955 ms;
preparation was 50–59 ms. New timing logs include a content-free route label.
First-sentence speech starts without the previous 60-character minimum in build
7. These changes remove avoidable waits; they do not guarantee subsecond Astra
Max reasoning. Post-update device/audio timing must be checked separately.
