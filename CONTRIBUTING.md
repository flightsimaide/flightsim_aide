# Contributing to FlightSim Aide

Thank you for helping. FlightSim Aide is for flight simulation only: it is never to be used for a real aircraft or for real-world navigation, and contributions must not suggest otherwise.

## Before you start

- Read [`Documentation/Architecture/ARCHITECTURE.md`](Documentation/Architecture/ARCHITECTURE.md). It is the source of truth for the layers (`domain/`, `data/`, `ui/`, `config/`) and for where new code goes (section 11).
- [`Documentation/Plan/PLAN.md`](Documentation/Plan/PLAN.md) holds the design and the acceptance criteria; [`Documentation/Architecture/DECISIONS.md`](Documentation/Architecture/DECISIONS.md) records why things are the way they are. [`Documentation/TODO.md`](Documentation/TODO.md) lists known gaps.
- For anything larger than a small fix, open an issue first so the approach can be agreed before you write code.

## Build and check

Build instructions, including the X-Plane SDK for the plugin, are in [`BUILDING.md`](BUILDING.md). In short:

```
flutter pub get
dart format .
flutter analyze
tools/verify.sh        # folder layout, layer rules, fixtures, acceptance tags, format, analyze, tests
```

`tools/verify.sh` must pass before you open a pull request. Changes to the plugin (`plugin/`) also need `plugin\build.ps1` (Windows) or the CMake and `ctest` steps in `BUILDING.md`, and a raised `pluginVersion()` (see `CLAUDE.md`, "Essential commands").

The checks against a running X-Plane (the live contract, the manual tests) are optional and are not part of `verify.sh`. What they need, including how to build the test aircraft, is in [`BUILDING.md`](BUILDING.md), "Tests, and what each one needs". Tests that need an add-on aircraft or a device you do not own can be skipped.

## Code rules

- `domain/` is pure Dart plus `equatable`. The UI talks only to repositories and use cases. Repositories return `Result<T>` and never throw to the UI.
- State management is Cubit / Bloc. Dependency injection is wired from `config/` only. No service locator.
- Every Cubit, Bloc and repository mapping needs unit tests (`mocktail`, `bloc_test`). `test/` mirrors `lib/`; shared fakes and fixtures live in `testing/`.
- Colours and text styles come from the theme. Status colours (red, amber, green) carry meaning and always come with an icon. Details are in `CLAUDE.md`.
- A new acceptance criterion in `PLAN.md` section 16 is tagged `[A]` (automated test with a `// AC-n` comment), `[SIM]` (an entry in `Documentation/Testing/MANUAL_TEST.md`) or both.

## Checklist files

If you add or change an example checklist, follow the rules in `CLAUDE.md` ("Writing or changing a checklist file") and the format in [`Documentation/Reference/GRAMMAR.md`](Documentation/Reference/GRAMMAR.md), and check that it parses with no new warnings.

Do **not** contribute checklist text copied from payware or other copyrighted aircraft documentation, or files from the real XChecklist plugin. Write your own, or use public-domain or properly licensed material and say where it came from.

## Commits and pull requests

- Commit subject: `<area>: <summary>` in the imperative, up to about 72 characters (`plugin: reject paths in requests`, `docs: fix the port range`). The body says why the change was made.
- Keep a pull request to one subject. Say what you tested and, for anything that needs X-Plane or a device, what you ran it on.
- Never commit personal paths, LAN addresses, email addresses, keystores or signing keys.

## Licence

By contributing you agree that your contribution is licensed under the [MIT licence](LICENSE) of this project. Third-party code and its licences are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md); do not add code you do not have the right to relicense.

## Security

Do not report a vulnerability in a public issue. See [`SECURITY.md`](SECURITY.md).
