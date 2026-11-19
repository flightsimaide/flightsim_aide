# FlightSim Aide

Checklists and live aircraft data for flight simulators.

> **For flight simulation only.** FlightSim Aide needs a running simulator to work. Never use it for a real aircraft or for real-world navigation. It is not affiliated with any simulator or aircraft maker.

**Status: early release.** The app shows an aircraft's checklists, finds the simulator on the local network through a companion, and can check items from live simulator values. It works with X-Plane 12 (a plugin) and Microsoft Flight Simulator 2020 and 2024 (a companion program, tested so far only on 2024 with the Steam version). Windows is the main development platform, Android is set up, and iOS and macOS builds are still to be done on a Mac.

## Microsoft Flight Simulator

The companion is a small Windows program that the simulator starts with itself. The app finds it on the network by itself, as it finds X-Plane.

1. Run `FlightSimAide-MSFS-Setup.exe`, tick your simulator and press Install. It copies the companion into the simulator's `Community` folder and adds one marked block to the simulator's `EXE.xml` (a backup of the original is kept). Remove undoes both.
2. Start the simulator. The companion starts with it, about a minute and a half after the main menu appears. If Windows Firewall asks, allow it on **private networks**.
3. Open the app on a device on the same network.

Notes:
- **Windows SmartScreen** may warn that the setup program is from an unknown publisher, because it is not signed. Choose More info, then Run anyway. The source is in this repository (`tools/platform/win/msfs_setup/` and `plugin/src/msfs/`) and you can build it yourself.
- Checklists go in the package's `checklists` folder, one file per aircraft, named `<aircraft>_clist.txt` (the PC-12 is `PC12_clist.txt`). Variable names are written as the simulator writes them, in quotes (`"L:NAME"`, `"A:NAME, bool"`); see [GRAMMAR.md](Documentation/Reference/GRAMMAR.md).
- Known limits: the main menu is not told apart from a pause (the app keeps showing the last aircraft); the Microsoft Store versions and MSFS 2020 are not tested yet.
- The companion contains Microsoft's SimConnect library. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## What is in this repository

| Folder | Contents |
|---|---|
| `lib/` | The Flutter app (layer-first: `domain/`, `data/`, `ui/`, `config/`) |
| `plugin/` | The companion X-Plane plugin and the Microsoft Flight Simulator companion (C++, CivetWeb) and the wire protocol, [PROTOCOL.md](plugin/PROTOCOL.md) |
| `Documentation/` | Architecture, plan, decisions, the checklist file grammar, test records and publishing notes |
| `test/`, `testing/` | Tests, and the shared fakes and fixtures |
| `tools/` | Scripts: the `verify.sh` gate, checks and helpers |
| `external/` | Downloads that must not be redistributed (the X-Plane SDK); see [BUILDING.md](BUILDING.md) |

Start with [Documentation/Architecture/ARCHITECTURE.md](Documentation/Architecture/ARCHITECTURE.md). To contribute, read [CONTRIBUTING.md](CONTRIBUTING.md); to report a security problem, [SECURITY.md](SECURITY.md).

## Identity

| | |
|---|---|
| Display name | FlightSim Aide |
| Dart package | `flightsim_aide` |
| Android application ID, iOS and macOS bundle ID | `com.flightsimaide.app` (permanent once published) |
| Version | `0.1.0+1` (`pubspec.yaml`) |
| Domain | `flightsimaide.com` |
| GitHub organisation | [github.com/flightsimaide](https://github.com/flightsimaide) |

## Build

```
flutter pub get
flutter analyze
flutter test
flutter run -d <device>
```

Full build instructions, including the files that go in `external/` (the X-Plane SDK) and the plugin: [BUILDING.md](BUILDING.md).

Release builds and what each store needs: [Documentation/PUBLISHING.md](Documentation/PUBLISHING.md). How the project got its name and what has been done towards the first release: [Documentation/RELEASE_HISTORY.md](Documentation/RELEASE_HISTORY.md).

## Icon

The icon is the "Flight Director" mark (navy `#0E2338`, magenta `#E845B8`, white `#F4F8FB`). Sources are in `assets/branding/svg/`; the PNGs next to them are rendered from those SVGs. To change the icon, replace `assets/branding/icon.png` (1024 x 1024, no transparency) and `assets/branding/icon_foreground.png` (1024 x 1024, transparent, mark inside the central 60 percent), then run:

```
dart run flutter_launcher_icons
```

## Licence

MIT, copyright (c) 2026 Ed Swafford, for the code and for the documentation and checklists too: see [LICENSE](LICENSE). Third-party notices, including the acknowledgement of XChecklist (whose checklist format this app reads), are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
