import {UUID} from '../web_billing/core.mjs';
import {createAccountRequestLimiter} from '../security/account_request_limiter.mjs';
import {firstStoreCharge} from './first_charge.mjs';

// A read-only source of truth for the signed-in account. This step never logs a conversion.
// Matching a charge to a consented installation and delivering it once are separate operations.
export function registerStorePaymentCheck(app, {database, requireUser, apple, play, enabled = false}) {
  if (!enabled) return;
  const consume = createAccountRequestLimiter({windowMs: 15 * 60_000, maxAttempts: 3});
  app.get('/api/billing/measurement/first-payment', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      const user = await requireUser(req);
      if (!UUID.test(user?.id ?? '') || user.is_anonymous || !user.email_confirmed_at) {
        return res.status(403).json({error: 'A verified KORLIX account is required.'});
      }
      consume(user.id);
      // Request one more row than we can reconcile. A truncated history must never count as a new customer.
      const [appleRows, playRows] = await Promise.all([
        database.from('korlix_apple_transaction_bindings').select('original_transaction_id,environment')
          .eq('user_id', user.id).limit(21),
        database.from('korlix_play_purchases').select('purchase_token')
          .eq('user_id', user.id).eq('test_purchase', false).limit(21),
      ]);
      for (const result of [appleRows, playRows]) {
        if (result.error || !Array.isArray(result.data) || result.data.length > 20) throw new Error('Incomplete bindings.');
      }
      const charge = await firstStoreCharge({userId: user.id, appleBindings: appleRows.data,
        googleBindings: playRows.data, apple, play});
      if (!charge) return res.json({status: 'no_verified_payment'});
      if (charge.refunded) return res.json({status: 'first_payment_refunded'});
      return res.json({status: 'verified', store: charge.store, value: charge.value,
        currency: charge.currency, paidAt: new Date(charge.time).toISOString()});
    } catch (error) {
      if (error.retryAfter) res.set('Retry-After', String(error.retryAfter));
      const status = [401, 403, 429].includes(error.statusCode) ? error.statusCode : 503;
      return res.status(status).json({error: status === 401 ? 'Sign in required.' :
        status === 429 ? 'Please try again later.' : 'The first payment could not be verified.'});
    }
  });
}
