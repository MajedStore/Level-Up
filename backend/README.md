# Level Up API

Node.js/Express REST API with owner-scoped MongoDB persistence, email/password
authentication, and authoritative planner rule processing. This is part of the
existing Level Up application. **Based on Streak by InlitX.** GPL-3.0-only; retain
the repository's [license](../LICENSE) and [additional terms](../ADDITIONAL_TERMS.md).

## Setup

Use Node.js 22.18 or later (verified here with Node 24.15). From `backend/`:

```powershell
npm ci
Copy-Item .env.example .env
node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"
# Put the generated key in .env as JWT_SECRET; configure MONGODB_URI as below.
npm run db:init
npm run dev
```

The `.env` file and `node_modules` are ignored. Never put a real MongoDB URI,
database password, refresh token, or JWT secret in Flutter or version control.
`npm start` runs the production entry point. `GET /health` pings MongoDB; it only
returns `{"status":"ok"}` when the database responds. Startup fails closed if
the configuration, connection, schema initialization, or indexes fail.

### MongoDB Atlas

1. Create an Atlas account/project and a cluster that supports transactions.
   Atlas replica sets support this API; a standalone local `mongod` does not.
2. Under Database Access, create a dedicated database user. Grant `readWrite`
   only on the application database (for example `level_up`), rather than an
   Atlas administrator role. Use a separate migration account for `db:init`:
   it needs `readWrite` plus database-scoped `collMod` (a custom role), or
   `readWrite` plus `dbAdmin` on that database. Keep migration credentials out of
   the running service. Runtime startup creates missing collections/indexes but
   never modifies existing validators, so it does not require `collMod`.
3. Under Network Access, allow the backend host's specific outbound IP or use
   private networking. Do not allow `0.0.0.0/0` as a production shortcut.
4. In Connect → Drivers, obtain the `mongodb+srv://...` Node connection string.
   URL-encode special characters in the database username/password. Set the URI
   only on the server. Keep Atlas TLS/certificate verification enabled.
5. Set `MONGODB_DATABASE=level_up`, a random `JWT_SECRET`, and the expected JWT
   issuer/audience. Run `npm run db:init` with the migration account's URI,
   then restore the runtime account's URI before `npm start`. Initialization is
   idempotent and additive: it never drops collections or resets users.
   Back up an existing deployment before migrations.
6. Run the service and check `/health`. Create an app account, sign in, sync a
   change, and verify the acknowledged record in Atlas. A cluster existing in
   the Atlas console alone is not evidence that the app has connected.

No Atlas credentials were provided in this workspace. Atlas connection and
production deployment have **not** been verified. Repository integration tests
use a real, temporary local MongoDB replica set, described below.

