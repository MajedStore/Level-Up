#requires -Version 5.1
<#
.SYNOPSIS
Build Level Up with a supplied, verified production HTTPS API origin.
.DESCRIPTION
Requires Node.js and Flutter. Reads no backend secret file and never creates a
keystore. PreflightOnly performs validation without dependency resolution/build.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,
    [string]$GoogleServerClientId = '',
    [string]$FlutterPath = 'flutter',
    [switch]$CheckHealth,
    [switch]$PreflightOnly,
    [switch]$AllowDebugSigning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'validate_api_origin.mjs'
$node = (Get-Command node -ErrorAction Stop).Source
$arguments = @($validator, $ApiBaseUrl)
if ($CheckHealth) { $arguments += '--auth-readiness' }
$origin = & $node @arguments
if ($LASTEXITCODE -ne 0) { throw 'Production API validation failed. No APK was built.' }
$origin = ($origin | Out-String).Trim()
if (-not $origin) { throw 'Production API validation returned no origin.' }
if (-not [string]::IsNullOrWhiteSpace($GoogleServerClientId) -and
    $GoogleServerClientId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.apps\.googleusercontent\.com$') {
    throw 'GoogleServerClientId must be the Web OAuth client ID ending in .apps.googleusercontent.com. No APK was built.'
}

$signingProperties = Join-Path $workspace 'android/key.properties'
$hasReleaseSigning = Test-Path -LiteralPath $signingProperties -PathType Leaf
if (-not $hasReleaseSigning -and -not $AllowDebugSigning) {
    throw 'android/key.properties is missing. Configure the existing release signing key first. For a diagnostic build only, explicitly pass -AllowDebugSigning. No APK was built.'
}
$versionLine = Select-String -LiteralPath (Join-Path $workspace 'pubspec.yaml') -Pattern '^version:\s*(\S+)'
if (-not $versionLine) { throw 'The application version could not be read.' }
$version = $versionLine.Matches[0].Groups[1].Value
Write-Output "API origin: $origin"
if (-not [string]::IsNullOrWhiteSpace($GoogleServerClientId)) {
    Write-Output 'Google Sign-In: Web OAuth client ID supplied (value not displayed).'
} else {
    Write-Warning 'Google Sign-In is not configured for this build; its button will show a clear unavailable message.'
}
Write-Output "Version from pubspec.yaml: $version"
if ($hasReleaseSigning) {
    Write-Output 'Signing: existing android/key.properties configuration (values not displayed).'
} else {
    Write-Warning 'Diagnostic build: the existing Gradle debug-key fallback will be used. This is not a production signing key.'
}
if ($CheckHealth) { Write-Output 'Unauthenticated database and private-route HTTPS readiness checks passed.' }
if ($PreflightOnly) { Write-Output 'Preflight complete. No dependency resolution or APK build was run.'; return }

$flutter = (Get-Command $FlutterPath -ErrorAction Stop).Source
$oldWindows = $env:FLUTTER_WINDOWS
$oldLinux = $env:FLUTTER_LINUX
try {
    # Process-only Android workflow: generate the current plugin registrant
    # without requiring desktop symlinks on this Windows machine.
    $env:FLUTTER_WINDOWS = 'false'
    $env:FLUTTER_LINUX = 'false'
    Push-Location -LiteralPath $workspace
    try {
        & $flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed. Build stopped to avoid a stale plugin registrant.' }
        $dartDefines = @("--dart-define=LEVEL_UP_API_BASE_URL=$origin")
        if (-not [string]::IsNullOrWhiteSpace($GoogleServerClientId)) {
            $dartDefines += "--dart-define=LEVEL_UP_GOOGLE_SERVER_CLIENT_ID=$GoogleServerClientId"
        }
        & $flutter build apk --release --no-pub @dartDefines
        if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed.' }
    } finally {
        Pop-Location
    }
} finally {
    $env:FLUTTER_WINDOWS = $oldWindows
    $env:FLUTTER_LINUX = $oldLinux
}
$apk = Join-Path $workspace 'build/app/outputs/flutter-apk/app-release.apk'
if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw 'Build completed without the expected APK artifact.' }
Write-Output "APK: $apk"
Write-Output "SHA256: $((Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash)"
