<#
Sets DEV and PKG for Windows desktop development and checks the toolchain.

Usage (PowerShell, from the repo root; note the leading dot, it must be dot-sourced):
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass    # only if scripts are blocked
    . .\tools\env_windows.ps1

Sets both $env:DEV / $env:PKG (visible to child processes) and $DEV / $PKG, so the
commands such as  flutter run -d $DEV  work as written.
Defines a helper:  verify [--no-test]   (runs tools/verify.sh with Git Bash)

Nothing is installed. Only "flutter config --enable-windows-desktop" is run (idempotent).
#>

$env:DEV = 'windows'
$env:PKG = 'flightsim_aide'
if (Test-Path -LiteralPath 'pubspec.yaml') {
    $m = Select-String -LiteralPath 'pubspec.yaml' -Pattern '^name:\s*(\S+)' | Select-Object -First 1
    if ($m) { $env:PKG = $m.Matches[0].Groups[1].Value }
}
$DEV = $env:DEV
$PKG = $env:PKG

$envFails = 0
function _envOk   ($t) { Write-Host "  ok    $t" -ForegroundColor Green }
function _envWarn ($t) { Write-Host "  warn  $t" -ForegroundColor Yellow }
function _envFail ($t) { Write-Host "  FAIL  $t" -ForegroundColor Red; $script:envFails++ }

Write-Host "FlightSim Aide env: DEV=$DEV PKG=$PKG"
if ($env:OS -eq 'Windows_NT') { _envOk 'running on Windows' }
else { _envFail 'this script is for Windows; use env_linux.sh or env_macos.sh' }

# --- Flutter ---
if (Get-Command flutter -ErrorAction SilentlyContinue) {
    _envOk ("flutter found: " + (Get-Command flutter).Source)
    flutter config --enable-windows-desktop *> $null
    _envOk 'windows desktop enabled'
    if ((flutter devices 2>$null | Out-String) -match 'windows-(x64|arm64)') { _envOk 'flutter lists a windows device' }
    else { _envFail 'flutter devices does not list windows (run: flutter doctor -v)' }
} else { _envFail 'flutter not on PATH' }
if (-not (Get-Command dart -ErrorAction SilentlyContinue)) { _envWarn 'dart not on PATH (it ships inside the flutter SDK)' }

# --- Visual Studio C++ workload (required to build Windows desktop apps) ---
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $vswhere) {
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($vs) { _envOk "Visual Studio C++ tools found" }
    else { _envFail "Visual Studio found but the 'Desktop development with C++' workload is missing" }
} else { _envFail 'Visual Studio not found (install it with the "Desktop development with C++" workload)' }

# --- Git and Git Bash (the tools/*.sh scripts are bash scripts) ---
if (Get-Command git -ErrorAction SilentlyContinue) { _envOk 'git found' } else { _envFail 'git not on PATH' }
$gitBashPath = @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe") |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($gitBashPath) {
    $global:GitBash = $gitBashPath
    _envOk "Git Bash found: $gitBashPath"
    foreach ($t in 'grep','awk','sed','xxd','file') {
        & $gitBashPath -lc "command -v $t" *> $null
        if ($LASTEXITCODE -ne 0) { _envWarn "$t not available in Git Bash (only needed for some research commands)" }
    }
} else { _envFail 'Git Bash not found (install Git for Windows). Do NOT use the WSL bash in System32: it cannot see Windows Flutter' }
# --- Line endings: bash scripts must be LF ---
$crlf = @(Get-ChildItem -LiteralPath 'tools' -Filter '*.sh' -ErrorAction SilentlyContinue |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match "`r" })
if ($crlf.Count -gt 0) {
    _envFail ("CRLF line endings in: " + (($crlf | ForEach-Object Name) -join ', ') + "  -> fix in Git Bash: sed -i 's/\r$//' tools/*.sh")
} else { _envOk 'tools/*.sh have LF line endings' }
if ((git config core.autocrlf 2>$null) -eq 'true') {
    $ga = ''
    if (Test-Path -LiteralPath '.gitattributes') { $ga = Get-Content -LiteralPath '.gitattributes' -Raw }
    if ($ga -match '\*\.sh\s+text\s+eol=lf') { _envOk 'core.autocrlf=true is fine: .gitattributes keeps *.sh as LF' }
    else { _envWarn 'core.autocrlf=true and .gitattributes has no "*.sh text eol=lf" rule (task 0.2). Add it, or git will convert the scripts to CRLF' }
}

# --- helper: verify ---
function global:verify {
    if (-not $global:GitBash) { Write-Host 'Git Bash not found; cannot run tools/verify.sh'; return }
    & $global:GitBash -lc ("cd '" + (Get-Location).Path.Replace('\','/') + "' && tools/verify.sh " + ($args -join ' '))
}
_envOk 'helper defined: verify [--no-test]'

if ($envFails -eq 0) { Write-Host 'ENV OK' -ForegroundColor Green } else { Write-Host "ENV INCOMPLETE: $envFails problem(s)" -ForegroundColor Red }
Remove-Item function:_envOk, function:_envWarn, function:_envFail -ErrorAction SilentlyContinue
Remove-Variable envFails, m, vswhere, vs, gitBashPath, crlf, ga -ErrorAction SilentlyContinue
