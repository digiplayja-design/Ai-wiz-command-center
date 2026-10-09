# Logo Studio: Astra creative direction

`POST /api/image/create` accepts an optional structured `logoBrief` from Logo
Studio. The dedicated planner uses `gpt-6-astra`, `reasoning.effort: max`, strict
JSON output, `store: false`, a 32,768-token output budget, a 180-second timeout,
and no automatic retries. The existing GPT Image service renders the resulting
direction. Its image model and quality are unchanged by this addition.

The brief includes the name, tagline, industry, personality, creative idea,
symbol, layout, typeface, and three selected colors. Fields are bounded and
validated before provider calls. Model and reasoning overrides supplied by a
client are ignored. The original name, tagline and colors are repeated as
rendering constraints after the generated plan.

Authentication and the existing credit check precede both provider calls.
Refused, unfinished, or malformed plans stop before rendering. Missing or
corrupt PNG output stops before history or credit accounting. A successful
concept consumes one existing generation credit. `logoDirection` returns the
concept title, brief design summary, planning model and reasoning effort.
Private reasoning and the internal render prompt are not returned.

Requests without `logoBrief` retain ordinary Imagine behavior. Editable local
logos are still free and use no provider calls. The new app waits 445 seconds
for planning plus the existing 240-second rendering timeout.

`/api/health` exposes `logoStudio` settings. Visibility in `chatModelAccess` is
only a model-access preflight, not proof of successful paid generation.

Validation: 56 backend checks passed across `logo_studio`, `korlix_astra`,
`chat_quality`, and `picture_studio`. The actual image-create route is exercised
with mocked providers for success, auth/credit denial, prompt constraints,
invalid plans, image errors, invalid PNGs, and ordinary Imagine compatibility.
The Docker build runs the logo route suite before deployment. Live generation
requires a signed-in app session; mocked tests do not establish visual quality
or production generation latency.
