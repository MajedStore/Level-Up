# Android production API configuration

Level Up already reads `LEVEL_UP_API_BASE_URL` through
`String.fromEnvironment` in
[`CloudHttpApi`](../lib/services/cloud_api.dart). This public URL is embedded at
build time; the phone has no server-address setting. The client appends
`/api/v1/...` for authentication and synchronization. Supply the HTTPS origin,
without an `/api/v1` suffix.

No production Render URL is known or supplied in this repository. A build made
without the define remains explicitly **Cloud sync is not configured for this
build**. An old APK does not acquire a newly deployed address automatically;
build and install a new APK after the actual service URL is available.

Only the public API origin belongs in Flutter or the repository variable. Keep
`MONGODB_URI`, database passwords and `JWT_SECRET` in the server environment.
Never pass those secrets as Flutter defines, workflow inputs or command-line
arguments. Existing authentication, account isolation, confirmed acknowledgements
and durable offline drafts continue to use the current cloud implementation.

## Verified configuration and signing

| Item | Current repository behavior |
| --- | --- |
| Version | `3.0.0+22`, read from `pubspec.yaml` |
| Android application ID | `com.streak.app` |
| Minimum/target SDK | 28 / 36 |
| Java | Build using JDK 17; existing Gradle fix retains the secure-storage plugin's Java 17 target |
| Release API transport | HTTPS; debug-only opt-in supports local HTTP |
| Release signing | Uses existing `android/key.properties` if present; Gradle otherwise retains its debug-key fallback |
| Local release signing file | Not present during inspection; only existence was checked, no signing values were read |

No keystore, application ID, version, signing fallback or installed app data was
changed for deployment preparation. Before a distributable production build,
configure the existing release keystore and its matching signing properties.
Use the same signing identity needed to update the currently installed app. A
different signer cannot update it in place. Keep private keystores and passwords
out of Git.

The build helper requires an existing `android/key.properties` by default and
does not generate a key. `-AllowDebugSigning` is an explicit diagnostic override
that preserves the existing Gradle fallback; it does not create a suitable
production signing identity.

## Build after the real Render URL is available

In PowerShell, assign the actual URL copied from the deployed Render Web Service:

```powershell
$RenderUrl = Read-Host 'Paste the actual deployed HTTPS API origin'
node scripts/validate_api_origin.mjs $RenderUrl --health
```

The validator accepts only an explicit public HTTPS origin. It rejects local
addresses, credentials, paths, query strings, nonstandard ports and known
example/placeholder hostnames. It prints only the normalized public origin.
`--health` sends an unauthenticated `GET /health`, requires HTTP 200 and
`{"status":"ok"}`, uses a 20-second timeout and refuses redirects. It does not
create an account or send database credentials. A failed check stops the helper.

Once release signing exists, use:

```powershell
.\scripts\Build-LevelUpAndroid.ps1 -ApiBaseUrl $RenderUrl -CheckHealth
```

If Flutter is not on `PATH`, pass its existing executable explicitly:

```powershell
.\scripts\Build-LevelUpAndroid.ps1 -ApiBaseUrl $RenderUrl -CheckHealth `
  -FlutterPath "$HOME\develop\flutter\bin\flutter.bat"
```

To validate configuration without resolving packages or building an APK:

```powershell
.\scripts\Build-LevelUpAndroid.ps1 -ApiBaseUrl $RenderUrl -PreflightOnly
```

The helper sets `FLUTTER_WINDOWS=false` and `FLUTTER_LINUX=false` only in its
current process and restores their previous values when finished. It requires
`flutter pub get` to succeed before building, so Flutter generates the current
Android plugin registrant, including secure storage. Do not proceed using an
old generated registrant after a failed dependency setup. The helper does not
edit generated plugin registration or change Windows Developer Mode.

The underlying verified command sequence is:

```powershell
$env:FLUTTER_WINDOWS = 'false'
$env:FLUTTER_LINUX = 'false'
flutter pub get
# Continue only when pub get exits successfully.
flutter build apk --release --no-pub "--dart-define=LEVEL_UP_API_BASE_URL=$RenderUrl"
```

The universal APK is written to
`build/app/outputs/flutter-apk/app-release.apk`. The helper prints its SHA-256
after a successful build. Version name/code come from `pubspec.yaml`; no version
override is added. The supplied origin is already inside the APK, so users sign
in directly without entering a URL on their phones.

## GitHub Actions

The Android workflow accepts the public URL through the repository variable
`LEVEL_UP_API_BASE_URL` or the manual workflow's `api_base_url` input. Use the
actual deployed origin. These public settings contain no MongoDB or JWT secret.

Production release jobs validate the origin before creating a cloud release
artifact and pass it as the same Dart define. Missing/invalid configuration must
fail explicitly. Repository signing secrets remain the existing keystore,
keystore password, key password and alias. No default example URL is supplied.
See [the workflow](../.github/workflows/build-apk.yml) for the final job details.

## Local development remains separate

Keep the existing backend running locally for development. Android emulator
`localhost` refers to the emulator; `10.0.2.2` reaches the development computer:

```powershell
flutter run `
  --dart-define=LEVEL_UP_API_BASE_URL=http://10.0.2.2:3000 `
  --dart-define=LEVEL_UP_ALLOW_INSECURE_API=true
```

For a physical development device, use a reachable development computer address
in a debug build. This local HTTP opt-in and debug manifest are preserved; they
are not a production configuration. The production helper deliberately rejects
these addresses.

## Verification and remaining live checks

The new validator tests use synthetic inputs and mocked health responses; helper
tests run preflight only. No new production-connected APK was built because the
real service URL is not available. These tests do not establish that a Render
service or Atlas connection is live.

Preparation verification: **7 validator/Windows preflight tests passed** and
**21 existing cloud API/controller regression tests passed**. The Windows
preflight checks confirm the existing APK's modification time does not change,
missing release signing fails before Flutter runs, and local API addresses are
rejected by the production helper.

After deployment, confirm `/health` readiness, register/sign in, synchronize a
routine and package, and confirm acknowledged changes survive a fresh local
installation when signing back into the same account. Test offline changes and
retries too. Clearing local app data cannot recover changes that were never
acknowledged by the server. Existing local Mongo integration results and cloud
limitations are recorded in [the cloud report](LEVEL_UP_CLOUD.md).

Preparation checks:

```powershell
node --test scripts/validate_api_origin.test.mjs scripts/build_android_preflight.test.mjs
flutter test --no-pub test/cloud_api_test.dart test/cloud_sync_controller_test.dart
```

End-to-end Render → Atlas → Android verification, production signing
configuration, the final URL-bearing release build and installation remain
pending until their real configuration is supplied. Any separate direct Atlas
connection check is recorded in [the backend deployment record](../backend/RENDER.md).
