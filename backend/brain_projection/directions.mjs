import {ProjectionError, normalizeQuery} from './core.mjs';

export const DIRECTIONS_FEATURE = 'brain_address_routing';
const modes = new Set(['driving', 'walking', 'transit']);

// Entitlements are server-managed and bound to the verified Auth UID. An email
// supplied in the request (or editable user metadata) never grants access.
export async function canUseBrainDirections(database, userId, now = Date.now()) {
  if (!database || typeof userId !== 'string' || !userId) return false;
  const {data, error} = await database.from('korlix_user_feature_entitlements')
    .select('status,expires_at').eq('user_id', userId).eq('feature_key', DIRECTIONS_FEATURE);
  if (error) throw new ProjectionError('Address routing could not be checked. Please try again.', 'directions_access_unavailable', 503);
  return Array.isArray(data) && data.some(row => row.status === 'active' &&
    (row.expires_at === null || (typeof row.expires_at === 'string' && Date.parse(row.expires_at) > now)));
}

// A route is a request to the user's chosen map application. We neither invent
// a geocoded match nor send the destination to a map provider in this endpoint.
// Opening the URL is a separate explicit user action in the native app.
export function brainDirectionLinks(body = {}) {
  const destination = normalizeQuery(body.destination);
  if (/^[a-z][a-z0-9+.-]*:\/\//iu.test(destination)) {
    throw new ProjectionError('Enter a street address or place name, not a website.', 'directions_invalid_destination');
  }
  const mode = body.mode ?? 'driving';
  if (!modes.has(mode)) throw new ProjectionError('Choose driving, walking, or transit.', 'directions_invalid_mode');
  const google = new URL('https://www.google.com/maps/dir/');
  google.search = new URLSearchParams({api: '1', destination, travelmode: mode}).toString();
  const apple = new URL('https://maps.apple.com/directions');
  apple.search = new URLSearchParams({destination, mode}).toString();
  if (google.href.length > 2048 || apple.href.length > 2048) {
    throw new ProjectionError('Shorten the destination before opening directions.', 'directions_invalid_destination');
  }
  return {destination, mode, requiresConfirmation: true, addressVerified: false,
    googleMapsUrl: google.href, appleMapsUrl: apple.href,
    message: 'Review the full destination, then choose a map app. Confirm its address match before starting navigation.'};
}
