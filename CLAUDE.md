# CLAUDE.md - FlightSim Aide guidelines

## Source of truth
- `Documentation/Architecture/ARCHITECTURE.md` is authoritative for structure and layering. `Documentation/Plan/PLAN.md` fills the gaps (parser rules, wire protocol, UI details, acceptance criteria). Decisions are in `Documentation/Architecture/DECISIONS.md`; the checklist file grammar is `Documentation/Reference/GRAMMAR.md`.
- This file summarizes those for day-to-day coding. If this file and `ARCHITECTURE.md` disagree, `ARCHITECTURE.md` wins and this file should be corrected.

## Project context
- **Architecture:** layer-first and Compass-app-inspired (`domain/`, `data/`, `ui/`, `config/`). Only `ui/` is organized by feature; `domain/` and `data/` are single shared layers. There is no `lib/features/` folder.
- **State management:** BLoC / Cubit (`flutter_bloc`).
- **Dependency injection:** `RepositoryProvider` / `MultiRepositoryProvider`, wired entirely from `config/`, the composition root and the only place concrete classes are named. No service-locator package (`get_it`).
- **Network layer:** the app finds the sim from X-Plane's multicast beacon (or a manual IP), probes the companion plugin's `GET /v1/hello` on a fixed port range (18086 to 18093), and fetches the aircraft and checklist over plain HTTP (`package:http`). Live values come over the plugin's own WebSocket protocol (`/v1/stream`, JSON, `dart:io`; `plugin/PROTOCOL.md`). X-Plane's native `RREF`/`DREF` and its Web API are not used by the app; the plugin is required for live data. Test tooling (`tools/live_setup.dart`, `tools/sim_set.sh`, the `--live` contract) does use the Web API on port 8086, as an independent reader and writer of datarefs. Everything stays behind `ChecklistSourceService` and `FlightSimService`, so transport details never leak into `domain/` or `ui/`. Do not hard-code Dio or Retrofit.
- **Conditions and auto-check:** an item's or a `sw_continue` link's condition (`GRAMMAR.md` section 8) is a pure `ItemCondition` evaluated in `domain/use_cases/autocheck/`. The app subscribes only to the names of the open checklist (`DatarefWatchHub`), auto-checks one item ahead of the pilot (one way, manual wins) and offers one conditional Continue button.
- **Plugin:** C++ with CivetWeb, in `plugin/`.
- **Code generation:** none. Models and state are plain immutable classes using `equatable` (the one third-party package allowed in `domain/`). Do not add Freezed or Bloc code generation unless the design docs call for it.

## Essential commands
- Run the app: `flutter run -d <device>` (entry point `lib/main.dart`; it finds the sim by its beacon and needs no flag). Dev option: `--dart-define=STREAM_RATE_HZ=<1-60>` sets the stream rate (default 5).
- Environment setup (once per terminal): Windows `. .\tools\env_windows.ps1`; macOS `source tools/env_macos.sh`; Linux `source tools/env_linux.sh`.
- Full gate: `tools/verify.sh` (`tools/verify.sh --no-test` for non-code changes). Run it before every commit.
- Layer and structure gates: `tools/check_structure.sh`, `tools/check_layers.sh`, `tools/check_temporary_isolation.sh`, `tools/check_acceptance_tags.sh`.
- Cleanup: `dart format . && flutter analyze`. Tests: `flutter test`.
- Plugin: `plugin\build.ps1` on Windows (MSVC and Ninja; runs `ctest`), or `ctest --test-dir plugin/build --output-on-failure`. Protocol contract: `dart run tools/protocol_contract.dart <baseUrl>`; against a running X-Plane add `--live` (it sets and restores a few datarefs through the web API; cases that need the fixture aircraft skip on any other aircraft, `--require-fixture-aircraft` fails them instead). What the live and manual tests need, and how to build the test aircraft, is in `BUILDING.md` ("Tests, and what each one needs"); they are optional and not part of `verify.sh`. CI is `.github/workflows/plugin.yml` (the plugin, on three systems, only when plugin files change) and `.github/workflows/app.yml` (`tools/verify.sh` on Linux, every push to main and every pull request).
- **Plugin version** (`pluginVersion()` in `plugin/src/core/version.cpp`, also `plugin/test_server/core_test_server.cpp` and the Plugin Admin line in `plugin/README.md`): any change to the plugin raises it, in the same commit. A fix that changes no behaviour a client can see raises the patch number (0.1.x); a functional change (a new or changed name form, limit, field or op) raises the minor number (0.x.0). It is separate from `protocolVersion`, which only changes when the meaning of the protocol changes.
- macOS and iOS builds are done on a Mac; the repo is shared with `git push` / `git pull`. Windows is the main development platform; Linux runs through WSL.

## Commit messages
- Subject: `<area>: <summary>` in the imperative, up to about 72 characters (`plugin: reject paths in requests`, `docs: merge the plans`).
- Body: why the change was made, not what it does. Tests come with the change.
- Add a `Co-Authored-By:` trailer only for a change Claude wrote.
- Never rewrite pushed commits to fix a message.

## Branches
- `main` is always releasable. Before starting a change, ask two questions: does it break backward compatibility (a checklist file that parses today, the wire protocol, a stored value, a setting, or any behaviour a user relies on), and would it be dead code if the work it serves (for example MSFS support) were dropped?
- If either answer is yes, the change goes on a branch named after the topic (for example `msfs-support`). The branch stays local until the user says to push, is brought up to date with `main` now and then, and is merged only when the whole path works.
- A change that is backward-compatible and useful on its own (for example a new optional grammar form that leaves existing files unchanged) may go straight to `main`.
- When proposing a plan, say which of the two cases the change is in.

