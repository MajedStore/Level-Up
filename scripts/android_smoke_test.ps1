param(
  [Parameter(Mandatory=$true)][string]$Command,
  [string]$Value,
  [string]$Device = 'emulator-5554',
  [string]$AdbPath
)
$ErrorActionPreference = 'Stop'
# UI actions are resolved from a fresh UI Automator accessibility snapshot.
# Example: ./scripts/android_smoke_test.ps1 dump -Device emulator-5554
if (!$AdbPath) {
  $sdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
  $AdbPath = Join-Path $sdkRoot 'platform-tools/adb.exe'
}
if (!(Test-Path -LiteralPath $AdbPath -PathType Leaf)) { throw 'ADB was not found. Set ANDROID_SDK_ROOT/ANDROID_HOME or pass -AdbPath.' }
$outputDir = Join-Path $PSScriptRoot '../build/verification'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$xmlPath = Join-Path $outputDir 'smoke-window.xml'
function Invoke-Adb {
  $ErrorActionPreference = 'Continue'
  $result = & $AdbPath -s $Device @args 2>&1 | ForEach-Object { $_.ToString() }
  if ($LASTEXITCODE -ne 0) { throw ($result -join "`n") }
  return $result
}
function Read-Nodes {
  $ready = $false
  for ($attempt = 0; $attempt -lt 4; $attempt++) {
    $result = Invoke-Adb shell uiautomator dump /sdcard/levelup-smoke.xml
    if ($result -match 'dumped to:') { $ready = $true; break }
  }
  if (!$ready) { throw 'UI Automator did not return a fresh accessibility snapshot.' }
  Invoke-Adb pull /sdcard/levelup-smoke.xml $xmlPath 2>$null | Out-Null
  [xml]$snapshot = Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8
  return $snapshot.SelectNodes('//node')
}
function Node-Label($node) {
  if ($node.GetAttribute('content-desc')) { return $node.GetAttribute('content-desc') }
  return $node.GetAttribute('text')
}
function Node-Bounds($node) { return @([regex]::Matches($node.GetAttribute('bounds'), '\d+') | ForEach-Object { [int]$_.Value }) }
switch ($Command) {
  'dump' { foreach ($node in (Read-Nodes)) { $label = Node-Label $node; if ($label -or $node.GetAttribute('class') -eq 'android.widget.EditText') { Write-Output ('{0} | {1} | {2} | click={3}' -f $node.GetAttribute('class'),$label.Replace("`n",' / '),$node.GetAttribute('bounds'),$node.GetAttribute('clickable')) } } }
  'tap' {
    $nodes = Read-Nodes
    $found = @($nodes | Where-Object { $label = Node-Label $_; $label -eq $Value -or ($label -split "`n")[0] -eq $Value })
    if (!$found.Count) { $found = @($nodes | Where-Object { (Node-Label $_).Contains($Value) }) }
    if (!$found.Count) { throw "No accessibility node matching '$Value'." }
    $node = $found | Sort-Object @{Expression={ $_.GetAttribute('clickable') -ne 'true' }}, @{Expression={ (Node-Bounds $_)[1] }} | Select-Object -First 1
    $b = Node-Bounds $node
    Write-Output ('TAP {0} {1}' -f (Node-Label $node),$node.GetAttribute('bounds'))
    Invoke-Adb shell input tap ([int](($b[0]+$b[2])/2)) ([int](($b[1]+$b[3])/2))
  }
  'text' { Invoke-Adb shell input text $Value.Replace(' ','%s') }
  'field' {
    $fields = @(Read-Nodes | Where-Object { $_.GetAttribute('class') -eq 'android.widget.EditText' })
    $node = $fields[[int]$Value]
    if (!$node) { throw 'The requested editable field is not visible.' }
    $b = Node-Bounds $node
    Invoke-Adb shell input tap ([int](($b[0]+$b[2])/2)) ([int](($b[1]+$b[3])/2))
  }
  'back' { Invoke-Adb shell input keyevent 4 }
  'swipe' {
    $scroll = Read-Nodes | Where-Object { $_.GetAttribute('scrollable') -eq 'true' } | Select-Object -First 1
    if (!$scroll) { throw 'No visible scroll container.' }
    $b = Node-Bounds $scroll
    $x = [int](($b[0]+$b[2])/2)
    $low = [int]($b[1]+($b[3]-$b[1])*.8)
    $high = [int]($b[1]+($b[3]-$b[1])*.25)
    if ($Value -eq 'up') { Invoke-Adb shell input swipe $x $low $x $high 400 } else { Invoke-Adb shell input swipe $x $high $x $low 400 }
  }
  'capture' { Invoke-Adb shell screencap -p /sdcard/levelup-smoke.png; Invoke-Adb pull /sdcard/levelup-smoke.png (Join-Path $outputDir "$Value.png") }
  default { throw 'Use dump, tap LABEL, text TEXT, back, swipe up/down, capture NAME.' }
}
