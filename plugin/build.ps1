# Builds and tests the plugin core on Windows. Usage (from the repo root):
#   plugin\build.ps1 [-NoTest]
#
# Uses Ninja inside the MSVC environment (vcvars64.bat).
param([switch]$NoTest)
$ErrorActionPreference = 'Stop'
# vcvars64.bat needs vswhere.exe on PATH; without it the MSVC environment is not set up and CMake picks another compiler (for example the gcc that ships with Strawberry Perl).
. "$PSScriptRoot\find_vcvars.ps1"
$test = if ($NoTest) { '' } else { '&& ctest --test-dir plugin/build --output-on-failure' }
cmd /c "set `"PATH=C:\Program Files (x86)\Microsoft Visual Studio\Installer;%PATH%`" && `"$vc`" >nul && cmake -S plugin -B plugin/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -DBUILD_TESTS=ON && cmake --build plugin/build $test"
if ($LASTEXITCODE -ne 0) { throw 'build or tests failed' }