Official guidance: [Atlas database users](https://www.mongodb.com/docs/atlas/security-add-mongodb-users/),
[network access](https://www.mongodb.com/docs/atlas/security/ip-access-list/),
[connection strings](https://www.mongodb.com/docs/atlas/driver-connection/), and
[Node driver transactions](https://www.mongodb.com/docs/drivers/node/current/crud/transactions/).

### Server variables

| Variable | Meaning |
| --- | --- |
| `MONGODB_URI` | Server-only replica-set or Atlas URI |
| `MONGODB_DATABASE` | Database name; default `level_up` |
| `JWT_SECRET` | At least 32 random bytes; do not use the example placeholder |
| `JWT_ISSUER`, `JWT_AUDIENCE` | Expected signed access-token identity |
| `ACCESS_TOKEN_SECONDS` | Default 900; allowed 60–3600 |
| `REFRESH_TOKEN_DAYS` | Default 30; allowed 1–90 |
| `HOST`, `PORT` | Default `127.0.0.1:3000` |
| `NODE_ENV` | `development`, `test`, or `production` |
| `CORS_ORIGINS` | Optional comma-separated exact browser origins; no wildcard |
| `TRUST_PROXY_HOPS` | Default 0; set only to the actual trusted proxy count |

Native Android does not need a CORS origin. Production rejects plain HTTP;
terminate TLS at a trusted reverse proxy and configure its real hop count. Bind
`HOST=0.0.0.0` when the host/container needs an external listener. Supply secrets
through the hosting service's secret manager and use `npm ci --omit=dev`, then
`npm run db:init` as a separate migration step using the migration account, and
`npm start` using the runtime `readWrite` account. Configure HTTPS, health checks, network rules,
process restarts, backups, monitoring, and a stable public API URL. This repository
does not silently create a public deployment or a paid Atlas cluster.

### Flutter API address

Set the app's documented `LEVEL_UP_API_BASE_URL` Dart define to the server's
public HTTPS origin, without `/api/v1` (the client adds versioned paths).

```powershell
flutter run --dart-define=LEVEL_UP_API_BASE_URL=https://api.example.com
```

Android emulator `localhost` refers to the emulator. For a local loopback server,
use an authorized debug development configuration and `adb reverse tcp:3000
tcp:3000`, or use `http://10.0.2.2:3000` with the existing debug-only Android
network policy. A physical device needs the development computer's reachable
LAN address, a scoped firewall rule, and a listener bound to that interface;
alternatively use an HTTPS development endpoint. Production builds require
HTTPS. Do not broadly enable cleartext traffic in the release manifest.

## Wire contract

All JSON routes use `/api/v1`. Private routes require
`Authorization: Bearer <accessToken>`; identity always comes from the verified
token and active session, never a request-body user ID.

| Route | Body / response |
| --- | --- |
| `POST /auth/register` | `{email,password}` → 201 session |
| `POST /auth/login` | `{email,password}` → session |
| `POST /auth/refresh` | `{refreshToken}` → rotated session |
| `POST /auth/logout` | `{refreshToken}` → 204; revokes that session |
| `GET /state` | `{revision,state,settings,serverTime}`; empty account has `state:null, revision:0` |
| `POST /sync` | `{mutationId,baseRevision,state,settings:{locale},timeZone}` → acknowledged canonical snapshot |

A session is `{user:{id,email},accessToken,refreshToken,expiresIn}`. Email is
trimmed and case-normalized; passwords need at least 12 characters and at most
72 UTF-8 bytes. The backend hashes passwords with bcrypt cost 12 and rejects
inputs that bcrypt would truncate. Refresh tokens are random opaque 48-byte
values; only SHA-256 hashes are stored. Refresh consumes the old session in a
transaction and creates a new one. JWT signatures, issuer, audience, expiry and
session revocation are checked on every private request. Sign-out revokes the
session; it does not delete cloud planner records.

Failures use `{error:{code,message}}`. Codes include `validation_failed`,
`invalid_email`, `weak_password`, `email_exists`, `invalid_credentials`,
`unauthorized`, `session_expired`, `rate_limited`, `revision_conflict`,
`history_conflict`, `deadline_passed`, `invalid_transition`, `mutation_reused`
and `service_unavailable`. The Flutter UI localizes these codes. A 409 revision
conflict also returns the current snapshot/revision for explicit reconciliation.
Do not discard the client's queued proposal on a failed request.

### Transition validation and offline rules

`state` is a **proposal**, not a trusted database replacement. Every accepted
transition independently validates typed definitions, real task parent IDs,
cycles, required group structure, leaf availability, prerequisites, step/amount
conditions, immutable instance snapshots, daily selection and receipt-time
deadlines. Client XP deltas and lifecycle claims are never copied as authority.
The server derives the skip cost, package reward, failure penalty and missed
selection penalty from the verified frozen rule. Existing routine completions
do not earn new challenge XP. Groups cannot produce a completion action.

The first import into an empty account replays existing ledger events against
their captured records/rules, including provable historic routine XP. Invalid
or unprovable history is rejected; the local draft remains available. This is
an integrity check of self-reported legacy data, not cryptographic proof that
an offline action physically happened. It is limited to a previously empty
account; later writes cannot replace accepted history.

Package-only snapshots with `skipPenalty:null` preserve the old no-skip-deduction
rule. New snapshots use a nonnegative package skip penalty and create one
`skip:<occurrenceId>` ledger audit event even when the balance floor makes the
actual deduction zero. Legacy per-task snapshots retain their original task
reward/skip rules. Skipping a required task never counts as completion and does
not cancel the package; deadline failure remains independent and idempotent.

The client queues ordered immutable checkpoints. It must not collapse a
create → assign → edit sequence, because each snapshot captures the template
that existed when it was assigned. The server uses its receipt time for new
deadline-sensitive actions, and IANA `timeZone` for local-day calculations.
An offline completion received after the package deadline is rejected rather
than backdated to mint XP. Preserve it as a visible conflict for review.

Each accepted mutation increments an account revision inside a MongoDB
transaction. `mutationId` is unique per user and bound to the original request;
retrying the identical request is acknowledged without replaying events. Map key
order is ignored, so native JSON reserialization after restart is safe. A
different payload using the same ID is rejected. Stale revisions receive 409.
Deadlines reconcile when a private state read or sync arrives; neither Android
nor this API promises exact midnight execution. `GET /state` may therefore
return a newer revision with server-derived deadline events. Later stale client
checkpoints remain conflicts until explicitly reconciled.

## Collections and integrity

| Collection | Contents / relationships |
| --- | --- |
| `users` | Stable account ID, unique normalized email, password hash |
| `sessions` | User owner ID, hashed refresh token, expiry, revocation; TTL expiry index |
| `accountSettings` | User locale, time zone, revision and scalar planner rules |
| `routines` | Independent recurring routine definitions |
| `routineOverrides`, `routineExclusions` | Stable occurrence edits/exclusions |
| `completionRecords` | Routine and challenge leaf records keyed by existing occurrence ID |
| `categories` | User category IDs and names |
| `packageTemplates` | Editable package rules; ordered task definitions with `parentId` embedded for one-read tree access |
| `challengeInstances` | Immutable embedded package/task snapshot and lifecycle |
| `dailyAssignments` | Frozen local-date selection/deadline; unique owner + target date |
| `xpLedger` | Event ID, type, related ID, computed change, timestamp; unique owner + idempotency key |
| `achievements` | Stable earned achievement IDs and unlock times |
| `occurrenceReminders` | Per-occurrence optional reminder overrides |
| `syncMutations` | Unique owner + mutation ID receipt/hash/revision |
| `schemaMigrations` | Additive initialization version record |

Every private collection uses server-controlled `ownerId` and owner-filtered
queries. Definitions and outcomes are separate structured documents rather than
one unstructured application-state blob. The wire snapshot is assembled for
compatibility with the existing Flutter repository. Indexed owner/record IDs,
Mongo validators and a transaction with snapshot reads/majority writes protect
multi-collection commits. A mid-write failure rolls everything back. Deploy on
a replica set/Atlas; the API fails instead of pretending standalone writes are
atomic.

## Tests and limits

```powershell
npm test
npm run check
npm audit
```

The backend verification run passed **34 tests**, with no skips, and syntax
checks passed. `npm audit` reported zero vulnerabilities for the installed
dependency tree. See `test-backend-final.log` in this directory (ignored local
execution evidence).

Integration tests start **real MongoDB 8.0.17 as a temporary local replica set**
using `mongodb-memory-server`. The first run downloads the MongoDB binary
(the Windows archive is approximately 756 MB); MongoDB is not mocked. They test
registration/login, authorization, user isolation, validation, refresh rotation,
revocation, confirmed restore reads, concurrent retries, revision conflicts,
additive initialization, runtime/migration validator-command separation, and
rollback after an injected multi-collection error. The validator-command check
uses an instrumented real MongoDB connection; the local fixture does not enable
database authentication, so it does not claim an authenticated Atlas role test.
Unit tests cover legacy migration/XP replay, nested completion, skips,
immutable snapshots, moved routine occurrences, prerequisite dates, assignment,
failure, deadlines, achievement proofs and invalid imported-history rejection.
These checks do not establish an Atlas connection or a production deployment.

This first version uses revision conflicts rather than automatic multi-device
merging; queued drafts must remain visible to the user. Authentication rate
limits are per-process, so a multi-instance deployment needs a shared limiter
or equivalent gateway policy. Password reset, email verification, account
deletion, push-based cross-device refresh and scheduled server jobs are not
implemented. Operational deployment and account recovery policies must be
configured by the owner. Database backups protect against cloud deletion;
clearing a device cache only restores successfully acknowledged cloud writes.

Security guidance used: [Express production security](https://expressjs.com/advanced/best-practice-security/),
[MongoDB role privileges](https://www.mongodb.com/docs/manual/reference/built-in-roles/),
[MongoDB connection timeouts](https://www.mongodb.com/docs/drivers/node/current/connect/connection-options/),
[bcryptjs security notes](https://www.npmjs.com/package/bcryptjs), and
[MongoMemoryReplSet](https://typegoose.github.io/mongodb-memory-server/docs/api/classes/mongo-memory-replset/).
