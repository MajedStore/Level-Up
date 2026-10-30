# Deploy the Level Up API on Render

This guide applies to the backend already in this repository. Authentication,
owner isolation, server-side XP checks and queued synchronization remain in use.
It does not create a GitHub repository, Render service or paid resource.

## Verified and still required

The local `backend/.env` was inspected without displaying its contents. Its
required configuration was valid. An actual MongoDB driver connection and
read-only `ping` to the configured Atlas database succeeded. No initialization,
collection/index changes, account registration or user-data writes were run
against Atlas during that check.

This verifies connectivity from this computer. Render has different outbound
addresses, so it does **not** establish that Render is deployed or connected.
No real Render service URL has been supplied. Live Render authentication,
cloud writes and phone restore remain to be tested after deployment.

Local verification after the preparation changes:

| Check | Result |
| --- | --- |
| `npm test` | **38 passed**, no skips, using a temporary real MongoDB replica set; 13.1s |
| `npm run check` | Passed |
| `npm audit` | Zero vulnerabilities |
| Existing local Atlas configuration + driver connect/ping | Valid; read-only ping succeeded; no user-data writes |

The new deployment tests cover host/port configuration, internal HTTP health
probes, HTTPS enforcement for APIs, safe readiness failure, and the three-second
readiness deadline. Existing authentication, ownership, XP and transaction tests
remain in the run. Local execution output is in ignored
`backend/test-render-preparation.log`.

## Web Service settings

In Render, choose **New + → Web Service → Connect GitHub repository** and select
the repository you own. Use these settings:

| Setting | Value |
| --- | --- |
| Service type | Web Service, not Static Site |
| Runtime | Node |
| Root Directory | `backend` |
| Build Command | `npm ci --omit=dev` |
| Start Command | `npm start` |
| Health Check Path | `/health` |
| Node version | `24.15.0` via `NODE_VERSION` |

The committed lockfile remains the installation source. No compilation or
development dependency is required to start this JavaScript service. The Node
engine range is bounded to `>=22.18.0 <25`; the Render variable pins the version
tested locally. Render gives `NODE_VERSION` precedence over the package range.

The optional repository-root [render.yaml](../render.yaml) contains the same
configuration as a reviewable Blueprint. Secrets use `sync: false`, prompting
for them in Render instead of embedding them in Git. You can use either the
normal Web Service setup above or a Blueprint; both produce a backend API.
The service name in the file is a configuration label, not a claim that a URL
with that name is available or deployed.

The Blueprint explicitly selects **Free** so applying it does not select a paid
instance implicitly. Free services spin down when idle and can take time to
wake. Choose a non-idling paid instance in Render when continuous availability
is required; review the current plan and price yourself before creation.
Hosting on Render removes the need to run the API on your personal computer.

## Environment variables

Add values in the Render dashboard's Environment settings. Copy the existing
secret values directly from your local configuration to Render yourself; never
paste them into chat, source code, GitHub, build arguments or logs.

| Variable | Render value |
| --- | --- |
| `MONGODB_URI` | The existing Atlas connection string; secret |
| `MONGODB_DATABASE` | `level_up` |
| `JWT_SECRET` | The existing separately generated signing secret; secret |
| `NODE_ENV` | `production` |
| `HOST` | `0.0.0.0` |
| `TRUST_PROXY_HOPS` | `1` for Render's direct HTTPS proxy configuration |
| `NODE_VERSION` | `24.15.0` |

Render supplies `PORT`; leave it managed by Render. The server reads that value.
Production defaults to `0.0.0.0`; local development continues to default to
`127.0.0.1:3000`. The Blueprint states the production host explicitly.

