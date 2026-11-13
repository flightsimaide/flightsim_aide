# Building FlightSim Aide

FlightSim Aide has two parts: the **app** (Flutter, `lib/`) and the **X-Plane plugin** (C++, `plugin/`). The app is built with Flutter alone. The plugin needs a C++ compiler and the X-Plane SDK.

## The `external/` folder

`external/` is where files go that this project needs but must not redistribute. It is in the repository as an empty folder (only `external/.gitkeep` is tracked), and git ignores everything else in it. Nothing you put there can be committed by accident.

| File | Used for | Where it goes | Where to get it |
|---|---|---|---|
| X-Plane SDK 4.3.0 | Building the X-Plane shell of the plugin (`plugin/src/xplane`) | Unzip so that the folder `external/XPSDK430/SDK` exists and contains `CHeaders/XPLM/XPLMDefs.h` | `https://developer.x-plane.com/wp-content/plugins/code-sample-generation/sdk_zip_files/XPSDK430.zip` (Laminar Research, <https://developer.x-plane.com/sdk/plugin-sdk-downloads/>) |

Check the unzip: `external/XPSDK430/SDK/CHeaders/XPLM/XPLMDefs.h` must exist. On Windows, unzipping can print symlink errors for the macOS part of the archive. They are harmless for a Windows build.

You do not need the SDK for the app, for the plugin core, or for the plugin's unit tests. CivetWeb and doctest are already in `plugin/third_party/` with their licences.

If the SDK lives somewhere else on your machine, give its path with `-Sdk <path>` (or the `XPLANE_SDK` environment variable) instead of copying it.

## Tools you need

| Tool | For | Notes |
|---|---|---|
| Flutter 3.47.7 (Dart 3.13.5) | The app | `flutter doctor` should be clean for the platforms you build |
| Android SDK (platform 36) and a JDK | Android build | Installed by Android Studio |
| Visual Studio with the C++ desktop workload, CMake, Ninja | Plugin on Windows | The scripts find it with `vswhere` (`plugin/find_vcvars.ps1`); needs the "Desktop development with C++" workload. To use another install, set `VCVARS64` to the full path of its `vcvars64.bat` |
| Apple clang and CMake | Plugin on macOS, and the iOS/macOS app | Not covered by the Windows steps below |
| GCC and CMake | Plugin on Linux | |

## The app

```
flutter pub get
flutter analyze
flutter test
flutter run                       # pick a device
```

Release builds:

```
flutter build appbundle --release   # Android, for Google Play
flutter build apk --release         # Android, for installing directly
flutter build windows --release
```

Without `android/key.properties` a release build still works but is signed with the debug key, which Google Play rejects. Creating the upload key is described in `Documentation/PUBLISHING.md` and `android/key.properties.example`. The keystore and its passwords are never committed.

iOS and macOS builds need a Mac with Xcode; see `Documentation/PUBLISHING.md`.

## The plugin

Core library and its tests (no SDK needed), from the repository root on Windows:

```
plugin\build.ps1            # builds and runs ctest
plugin\build.ps1 -NoTest
```

The X-Plane shell (needs the SDK in `external/`):

```
plugin\build_shell.ps1                         # uses external/XPSDK430/SDK
plugin\build_shell.ps1 -Sdk C:/path/to/SDK     # or any other location
```

The result is `plugin/build-xp/flightsim_aide.xpl`. Install it by copying it to `X-Plane 12/Resources/plugins/flightsim_aide/64/win.xpl` (see `plugin/README.md` for the macOS and Linux names and the two folder layouts). Start X-Plane and check Plugins > Plugin Admin for "FlightSim Aide".

macOS and Linux build commands are in `plugin/README.md`.

## Checking everything

```
flutter analyze
flutter test
plugin\build.ps1
```

Build output (`build/`, `plugin/build/`, `plugin/build-xp/`) is ignored by git.

## Tests, and what each one needs

**Required, no simulator:** `tools/verify.sh` (structure, layers, fixtures, acceptance tags, format, analyze and the whole Dart test suite) and `plugin\build.ps1` (the plugin core and its `ctest` suites). They use the files in `testing/` and need nothing installed beyond the tools above. These are what a pull request must pass.

**Optional, needs X-Plane 12:** the live checks run the real plugin inside the sim. They are not part of `verify.sh`; a missing sim or aircraft never fails a pull request, but run them when you change `plugin/` or the protocol. They need:

1. X-Plane 12 with the plugin installed (see "The plugin" above) and its web API reachable on port 8086 (check with `curl -g "http://127.0.0.1:8086/api/v2/datarefs?filter[name]=sim/cockpit/misc/barometer_setting"`, which should return JSON). The scripts use it to set and read datarefs.
2. A **test aircraft**: copy the stock `Aircraft/Laminar Research/Cessna 172SP` folder to `Aircraft/XChecklist Test/C172 With Checklist`, then copy `testing/fixtures/protocol/checklist_sample.txt` into it, beside `Cessna_172SP.acf`, renamed to `Cessna_172SP_clist.txt`. (The file in the repo and the one in the sim must be byte-identical: the contract compares the checklist text.) For the no-checklist cases make a second copy, `C172 No Checklist`, with no checklist file.
3. The test aircraft loaded in the sim and parked on a runway.

Then, with the plugin answering on port 18086 (`curl http://127.0.0.1:18086/v1/hello`):

```
dart run tools/protocol_contract.dart http://127.0.0.1:18086 --live
```

With the test aircraft loaded the last line should read `54 passed, 0 failed` (the count grows with new cases). With any other aircraft loaded (stock, or an add-on such as the Thranda PC-12) the 10 cases that compare the aircraft and the checklist text with the fixtures print `SKIP` and are counted apart: `44 passed, 0 failed, 10 skipped`. That run is still a valid check of the plugin, only a smaller one. For a full check pass `--require-fixture-aircraft`, which fails those cases instead of skipping them. Before the stream cases it sets a few datarefs through the web API (`tools/live_setup.dart`: the barometer setting, `ignition_key[0]` and `throttle_ratio[0..3]`) and puts the old values back afterwards. `--no-setup` skips that, `--sim-api <url>` points it at another address. For the no-checklist cases load `C172 No Checklist` and add `--scenario no_checklist`.

The step-by-step manual tests (phone and tablet runs, edits to a checklist while the sim runs, add-on aircraft such as the Thranda PC-12) are in `Documentation/Testing/MANUAL_TEST.md`, each with the setup it needs. Anything that needs an add-on aircraft or a device you do not own is optional: record it as "not run".
