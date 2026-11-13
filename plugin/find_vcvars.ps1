# Finds vcvars64.bat of the newest Visual Studio that has the C++ x64 tools, using vswhere
# (installed by Visual Studio at "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer").
# Dot-source it, then use $vc:   . "$PSScriptRoot\find_vcvars.ps1"
# Override with the VCVARS64 environment variable (full path to vcvars64.bat).
$vc = $env:VCVARS64
if (-not $vc) {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found. Install Visual Studio (or Build Tools) with the 'Desktop development with C++' workload, or set VCVARS64 to the full path of vcvars64.bat."
  }
  $install = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (-not $install) {
    throw "No Visual Studio with the C++ x64 tools was found. Install the 'Desktop development with C++' workload, or set VCVARS64 to the full path of vcvars64.bat."
  }
  $vc = Join-Path ($install | Select-Object -First 1) 'VC\Auxiliary\Build\vcvars64.bat'
}
if (-not (Test-Path $vc)) { throw "vcvars64.bat not found at $vc" }
