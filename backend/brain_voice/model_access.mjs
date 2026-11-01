import {BRAIN_MODEL} from './models.mjs';

// One non-generating check at startup. Never blocks voice, exposes credentials,
// retries, or sends user context. Model discovery is not an inference benchmark.
export async function checkBrainModelAccess({apiKey, fetchImpl = fetch}) {
  if (!apiKey) return {model: BRAIN_MODEL, status: 'not_configured'};
  try {
    const response = await fetchImpl(`https://api.openai.com/v1/models/${BRAIN_MODEL}`, {
      headers: {Authorization: `Bearer ${apiKey}`}, signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) return {model: BRAIN_MODEL, status: 'unverified', providerStatus: response.status};
    const result = await response.json();
    return {model: BRAIN_MODEL, status: result.id === BRAIN_MODEL && result.object === 'model' ? 'available' : 'unverified', providerStatus: response.status};
  } catch {
    return {model: BRAIN_MODEL, status: 'unverified'};
  }
}
