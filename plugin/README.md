# Companion plugin

The X-Plane plugin that serves the aircraft's checklist and live values to the FlightSim Aide app over the local network. C++17, X-Plane SDK (XPLM), CivetWeb, CMake. The wire protocol is in [PROTOCOL.md](PROTOCOL.md).

## Layout

| Folder | What |
|---|---|
| `src/core` | The server, cache, stream hub and parsers. Pure C++: no XPLM, no file access (a `ctest` enforces it). |
| `src/platform` | File stat/read and the checklist change watch. No XPLM. |
| `src/xplane` | The shell: the only code that includes XPLM headers. Builds the `flightsim_aide` plugin. |
| `test`, `test_server` | `core_tests` (doctest) and `core_test_server`, the core with scripted data and no simulator. |

## Build

Needs CMake 3.20+ and a C++17 compiler. The tests need no SDK:

```
cmake -S plugin -B plugin/build -DBUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build plugin/build
ctest --test-dir plugin/build --output-on-failure
```

On Windows, `plugin\build.ps1` does this with Ninja inside the MSVC environment (`-NoTest` skips the tests). The loopback WebSocket tests take about a minute.

The X-Plane plugin additionally needs the SDK (4.3.0 is what the plugin is built with; download from https://developer.x-plane.com/sdk/plugin-sdk-downloads/ and unpack it). Point `XPLANE_SDK` at the folder that contains `CHeaders/` and `Libraries/`:

```
cmake -S plugin -B plugin/build-xp -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DXPLANE_SDK=<sdk folder>
cmake --build plugin/build-xp --target flightsim_aide
```

On Windows: `plugin\build_shell.ps1 [-Sdk <folder>]`. Only XPLM 2.00 to 3.01 is used, and the plugin is tested on X-Plane 12 only. X-Plane 11 is not supported (D-46).

| OS | Compiler | Output |
|---|---|---|
| Windows | MSVC, x64 | `flightsim_aide.xpl` |
| macOS | Apple clang, universal `x86_64;arm64` (set automatically when `XPLANE_SDK` is given) | `flightsim_aide.xpl` |
| Linux | GCC, x64 (`-fvisibility=hidden`) | `flightsim_aide.xpl` |

macOS notes: the plugin links XPLM with `-undefined dynamic_lookup`. To distribute it, sign it with a Developer ID and notarize it; X-Plane on a Mac that has not been given a signed build may refuse to load it. For local use `codesign --force --sign - flightsim_aide.xpl` is enough.

## Install

Pass `-DXPLANE_PLUGINS="<X-Plane>/Resources/plugins"` to copy the built file after the build (nothing is copied otherwise). `-DPLUGIN_LAYOUT=A|B` picks the folder layout:

- A: `plugins/flightsim_aide/64/<win|mac|lin>.xpl`. Loads on X-Plane 12 (Windows).
- B: `plugins/flightsim_aide/<win_x64|mac_x64|lin_x64>/flightsim_aide.xpl`. Loads on X-Plane 12 (Windows). Use only one of the two layouts.

Which layout loads with the real plugin is still to be confirmed in the simulator (task 4.1).

## Status

- Windows: built, unit-tested and run in X-Plane 12 (contract passes against the real plugin).
- macOS and Linux: **untested at runtime.** They are compiled and tested by CI only (task 4.13).
- CI: `.github/workflows/plugin.yml` builds and tests the plugin on Windows, macOS and Linux (see the Actions tab of the repository).

## Microsoft Flight Simulator companion

`src/msfs/` is a separate Windows program for Microsoft Flight Simulator 2020 and 2024 (design: `Documentation/Architecture/DECISIONS.md` D-86 to D-88; wire details: `PROTOCOL.md` section 11). MSFS cannot load a plugin that listens on a port, so it is an external program that the simulator starts through an `EXE.xml` entry. It reuses the same core (server, cache, stream hub) and replaces the X-Plane SDK with SimConnect.

- **Build.** It needs the MSFS SDK, which is **not** in this repository and is not redistributable here (its licence allows development of add-ons; whether a release binary may contain the SimConnect static library is still to be confirmed). Install the SDK, then run `plugin\build_msfs.ps1` (the folder comes from the `MSFS2024_SDK` environment variable, or `-Sdk <folder>`). The result is `plugin\build-msfs\flightsim_aide_msfs.exe`. The SimConnect library links the dynamic C++ runtime, so a PC needs the Visual C++ runtime. CI does not build it (no SDK); the logic that does not need SimConnect (`src/msfs_logic/`, `src/core/aircraft_key.*`, `src/core/companion_beacon.*`) is built and tested with the other core tests.
- **Install and remove.** `tools/platform/win/msfs_setup/` builds `FlightSimAide-MSFS-Setup.exe`, which puts the package `flightsimaide-checklists` into each simulator's `Community` folder and adds one marked block to its `EXE.xml`.
- **Run by hand** (for development): `flightsim_aide_msfs.exe --run --no-parent-watch --checklists <folder>`, with the simulator running. It has no window; its log is `%LOCALAPPDATA%\FlightSimAide\msfs-companion.log`. `--serve-only <seconds>` serves the hello and the beacon without the simulator.
- **Watch it.** `dart run tools/stream_watch.dart http://127.0.0.1:18086 "L:ELECTRICAL_Switch_BATTERY_Bus_1" 2` prints the values of one name.

## Network

The server binds the first free port from 18086 to 18093 and never asks the OS for another one, so the app's probe range always covers it. `/v1/hello` reports the bound port. Only private-range and loopback sources are accepted.

On Windows, the first run shows a Windows Defender Firewall prompt for X-Plane: allow **private networks**, otherwise the phone cannot connect.

## Tests and the contract script

```
ctest --test-dir plugin/build --output-on-failure           # core, isolation, shared start
core_test_server --port 18086 --bind 127.0.0.1               # core with scripted data
dart run tools/protocol_contract.dart http://127.0.0.1:18086 # same cases against any implementation
```

The contract script runs the same HTTP and stream cases against the Dart fake, `core_test_server` and the real plugin. Against the real plugin, use `--live` (see the header of `tools/protocol_contract.dart`): the aircraft path, generation and checklist time are read from the sim, and the aircraft must match the fixtures. Setting up that test aircraft (a copy of the stock Cessna 172 with `testing/fixtures/protocol/checklist_sample.txt` as its checklist) is described in `BUILDING.md`, "Tests, and what each one needs". The script sets a few datarefs through X-Plane's web API first and restores them after.

## Install and troubleshooting (for users)

1. Close X-Plane. Copy the `flightsim_aide` folder (from a release or your own build with `-DXPLANE_PLUGINS`) into `X-Plane/Resources/plugins/`, so that the file sits at `Resources/plugins/flightsim_aide/64/win.xpl` (`mac.xpl` or `lin.xpl` on macOS and Linux).
2. Start X-Plane. In **Plugins > Plugin Admin** the entry "FlightSim Aide 0.3.0" (the name followed by the plugin version) should be enabled. `Log.txt` in the X-Plane folder has a line `flightsim_aide: listening on port 18086` (or a port up to 18093).
3. Windows: when the firewall asks, allow X-Plane on **private networks**.
4. Check from the phone or another computer on the same network: `curl http://<sim-ip>:18086/v1/hello` answers with a short JSON text that names the plugin and its port. Use the port from `Log.txt` if it is not 18086.

If the app says **plugin not detected**:

- The app found X-Plane but nothing answered on ports 18086 to 18093. Check that the plugin is enabled in Plugin Admin and that `Log.txt` has the `listening` line. A line saying no port could be bound means other programs hold all eight ports.
- The curl check works on the sim PC (`http://127.0.0.1:18086/v1/hello`) but not from the phone: the firewall is blocking it, or the phone is on another network (guest Wi-Fi, VPN).
- The app shows "no checklist" for an aircraft: the plugin looks for `<aircraft>_clist.txt` or `clist.txt` next to the `.acf` file. `Log.txt` shows the path it tried when the aircraft loaded.

Not yet tested on a clean X-Plane install (task 4.14 verify).
