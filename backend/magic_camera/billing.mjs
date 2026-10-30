import {createHash} from 'node:crypto';
import {BillingError, fail} from '../web_billing/core.mjs';
import {googlePlay} from '../google_play/provider.mjs';
import {registerGooglePlay} from '../google_play/routes.mjs';

export const MAGIC_PACKAGE = 'com.korlixdeveloper.magiccamera';
export const MAGIC_PRODUCTS = Object.freeze({magic_camera_starter:'starter',magic_camera_plus:'plus'});
export const magicAccountId = id => createHash('sha256').update(`korlix:magic-camera:google-play:${id.toLowerCase()}`).digest('hex');
export function magicBillingStore(database) {
  return {async command(actor, action, payload = {}) {
    if (!database) fail('Magic Camera subscription storage is unavailable. Please retry.', 503);
    const {data, error} = await database.rpc('korlix_magic_billing_command', {p_actor: actor || null, p_action: action, p: payload});
    if (error) {
      const known = /BILL(\d{3}): (.+)/.exec(error.message || '');
      if (known) throw new BillingError(known[2], Number(known[1]));
      fail('Magic Camera subscription storage is unavailable. Please retry.', 503);
    }
    return data;
  }};
}
export function registerMagicBilling(app, {database, requireUser, loadProfile, environment = process.env, ...overrides} = {}) {
  const scopedEnvironment = {...environment,
    KORLIX_GOOGLE_PLAY_BILLING_ENABLED: environment.KORLIX_MAGIC_CAMERA_BILLING_ENABLED || 'false'};
  return registerGooglePlay(app, {database, requireUser, loadProfile, environment: scopedEnvironment,
    configuration: {root: '/api/magic-camera/billing/google', packageName: MAGIC_PACKAGE,
      products: MAGIC_PRODUCTS, version: 'magic_camera_monthly_v1', accountIdentifier: magicAccountId},
    store: magicBillingStore(database),
    provider: googlePlay(scopedEnvironment, {packageName: MAGIC_PACKAGE, products: MAGIC_PRODUCTS}),
    ...overrides});
}
