# Level Up deployment handoff — GitHub, Render, Atlas and Android

The existing project is prepared locally for deployment. No GitHub repository,
Render service, production API address or release signing identity was invented.
Version `3.0.0+22`, Android ID `com.streak.app`, XP rules, user data and the
existing Gradle signing configuration remain unchanged.

## Current production diagnosis

The actual public API origin is `https://level-up-5nmw.onrender.com`. Its
`/health` endpoint returns `{"status":"ok"}`, proving Render can reach Atlas.
On 30 October 2026, a safe unauthenticated request to `/api/v1/state` returned
`426 https_required` instead of the expected `401 unauthorized`. Registration,
sign-in and synchronization therefore fail at the same HTTPS proxy check before
they reach authentication or MongoDB. Set `TRUST_PROXY_HOPS=1` on the existing
Render service, deploy the current backend source, and require the documented
`401` verification before distributing another APK. See
[authentication configuration](AUTH_CONFIGURATION.md).

## Earlier deployment-preparation snapshot

| Item | Verified status |
| --- | --- |
| Git | Branch `main`; initial working tree clean; `origin` still `https://github.com/InlitX/streak.git` |
| Reported GitHub 403 | Not resolved by local changes; no push or remote change attempted |
| Secrets | Real `backend/.env` ignored/untracked; current files, index and all reachable history scanned with zero findings |
| MongoDB Atlas | Actual local driver connection and read-only database ping succeeded; no initialization or user-data writes performed |
| Render | Backend/Blueprint prepared and tested locally; no service deployed or live Render URL supplied |
| Android | Build-time API define and guarded build/CI prepared; no new APK built with a guessed URL |
| Release signing | `android/key.properties` absent; configure the intended existing signing identity before a production build |

The local Atlas check does not verify Render's network access, transaction/write
privileges, account flow or phone recovery against that deployment. Those checks
remain after the actual service exists. Earlier real local MongoDB recovery tests
remain documented in [the cloud report](LEVEL_UP_CLOUD.md).

## GitHub: your next action

Create an **empty** repository under `MajedStore`, for example `level-up`, without
adding README/license/gitignore files. After it actually exists, run these from
the current project folder (substitute the chosen real repository name):

```powershell
git remote -v
git remote rename origin upstream
git remote add origin https://github.com/MajedStore/level-up.git
node scripts/check-upload-safety.mjs
git add -- .gitignore .github/workflows backend docs render.yaml scripts README.md
git diff --cached --name-only
node scripts/check-upload-safety.mjs
git commit -m "Prepare Level Up deployment"
git remote get-url origin
git push -u origin main
```

Inspect an existing `upstream` name before renaming; do not overwrite it. The
push URL must be your confirmed repository. The audit must exit zero with PASS
before commit/push. Private files stay on disk and out of Git. No force push,
history rewrite or permission bypass is required. Preserve the existing GPL
license and attribution. See [the full GitHub guide](DEPLOYMENT_GITHUB.md).

## Render: create the backend service

Choose **New + → Web Service → Connect GitHub repository**, then your own
uploaded repository. Use:

| Setting | Exact value |
| --- | --- |
| Runtime | Node |
| Branch | `main` |
| Root Directory | `backend` |
| Build Command | `npm ci --omit=dev` |
| Start Command | `npm start` |
| Health Check Path | `/health` |

In Render's Environment page, set:

| Variable | Value |
| --- | --- |
| `MONGODB_URI` | Copy your existing private local value directly into Render |
| `MONGODB_DATABASE` | `level_up` |
| `JWT_SECRET` | Copy your existing private local value directly into Render |
| `NODE_ENV` | `production` |
| `HOST` | `0.0.0.0` |
| `TRUST_PROXY_HOPS` | `1` for Render's direct proxy path |
| `NODE_VERSION` | `24.15.0` |

Leave `PORT` managed by Render. Existing optional auth defaults remain unchanged:
issuer `level-up-api`, audience `level-up-android`, access expiry 900 seconds,
refresh expiry 30 days. Native Android requires no browser CORS origin.

The root [render.yaml](../render.yaml) is an optional equivalent Blueprint with
secret prompts, not embedded credentials. It selects Free explicitly for review;
Free instances idle, so choose a non-idling service plan for continuous
availability. Creating a paid resource is your dashboard decision. See
[the complete Render guide](../backend/RENDER.md), including proxy/health behavior.

## Atlas: authorize Render's network

Keep the existing `level_up` database. In the Render service's **Connect →
Outbound** tab, copy its current outbound CIDR ranges into Atlas **Network
Access → IP Access List**. Use those specific ranges or dedicated outbound IPs;
do not open `0.0.0.0/0` permanently. The runtime user needs `readWrite` scoped to
`level_up`. Validator migrations use a separate privileged maintenance identity;
they are not part of Render's build command.

