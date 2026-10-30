import test from 'node:test';
import assert from 'node:assert/strict';
import { signingFiles } from './configure_android_signing.mjs';

test('missing signing credentials fail with names only', () => {
  assert.throws(() => signingFiles({ KEYSTORE_PASSWORD: 'must-not-print-me' }), error => {
    assert.match(error.message, /KEYSTORE_BASE64/);
    assert.doesNotMatch(error.message, /must-not-print-me/);
    return true;
  });
});

test('malformed base64 fails without exposing input', () => {
  assert.throws(() => signingFiles({ KEYSTORE_BASE64: 'private-invalid!',
    KEYSTORE_PASSWORD: 'password', KEY_PASSWORD: 'password', KEY_ALIAS: 'alias' }),
    error => !error.message.includes('private-invalid!'));
});

test('existing binary key is preserved and properties escape special characters', () => {
  const binary = Buffer.alloc(64, 73);
  const result = signingFiles({ KEYSTORE_BASE64: binary.toString('base64'),
    KEYSTORE_PASSWORD: ' a\\b\nc:=', KEY_PASSWORD: 'different', KEY_ALIAS: 'existing alias' });
  assert.deepEqual(result.keystore, binary);
  assert.equal(result.properties,
    'storePassword=\\ a\\\\b\\nc\\:\\=\nkeyPassword=different\nkeyAlias=existing\\ alias\nstoreFile=streak-release.jks\n');
});
