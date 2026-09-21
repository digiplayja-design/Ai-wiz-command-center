'use strict';

const TEXT_MODEL = 'gpt-6-astra';
const EFFORTS = new Set(['low', 'medium', 'high', 'xhigh', 'max']);

// Normalize only Astra text requests; specialized media transports never use this.
// https://developers.openai.com/api/docs/guides/latest-model
function astraRequest(request, endpoint = 'responses') {
  const body = {...request};
  if (body.model !== TEXT_MODEL) return body;
  for (const key of ['temperature', 'top_p', 'top_logprobs', 'logprobs']) delete body[key];
  const configured = body.reasoning?.effort ?? body.reasoning_effort ?? 'low';
  const effort = ['none', 'minimal'].includes(configured) ? 'low' : configured;
  if (!EFFORTS.has(effort)) throw new Error('Unsupported Astra reasoning effort');
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
    if (body.max_completion_tokens != null) {
      body.max_completion_tokens = Math.max(8192, body.max_completion_tokens);
    }
  } else {
    body.reasoning = {...body.reasoning, effort};
    delete body.reasoning_effort;
    if (body.max_output_tokens != null) {
      body.max_output_tokens = Math.max(8192, body.max_output_tokens);
    }
    if (body.include) body.include = body.include.filter(x => x !== 'message.output_text.logprobs');
    if (body.prompt_cache_retention != null) {
      body.prompt_cache_options = {ttl: '30m', ...body.prompt_cache_options};
      delete body.prompt_cache_retention;
    }
  }
  return body;
}

async function createTextResponse(client, request, options) {
  const result = await client.responses.create(astraRequest(request), options);
  if (request.model === TEXT_MODEL && ['incomplete', 'failed'].includes(result?.status)) {
    throw new Error('Astra could not complete this response. Please try again.');
  }
  return result;
}

module.exports = {TEXT_MODEL, astraRequest, createTextResponse};