Optional settings retain the existing defaults: `JWT_ISSUER=level-up-api`,
`JWT_AUDIENCE=level-up-android`, `ACCESS_TOKEN_SECONDS=900`, and
`REFRESH_TOKEN_DAYS=30`. Native Android needs no browser CORS origin, so leave
`CORS_ORIGINS` empty unless adding a browser client. If needed, list only its
exact HTTPS origins; a wildcard is rejected. Keep issuer/audience stable across
deploys and avoid changing the JWT key casually, which invalidates sessions.

Render terminates HTTPS at its edge and forwards HTTP internally. With one
trusted proxy hop, forwarded HTTPS API requests remain authenticated and
protected; direct insecure API requests are rejected. If you add another proxy
or CDN, review the exact network path before changing the hop count. Do not set
unrestricted proxy trust.

`GET /health` is a narrow public readiness endpoint that also works for Render's
internal HTTP probe. It performs only a database ping, responds with
`{"status":"ok"}` on success and a safe 503 error on failure, and has a
three-second application deadline. It returns no database names, credentials,
user data or internal diagnostics. All private API routes still require HTTPS
and verified sessions in production.

## Atlas network and database permissions

After creating the Render service, open its **Connect → Outbound** tab. Copy
all current outbound CIDR ranges for that service's region into Atlas
**Security → Network Access → IP Access List**. Render can use any address in
those ranges. The ranges are shared with other services in the region; for a
narrower allowlist, evaluate Render's dedicated outbound IP option. Update the
allowlist if the region or outbound configuration changes. Do not use
`0.0.0.0/0` as a permanent shortcut.

Retain the existing `level_up` database. The runtime database user needs
`readWrite` only on that database. Startup creates any missing validated
collections/indexes and checks existing indexes without clearing data. It never
runs `collMod` on existing validators. Existing validator migrations belong to
the explicit `npm run db:init` maintenance command, using a separate migration
account with database-scoped `collMod` plus `readWrite`, or database-scoped
`dbAdmin` plus `readWrite`. Do not give the permanent Render service those
migration credentials. No privileged migration is included in the Build
Command or a pre-deploy hook.

A connection/ping does not prove write privileges or exercise transaction
workflows. Verify the deployed app against the existing database after the
service is reachable, without resetting it or replacing existing records.

## Deployment verification

1. Save the Render environment variables and Atlas network entries, then deploy.
2. Check Render logs for the safe listener/startup messages. A startup failure
   is reported by error category; secrets and connection-string diagnostics are
   deliberately excluded.
3. Copy the **actual HTTPS service URL** from Render. Open its `/health` path
   and require HTTP 200 with `{"status":"ok"}`. Do not substitute the
   illustrative URL from the specification.
4. Build the Android APK with that real URL in `LEVEL_UP_API_BASE_URL`, using
   the project's production build procedure. The existing Flutter client adds
   `/api/v1` paths, so the base URL is the HTTPS origin without `/api/v1`.
5. On the phone, register/sign in and sync a small routine/package. Require a
   server acknowledgment before calling it synchronized. Verify the records
   under the matching account in Atlas.
6. Confirm account isolation, queued offline changes and duplicate-event
   protection. Only after confirmed synchronization, verify recovery using the
   same account on a fresh installation or separate test device. Unsynchronized
   local-only records are not protected by cloud storage.

The final APK's real production URL cannot be prepared until the Render URL is
known. No production address, signing key or app version was invented or changed
by this backend preparation.

## References

- [Render Web Services: host/port and HTTPS proxy](https://render.com/docs/web-services)
- [Render health checks](https://render.com/docs/health-checks)
- [Render Node version selection](https://render.com/docs/node-version)
- [Render outbound IP ranges](https://render.com/docs/outbound-ip-addresses)
- [Render Free instance limits](https://render.com/docs/free)
- [Render Blueprint configuration](https://render.com/docs/blueprint-spec)
- [MongoDB Atlas integration with Render](https://www.mongodb.com/docs/atlas/reference/partner-integrations/render/)
- [MongoDB database roles](https://www.mongodb.com/docs/manual/reference/built-in-roles/)
