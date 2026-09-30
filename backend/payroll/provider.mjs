import { fail, PayrollError } from './core.mjs';

export function createGustoProvider(config, fetchImpl = globalThis.fetch) {
  async function request(path, { token, method = 'GET', body } = {}) {
    if (!config.ready) fail('Payroll provider activation is pending.', 503, 'PAYROLL_SETUP_REQUIRED');
    let response;
    try {
      response = await fetchImpl(config.apiBase + path, { method, redirect: 'error',
        signal: AbortSignal.timeout(15000), headers: { Accept: 'application/json', 'Content-Type': 'application/json',
          'X-Gusto-API-Version': config.version, ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        ...(body ? { body: JSON.stringify(body) } : {}) });
    } catch { fail('The payroll provider could not be reached. Refresh the workspace before retrying.', 502, 'PAYROLL_PROVIDER_UNAVAILABLE'); }
    if (!response.ok) {
      // Never return upstream bodies: they can contain tax, bank, or token data.
      const error = new PayrollError(response.status === 429 ? 'Payroll provider is busy. Try again shortly.' :
        response.status === 422 ? 'The provider requires additional information. Review company setup or contact payroll support.' :
        'Payroll provider could not complete this request. Refresh or contact payroll support.', response.status === 429 ? 429 : 502, 'PAYROLL_PROVIDER_ERROR');
      error.providerStatus = response.status; throw error;
    }
    try { return await response.json(); } catch { fail('Payroll provider returned an invalid response.', 502); }
  }
  return {
    systemToken: () => request('/oauth/token', { method: 'POST', body: {
      grant_type: 'system_access', client_id: config.clientId, client_secret: config.clientSecret } }),
    createCompany: (token, body) => request('/v1/partner_managed_companies', { method: 'POST', token, body }),
    refresh: refreshToken => request('/oauth/token', { method: 'POST', body: {
      grant_type: 'refresh_token', client_id: config.clientId, client_secret: config.clientSecret, refresh_token: refreshToken } }),
    onboarding: (company, token) => request(`/v1/companies/${company}/onboarding_status`, { token }),
    flow: (company, token, body) => request(`/v1/companies/${company}/flows`, { method: 'POST', token, body }),
    terms: (company, token, body) => request(`/v1/partner_managed_companies/${company}/terms_of_service`, { method: 'POST', token, body }),
  };
}
