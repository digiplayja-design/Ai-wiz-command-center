import {isIP} from 'node:net';

export const CREDIT_COST = 3;
export class SeoError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.name = 'SeoError';
    this.status = status;
  }
}
export const fail = (message, status = 400) => { throw new SeoError(message, status); };
export function text(value, max, label, optional = false) {
  if (value == null && optional) return '';
  if (typeof value !== 'string' || value.trim().length > max || (!optional && !value.trim())) {
    fail(`${label} must contain ${optional ? '0' : '1'}–${max} characters.`);
  }
  return value.trim();
}
export function uuid(value) {
  if (typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    fail('Reopen SEO Agent and try again.');
  }
  return value.toLowerCase();
}
// Syntax validation only. The crawler must also validate DNS and pin connections.
export function websiteUrl(value) {
  let raw = text(value, 2000, 'Website');
  if (!/^\w+:/.test(raw)) raw = 'https://' + raw;
  let url;
  try { url = new URL(raw); } catch { fail('Enter a public HTTPS website.'); }
  const host = url.hostname.toLowerCase();
  if (url.protocol !== 'https:' || url.username || url.password || url.port ||
      isIP(host) || host.includes(':') || !host.includes('.') ||
      !/^[a-z\d.-]+$/.test(host) || !/[a-z]/.test(host.split('.').at(-1)) ||
      /\.(?:localhost|local|internal|test|invalid)$/.test(host)) {
    fail('Use a public HTTPS website without a login, private address or custom port.');
  }
  if (url.search) fail('Use a website address without query parameters or access tokens.');
  url.hash = '';
  return url.href;
}
export function profileData(value = {}) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('Enter your business details.');
  return {
    businessName: text(value.businessName, 120, 'Business name'),
    website: websiteUrl(value.website),
    services: text(value.services, 350, 'Services or products'),
    market: text(value.market, 160, 'Target market'),
    facts: text(value.facts, 3000, 'Business facts', true),
  };
}