Deploy, copy the **actual HTTPS origin** from Render, then verify `/health`
returns HTTP 200 and `{"status":"ok"}`. The backend honors Render's port,
binds publicly in production and performs a bounded database readiness check.
Health probes do not weaken authentication/HTTPS enforcement for private APIs.

## Android: embed the real origin

The phone obtains its public API origin from the compile-time
`LEVEL_UP_API_BASE_URL` define. It does not need your computer or a manually
entered phone setting. It receives neither MongoDB credentials nor the JWT
signing secret. An old APK must be rebuilt to contain the new origin.

After Render is live and release signing is configured:

```powershell
$RenderUrl = Read-Host 'Paste the actual deployed HTTPS API origin'
.\scripts\Build-LevelUpAndroid.ps1 -ApiBaseUrl $RenderUrl -CheckHealth
```

The helper validates the real public HTTPS origin, checks readiness, requires
existing signing, runs a successful `flutter pub get` and builds the APK. It
uses process-only Windows desktop flags to avoid stale plugin registration.
The equivalent core Flutter command is:

```powershell
flutter build apk --release --dart-define=LEVEL_UP_API_BASE_URL="$RenderUrl"
```

Artifact: `build/app/outputs/flutter-apk/app-release.apk`. It will automatically
use the supplied deployed URL after installation. Local development remains
available with the existing debug-only `LEVEL_UP_ALLOW_INSECURE_API=true` flag;
production transport stays HTTPS. See [Android build instructions](DEPLOYMENT_ANDROID.md)
for JDK/Flutter paths, signing and local emulator commands.

GitHub's manual **Build & Release** workflow now accepts `api_base_url`, falling
back to repository variable `LEVEL_UP_API_BASE_URL`. It checks URL/readiness,
upload safety and the existing signing secrets before producing a cloud release.
Configure `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD` and `KEY_ALIAS`
as GitHub Actions secrets for that workflow. They describe your existing key;
the workflow never generates a new one. Pull-request artifacts remain local-mode
checks and are labeled accordingly. No Actions run on GitHub is claimed here.

## Final verification

| Local check | Result |
| --- | --- |
| Flutter full suite | **722 passed, 3 skipped**, 2m 03s; `test-deployment-flutter.log` |
| Flutter analyzer | **0 errors, 0 warnings**, 8 existing deprecation infos; `analysis-deployment-flutter.log` |
| Backend full suite | **38 passed**, temporary real MongoDB replica set; `backend/test-render-preparation.log` |
| Backend syntax / dependency audit | Passed / 0 vulnerabilities |
| Deployment helper tests | **15 passed**, including upload/history scanning, HTTPS/health validation, signing-file handling and Windows preflight |
| Production-only installation | `npm ci --omit=dev` succeeded in an isolated copy; production app/store imports passed without development dependencies |
| Workflow / Blueprint validation | All three prepared workflows passed official actionlint and YAML parsing; `render.yaml` passed Render's official JSON Schema validation |
| Actual Atlas check | Authenticated driver connect + read-only ping succeeded; no Atlas user-data writes |
| Upload safety | Zero findings across current upload candidates, index and all reachable history; local secret values compared in memory only |

The README's pre-existing mixed-encoding tail/control bytes were normalized to
UTF-8 while preserving its text. `git diff --check` passes; existing Windows
line-ending notices remain informational.

The three Flutter skips are the opt-in local Mongo end-to-end test plus the
existing optional screenshot/host-DST cases. The real-Mongo end-to-end test was
verified in the prior cloud implementation; it was not rerun against Atlas or
Render during this preparation. The deployment scripts and workflows are
repository preparation, not an executed GitHub Actions run or external deploy.
Actionlint's optional ShellCheck/Pyflakes integrations were unavailable; the
workflow syntax/expression checks ran, and helper scripts were tested directly.

## Earlier preparation handoff

1. Create/select your GitHub repository and run the audited upload commands.
2. Create the Render Web Service, choose its plan and enter private environment
   values directly in Render.
3. Add Render's outbound ranges to Atlas, deploy and confirm the real `/health`.
4. Configure the intended Android release signing key and build with the actual
   Render HTTPS origin, locally or through the prepared Actions workflow.
5. Install and verify registration, sync acknowledgements, owner isolation and
   XP/history in Atlas. Confirm offline retry and duplicate protection. Verify
   fresh-install recovery on a separate test device or after confirmed sync and
   backup; unsynchronized local changes cannot be recovered after deletion.

## Official references

- [Render Web Services](https://render.com/docs/web-services)
- [Render health checks](https://render.com/docs/health-checks)
- [Render outbound IP ranges](https://render.com/docs/outbound-ip-addresses)
- [Render Free service behavior](https://render.com/docs/free)
- [Atlas IP access lists](https://www.mongodb.com/docs/atlas/security/ip-access-list/)
- [GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
