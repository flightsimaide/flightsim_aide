# Builds FlightSimAide-MSFS-Setup.exe: the Setup program with the companion and the checklists
# of Documentation\Examples\msfs\*_clist.txt embedded in it.
# Usage (from the repo root):  tools\platform\win\msfs_setup\build_setup.ps1 [-Sdk <folder>]
# The MSFS SDK is needed to build the companion (see plugin\build_msfs.ps1); it is not in the repo.
# Output: tools\platform\win\msfs_setup\out\FlightSimAide-MSFS-Setup.exe
param([string]$Sdk = $env:MSFS2024_SDK)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\..\..\.."
. "$root\plugin\find_vcvars.ps1"
& "$root\plugin\build_msfs.ps1" -Sdk $Sdk | Out-Null
$companion = "$root\plugin\build-msfs\flightsim_aide_msfs.exe"
$work = "$PSScriptRoot\work"
$outDir = "$PSScriptRoot\out"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force $work, $outDir | Out-Null

function Invoke-Vc([string]$line) {
  cmd /c "`"$vc`" >nul 2>&1 && $line"
  if ($LASTEXITCODE -ne 0) { throw "failed: $line" }
}

# The payload: what Setup writes into the package (path relative to it; keep = leave an existing file alone).
$payload = @(@{ file = $companion; path = 'companion\flightsim_aide_msfs.exe'; keep = $false })
Get-ChildItem "$root\Documentation\Examples\msfs" -Filter '*_clist.txt' -ErrorAction SilentlyContinue | ForEach-Object {
  $payload += @{ file = $_.FullName; path = "checklists\$($_.Name)"; keep = $true }
}
$rc = New-Object System.Text.StringBuilder
$h = New-Object System.Text.StringBuilder
[void]$h.AppendLine('#pragma once')
[void]$h.AppendLine('struct Payload { const wchar_t* res; const wchar_t* path; bool keepIfExists; };')
[void]$h.AppendLine('static const Payload kPayload[] = {')
for ($i = 0; $i -lt $payload.Count; $i++) {
  $p = $payload[$i]
  [void]$rc.AppendLine(('P{0} RCDATA "{1}"' -f $i, ($p.file.Replace([string][char]92, '/'))))
  [void]$h.AppendLine(('  {{ L"P{0}", L"{1}", {2} }},' -f $i, ($p.path.Replace([string][char]92, ([string][char]92 + [char]92))), $p.keep.ToString().ToLower()))
}
[void]$h.AppendLine('};')
Set-Content "$work\payload.rc" $rc.ToString() -Encoding ASCII
Set-Content "$work\payload.h" $h.ToString() -Encoding ASCII
Invoke-Vc "rc /nologo /fo `"$work\payload.res`" `"$work\payload.rc`""

$setup = "$outDir\FlightSimAide-MSFS-Setup.exe"
Invoke-Vc "cl /nologo /EHsc /MT /W3 /I`"$work`" `"$PSScriptRoot\setup.cpp`" /Fe:`"$setup`" /Fo:`"$work\setup.obj`" /link /SUBSYSTEM:WINDOWS `"$work\payload.res`" user32.lib gdi32.lib shell32.lib advapi32.lib ole32.lib oleaut32.lib"
Get-Item $setup | Select-Object FullName, Length
