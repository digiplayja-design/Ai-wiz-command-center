import OpenAI from 'openai';
import astra from '../../korlix_astra.cjs';
import {fail, nativeAiConfiguration, nativeAiConfigured} from './catalog.mjs';

export function eshaResponseRequest(configuration, prompt, textFormat) {
  if (!configuration.configured) fail('Esha consultations are being configured.', 503, 'native_ai_not_configured');
  return {model: configuration.model, reasoning: {effort: configuration.reasoningEffort},
    instructions: prompt.instructions, input: prompt.input, text: {format: textFormat},
    truncation: 'disabled', max_output_tokens: configuration.maxOutputTokens, store: false};
}

// Esha's only model adapter. The rest of Korlix continues using korlix_astra.cjs.
// https://developers.openai.com/api/docs/guides/token-counting
// Count all context-bearing fields, including the server catalog and JSON schema.
// max_output_tokens/store are creation-only fields and do not add input context.
export function createEshaAi({environment = process.env, clientFactory = options => new OpenAI(options)} = {}) {
  function check(request) {
    const config = nativeAiConfiguration(environment);
    if (!nativeAiConfigured(environment) || request.model !== config.model || request.reasoning?.effort !== config.reasoningEffort ||
        request.max_output_tokens !== config.maxOutputTokens || request.store !== false || request.truncation !== 'disabled') {
      fail('Esha consultations are being configured.', 503, 'native_ai_not_configured');
    }
  }
  function client(timeout) {
    // Retries of paid generation must never happen outside the durable ledger.
    return clientFactory({apiKey: environment.OPENAI_API_KEY, maxRetries: 0, timeout});
  }
  return {
    async countInputTokens(request, {signal} = {}) {
      check(request);
      const {max_output_tokens: _output, store: _store, ...inputRequest} = request;
      const response = await client(30000).responses.inputTokens.count(inputRequest, {signal, timeout: 30000, maxRetries: 0});
      if (response?.object !== 'response.input_tokens' || !Number.isSafeInteger(response.input_tokens) || response.input_tokens <= 0) {
        fail('Esha could not verify this request’s size. Please try again.', 503, 'token_count_unavailable');
      }
      return response.input_tokens;
    },
    async generate(request, {signal} = {}) {
      check(request);
      const api = client(180000), options = {signal, timeout: 180000, maxRetries: 0};
      // Keep the existing Astra/max behavior exactly; the explicitly approved
      // Luna branch has no escalation, fallback, repair request or hidden retry.
      if (request.model === astra.TEXT_MODEL) return astra.createTextResponse(api, request, options);
      const response = await api.responses.create(request, options);
      if (response?.status !== 'completed') fail('Esha could not complete this consultation. Please try again.', 502, 'invalid_ai_response');
      return response;
    },
  };
}
