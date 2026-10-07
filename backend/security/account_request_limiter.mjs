// Supplemental per-process abuse budgets for authenticated side-effect routes.
// Keys come only from the verified principal, never caller-supplied account IDs.
export function createAccountRequestLimiter({windowMs, maxAttempts, maxAccounts = 10000, now = Date.now}) {
  const attempts = new Map();
  return function consume(userId) {
    if (typeof userId !== 'string' || !userId) throw Object.assign(new Error('Sign in required.'), {statusCode: 401});
    const timestamp = now();
    for (const [key, entry] of attempts) if (entry.expiresAt <= timestamp) attempts.delete(key);
    const current = attempts.get(userId);
    if (current?.count >= maxAttempts) {
      throw Object.assign(new Error('Too many requests. Please try again later.'), {
        statusCode: 429, retryAfter: Math.max(1, Math.ceil((current.expiresAt - timestamp) / 1000)),
      });
    }
    if (!current && attempts.size >= maxAccounts) {
      throw Object.assign(new Error('This service is busy. Please try again later.'), {statusCode: 503});
    }
    attempts.set(userId, current
      ? {...current, count: current.count + 1}
      : {count: 1, expiresAt: timestamp + windowMs});
  };
}
