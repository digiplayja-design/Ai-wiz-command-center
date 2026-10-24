import {createHash} from 'node:crypto';

// Supplemental per-process mailbox budget. Provider and ingress throttles remain
// necessary across processes. No raw email, password, or account lookup is stored.
export function createReceiptSignupThrottle({now = Date.now, maxEntries = 5000} = {}) {
  const attempts = new Map();
  return email => {
    const timestamp = now();
    for (const [key, value] of attempts) {
      if (value.expires <= timestamp) attempts.delete(key);
    }
    const key = createHash('sha256').update(email.trim().toLowerCase()).digest('hex');
    const entry = attempts.get(key);
    if (entry?.count >= 5 || (!entry && attempts.size >= maxEntries)) {
      throw Object.assign(new Error('Too many signup attempts. Please try again later, or sign in with your existing KORLIX account.'), {statusCode: 429});
    }
    attempts.set(key, entry ? {...entry, count: entry.count + 1}
      : {count: 1, expires: timestamp + 15 * 60 * 1000});
  };
}
