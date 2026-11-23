import {createPrivateKey} from 'node:crypto';

// The App Store Server client signs ES256 requests with a PEM private key.
export function readAppleSigningKey(env) {
  const encoded = env.KORLIX_APPLE_PRIVATE_KEY_BASE64?.trim();
  const value = encoded || env.KORLIX_APPLE_PRIVATE_KEY?.trim();
  if (!value) return '';

  try {
    let key;
    if (!encoded && value.startsWith('-----BEGIN ')) {
      key = createPrivateKey(value.replace(/\\r\\n|\\n/g, '\n'));
    } else {
      const base64 = value.replace(/\s/g, '');
      if (!/^[A-Za-z0-9+/_-]+={0,2}$/.test(base64)) return '';
      const bytes = Buffer.from(base64, 'base64');
      const text = bytes.toString('utf8').trim();
      key = text.startsWith('-----BEGIN ')
        ? createPrivateKey(text)
        : createPrivateKey({key: bytes, format: 'der', type: 'pkcs8'});
    }
    if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails.namedCurve !== 'prime256v1') return '';
    return key.export({format: 'pem', type: 'pkcs8'});
  } catch {
    return '';
  }
}
