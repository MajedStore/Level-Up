#!/usr/bin/env node
// Level Up — Based on Streak by InlitX. GPL-3.0-only.
// Read-only: never stage files, change remotes, or print matched secret values.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const maxOutput = 512 * 1024 * 1024;
const findings = new Map();
const emit = (value) => process.stdout.write(`${JSON.stringify(value)}\n`);
const git = (args, input) => execFileSync('git', args, {
  input, maxBuffer: maxOutput, stdio: ['pipe', 'pipe', 'pipe'],
});
const lines = (buffer) => buffer.toString('utf8').split('\n').filter(Boolean);
const placeholder = (value) => /^(?:|\*+|\[REDACTED\]|<[^>]+>)$/.test(value) ||
  /replace[-_ ]?(?:this|with|me)|change[-_ ]?me|your[-_ ]|example|placeholder|test[-_ ]only|development[-_ ]only|\$\{|^process\.env|^secret-from-env/i.test(value);
const finding = (source, file, line, category) => {
  const value = { source, path: file, line, category, value: '[REDACTED]' };
  findings.set(JSON.stringify(value), value);
};
const forbiddenPath = (file) => {
  if (/(?:^|\/)(?:node_modules|build|\.dart_tool|\.gradle|\.pub-cache)(?:\/|$)/i.test(file)) return 'generated-or-dependency-artifact';
  if (/(?:^|\/)\.env[^/]*$/i.test(file) && !/(?:^|\/)\.env\.example$/.test(file)) return 'private-environment-file';
  if (/(?:^|\/)(?:key|local)\.properties$|\.(?:jks|keystore|pem|key|p12|pfx)$/i.test(file)) return 'private-key-or-machine-configuration';
  if (/\.(?:hive(?:\.lock)?|sqlite3?(?:-journal)?|db(?:-journal)?|mongodump|dump)$/i.test(file)) return 'local-database-file';
  if (/\.(?:apk|aab|ipa)$/i.test(file)) return 'compiled-application';
  return null;
};

try {
  const root = git(['rev-parse', '--show-toplevel']).toString('utf8').trim();
  process.chdir(root);
  const knownSecrets = new Map();
  const sensitiveKey = /(?:^|_)(?:SECRET|PASSWORD|PASSWD|PRIVATE_KEY|ACCESS_TOKEN|REFRESH_TOKEN|API_KEY|URI)$/i;
  let privateEnvironmentFiles = 0;
  const ignoreDirectories = new Set(['.git', 'node_modules', 'build', '.dart_tool', '.gradle', '.pub-cache', '.cache']);
  function readLocalEnvironment(directory = '.') {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      if (entry.isSymbolicLink()) continue;
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        if (!ignoreDirectories.has(entry.name)) readLocalEnvironment(file);
      } else if (/^\.env/.test(entry.name) && entry.name !== '.env.example') {
        privateEnvironmentFiles++;
        const text = fs.readFileSync(file, 'utf8');
        for (const line of text.split(/\r?\n/)) {
          const match = /^\s*(?:export\s+)?([\w]+)\s*=\s*(.*?)\s*$/.exec(line);
          if (!match || !sensitiveKey.test(match[1])) continue;
          let value = match[2];
          if (/^(['"]).*\1$/.test(value)) value = value.slice(1, -1);
          else value = value.replace(/\s+#.*$/, '').trim();
          if (value.length >= 8 && !placeholder(value)) knownSecrets.set(value, match[1]);
          if (/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) {
            try {
              const url = new URL(value);
              const password = decodeURIComponent(url.password);
              if (password.length >= 4 && !placeholder(password)) knownSecrets.set(password, 'database-password');
            } catch { /* The exact URI is still checked without logging it. */ }
          }
        }
      }
    }
  }
  readLocalEnvironment();

  let scannedBytes = 0;
  const checkedContent = new Set();
  function inspect(buffer, source, file, contentId) {
    const artifact = forbiddenPath(file);
    if (artifact) finding(source, file, 0, artifact);
    // A shared historical blob needs content inspection once; every file path
    // still receives the sensitive-path check above.
    const cacheId = `${source}:${contentId}`;
    if (checkedContent.has(cacheId)) return;
    checkedContent.add(cacheId);
    scannedBytes += buffer.length;
    for (const [secret, category] of knownSecrets) {
      let offset = buffer.indexOf(secret);
      while (offset !== -1) {
        const line = buffer.subarray(0, offset).toString('utf8').split('\n').length;
        finding(source, file, line, `matches-local-${category}`);
        offset = buffer.indexOf(secret, offset + secret.length);
      }
    }
    if (buffer.includes(0)) return;
    const text = buffer.toString('utf8');
    const checks = [
      ['private-key', /-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----/g],
      ['github-token', /\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b/g],
      ['aws-access-key', /\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/g],
      ['jwt-token', /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{15,}\b/g],
      ['credential-url', /[a-z][a-z0-9+.-]*:\/\/([^\s/"'`<>:@]+):([^\s/"'`<>@]+)@[^\s"'`<>]+/gi],
      ['secret-assignment', /^\s*(?:export\s+)?(?:[A-Z0-9_]*(?:SECRET|PASSWORD|PASSWD|PRIVATE_KEY|ACCESS_TOKEN|REFRESH_TOKEN|API_KEY))\s*=\s*["']?([^\r\n"']+)/gm],
    ];
    for (const [category, regex] of checks) {
      for (const match of text.matchAll(regex)) {
        if (category === 'credential-url') {
          // Rejection tests use deliberately invalid credentials on RFC 2606
          // example hosts. Only obvious synthetic values qualify; matching a
          // real local environment value is always reported above.
          let exampleFixture = false;
          try {
            const host = new URL(match[0]).hostname;
            exampleFixture = /(?:^|\.)example\.(?:com|org|net)$|\.(?:test|invalid)$|^localhost$/.test(host) &&
              /^(?:user|username|test)$/.test(match[1]) && /^(?:pass|password|test|secret|pwd)$/.test(match[2]);
          } catch { /* Treat malformed credential URLs as findings. */ }
          if (exampleFixture || placeholder(match[1]) && placeholder(match[2])) continue;
        }
        if (category === 'secret-assignment' && placeholder(match[1].trim())) continue;
        finding(source, file, text.slice(0, match.index).split('\n').length, category);
      }
    }
  }

  const tracked = git(['ls-files', '-z']).toString('utf8').split('\0').filter(Boolean);
  const untracked = git(['ls-files', '--others', '--exclude-standard', '-z']).toString('utf8').split('\0').filter(Boolean);
  for (const file of [...tracked, ...untracked]) {
    if (fs.existsSync(file) && fs.lstatSync(file).isFile()) {
      inspect(fs.readFileSync(file), tracked.includes(file) ? 'working-tree' : 'untracked-upload-candidate', file, file);
    }
  }

  // Inspect staged/index bytes independently from the working tree. A secret
  // removed in an unstaged edit can otherwise still be committed accidentally.
  const indexObjects = git(['ls-files', '--stage', '-z']).toString('utf8').split('\0').filter(Boolean).map((line) => {
    const match = /^\d+ ([a-f0-9]+) \d\t([\s\S]+)$/.exec(line);
    if (!match) throw new Error('Invalid Git index entry.');
    return { id: match[1], file: match[2], source: 'index' };
  });
  // All local refs, including upstream history: deleting a secret from HEAD
  // alone never makes a historical credential safe to push.
  const historical = lines(git(['rev-list', '--objects', '--all'])).map((line) => {
    const space = line.indexOf(' ');
    return { id: space < 0 ? line : line.slice(0, space), file: space < 0 ? '[historical-object]' : line.slice(space + 1), source: 'history' };
  });
  const objects = [...indexObjects, ...historical];
  const ids = [...new Set(objects.map((object) => object.id))];
  const metadata = new Map(lines(git(['cat-file', '--batch-check=%(objectname) %(objecttype) %(objectsize)'], `${ids.join('\n')}\n`)).map((line) => {
    const [id, type, size] = line.split(' ');
    return [id, { type, size: Number(size) }];
  }));
  const blobs = ids.filter((id) => metadata.get(id)?.type === 'blob');
  const payload = git(['cat-file', '--batch'], `${blobs.join('\n')}\n`);
  const buffers = new Map();
  let offset = 0;
  for (const id of blobs) {
    const headerEnd = payload.indexOf(10, offset);
    if (headerEnd < offset) throw new Error('Incomplete Git object stream.');
    const size = metadata.get(id).size;
    const begin = headerEnd + 1;
    if (begin + size > payload.length) throw new Error('Incomplete Git blob.');
    buffers.set(id, payload.subarray(begin, begin + size));
    offset = begin + size + 1;
  }
  for (const object of objects) {
    if (buffers.has(object.id)) inspect(buffers.get(object.id), object.source, object.file, object.id);
  }
  for (const item of findings.values()) emit(item);
  emit({
    result: findings.size ? 'BLOCKED' : 'PASS',
    trackedFiles: tracked.length, untrackedUploadCandidates: untracked.length,
    privateEnvironmentFilesReadInMemory: privateEnvironmentFiles,
    knownSecretValuesChecked: knownSecrets.size,
    historicalBlobs: blobs.length,
    inspectedBytes: scannedBytes,
    findings: findings.size,
  });
  process.exitCode = findings.size ? 1 : 0;
} catch {
  // Never print subprocess stderr or Error stacks: they can contain file data.
  emit({ result: 'ERROR', category: 'safety-check-incomplete', value: '[REDACTED]' });
  process.exitCode = 2;
}
