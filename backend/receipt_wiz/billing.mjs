import {createHash} from 'node:crypto';
import {BillingError, fail} from '../web_billing/core.mjs';
import {googlePlay} from '../google_play/provider.mjs';
import {registerGooglePlay} from '../google_play/routes.mjs';

export const RECEIPT_PACKAGE = 'com.korlixdeveloper.receiptwiz';
export const RECEIPT_PRODUCTS = Object.freeze({receipt_wiz_full: 'full'});
export const receiptAccountId = id => createHash('sha256').update(`korlix:receipt-wiz:google-play:${id.toLowerCase()}`).digest('hex');
export function receiptBillingStore(database) {
  return {async command(actor, action, payload = {}) {
    if (!database) fail('Receipt subscription storage is unavailable. Please retry.', 503);
    const {data, error} = await database.rpc('korlix_receipt_billing_command', {p_actor: actor || null, p_action: action, p: payload});
    if (error) {
      const known = /BILL(\d{3}): (.+)/.exec(error.message || '');
      if (known) throw new BillingError(known[2], Number(known[1]));
      fail('Receipt subscription storage is unavailable. Please retry.', 503);
    }
    return data;
  }};
}
export function registerReceiptBilling(app, {database, requireUser, loadProfile, environment = process.env, ...overrides} = {}) {
  const scopedEnvironment = {...environment,
    KORLIX_GOOGLE_PLAY_BILLING_ENABLED: environment.KORLIX_RECEIPT_WIZ_BILLING_ENABLED || 'false'};
  return registerGooglePlay(app, {database, requireUser, loadProfile, environment: scopedEnvironment,
    configuration: {root: '/api/receipt-wiz/billing/google', packageName: RECEIPT_PACKAGE,
      products: RECEIPT_PRODUCTS, version: 'receipt_wiz_full_monthly_v1', accountIdentifier: receiptAccountId},
    store: receiptBillingStore(database),
    provider: googlePlay(scopedEnvironment, {packageName: RECEIPT_PACKAGE, products: RECEIPT_PRODUCTS}),
    ...overrides});
}
