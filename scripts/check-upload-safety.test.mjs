// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scanner = fileURLToPath(new URL('./check-upload-safety.mjs', import.meta.url));
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'levelup-upload-audit-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, stdio: 'pipe' });
  git('init', '--quiet');
  fs.writeFileSync(path.join(root, '.gitignore'), '.env*\n!.env.example\n');
  const secret = randomBytes(32).toString('hex');
  fs.writeFileSync(path.join(root, '.env'), `JWT_SECRET=${secret}\n`);
  fs.writeFileSync(path.join(root, '.env.example'), 'JWT_SECRET=replace-with-a-random-value\n');
  git('add', '.gitignore', '.env.example');
  const commit = () => git('-c', 'user.name=Safety test', '-c', 'user.email=safety@example.invalid', 'commit', '--quiet', '-m', 'Fixture');
  const audit = () => {
    const result = spawnSync(process.execPath, [scanner], { cwd: root, encoding: 'utf8' });
    assert.equal(result.stderr, '');
    assert.equal(result.stdout.includes(secret), false, 'Secret values must never enter audit output.');
    return { ...result, items: result.stdout.trim().split('\n').map((line) => JSON.parse(line)) };
  };
  return { root, git, secret, commit, audit };
}

test('ignored local secrets and sanitized examples remain safe', (t) => {
  const f = fixture(t);
  f.commit();
  const result = f.audit();
  assert.equal(result.status, 0);
  assert.equal(result.items.at(-1).findings, 0);
  assert.equal(result.items.at(-1).knownSecretValuesChecked, 1);
});

test('staged bytes are checked even after the working copy is sanitized', (t) => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.root, 'public.txt'), `accidental value ${f.secret}\n`);
  f.git('add', 'public.txt');
  fs.writeFileSync(path.join(f.root, 'public.txt'), 'sanitized\n');
  const result = f.audit();
  assert.equal(result.status, 1);
  assert.ok(result.items.some((item) => item.source === 'index' && item.category === 'matches-local-JWT_SECRET'));
});

test('deleted historical secrets still block upload', (t) => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.root, 'public.txt'), `accidental value ${f.secret}\n`);
  f.git('add', 'public.txt');
  f.commit();
  f.git('rm', '--quiet', 'public.txt');
  f.commit();
  const result = f.audit();
  assert.equal(result.status, 1);
  assert.ok(result.items.some((item) => item.source === 'history' && item.path === 'public.txt'));
});

test('forced environment copies and private keys block upload without known values', (t) => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.root, '.env copy.example'), 'PRIVATE_SETTING=keep-local\n');
  f.git('add', '--force', '.env copy.example');
  fs.writeFileSync(path.join(f.root, 'unexpected.txt'), ['-----BEGIN ', 'PRIVATE KEY-----', '\nsynthetic\n'].join(''));
  const result = f.audit();
  assert.equal(result.status, 1);
  assert.ok(result.items.some((item) => item.category === 'private-environment-file'));
  assert.ok(result.items.some((item) => item.category === 'private-key'));
});

test('credential-bearing URLs are reported independently of local environment secrets', (t) => {
  const f = fixture(t);
  const password = randomBytes(16).toString('hex');
  fs.writeFileSync(path.join(f.root, 'unexpected.txt'), ['db+srv:', '//account:', password, '@cluster.example.net/database'].join(''));
  const result = f.audit();
  assert.equal(result.status, 1);
  assert.equal(result.stdout.includes(password), false);
  assert.ok(result.items.some((item) => item.category === 'credential-url'));
});
