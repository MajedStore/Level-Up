// Write existing release credentials from CI environment without logging them.
// This never creates a new signing key or changes the Gradle signing setup.
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function signingFiles(env) {
  const required = ['KEYSTORE_BASE64', 'KEYSTORE_PASSWORD', 'KEY_PASSWORD', 'KEY_ALIAS'];
  const missing = required.filter(key => typeof env[key] !== 'string' || env[key].length === 0);
  if (missing.length) throw new Error(`Configure these existing signing secrets: ${missing.join(', ')}.`);
  const encoded = env.KEYSTORE_BASE64.replace(/\s/g, '');
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encoded) || encoded.length % 4 !== 0) {
    throw new Error('KEYSTORE_BASE64 must contain a valid encoded keystore.');
  }
  const keystore = Buffer.from(encoded, 'base64');
  if (keystore.length < 32 || keystore.toString('base64') !== encoded) {
    throw new Error('KEYSTORE_BASE64 must contain a valid encoded keystore.');
  }
  const escape = value => value.replaceAll('\\', '\\\\').replaceAll('\r', '\\r')
    .replaceAll('\n', '\\n').replaceAll('\t', '\\t').replaceAll(' ', '\\ ')
    .replaceAll(':', '\\:').replaceAll('=', '\\=');
  return { keystore, properties: [
    `storePassword=${escape(env.KEYSTORE_PASSWORD)}`,
    `keyPassword=${escape(env.KEY_PASSWORD)}`,
    `keyAlias=${escape(env.KEY_ALIAS)}`,
    'storeFile=streak-release.jks', '',
  ].join('\n') };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const files = signingFiles(process.env);
    await mkdir('android/app', { recursive: true });
    await writeFile('android/app/streak-release.jks', files.keystore, { mode: 0o600 });
    await writeFile('android/key.properties', files.properties, { mode: 0o600 });
    console.log('Existing release signing credentials prepared.');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
