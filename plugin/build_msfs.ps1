# Builds the Microsoft Flight Simulator companion (plugin\build-msfs\flightsim_aide_msfs.exe).
# Usage (from the repo root):  plugin\build_msfs.ps1 [-Sdk <folder>]
#
# <folder> is the MSFS SDK folder, the one that holds "SimConnect SDK"; by default the
# MSFS2024_SDK environment variable. The SDK is not part of this repository.
param([string]$Sdk = $env:MSFS2024_SDK)
$ErrorActionPreference = 'Stop'
if (-not $Sdk) { throw "Pass -Sdk <folder> or set MSFS2024_SDK to the folder that holds 'SimConnect SDK'." }
. "$PSScriptRoot\find_vcvars.ps1"
$line = "set `"PATH=C:\Program Files (x86)\Microsoft Visual Studio\Installer;%PATH%`" && `"$vc`" >nul && " +
  "cmake -S plugin -B plugin/build-msfs -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -DBUILD_TESTS=OFF `"-DMSFS_SDK=$Sdk`" && " +
  "cmake --build plugin/build-msfs --target flightsim_aide_msfs"
cmd /c $line
if ($LASTEXITCODE -ne 0) { throw 'build failed' }
Get-Item "$PSScriptRoot\build-msfs\flightsim_aide_msfs.exe" | Select-Object FullName, Length