## Privacy
- Never commit personal paths, LAN addresses, email addresses, keystores, signing keys or account details. Use placeholders (`<X-Plane>`, `192.168.1.x`, `you@example.com`).
- Commits use the GitHub noreply address (`<id>+<login>@users.noreply.github.com`), set per repository with `git config user.email`, never a private mailbox: the history is public.
- `Documentation/temp/` is never committed (it is in `.gitignore`).
- Do not commit payware or third-party aircraft checklist content, or files from the real XChecklist.

## Repository and tests
- The repository is public (`github.com/flightsimaide/flightsim_aide`). `main` is protected by a ruleset: no deletion, no force-push, and the `verify` check (the `app` workflow) must pass; admins can bypass it. Private vulnerability reporting is on, and CI for a first-time contributor's pull request waits for approval. `Documentation/RELEASE_HISTORY.md` is the timeline of how it got here.
- No test may assume an aircraft's data (datarefs are shared slots; array lengths and values differ between aircraft). A test that needs the fixture aircraft, an add-on or a device skips instead of failing, is optional, and has what it needs written down in `BUILDING.md`.

## Scripts in `tools/`
- `tools/` holds scripts for every platform; scripts specific to one platform go under `tools/platform/<ios|mac|linux|win>/`.
- A script asks the user for input only when the answer can only come from a person looking at the screen. Anything a command can find out (HTTP status, timing, log lines, exit codes, device ids, versions) is measured by the script, not asked. For a visual check, print what to look for before the action, then perform it, then ask one pass/fail question.

## UI conventions
- **Material 3 only:** `useMaterial3: true`, `ColorScheme`-based themes, M3 components. Colours and text styles come from the theme (`lib/ui/core/themes/`), never hard-coded in a widget. Dark and light themes are both maintained.
- **Status colours mean something:** red = warning, critical, cannot continue (used sparingly); amber = caution, can continue but degraded (for example skipping an item); green = good (for example ticking an item where the dataref agrees). Use them for nothing else, and never rely on colour alone: each status has a filled icon (green check mark, red `error`, amber `warning`).
- **Text and icons on a status fill:** use `StatusPill` (`lib/ui/core/widgets/status_pill.dart`), which picks black or white by contrast. Whenever text or an icon sits on a status colour, set its colour explicitly to the black or white with the higher contrast, check both themes, and cover it with a contrast test (see `test/ui/core/widgets/status_pill_test.dart`). Use `StatusColors.cautionBackground` for amber fills.
- **VelocityX (`velocity_x`), sparingly:** only where it cuts boilerplate and reads better (padding, sizing, text and box shortcuts). Not for navigation (`go_router`), state (`flutter_bloc`) or theming.
- **Appearance:** the Settings page (`lib/ui/settings/`) holds dark/light/system, the colours of each theme and Restore defaults. `ThemeCubit` keeps the choices in `SettingsRepository`.

## Writing or changing a checklist file
Applies to any `sw_item` file (for example `Documentation/Examples/*.txt`). Format reference: `Documentation/Reference/GRAMMAR.md`.
- **The result is short:** the text after `|` is ideally one or two words, the state to reach (`SET`, `ON`, `OFF`, `CHECK`, `AVAILABLE`, `AS REQUIRED`). If it wraps to a second line it is too long.
- **The rest goes in `sw_item_details`:** put extra text on a `sw_item_details:` line directly under the item, in sentence case (never all capitals, apart from names such as CAWS or ENG FIRE). Drop words that only restate the result (`SET to cruise altitude + 500 ft` becomes result `SET`, details `Cruise altitude + 500 ft`).
- The dataref condition stays on the `sw_item` line, after the result.
- Check that the file still parses with no new warnings (`AircraftWorkflowParser`).

## Architectural rules and coding conventions
- **Domain independence:** `domain/` is pure Dart plus `equatable`. Never import Flutter, `flutter_bloc`, `dio`, raw sockets, or anything from `data/` or `ui/` into it.
- **Models vs entities:** services in `data/services/` return raw, non-domain data (for example `RawChecklistDocument`). `data/parsers/` and `data/repositories/` turn that into immutable `domain/` entities. Domain entities never parse or fetch.
- **Repositories never throw to the UI:** they return `Result<T>` (`Ok`/`Error`) and wrap any parser or service exception in a typed `AppException`.
- **Cubits and Blocs:** Cubits for simple, linear flows; Blocs for complex, multi-event or stream work. They depend only on abstract repositories and use cases, never on a concrete repository, a service or a parser. State classes are immutable (loading, loaded, failure shapes) with `equatable` for equality.
- **Network and streams:** never do high-frequency socket parsing or buffering in a widget lifecycle or `build()`. Filter, throttle or buffer the stream in the data layer (service or repository) before it reaches a Cubit. Wire the connection as a `RepositoryProvider` from `config/`; `ui/core/` is UI-only and holds no DI registration.
- **Async and `BuildContext`:** do not change state or start async work inside `build()`. Check `if (!context.mounted) return;` across async gaps.

## Testing
- Unit tests are mandatory for all Cubits, Blocs and repository mapping code.
- Use `mocktail` for mocks and `bloc_test` for state sequences.
- `test/` mirrors `lib/`; shared fakes and fixtures live in the root `testing/` folder.
- An acceptance criterion in `PLAN.md` section 16 tagged `[A]` needs a test with a `// AC-n` comment; one tagged `[SIM]` needs an entry in `Documentation/Testing/MANUAL_TEST.md`. `tools/check_acceptance_tags.sh` checks both.
