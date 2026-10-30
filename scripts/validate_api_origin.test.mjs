import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { validateApiOrigin, verifyApiHealth, verifyApiAuthReadiness } from './validate_api_origin.mjs';

// These hostnames are synthetic test inputs only. No test builds an APK or
// contacts a hosted service; real deployment has no configured origin yet.
const publicInput = 'https://levelup-production-verified.onrender.com';

test('explicit HTTPS origin is normalized without inventing a fallback', () => {
  assert.equal(validateApiOrigin(` ${publicInput}/ `), publicInput);
  assert.equal(validateApiOrigin('https://API.MyPlannerCloud.com:443/'), 'https://api.myplannercloud.com');
  assert.throws(() => validateApiOrigin(''));
  assert.throws(() => validateApiOrigin(undefined));
});

test('rejects local, plaintext, credentials, placeholders and API paths', () => {
  const credentialUrl = new URL('https://api.myplannercloud.com');
  credentialUrl.username = 'user';
  credentialUrl.password = 'private-value';
  for (const value of [
    'http://api.myplannercloud.com', 'https://localhost', 'https://localhost.local',
    'https://127.0.0.1', 'https://2130706433', 'https://[::1]', 'https://192.168.1.20',
    'https://api.internal', 'https://api.local', 'https://api.test', 'https://api.invalid',
    'https://example.com', 'https://api.example.com', 'https://level-up-api.onrender.com',
    'https://your-service.onrender.com', 'https://api.myplannercloud.com/api/v1',
    'https://api.myplannercloud.com:3000', credentialUrl.href,
    'https://api.myplannercloud.com?token=private-value', 'https://api.myplannercloud.com#fragment',
  ]) assert.throws(() => validateApiOrigin(value), undefined, value);
});

test('health probe is unauthenticated, bounded and rejects redirects or invalid readiness', async () => {
  let called = false;
  await verifyApiHealth(publicInput, async (url, options) => {
    called = true;
    assert.equal(url, `${publicInput}/health`);
    assert.equal(options.redirect, 'manual');
    assert.deepEqual(options.headers, { Accept: 'application/json' });
    assert.ok(options.signal instanceof AbortSignal);
    return { status: 200, json: async () => ({ status: 'ok' }) };
  });
  assert.ok(called);
  for (const response of [
    { status: 302, json: async () => ({ status: 'ok' }) },
    { status: 503, json: async () => ({ status: 'ok' }) },
    { status: 200, json: async () => ({ status: 'starting' }) },
    { status: 200, json: async () => { throw new Error('private server text'); } },
  ]) await assert.rejects(() => verifyApiHealth(publicInput, async () => response), /API health check failed/);
});

test('CLI fails closed without printing submitted credentials', () => {
  const script = fileURLToPath(new URL('./validate_api_origin.mjs', import.meta.url));
  const credentialUrl = new URL('https://api.myplannercloud.com');
  credentialUrl.username = 'user';
  credentialUrl.password = 'do-not-display';
  const result = spawnSync(process.execPath, [script, credentialUrl.href], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.doesNotMatch(result.stderr, /do-not-display/);
  const missing = spawnSync(process.execPath, [script], { encoding: 'utf8' });
  assert.equal(missing.status, 1);
});

test('production preflight detects a healthy database behind a broken HTTPS proxy or unprotected API', async () => {
  const run = (privateResponse) => verifyApiAuthReadiness(publicInput, async (url, options) => {
    assert.deepEqual(options.headers, { Accept: 'application/json' });
    assert.equal(options.redirect, 'manual');
    if (url.endsWith('/health')) return { status: 200, json: async () => ({ status: 'ok' }) };
    assert.equal(url, `${publicInput}/api/v1/state`);
    return privateResponse;
  });
  await run({ status: 401, json: async () => ({ error: { code: 'unauthorized' } }) });
  for (const response of [
    { status: 426, json: async () => ({ error: { code: 'https_required' } }) },
    { status: 200, json: async () => ({ state: {} }) },
    { status: 302, json: async () => ({ error: { code: 'unauthorized' } }) },
    { status: 401, json: async () => ({ error: { code: 'different_failure' } }) },
  ]) await assert.rejects(run(response), /authentication readiness failed/);
});
