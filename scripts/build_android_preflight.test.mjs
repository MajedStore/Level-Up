import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const helper = fileURLToPath(new URL('./Build-LevelUpAndroid.ps1', import.meta.url));
const signing = fileURLToPath(new URL('../android/key.properties', import.meta.url));
const artifact = fileURLToPath(new URL('../build/app/outputs/flutter-apk/app-release.apk', import.meta.url));
const run = (args) => spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', helper, ...args], { encoding: 'utf8' });

test('Windows helper preflight never resolves dependencies or changes an APK', { skip: process.platform !== 'win32' }, () => {
  const before = existsSync(artifact) ? statSync(artifact).mtimeMs : null;
  // Synthetic validator input only; no CheckHealth, network or build is run.
  const result = run(['-ApiBaseUrl', 'https://levelup-production-verified.onrender.com', '-PreflightOnly', '-AllowDebugSigning', '-FlutterPath', 'must-not-execute-flutter']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Preflight complete\. No dependency resolution or APK build was run/);
  assert.match(result.stdout, /Version from pubspec\.yaml: 3\.0\.0\+22/);
  assert.equal(existsSync(artifact) ? statSync(artifact).mtimeMs : null, before);
});

test('Windows helper rejects missing production signing before invoking Flutter', { skip: process.platform !== 'win32' || existsSync(signing) }, () => {
  const result = run(['-ApiBaseUrl', 'https://levelup-production-verified.onrender.com', '-PreflightOnly', '-FlutterPath', 'must-not-execute-flutter']);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /android\/key\.properties is missing/);
  assert.doesNotMatch(result.stderr, /must-not-execute-flutter/);
});

test('Windows helper fails closed on local URL before signing or Flutter work', { skip: process.platform !== 'win32' }, () => {
  const result = run(['-ApiBaseUrl', 'http://10.0.2.2:3000', '-PreflightOnly', '-AllowDebugSigning', '-FlutterPath', 'must-not-execute-flutter']);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Production API validation failed|Use the actual public HTTPS origin/);
  assert.doesNotMatch(result.stderr, /must-not-execute-flutter/);
});

test('Windows helper rejects a malformed Google server client ID before Flutter work', { skip: process.platform !== 'win32' }, () => {
  const result = run(['-ApiBaseUrl', 'https://levelup-production-verified.onrender.com', '-GoogleServerClientId', 'not-a-google-client-id', '-PreflightOnly', '-AllowDebugSigning', '-FlutterPath', 'must-not-execute-flutter']);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /GoogleServerClientId must be the Web OAuth client ID/);
  assert.doesNotMatch(result.stderr, /must-not-execute-flutter/);
});
