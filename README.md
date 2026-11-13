# FlightSim Aide

Checklists and live aircraft data for flight simulators.

> **For flight simulation only.** FlightSim Aide needs a running simulator to work. Never use it for a real aircraft or for real-world navigation. It is not affiliated with any simulator or aircraft maker.

**Status: early release (0.1.0).** The app shows an aircraft's checklists, finds X-Plane on the local network through a companion plugin, and can check items from live simulator values. It is built for X-Plane 12; Windows is the main development platform, Android is set up, and iOS and macOS builds are still to be done on a Mac.

## What is in this repository

| Folder | Contents |
|---|---|
| `lib/` | The Flutter app (layer-first: `domain/`, `data/`, `ui/`, `config/`) |
| `plugin/` | The companion X-Plane plugin (C++, CivetWeb) and the wire protocol, [PROTOCOL.md](plugin/PROTOCOL.md) |
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

MIT, copyright (c) 2026 Ed Swafford: see [LICENSE](LICENSE). Third-party notices, including the acknowledgement of XChecklist (whose checklist format this app reads), are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
