# Compiles the X-Plane shell (plugin/src/xplane) on Windows. Does not install it.
#   plugin\build_shell.ps1 [-Sdk <path to the X-Plane SDK>]  (default: the XPLANE_SDK environment variable, else external/XPSDK430/SDK)
param([string]$Sdk = $env:XPLANE_SDK)
$ErrorActionPreference = 'Stop'
if (-not $Sdk) { $Sdk = "external/XPSDK430/SDK" }
if (-not (Test-Path "$Sdk/CHeaders/XPLM/XPLMDefs.h")) { throw "X-Plane SDK not found at $Sdk. Put it in external/ (see BUILDING.md) or pass -Sdk <path>." }
# vcvars64.bat needs vswhere.exe on PATH; without it the MSVC environment is not set up and CMake picks another compiler (for example the gcc that ships with Strawberry Perl).
. "$PSScriptRoot\find_vcvars.ps1"
cmd /c "set `"PATH=C:\Program Files (x86)\Microsoft Visual Studio\Installer;%PATH%`" && `"$vc`" >nul && cmake -S plugin -B plugin/build-xp -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -DBUILD_TESTS=OFF -DXPLANE_SDK=$Sdk && cmake --build plugin/build-xp --target flightsim_aide"
if ($LASTEXITCODE -ne 0) { throw 'shell build failed' }
