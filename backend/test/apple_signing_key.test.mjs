import assert from 'node:assert/strict';
import {generateKeyPairSync, sign, verify} from 'node:crypto';
import test from 'node:test';
import {readAppleSigningKey} from '../web_billing/apple_signing_key.mjs';

const {privateKey, publicKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
const pem = privateKey.export({format: 'pem', type: 'pkcs8'});
const encodedPem = Buffer.from(pem).toString('base64');
const encodedDer = privateKey.export({format: 'der', type: 'pkcs8'}).toString('base64');

test('App Store signing accepts DER and existing PEM representations of the same key', () => {
  const message = Buffer.from('local signing-key format test');
  for (const env of [
    {KORLIX_APPLE_PRIVATE_KEY: encodedDer},
    {KORLIX_APPLE_PRIVATE_KEY: pem},
    {KORLIX_APPLE_PRIVATE_KEY: pem.replaceAll('\n', '\\n')},
    {KORLIX_APPLE_PRIVATE_KEY_BASE64: encodedPem},
    {KORLIX_APPLE_PRIVATE_KEY_BASE64: encodedDer},
    {KORLIX_APPLE_PRIVATE_KEY_BASE64: '  ', KORLIX_APPLE_PRIVATE_KEY: encodedDer},
    {KORLIX_APPLE_PRIVATE_KEY_BASE64: encodedPem, KORLIX_APPLE_PRIVATE_KEY: 'unusable'},
  ]) {
    const normalized = readAppleSigningKey(env);
    assert.ok(normalized.startsWith('-----BEGIN PRIVATE KEY-----'));
    assert.ok(verify('sha256', message, publicKey, sign('sha256', message, normalized)));
  }
});

test('invalid or unsuitable signing material fails closed without exposing it or falling back', () => {
  const otherCurve = generateKeyPairSync('ec', {namedCurve: 'secp384r1'}).privateKey;
  for (const env of [
    {}, {KORLIX_APPLE_PRIVATE_KEY: '-----BEGIN PRIVATE KEY-----\ninvalid'},
    {KORLIX_APPLE_PRIVATE_KEY: encodedDer.slice(0, 20)},
    {KORLIX_APPLE_PRIVATE_KEY: encodedDer + '!'},
    {KORLIX_APPLE_PRIVATE_KEY: publicKey.export({format: 'pem', type: 'spki'})},
    {KORLIX_APPLE_PRIVATE_KEY: otherCurve.export({format: 'pem', type: 'pkcs8'})},
    {KORLIX_APPLE_PRIVATE_KEY_BASE64: 'invalid', KORLIX_APPLE_PRIVATE_KEY: pem},
  ]) assert.ok(readAppleSigningKey(env) === '');
});
