// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import { isIP } from 'node:net';
import { pathToFileURL } from 'node:url';

/** Validate the public API origin embedded in an Android production artifact.
 * It contains no database credentials and never supplies a default hostname.
 */
export function validateApiOrigin(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error('Supply the actual deployed HTTPS API origin. No default is configured.');
  }
  const raw = value.trim();
  let url;
  try { url = new URL(raw); } catch {
    throw new Error('API origin must be a valid public HTTPS URL.');
  }
  const host = url.hostname.toLowerCase();
  const ipHost = host.replace(/^\[|\]$/g, '');
  if (url.protocol !== 'https:' || !host || url.username || url.password ||
      (url.port && url.port !== '443') || url.pathname !== '/' ||
      raw.includes('?') || raw.includes('#') || !host.includes('.') ||
      host.endsWith('.') || isIP(ipHost) ||
      /(?:^|\.)(?:localhost|local|internal|test|invalid|example)$/.test(host) ||
      /(?:^|\.)example\.(?:com|org|net)$/.test(host) ||
      /(?:^|[.-])(?:your|placeholder|replace-me)(?:[.-]|$)/.test(host) ||
      host === 'level-up-api.onrender.com') {
    throw new Error('Use the actual public HTTPS origin only, without credentials, API paths, query strings, local addresses or example hostnames.');
  }
  return url.origin;
}

/** Optional unauthenticated readiness check. Never send credentials or follow a
 * redirect to another host. Failure cannot be mistaken for a configured build.
 */
export async function verifyApiHealth(origin, request = fetch) {
  const validated = validateApiOrigin(origin);
  let response;
  try {
    response = await request(`${validated}/health`, {
      method: 'GET', redirect: 'manual',
      headers: { Accept: 'application/json' }, signal: AbortSignal.timeout(20_000),
    });
    if (response.status !== 200) throw new Error('unhealthy');
    const body = await response.json();
    if (body?.status !== 'ok') throw new Error('unhealthy');
  } catch {
    throw new Error('API health check failed. Confirm the deployment and database readiness before building.');
  }
}

const invoked = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invoked) {
  try {
    const args = process.argv.slice(2);
    if (args.length < 1 || args.length > 2 || (args.length === 2 && args[1] !== '--health')) {
      throw new Error('Usage: node scripts/validate_api_origin.mjs HTTPS_ORIGIN [--health]');
    }
    const origin = validateApiOrigin(args[0]);
    if (args[1] === '--health') await verifyApiHealth(origin);
    process.stdout.write(`${origin}\n`);
  } catch (error) {
    // Errors deliberately omit the supplied value and any server response body.
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
