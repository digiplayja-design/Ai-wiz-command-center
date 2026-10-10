'use strict';

const TEXT_MODEL = 'gpt-6-astra';
const TEXT_EFFORT = 'max';
const TEXT_OUTPUT_TOKENS = 32768;
const EFFORTS = new Set(['low', 'medium', 'high', 'xhigh', 'max']);

// Normalize only Astra text requests; specialized media transports never use this.
// https://developers.openai.com/api/docs/guides/latest-model
function astraRequest(request, endpoint = 'responses') {
  const body = {...request};
  if (body.model !== TEXT_MODEL) return body;
  for (const key of ['temperature', 'top_p', 'top_logprobs', 'logprobs']) delete body[key];
  const configured = body.reasoning?.effort ?? body.reasoning_effort ?? TEXT_EFFORT;
  if (!EFFORTS.has(configured) && !['none', 'minimal'].includes(configured)) throw new Error('Unsupported Astra reasoning effort');
  // All compatible reasoning uses the owner's Astra max policy, including old
  // callers that still supply a lower effort. Audio/image transports stay separate.
  const effort = TEXT_EFFORT;
  if (endpoint === 'chat/completions') {
    if (body.tools?.length || body.functions?.length) {
      throw new Error('Astra tool calls require the Responses API');
    }
    body.reasoning_effort = effort;
    delete body.reasoning;
    if (body.max_tokens != null) {
      body.max_completion_tokens ??= body.max_tokens;
      delete body.max_tokens;
    }
    body.max_completion_tokens = Math.max(TEXT_OUTPUT_TOKENS, body.max_completion_tokens || 0);
  } else {
    body.reasoning = {...body.reasoning, effort};
    delete body.reasoning_effort;
    body.max_output_tokens = Math.max(TEXT_OUTPUT_TOKENS, body.max_output_tokens || 0);
    if (body.include) body.include = body.include.filter(x => x !== 'message.output_text.logprobs');
    if (body.prompt_cache_retention != null) {
      body.prompt_cache_options = {ttl: '30m', ...body.prompt_cache_options};
      delete body.prompt_cache_retention;
    }
  }
  return body;
}

async function createTextResponse(client, request, options) {
  // This entry point is text/vision reasoning only. Legacy model overrides must
  // not silently downgrade a feature; specialized media never calls this helper.
  const result = await client.responses.create(astraRequest({...request, model: TEXT_MODEL}), options);
  if (['incomplete', 'failed'].includes(result?.status)) {
    throw new Error('Astra could not complete this response. Please try again.');
  }
  return result;
}

module.exports = {TEXT_MODEL, TEXT_EFFORT, TEXT_OUTPUT_TOKENS, astraRequest, createTextResponse};
