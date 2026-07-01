# KORLIX AI OpenAI Production Quality Policy

Build 94 introduces app-wide AI quality routing.

## Default model policy

- Text / reasoning / writing / app planning / documents / credit report / utility output:
  - `gpt-5.5-pro`
  - reasoning effort: `xhigh`
- Streaming fallback:
  - `gpt-5.5`
- Image generation / image editing:
  - `gpt-image-2`
- Embeddings:
  - `text-embedding-3-large`
- Moderation:
  - `omni-moderation`

## Security rule

OpenAI API keys must remain server-side only.

Never add `OPENAI_API_KEY` to:

- Flutter `.dart` files
- iOS plist/project files
- Android gradle/xml files
- web frontend files
- committed source code

## Frontend behavior

Flutter now sends quality headers with backend requests:

- `X-Korlix-AI-Quality`
- `X-Korlix-OpenAI-Preferred-Model`
- `X-Korlix-OpenAI-Text-Model`
- `X-Korlix-OpenAI-Streaming-Model`
- `X-Korlix-OpenAI-Image-Model`
- `X-Korlix-OpenAI-Reasoning-Effort`

Prompts sent from the command center also receive a production-quality directive.

## Backend behavior

Backend files are swept for hard-coded OpenAI model literals and routed toward premium defaults through environment variables. Keep the `.env.openai-quality.example` file as the deployment reference.

