# Plan: FlightSim Aide

The design of the app, the companion plugin and the live-data helper: what each part does, the rules it follows and the criteria it is accepted against. Decisions are in `Documentation/Architecture/DECISIONS.md`, the structure in `Documentation/Architecture/ARCHITECTURE.md`, the checklist grammar in `Documentation/Reference/GRAMMAR.md`.

## Contents

  - [1. Goal, scope and non-goals](#1-goal-scope-and-non-goals)
- **Part A: Checklist viewer**
  - [2. Checklist file format and parser](#2-checklist-file-format-and-parser)
  - [3. Data model](#3-data-model)
  - [4. State and screens](#4-state-and-screens)
- **Part B: Connection and companion plugin**
  - [5. Wire protocol](#5-wire-protocol)
  - [6. The companion plugin](#6-the-companion-plugin)
  - [7. App side of the connection](#7-app-side-of-the-connection)
  - [8. Progress persistence and the restore rule](#8-progress-persistence-and-the-restore-rule)
  - [9. Mobile and desktop configuration](#9-mobile-and-desktop-configuration)
- **Part C: Live data and auto-check**
  - [10. Conditions and the plugin](#10-conditions-and-the-plugin)
  - [11. Domain model and evaluation](#11-domain-model-and-evaluation)
  - [12. Auto-check semantics](#12-auto-check-semantics)
  - [13. App side of auto-check](#13-app-side-of-auto-check)
  - [14. User options and the stream rate](#14-user-options-and-the-stream-rate)
- **All parts: testing, acceptance, risks, open items**
  - [15. Testing strategy](#15-testing-strategy)
  - [16. Acceptance criteria](#16-acceptance-criteria)
  - [17. Risks](#17-risks)
  - [18. Open items and questions](#18-open-items-and-questions)

---

### 1. Goal, scope and non-goals

**Goal:** A Flutter app that, with X-Plane running the companion plugin, finds the sim on the local network, fetches the loaded aircraft's XChecklist file, shows its checklists and lets the pilot tick items off, keeps the check state across restarts, and uses live values from the sim as a helper: items whose conditions are met are checked for the pilot, and a checklist can offer to continue to the next.

**How to read this plan:** `Documentation/Architecture/ARCHITECTURE.md` wins on every conflict. This plan fills gaps: the file format, parser rules, wire protocol, plugin behaviour, auto-check rules, UI behaviour and acceptance criteria. Anything here that the architecture does not state is marked **(gap-fill)** and, where it is a real choice, repeated in section 18. Where an early experiment contradicted an earlier version of this plan, the experiment won and the plan was corrected; lines say "confirmed early on" or "changed by an early measurement" where an experiment decided them. The plan has three parts: **Part A** the checklist viewer (sections 2 to 4), **Part B** the connection and the companion plugin (sections 5 to 9), **Part C** live data and auto-check (sections 10 to 14). Sections 15 to 18 cover testing, acceptance criteria, risks and open items for all three.

**In scope**

Part A, the checklist viewer
- Parse checklists, check items and note lines from an XChecklist-style text file.
- Display checklists and items, toggle items, show progress, reset.

Part B, connection and plugin
- Companion plugin in `plugin/` (C++, XPLM SDK, CivetWeb, CMake) with Windows, macOS and Linux build files.
- Plugin handshake `GET /v1/hello` and stream `GET /v1/stream` (WebSocket, JSON), carrying the reserved signal `flightsim_aide/aircraft_generation` and the stock on-ground dataref `sim/flightmodel/failures/onground_any` (D-36 to D-40). No plugin datarefs are registered.
- HTTP API v1: `GET /v1/hello`, `GET /v1/aircraft`, `GET /v1/checklist`, ETag / `If-None-Match`, and the WebSocket stream.
- App: `FlightSimConnectionService`, `CompanionPluginService`, `NetworkChecklistSourceService`, `FlightSimRepository` (connection status plus the few low-rate values above), `SettingsRepository` (manual IP), checklist cache, progress persistence and the restore rule.
- `ui/connection/` (status, manual IP, "plugin not detected", "update the plugin", "no checklist for this aircraft").
- Mobile configuration for iOS and Android.

Part C, live data and auto-check
- The whole XChecklist condition grammar on item lines and `sw_continue` (decision D-48), pinned against the real checker and a set of hand-written test checklists. (`sw_show` is parsed past and ignored, D-70.)
- Domain: `ItemCondition` (an expression tree), `Dataref`, `DatarefValue`, a pure evaluator and `EvaluateItemConditionsUseCase` (`domain/use_cases/autocheck/`).
- Parser extension: fill `ItemCondition` on items and conditions on `sw_continue` links. Lines the evaluator cannot handle stay manual and keep a warning.
- `FlightSimRepository`: value streams for named signals, throttled in the data layer, with a rate that comes from user options (default 5 Hz).
- A general `SettingsRepository` options mechanism (typed, defaulted, persisted, observable), used first for two options: the stream rate and auto-continue.
- Auto-check in `ChecklistProgress` and `ChecklistProgressRepository`: auto-checked marks, manual-uncheck suppression, both persisted.
- Detail screen: auto-checked items are marked as such; a "Continue" button when a `sw_continue` condition holds, or automatic navigation when the user has turned the auto-continue option on.
- Plugin additions needed by the full grammar: array-index names and a higher subscription cap.
- `FlightSimRepositoryLocal` simulated values for development and tests.

**Non-goals**
- **No dataref writes.** The `set` operation stays reserved and answered `unsupported` (D-40 is not extended). The `SET` that appears in many item lines (`sw_item:Parking brake|SET:sim/flightmodel/controls/parkbrake:1`) is a result word shown to the pilot; the `dataref:value` part is the condition for the check, as in the real plugin. Nothing is ever written to the sim. (If writes are wanted later, they need their own plugin-side safety design.)
- **No auto-uncheck, ever** (D-50). A condition that goes false again does not change a mark.
- **Voice is limited** (D-84): it reads items aloud and listens for a short fixed set of spoken answers. It never writes a dataref and ticks only what the pilot did or said; there is no free speech and no assistant. `@` stays stripped and ignored.
- No UI for choosing user options is specified here. The mechanism and the default exist (section 14).
- No evaluation of checklists that are not open (section 13.2), and no offline evaluation: without live values nothing is auto-checked.
- No Web API use (X-Plane 12.1.1 and later only), no X-Plane 11, and no fallback to X-Plane's native `RREF`/`DREF` (D-36, D-46).
- No general browse or navigate endpoint, no serving of any file other than the current aircraft's checklist, and no extra checklist search locations beyond the aircraft folder (open item, section 18).
- No authentication or TLS on the LAN API. The threat model is "a trusted home LAN"; see risks.
- No offline use of a cached checklist when the sim is unreachable (question Q5).
- No new top-level folders under `lib/`; no Freezed or Bloc code generation.

Checks that need a flight or a device and have not been run are listed in `Documentation/TODO.md`.

---

## Part A: Checklist viewer

### 2. Checklist file format and parser

The keywords were confirmed from published sample files and then pinned against real files and the real parser. The full, status-marked grammar is `Documentation/Reference/GRAMMAR.md`; this section is the summary.

```
sw_checklist:Prepare:Prepare for flight
sw_itemvoid:----- Prepare -----
sw_item:Parking brake|SET
sw_item:Batteries|ON
sw_item:Flight plan|loaded
```

| Line | Meaning | Behaviour |
|---|---|---|
| `sw_checklist:Name[:Menu text]` | Starts a new checklist | Menu text is the display title if present, otherwise Name |
| `sw_item:Label\|Result` | A checkable item | Label on the left, result on the right |
| `sw_itemvoid:Text[\|Text2]` | A non-checkable line (header or note), optionally with right-hand text | Shown without a checkbox |
| `sw_item_c:` / `sw_itemvoid_c:` | The same as `sw_item` / `sw_itemvoid`, with `\colour\` markers in the text | Markers removed from `label`/`result`; each marker also starts a coloured text run (several colours per label are kept as ordered runs) |
| `sw_define_colour:name:r,g,b` | Defines a named colour (floats 0 to 1) | Stored in a file-level palette; the first definition of a name wins (a repeat warns); components outside 0 to 1 are clamped with a warning; a malformed line warns and is skipped |
| `sw_continue[:Name]` | Continues to the next checklist (bare) or to the checklist called `Name`. Several may follow one another | Stored on the checklist as an ordered list of continue links; the links define the flight sequence, not file order. Invalid ones are dropped with a warning |
| `sw_show:expr` | Dataref condition that controls when a page shows | Not supported: the line is ignored like a comment, with no warning and no effect (D-70) |
| `sw_iteminfo:Label\|Result` | A display-only item | Shown as a note with label and result |
| `sw_remark:Text` | A spoken remark | Shown as a note |
| `sw_rcolsize` | Valid, but only meaningful to the plugin | Ignored without a warning |
| Blank lines | Spacing | Ignored |

#### Things to handle on purpose

- **Dataref suffixes:** Real files contain lines like `sw_item:Parking brake|set:sim/flightmodel/controls/parkbrake:1`. The result is the text after the first `|` up to the next `:`, and the rest is dataref logic, which the condition parser reads (section 10).
- **Missing result:** An item with no `|` has a label only, with an empty result. If the item has a `:` and no `|` before it (for example `sw_item:Test bigger than:checklist/test/int_dref1:>50`), the label is the text before the first `:` and the rest is dataref logic. A `|` that comes after the first `:` belongs to the dataref expression.
- **Stray prefixes and spaces:** A leading `@` (confirmed: it means "do not speak") is stripped. Many lines have a space after the colon or padding in the text (for example `sw_checklist: Preliminary:Preliminary`), so trim all values.
- **Comments:** Lines starting with `#` are comments. `//` and `;` are **not** comments (confirmed in Step 0); such lines are unrecognized lines.
- **Colour markers:** `\white\`-style markers (very common in `sw_item_c` lines) are removed from the plain `label`/`result` text. A marker switches the colour of the text that follows it until the next marker, so each label and result also keeps ordered colour runs (text plus an optional colour name). Markers form a stack as in the real plugin: `\\` (two backslashes) returns to the previous colour, it is not an escaped backslash. The real plugin reads markers only in `_c` lines; we read them everywhere. The parser keeps colour names only; the palette (`sw_define_colour`) resolves them to values, and the UI picks the real colour. A name never defined in the file warns `unknown colour` and falls back to the default colour. Showing colours is a UI task (Phases 9 and 10).
- **Checklist order:** `ChecklistDocument.checklists` stays in file order, but the file order is not the flight order. `sw_continue` links define the sequence. `sw_continue:Name` is valid when some checklist in the file (before or after it) has that exact `Name`, so the parser collects all checklist names first. A bare `sw_continue` is valid only when the next significant line is a `sw_checklist`; blank lines, `#` comments and further `sw_continue` lines are skipped when looking. A `sw_continue` always belongs to the checklist that is open. A pure domain helper follows the links (and guards against loops).
- **Unknown lines:** Skip them and record a warning. Never crash.
- **Items before any `sw_checklist`:** Skip them with a warning.

#### Parser spec

A single pure function: `ChecklistDocument XChecklistTextParser.parse(String text)`. No Flutter imports, so it is easy to unit test.

1. Normalize line endings (`\r\n` and `\r` to `\n`) and strip a UTF-8 BOM (byte order mark: an invisible `U+FEFF` character some editors put at the start of a file) if present.
2. For each line (tracking the line number for warnings):
   1. Trim it, then strip a leading `@`.
   2. Skip it if it is empty or a `#` comment. (`//` and `;` are not comments.)
   3. Split on the first `:` into keyword and value. Compare the keyword case-insensitively (a deliberate tolerance; the real plugin is case sensitive).
   4. **`sw_checklist`:** split the value on the first `:` into Name and optional Menu text. Trim both. Start a new checklist. Warn if the Name is empty.
   5. **`sw_item` / `sw_item_c`:** if there is no open checklist, warn and skip. Otherwise, if a `|` exists before the first `:` (or there is no `:`), split on the first `|` into label and the rest, and cut the rest at its first `:` to get the result. If the first `:` comes first, the label is the text before it and the result is empty. Remove `\colour\` markers (keeping them as colour runs), trim, and if the label is empty warn and skip.
   6. **`sw_itemvoid` / `sw_itemvoid_c`:** the value becomes a note item. Split on the first `|` into label and result; colons are not special. Remove colour markers (keeping them as colour runs).
   7. **`sw_iteminfo`** becomes a note (split like an item); **`sw_remark`** becomes a note with the whole value as label.
   8. **`sw_define_colour`:** value is `name:r,g,b` (three floats 0 to 1, padding allowed). Store it in the palette (the first definition of a name wins and a repeat warns). Components outside 0 to 1 are clamped with a warning. A malformed value warns and is skipped. After parsing, every marker name that is not in the palette warns `unknown colour`.
   9. **`sw_continue`:** the value is the text before its next `:` (a dataref condition after it is dropped), trimmed. No open checklist: warn and skip. Otherwise add a link to the open checklist, in file order. *Named:* valid if the name matches a checklist anywhere in the file, otherwise dropped with a warning. A valid named link followed by an item or note line (skipping blanks, comments and other `sw_continue` lines) keeps its link and the items stay in the checklist, but warns `Line N: sw_continue should be at the end of its checklist` (the real checker allows it; the warning is ours). *Bare:* valid only if the next significant line, skipping blanks, comments and other `sw_continue` lines, is `sw_checklist`; otherwise (any other line, or end of file) dropped with a warning.
   10. **`sw_show`:** ignore the line like a comment: no warning, no effect (D-70).
   11. **`sw_rcolsize`:** ignore without a warning.
   12. **Anything else:** add a warning.
3. Drop checklists with zero items, with a warning.
4. If no checklists were found, return an empty result with a clear warning. The UI reports this to the user.

### 3. Data model

Keep parsed data immutable and keep check state separate. That makes live data easier to add later.

```dart
enum ItemType { check, note }

class ColourRun {
  final String text;
  final String? colour; // name from a \colour\ marker; null = default
  const ColourRun(this.text, [this.colour]);
}

class ChecklistItem {
  final ItemType type;
  final String label;   // plain text, markers removed
  final String result;  // empty if none
  final List<ColourRun> labelRuns;
  final List<ColourRun> resultRuns;
  const ChecklistItem(this.type, this.label, [this.result = '', this.labelRuns = const [], this.resultRuns = const []]);
}

class Checklist {
  final String name;   // from sw_checklist
  final String title;  // menu text or name
  final List<ChecklistItem> items;
  final List<ContinueLink> continues; // from sw_continue, in file order; each is next or named
  const Checklist(this.name, this.title, this.items, [this.continues = const []]);
}

// ChecklistDocument also holds `colours`: Map<String, ChecklistColour> (r, g, b as 0..1)
// from sw_define_colour.

class ChecklistDocument {
  final List<Checklist> checklists;
  final List<String> warnings; // e.g. "Line 14: unknown keyword"
  final String sourceName;     // file name, for display
  const ChecklistDocument({required this.checklists, required this.warnings, this.sourceName = ''});
}

// Check state is a separate immutable value, keyed by checklist name:
class ChecklistProgress {
  final Map<String, Set<int>> checked;
  const ChecklistProgress([this.checked = const {}]);
  // toggled(name, index), reset(name), countsFor(checklist)
}
```

### 4. State and screens

#### State

> Superseded: the original `ChecklistController` (`ChangeNotifier`) was replaced by Cubits plus two repositories (`ARCHITECTURE.md` sections 4, 6 and 9).

- `ChecklistRepository` loads the raw text from a `ChecklistSourceService`, runs the parser and caches the `ChecklistDocument` (warnings included). A document with no checklists is a `ParseFailure`.
- `ChecklistProgressRepository` holds the `ChecklistProgress` (check state keyed by checklist **name**, not index) and exposes a stream.
- One Cubit per screen (`HomeCubit`, `ChecklistListCubit`, `ChecklistDetailCubit`) depends only on those abstract repositories.

| Method | Where | Purpose |
|---|---|---|
| `load()` | `ChecklistRepository` | Fetch, parse and replace the current document |
| `toggle(checklistName, itemIndex)` | `ChecklistProgressRepository` | Check or uncheck an item |
| `reset(checklistName)` / `resetAll()` | `ChecklistProgressRepository` | Clear one checklist, or all (after each new load) |
| `countsFor(checklist)` | `ChecklistProgress` | Checked and total counts (notes excluded) |

#### Screens

##### Home screen
- *(The original Open-file button and the bundled sample were removed when the network source became the only source, D-69. What the home screen shows now is described in sections 7 and 14.)*
- Parse warnings: a dismissible banner such as "3 lines were skipped" with a details view, shown on the checklist list screen (a successful load goes straight there).

##### Checklist list screen
- One tile per checklist showing its title and progress (for example `4 / 9`).
- Tapping a tile opens it.

##### Checklist screen
- **Item rows:** each check item has a checkbox, the label on the left, and the result on the right, similar to XChecklist's layout. Note items render as a section header with no checkbox.
- **Tap target:** the whole row toggles. The checked state shows as a checkmark plus dimmed or struck-through text.
- **Progress:** a bar or `5 / 12` in the app bar.
- **Reset:** a button to clear the checklist, with a confirmation.
- **Completion:** a small "Checklist complete" banner when all items are checked.

##### Theme
- Support dark mode, since people fly at night.
- Use large rows (minimum 48px height) and readable fonts.
- Do not rely on color alone to convey meaning.

---

## Part B: Connection and companion plugin

### 5. Wire protocol

#### 5.1 Beacon (gap-fill, confirmed early on)

- Group `239.255.1.1`, UDP port `49707`. The app only listens; it never sends to the group.
- Packet: the 5-byte header `BECN\0`, then (little-endian) `beacon_major_version` (u8), `beacon_minor_version` (u8), `application_host_id` (i32), `version_number` (i32), `role` (u32), `port` (u16), then a NUL-terminated computer name. Only role "master" (the sim, not an external visual) is accepted.
- Output: `(ip = packet source address, udpPort = port field, computerName, xplaneVersion)`. The sim IP is the packet's source address, not a field.
- Several sims on one LAN produce several distinct beacons: see Q13. Measured layout (confirmed early on): 33 bytes, version 1.2, role 1, port 49000, one beacon per second per interface. A PC with several adapters sees the same beacon from several source addresses (changed by an early measurement: do not take the first; prefer the LAN interface or let the user choose).
- The listener joins the group on each IPv4 interface that is up and not loopback, and re-joins when interfaces change (Wi-Fi roaming).

#### 5.2 Handshake and port (decided by D-36, D-38)

`GET /v1/hello` returns `application/json; charset=utf-8`, `Cache-Control: no-store`:

```json
{
  "protocolVersion": 1,
  "sim": { "kind": "xplane", "version": "12.1.4" },
  "pluginVersion": "0.1.0",
  "port": 18086,
  "streamPath": "/v1/stream"
}
```

- `protocolVersion`, `port` and `streamPath` are required; unknown fields are ignored. The app requires `protocolVersion` equal to 1 and checks it before anything else ("update the plugin" otherwise). `sim.kind` is `xplane` for this plugin; another sim's companion would say something else and serve the same protocol.
- The plugin prefers port **18086** and walks 18086 to 18093 (confirmed early on on XP12: 18086 was chosen, no firewall prompt). There is **no OS-assigned fallback** (changed by D-38: the app could not find it). If no port binds, the plugin logs why and serves nothing.
- The app probes the range in parallel with a short timeout (about 1 s), takes the first valid answer, and remembers the working port for the next start. The probe is the only thing it sends before the version check.

#### 5.3 Stream protocol (decided by D-37, D-40)

`GET /v1/stream` upgrades to a WebSocket (CivetWeb, same port, `ws://` cleartext on the LAN). Every frame is a JSON text frame with an `op` field. Subscriptions belong to the connection: nothing survives a disconnect, so there are no ghost streams (changed by an early measurement, which saw a closed socket still streamed to for 43 s or more).

Client to server:

| Frame | Meaning |
|---|---|
| `{"op":"subscribe","id":1,"name":"sim/flightmodel/failures/onground_any","hz":2}` | Start a subscription. `id` is chosen by the client. `hz` is 1 to 60; the plugin never sends faster. A repeated `id` replaces the old subscription. |
| `{"op":"unsubscribe","id":1}` | Stop it. |
| `{"op":"ping"}` | Optional liveness probe. |
| `{"op":"set",...}` | Reserved; answered `unsupported`. |

Server to client:

| Frame | Meaning |
|---|---|
| `{"op":"subscribed","id":1}` | The name resolved. Sent after the plugin's next flight-loop tick (at most about 1 s), because server threads never call XPLM. |
| `{"op":"error","id":1,"code":"unknown_name"}` | Codes: `unknown_name`, `bad_request`, `limit`, `unsupported`. Deterministic: a missing name always answers `unknown_name` (replaces the `0.0` or nothing of `RREF`). |
| `{"op":"values","t":1761206400123,"v":{"1":1}}` | At most one frame per tick with the latest value of each due subscription (latest wins). `t` is the sample time in epoch milliseconds. Numbers are JSON numbers. A value is sent every tick, changed or not, so staleness is judged by frame arrival, never by value change. |
| `{"op":"hb"}` | Sent about once a second when no `values` frame was sent. |
| `{"op":"pong"}` | Answer to `ping`. |

- Reserved signal `flightsim_aide/aircraft_generation` (integer): delivered at subscribe time and again immediately at every change, in addition to its `hz` ticks. It increments on every aircraft load, not on file changes, and wraps at 2^31 (changed by D-36: the 2^24 wrap existed only because `RREF` sends float32). The app compares for inequality, not ordering. All other names are opaque strings resolved by the plugin (X-Plane dataref names for the X-Plane plugin).
- Limits: at most 4 stream clients (a fifth upgrade gets `503`), at most 32 subscriptions per client, name length at most 200, frame size at most 4 KB. Over the limit: `error` with `limit`.
- Liveness: the client treats 3 s without any frame as stale (carried over from the early stream experiment) and reconnects with back-off 1 s, 2 s, 5 s, re-subscribing everything. The server closes a connection that sent nothing and failed to answer its ping for 15 s.
- The app always subscribes to `flightsim_aide/aircraft_generation` (1 Hz) and `sim/flightmodel/failures/onground_any` (2 Hz). The datarefs of the open checklist are added on top.

#### 5.4 HTTP API v1 (aircraft and checklist)

Base URL `http://<sim-ip>:<port>` (the port from the handshake). Paths served: `/v1/hello`, `/v1/aircraft`, `/v1/checklist` and the WebSocket `/v1/stream`. All methods other than `GET` (and `HEAD`) return `405`. All other paths return `404`. Query strings are ignored. No request parameter ever selects a file.

**`GET /v1/aircraft`** returns `application/json; charset=utf-8`, `Cache-Control: no-store`:

```json
{
  "protocolVersion": 1,
  "generation": 12,
  "icao": "C172",
  "description": "Cessna Skyhawk 172SP",
  "aircraftPath": "Aircraft/Laminar Research/Cessna 172SP/Cessna_172SP.acf",
  "checklistPath": "Aircraft/Laminar Research/Cessna 172SP/clist.txt",
  "checklistModified": 1761206400123,
  "checklistSize": 18342
}
```

- `checklistModified` (integer epoch **milliseconds**, UTC) and `checklistSize` (bytes) are **absent** when the aircraft has no checklist file. `checklistPath` is also absent then.
- `generation`, `checklistPath` and `protocolVersion` are **gap-fill additions** (Q8): `checklistPath` is needed because the architecture's cache entry stores "the path of the file the plugin used"; `generation` lets the app detect that the aircraft changed between its stream notification and its HTTP fetch; `protocolVersion` lets a plain HTTP client check compatibility (it equals the handshake's).
- Unknown JSON fields are ignored by the app (forward compatibility). Missing required fields (`protocolVersion`, `generation`, `aircraftPath`) are a protocol error.
- Paths are reported as the plugin sees them (POSIX separators, native-path mode). The app treats `aircraftPath` as an opaque string and only hashes it.

**`GET /v1/checklist`**
- `200`: body is the **raw bytes** of the file, `Content-Type: text/plain` (no charset claim, so the app's `decodeChecklistText` applies strict UTF-8 with Latin-1 fallback, exactly as in the viewer), `ETag: "<mtime>-<size>"` (the same two numbers as in `/v1/aircraft`, quotes included), `Last-Modified` (HTTP date, informational only), `X-Aircraft-Generation: <n>`.
- `304` with the `ETag` when `If-None-Match` equals the current ETag.
- `404` when the aircraft has no checklist file (body: short JSON error).
- Files above 2 MB are refused with `413` (real files are tens of KB). Limit is plugin-side and documented in the protocol file.
- `Content-Length` always set. `HEAD` is supported and returns headers only.

**Timestamp rule (one definition, tested on both sides):** modification time is the file's last-write time as integer epoch milliseconds UTC. The ETag is `"` + mtime + `-` + size + `"`. The plugin computes it with platform APIs that give millisecond resolution (not `st_mtime` seconds). The app compares by exact equality, never ordering (an older file means a restored backup and must also refetch).

**Errors** are small JSON bodies `{"error": "<code>", "message": "<text>"}` with the right status. The app maps: connection refused or timeout to `PluginUnreachable`, `404` on checklist to `NoChecklistForAircraft`, malformed JSON or missing fields to `ProtocolError`, `protocolVersion` mismatch to `PluginVersionMismatch`.

**Race rule:** after a fetch, the app checks that the checklist response's ETag equals the aircraft JSON's `checklistModified`-`checklistSize` and that `X-Aircraft-Generation` equals the aircraft JSON's `generation`. If either differs, the aircraft changed mid-flight of the requests: re-fetch `/v1/aircraft` and start over, at most 3 times, then report `ProtocolError`.

#### 5.5 Discovery sequence (from the architecture, updated by D-38)

1. Sim IP from the beacon or manual entry.
2. Probe `GET /v1/hello` on 18086 to 18093. Check `protocolVersion` (equal to 1, else "update the plugin").
3. "No valid answer from any port within about 2 s of the sim IP being known" is **plugin not detected**. The UI says "not detected", never "not installed", because X-Plane still loading looks identical. Keep retrying (it recovers by itself when the plugin appears).
4. `GET /v1/aircraft`, then open `/v1/stream`, subscribe, and refetch `/v1/aircraft` only when `flightsim_aide/aircraft_generation` changes.

#### 5.6 Findings from the early experiments

Short experiments with the beacon, X-Plane's native `RREF` protocol and a first plugin shaped this section. Their write-ups are not published; the results that still matter are kept here.

##### Beacon listener and manual IP

desktop beacon in 10 of 10 trials, worst 889 ms, with and without virtual adapters (confirmed early on); bind with `reuseAddress` or another tool holding the port exclusively makes ours fail (changed by an early measurement: bind failure is a recoverable state); Android receives the beacon 10 of 10 with the lock and 6 of 6 without on the SM-T380 (confirmed early on: the lock stays, it is cheap); manual IP works with no multicast (confirmed early on); on an iPhone 16 (iOS 26.6.2, debug build) the beacon arrived in 371 ms **without** the multicast entitlement after the Local Network prompt was allowed, and manual IP and the stream worked (changed by an early measurement: the app does not wait for the entitlement). With the permission denied the beacon is silent and `http://` to the PC fails at once with errno 65, so manual IP is not a fallback for denial; the app needs a "Local Network access may be off" message, and re-enabling needs no restart (changed by an early measurement; release build still open).

##### X-Plane's native `RREF` protocol (evidence about X-Plane, not the design)

The transport decision of 2026-10-23 (keep `RREF`) was superseded by D-36. What was measured, and what each result now means:

- `RREF` request and reply layouts: confirmed early on. Not used by the app any more.
- Rate: X-Plane delivered about 0.86 of the requested rate at 10, 30 and 60 Hz, with no loss or reordering on the network (changed by an early measurement; irrelevant to our own sender, which is limited by the flight-loop rate and measured against the core test server).
- Tablet Wi-Fi gaps (311 to 423 ms at the worst, 0 duplicates, 0 out of order): kept as an input to the auto-check design.
- Missing dataref answers `0.0` or nothing, and back-to-back subscribes are dropped (changed by an early measurement): the reason the transport was replaced. Our plugin answers an unknown name with an explicit `unknown_name` error.
- Subscription lifecycle: a closed socket was still streamed to for 43 s or more (changed by an early measurement). Our stream belongs to a WebSocket connection, so a close ends it at once.
- Keep-alive 5 s and stale 3 s are the starting values for the heartbeat and stale rule of the new stream (confirmed early on as sensible by the 30-minute run: 0 of 30 windows over 3 s). Stale is judged by frame arrival, never by value change (a paused sim keeps sending frozen values).
- On-ground dataref: `sim/flightmodel/failures/onground_any` = 1 parked, confirmed on XP12 early on; the flight sequence is still open (`Documentation/TODO.md` 4.3a).
- Replies came from source ports 49001/49002, not 49000: irrelevant now.

##### First plugin on X-Plane 12

layout A (`plugins\flightsim_aide\64\win.xpl`) loads (confirmed early on); port 18086 chosen from the range (confirmed early on); `/v1/aircraft` and `/v1/checklist` answer 200 locally and from the tablet, ETag then 304 works, POST gives 405, `/` and traversal give 404, a query string is ignored (confirmed early on); no Windows Firewall prompt (confirmed early on); the generation rises on every aircraft load (confirmed early on); a PC12 checklist uses CR-only line endings and the parser handles it (confirmed early on).

### 6. The companion plugin

Lives in `plugin/` at the repo root, outside `lib/`. Coexists with the real XChecklist plugin; the only shared dependency is the checklist file syntax. The plugin never parses the checklist.

#### 6.1 Layout (gap-fill)

```
plugin/
├── CMakeLists.txt
├── README.md                    # per-OS build and install notes, folder layout, how to run the tests
├── PROTOCOL.md                  # the wire contract: datarefs, endpoints, JSON, ETag rule, error codes, examples
├── cmake/                       # toolchain / platform helpers
├── third_party/civetweb/        # vendored, pinned release (source + licence); no SSL, no CGI, no file serving
├── src/
│   ├── core/                    # NO XPLM includes: cache, JSON writer, ETag, request handlers, address filter,
│   │                            #   stream module (subscriptions, rate limiter, codec, ValueSource interface)
│   ├── platform/                # file stat and read (ms mtime), no XPLM, tested with ctest on temp files
│   └── xplane/                  # thin XPLM shell: plugin entry points, flight loop, dataref reads (ValueSource), aircraft info
└── test/                        # core unit tests; contract test script
```

The split into `core/` (platform-neutral, no XPLM) and `xplane/` (XPLM-facing) is what makes the plugin testable without X-Plane and buildable for tests on any OS. It also enforces the rule that server threads never call XPLM.

#### 6.2 Build files

- CMake, C++17. X-Plane SDK path passed as `-DXPLANE_SDK=<path>` (the SDK is downloaded separately, not vendored; its licence is Laminar's). Native-path mode enabled (`XPLM_USE_NATIVE_PATHS`).
- Targets: Windows (MSVC, x64), macOS (universal x86_64 + arm64, with the signing/notarization steps documented), Linux (GCC, x64). Output named per X-Plane's plugin convention; the folder layout that loads on XP12 was decided by an early experiment (section 5.6).
- **Constraint:** developed and tested on Windows only. macOS and Linux build files are provided and documented but **never run by us**; they are labelled untested in `plugin/README.md`. They are **compiled** (not run) by a GitHub Actions job, see 6.4, and optionally by hand on the MacBook (Q7 answered).

#### 6.3 Runtime behaviour

- **No plugin datarefs** (changed by D-36). The handshake and the stream replace them.
- **Stream module (in `core/`):** a subscription table per connection, the union of requested names exposed to the shell, a rate limiter driven by an injected clock, latest-wins coalescing, the codec of 4.3, caps and expiry. The shell implements `ValueSource` (resolve a name, read a value) and runs it in the flight loop; the sender thread reads only the published snapshot. A fake `ValueSource` drives the `ctest` loopback tests and `core_test_server`.
- **Cache:** one struct holding generation, ICAO, description, aircraft path, checklist path, mtime, size, text bytes and a "has checklist" flag, behind a mutex.
- **Flight loop callback** (about 1 Hz, in the sim thread, the only place XPLM and file IO are used):
  - Reads the ICAO and description datarefs and the user aircraft path (`XPLMGetNthAircraftModel(0, ...)`).
  - Resolves newly requested stream names (`XPLMFindDataRef`; a null result becomes `unknown_name`) and reads every subscribed dataref, publishing a snapshot for the sender thread. The callback interval follows the fastest subscription (1 s when only slow ones exist).
  - On aircraft load (`XPLM_MSG_PLANE_LOADED` for the user plane, received in `XPluginReceiveMessage`, which only sets a dirty flag and bumps the generation) the callback rebuilds the cache: derives the aircraft folder, looks for `<acf name>_clist.txt` and then `clist.txt` next to the `.acf`, reads the first found, records mtime and size.
  - Cheaply re-stats the file every few seconds; if mtime or size changed, rereads it and updates the cache. **The generation does not change** on file edits (architecture: generation = aircraft load).
  - Livery changes (`XPLM_MSG_LIVERY_LOADED`) are treated as an aircraft load unless measurement shows they do not change the path/files (to confirm).
- **HTTP and WebSocket server (CivetWeb):** handlers registered for exactly four URIs (`/v1/hello`, `/v1/aircraft`, `/v1/checklist`, `/v1/stream`); everything else 404. Handler threads copy from the cache under the mutex and never call XPLM. A stream client holds a worker thread, so the pool is raised (8) and stream clients are capped at 4. Directory listing, CGI, SSL, document root and keep-alive abuse are all off or bounded; request header and size limits are set; WebSocket is on.
- **Binding / LAN-only:** listens on all IPv4 interfaces but admits only private-range and loopback sources (10/8, 172.16/12, 192.168/16, 169.254/16, 127/8) through CivetWeb's access control list; anything else is refused. IPv6 off. A pure address-filter function in `core/` is unit tested. Binding to the specific LAN interface instead is an alternative (Q2b).
- **Read-only, no path from requests:** the only files ever opened are `<aircraft folder>/<acf name>_clist.txt` or `<aircraft folder>/clist.txt` (the XChecklist file names; `_clist.txt` is searched first) for the user's current aircraft, chosen by the plugin. Request URL, query and headers never reach the filesystem layer. Verified by contract tests (section 15) with traversal-style URLs.
- **Port selection (changed by D-38):** try 18086, then walk 18087 to 18093; no OS-assigned fallback. The bound port is announced by `/v1/hello`. If nothing binds, the plugin serves nothing and writes the reason to `Log.txt`. The bind logic takes an injected bind function so "preferred port occupied" is a `ctest` case.
- **Lifecycle:** server starts in `XPluginEnable` and stops in `XPluginDisable` (stream connections closed, the server joined, then the cache freed). No threads outlive `XPluginStop`.
- **Logging:** a short line per start/stop/bind/aircraft change into X-Plane's `Log.txt`; no per-request logging by default.
- **Performance budget:** the flight loop callback averages under 1 ms (measured in AC-24).
- **Search locations:** only the aircraft folder, with the XChecklist names: `<acf name>_clist.txt` (acf file name without `.acf`, e.g. `Cessna_172SP_clist.txt`) first, then `clist.txt` (open item 1). The lookup is isolated in one function so more locations are an additive change.

#### 6.4 Continuous integration (GitHub Actions)

The repo is on GitHub, so CI is a workflow file in `.github/workflows/` that you commit; there is nothing to install or pay for beyond enabling Actions (free for public repos; private repos use a monthly free quota, check the current figure). macOS minutes cost more against that quota, so jobs are kept short.

- **`plugin.yml`**, runs on pushes and pull requests that touch `plugin/` or `testing/fixtures/protocol/`. A matrix of `windows-latest`, `macos-latest` and `ubuntu-latest`: download the pinned X-Plane SDK, configure with CMake, build the plugin and the XPLM-free `core/` tests, run the core tests and the contract script. This is **compile and core-test only**; it never runs X-Plane.
- **`app.yml`** (optional, small): `flutter pub get`, `flutter analyze`, `flutter test` on Linux. The existing `tools/verify.sh` is bash and could be reused there. Not required; listed because the workflow infrastructure is already being set up.
- The SDK is fetched in the job from a pinned URL (not vendored, licence is Laminar's); if the URL ever disappears the job fails loudly rather than silently skipping.
- The MacBook is the backup: if CI cannot build the macOS plugin (signing, universal binary), build and sanity-check it there per `plugin/README.md`, using a script in `tools/platform/mac/` that the user runs (the PC never connects to the MacBook). The Linux build can be run in WSL. Neither route runs the plugin inside X-Plane on macOS or Linux, so those builds stay labelled untested.
- CI results do not replace the Windows sim tests; AC-24 stays a manual criterion.

### 7. App side of the connection

All of this follows `ARCHITECTURE.md` sections 5 to 9. New files only; existing files get specific, small edits.

#### 7.1 Domain (pure Dart, `equatable` only)

- `domain/models/aircraft/aircraft_identity.dart`: `AircraftIdentity` (icao, description, aircraftPath, plus the checklist's mtime and size as optional fields).
- `domain/models/flight_sim/connection_status.dart` (per the architecture): a small sealed/enum shape covering `searching`, `connecting` (sim found, plugin not yet confirmed), `connected` (sim IP, plugin ok), `pluginNotDetected`, `pluginVersionMismatch`, `noNetwork` (the device has no usable local network), `simUnreachable(lastSeen)` (network present, X-Plane silent).
- `domain/models/checklist/progress_restore_policy.dart` **(gap-fill)**: the pure restore rule of section 8 as a function over plain values, so the rule is domain logic, not Cubit logic.
- Extension of `ChecklistProgress` is **not** needed for persistence itself; serialisation lives in the data layer.

#### 7.2 Services (`data/services/`; return raw data, no domain models, no business rules)

- `flight_sim/flight_sim_service.dart` (abstract transport) and `flight_sim/flight_sim_connection_service.dart`:
  - Beacon listener (section 5.1), manual-IP mode, the handshake probe (5.2), the WebSocket stream client with subscribe, heartbeat/stale detection and reconnect (5.3), streams of raw `RawSignalMessage` values and of discovered sim endpoints.
  - Uses `dart:io` `RawDatagramSocket` for the beacon and `WebSocket` for the stream. The socket and WebSocket factories and the clock are injectable so tests use loopback servers and fake time.
  - Android multicast lock: acquired while the beacon listener is active, released when it stops (small platform channel or plugin, section 9).
  - Handles app lifecycle: stops the listener and closes the stream on pause; rediscovers, re-handshakes and resubscribes on resume.
  - No UI imports; no parsing of checklists.
- `flight_sim/companion_plugin_service.dart`: `package:http` only here (and in the network checklist source). `getHello(host, port)` returning a raw hello DTO, and `getAircraft(endpoint)` returning a raw aircraft DTO (`xplane/model/`), `getChecklist(endpoint, ifNoneMatch)` returning bytes + ETag + generation or `NotModified`. Timeouts (3 s connect/response) and the race rule of 4.4 live in the repository/source, not here.
- `checklist/network_checklist_source_service.dart`: implements the unchanged `ChecklistSourceService`. `load()` has no parameters: it asks the endpoint source for the current plugin endpoint, fetches `/v1/aircraft`, consults the cache, fetches `/v1/checklist` only when needed, stores the result, and returns `RawChecklistDocument(name, text)`. Decodes with `decodeChecklistText`. It never produces `SourceCancelled`. Failures map to the typed exceptions of 6.6.
- `local/checklist_cache_service.dart`: one file per aircraft in the app-support directory (`path_provider`), file name = hash of the aircraft path; contents = raw text, checklist path, mtime, size. Reads and writes atomically (write temp then rename). A corrupt or unreadable entry is treated as a miss.
- `local/progress_storage_service.dart`: one file per aircraft (same hashing), JSON: version, per-checklist checked indexes plus the fingerprint (8.2), last viewed checklist. Atomic writes. Corrupt file is a miss, never thrown.
- `local/preferences_service.dart`: wraps `shared_preferences` for the manual IP and later preferences.
- A small abstract `PluginSessionSource` **(gap-fill)** in `flight_sim/`, implemented by `PluginSessionService`, is the single owner of the aircraft identity: it follows `aircraft_generation`, fetches `/v1/aircraft` once per change, and publishes the host, port, aircraft info and generation. The network checklist source and `FlightSimRepository` both read it; neither fetches the aircraft itself (Q3, revised).
- `xplane/network_status_service.dart` **(gap-fill)**: tells whether the device has a usable local network (polls `NetworkInterface.list`, no extra package), so the app can say "No network connection" separately from "X-Plane is not responding".

#### 7.3 Repositories (`data/repositories/`)

- `flight_sim/flight_sim_repository.dart` (abstract) and `flight_sim_repository_remote.dart`: exposes `connectionStatus`, current `AircraftIdentity?` (a stream), `onGround` (`bool?`, null = unknown), `useManualIp(ip)` / `useAutomaticDiscovery()`, and `reload()`. Maps raw datarefs and HTTP DTOs to domain models, applies the plugin-not-detected rule (5.5), and returns `Result` for anything that can fail. Throttling to 30 to 60 Hz matters only for the checklist datarefs and is not needed at 1 Hz, but the throttle seam (the place it will go) is in this class, not in a widget.
- `flight_sim_repository_local.dart`: a scriptable fake for the development entry point when no sim is available (also used by widget tests). Simulated *values* come with auto-check.
- `settings/settings_repository.dart` + `_impl`: manual sim IP (validated IPv4), remembered across restarts.
- `checklist/checklist_progress_repository.dart` + `_impl` (extended, 7.3): persistence, attach / restore, last viewed.
- `checklist/checklist_repository_impl.dart`: **no change** to its logic. It still asks its `ChecklistSourceService` for `load()`.

#### 7.4 Cubits and screens

- `ui/connection/cubit/connection_cubit.dart` + state: depends only on `FlightSimRepository` and `SettingsRepository`. States: searching, found (list of sims, when more than one), connecting, connected (aircraft shown), pluginNotDetected, versionMismatch, noChecklistForAircraft, simUnreachable, noNetwork. Actions: `setManualIp`, `clearManualIp`, `retry`, `reload`.
- `ui/connection/widgets/`: a status panel (used on the home screen), a manual-IP dialog (IPv4 validation, clear error text), the "plugin not detected" explanation (how to install, "X-Plane may still be loading"), the "update the plugin" message, the "no checklist for this aircraft" message.
- `ui/home/`: with the network source the screen shows the connection panel and, when the aircraft's checklist is fetched, loads it and navigates to the list as today. A **Reload** action (re-runs the cache comparison) handles an edited checklist while connected, since the plugin does not bump the generation on file edits.
- `ui/checklist_detail/`: when the user opens a checklist, the cubit records it as "last viewed" through the progress repository.
- The restore **popup** ("use saved progress" / "reset"): shown by the home/connection flow as a dialog driven by a cubit state, never from `build()`. `context.mounted` is checked across async gaps.
- Aircraft change while connected: the app informs the user within 3 s with a persistent notice naming the new aircraft and a **Switch** action; it does not swap the checklist silently. The current checklist stays usable, labelled as belonging to the previous aircraft. Switch loads the new checklist and runs the restore rule. The first load after connecting is automatic.

#### 7.5 Package additions

`http`, `shared_preferences`, `path_provider` (all in `ARCHITECTURE.md` section 14), plus possibly a tiny Android-only plugin or platform channel for `MulticastLock`. No other packages; `get_it`, Dio and Retrofit are not used.

#### 7.6 New `AppException` cases (gap-fill, `utils/app_exception.dart`)

`PluginNotDetected`, `PluginVersionMismatch(found, required)`, `PluginUnreachable`, `NoChecklistForAircraft`, `ProtocolError`, `InvalidManualIp`. Each has a human-readable `message`. The type stays sealed, so every `switch` in repositories and cubits must handle them (compiler-enforced).

#### 7.7 Wiring and entry points

- `config/` remains the only place concrete classes are named.
- `main.dart` builds the app from `dependencies_production.dart`; the network source is the only checklist source.

### 8. Progress persistence and the restore rule

Reason (from the architecture): if the app is killed mid-flight the pilot must not lose their place.

#### 8.1 Storage

One JSON file per aircraft path in the app-support directory, named by a hash of the aircraft path. Written after every change (toggle, reset, resetAll, last-viewed). Atomic write. A failed write is logged and surfaced as a non-blocking warning, never a crash and never lost in-memory state.

#### 8.2 Content and matching

- Per checklist (keyed by checklist name): the set of checked item indexes, and a **fingerprint of that checklist's item labels** (gap-fill, Q11), plus the last viewed checklist name, plus a format version, plus `lastConnectedAt` (epoch ms, refreshed about once a minute while connected and set to the last-seen time when the connection is lost).
- "Marks that no longer match the current file are ignored" is implemented as: a checklist's saved marks are applied only if its name exists in the current file **and** its fingerprint equals the current one. Otherwise that checklist starts clean. Indexes are never applied out of range.
- A corrupt, unknown-version or unreadable file is treated as "no saved progress".

#### 8.3 Restore rule (verbatim from the architecture, plus attach semantics)

On connect or aircraft change, once the checklist for the loaded aircraft is parsed, the repository is told `attach(aircraft, document, onGround)`:

1. No saved progress for this aircraft path: start clean, nothing shown.
2. Saved progress exists and **airborne** (`onground_any` = 0): restore silently and reopen the last viewed checklist, whatever the time gap.
3. Saved progress exists, **on the ground**, and either more than **30 minutes** have passed since `lastConnectedAt` (treated as a new flight) or the last checklist in the file (taken to be the shutdown checklist) is **complete**: reset silently. *(Superseded 2026-11-01 by D-35: the restore rule uses the plugin's run id; there is no 30-minute gap and no `NEW_FLIGHT_GAP_MINUTES` any more.)*
4. Saved progress exists, **on the ground**, otherwise: popup "use saved progress" / "reset"; the repository holds the saved state until the user answers, and either answer is persisted.
5. On-ground state **unreadable** (no reply, plugin or X-Plane unreachable): popup, same as 4.

Rule 3's "last checklist in the file" and its meaning are an open item (Q10). The rule is a pure function in the domain (`ProgressRestorePolicy`) returning `restore | reset | prompt | nothing`; the repository executes it; the cubit shows the popup. The decision is therefore unit-testable without a cubit or a sim.

`attach` is idempotent: attaching the same aircraft path while already attached and connected is a no-op, so a polling glitch does not re-run the rule. The rule re-runs on a new connected transition and on aircraft path change only (Q14).
`attach` is idempotent: attaching the same aircraft path while already attached is a no-op. A reconnect with the same aircraft while the app kept running uses a second pure function (`decideReconnect`): a gap up to 30 minutes keeps everything silently (a Wi-Fi drop or sim restart); a longer gap resets on the ground, keeps when airborne, and prompts when on-ground is unknown. The 30 minutes is a named constant, overridable in development with `--dart-define=NEW_FLIGHT_GAP_MINUTES`. *(Superseded 2026-11-01 by D-35: the restore rule uses the plugin's run id; there is no 30-minute gap and no `NEW_FLIGHT_GAP_MINUTES` any more.)* The airborne exception to the gap rule is deliberate: a phone asleep during a long cruise must not lose the pilot's place.

### 9. Mobile and desktop configuration

#### iOS
- `Info.plist`: `NSLocalNetworkUsageDescription` (the local-network permission prompt text) and `NSBonjourServices` only if the prompt behaviour needs it; `NSAppTransportSecurity` with **`NSAllowsLocalNetworking = true`** so cleartext `http://` and `ws://` to LAN IPs work without opening ATS globally, **if** it is needed: `dart:io` sockets may not be subject to ATS at all. checks this on a physical iPhone against `core_test_server`, so it is decided without X-Plane.
- Multicast receive needs the `com.apple.developer.networking.multicast` entitlement, an Apple request. An early test (iPhone 16 / iOS 26.6.2) decided: the beacon arrived without it, so we ship without the entitlement and with manual IP as the fallback. The entitlement is added to `Runner.entitlements` only once approved (an unapproved entitlement breaks signing).
- Test on a physical device. The simulator is not valid for multicast or local-network permission behaviour.

#### Android
- `AndroidManifest.xml`: `INTERNET`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`.
- Cleartext (`http://` and `ws://`): a `network_security_config.xml` permitting cleartext only for private-range addresses (a domain config cannot express CIDR ranges, so if that is not possible the fallback is `usesCleartextTraffic="true"`). Whether `dart:io` is subject to it at all is checked in on the tablet against `core_test_server`; the result is recorded in `Documentation/Architecture/DECISIONS.md`.
- `WifiManager.MulticastLock` acquired while the beacon listener runs, released when it stops (a small plugin or method channel, in `android/`).
- Release builds are tested too (network security config and R8 behave differently from debug).

#### Desktop
- Windows: Windows Firewall may prompt for the app's inbound UDP socket (the beacon listener) (expected, not an error). macOS desktop entitlements `com.apple.security.network.client` / `.server` if macOS desktop is used. Not an acceptance target beyond Windows.

---

## Part C: Live data and auto-check

### 10. Conditions and the plugin

#### 10.1 Condition text (decided by D-48; exact grammar in `GRAMMAR.md`)

- The grammar is the one in `GRAMMAR.md` section 8; this plan does not restate it. It is expected to cover: the three places a condition appears (the tail of an item line, `sw_show`, and `sw_continue`), comparison operators and their tolerance forms, array elements (`name[3]`), `&&`, `||`, grouping, and the literal kinds.
- **Two kinds of comparison (checked in the manual, `XchecklistUserManual.tex` lines 360 to 400, 2026-10-27):**
  - *Plain* comparisons look at the current value only: `:1` (equal), `:!1`, `:<1`, `:>1`, `:<=1`, `:>=1`.
  - *Change-since-activation* comparisons are `:+>n` (grew by more than n), `:-<n` (shrank by more than n) and `:><n` (changed by more than n in either direction), measured **against the value the dataref had when the item was activated**. They are not tolerance tests. The evaluator therefore needs a baseline value per dataref (5.3, 6.6).
- **Numeric equality tolerance (gap-fill):** how equality treats floats is pinned in `GRAMMAR.md` section 8. Until then, float and double values compare within a documented tolerance and integers compare exactly. The rule is one function in `domain/` with table tests.
- **A condition is never partly evaluated.** If any dataref a condition needs is unknown (`unknown_name`, no value yet, stale stream), the whole condition is `unknown`, which counts as "not met". `unknown` never checks an item and never shows or hides one in a way different from its "no condition" behaviour (12.4).
- A line the parser cannot turn into a condition keeps the original behaviour for that item (manual) and adds a warning `Line N: condition not supported: <reason>` to the document warnings, shown in the existing warnings banner. The earlier rule that dataref text is parsed past and dropped is replaced by this: the text is kept, and parsed.

#### 10.2 Plugin changes (additive; protocol stays version 1)

All of these keep v1 valid for an earlier client, so `protocolVersion` stays 1 (the app requires equality). Each gets golden fixtures in `testing/fixtures/protocol/` and a contract case so the Dart fake, `core_test_server` and the real plugin agree (AC-42).

| Change | Why | Where |
|---|---|---|
| Array-index names: a subscribe name may end in `[n]` (`sim/cockpit2/engine/actuators/throttle_ratio[1]`). The shell resolves the base name and reads that element | Conditions use array elements; the name stays an opaque string to the protocol | `plugin/src/xplane` (value source), codec name rules in `core/`, `PROTOCOL.md` |
| Higher per-client subscription cap (from 32 to the value chosen from measurement, expected 128) and the matching `limit` golden | A real checklist can need more than 32 names: the largest checklist in a large real 737 file needs about 51, so 128 gives about 2.5x headroom for one open checklist. It does not cover a whole file (about 440), which is why only the open checklist is subscribed (D-52) | `plugin/src/core` stream module, `PROTOCOL.md` limits table |
| Kinds beyond float (int, double, int and float arrays) delivered as JSON numbers | The grammar compares all of them | `plugin/src/xplane` value source |
| Strings and byte arrays, only if measurement shows they fit | Optional; otherwise unsupported conditions stay manual | A frame extension is a protocol change: it is decided and recorded in `Documentation/Architecture/DECISIONS.md` before any code |
| A rate honoured as requested up to 60 Hz, and `values` frame coalescing measured at load | The user selects the rate (section 14) | `plugin/src/core` rate limiter (exists), flight-loop interval (exists: follows the fastest subscription) |

The stream protocol's other rules are unchanged: server threads never call XPLM, a subscribe is answered after the next flight-loop tick, `unknown_name` is deterministic, a closed connection ends its subscriptions at once, a value frame is sent every tick whether or not the value changed.

#### 10.3 Subscription management (gap-fill)

- `FlightSimRepository` owns the stream subscriptions; no cubit sees ids. A cubit asks for `watch(names, ...)` and gets values back.
- Names are reference-counted: two items on the same dataref use one subscription. When the last user of a name goes away (the pilot leaves the checklist) the repository unsubscribes after a short delay, so moving between two checklists that share names does not churn.
- A name the plugin answers `unknown_name` for is remembered as unavailable for the rest of the connection, not retried every tick, and reaches the evaluator as `unknown` (not met), never as a crash.
- On reconnect the repository resubscribes the whole current set (exists for the two fixed signals; extended to the dynamic set).
- The aircraft-generation and on-ground subscriptions are unchanged and always on.

#### 10.4 Findings from the early experiments

- **The grammar was pinned against the real parser, plugin and checker** by hand-written test checklists (`testing/fixtures/conditions/`, each with a values file and an expected-results file). Two plan assumptions turned out wrong: `sw_show` is a condition on a whole checklist that pops it up, it does not hide items (later not supported at all, D-70), and a missing dataref reads as 0 in the plugin, not unknown. The result is `Documentation/Reference/GRAMMAR.md` section 8.
- **Subscription scale.** A large real aircraft file has 54 checklists and about 440 distinct datarefs in total, so a whole file is far above any sensible cap, and only the open checklist is subscribed (D-52). In the 27 surveyed files the largest single checklist needs 62 signals, 24 of 636 checklists exceeded the old cap of 32, and the cap became 128 (D-66). Measured cost: 100 subscriptions at 10 Hz average 44 microseconds per flight-loop tick against a 1 ms budget.
- **Rate.** The delivered rate holds at the sim's frame rate; the low-frame-rate case was not pursued (`Documentation/TODO.md`).

### 11. Domain model and evaluation

All pure Dart plus `equatable`, in `domain/`, per `ARCHITECTURE.md` section 5. Placeholder files named there are filled in; no new folders.

#### 11.1 Models (`domain/models/flight_sim/`)

- `dataref.dart`: `Dataref` (name, optional array index). The wire name is built in one place.
- `dataref_value.dart`: `DatarefValue` (the number or text, sample time) and an `unknown` shape.
- `item_condition.dart`: a sealed expression tree: comparison of a dataref against a literal (operator, operand, tolerance where the grammar has one), `and`, `or`, `not` if the grammar has it, and a `ConditionUnsupported(reason)` leaf the parser never emits into a live condition (it produces a warning and no condition instead). The exact node set comes from `GRAMMAR.md` section 8.
- `connection_status.dart` already exists.

#### 11.2 Fields on the checklist models (`domain/models/checklist/`)

Additive fields, no new files except where noted:

- `ChecklistItem.condition` (`ItemCondition?`): when it is met the item is complete.
- ~~`ChecklistItem.showWhen`~~ **Dropped by D-70:** `sw_show` is ignored, there is no show field.
- A continue link carries an optional `ItemCondition` (`ContinueLink.condition`).
- `ChecklistDocument` exposes `signalsFor(Checklist)`: the ordered distinct set of `Dataref`s that checklist's conditions, show-conditions and continue conditions need (a pure function, used by the cubit to ask the repository for values).

The original parser tests, the `ChecklistSequence.ordered` helper and the fingerprint (`fingerprintOf`) are unchanged in behaviour; the fingerprint continues to cover item labels only, so adding a condition to a file does not drop saved marks (a label change still does).

#### 11.3 Evaluator and use case (`domain/use_cases/autocheck/`)

- A pure `evaluate(ItemCondition, ValueLookup, BaselineLookup) -> Tri` where `Tri` is `met | notMet | unknown`. No clock, no I/O. `BaselineLookup` supplies the value a dataref had when the item was activated (12.6); a change-since-activation comparison with no baseline is `notMet`, as the manual says it is on the first check.
- `EvaluateItemConditionsUseCase`: input is the checklist, the latest values and the current `ChecklistProgress`; output is an `AutoCheckResult` listing items to auto-check, items now visible or hidden, and a continue suggestion if one holds. It is a pure function over plain values, like `ProgressRestorePolicy`: the cubit supplies values, the repository executes the result. This keeps the rule unit-testable without a cubit or a sim, and keeps `domain/` free of repository imports (the architecture's flow diagram shows the use case between the repositories; here the cubit does the wiring and the use case is the rule).
- Where the evaluator needs "the first time the condition became true" (the suppression rule in 6.2), it is given the previous result by the caller; it holds no state.

### 12. Auto-check semantics

These rules are the user's decisions (D-50): auto-check is a helper, not the driver.

#### 12.1 One direction only

- A met condition **checks** an item. Nothing in the app ever **unchecks** because a condition stopped holding. Many checklist conditions are transient (a warning light that comes on and goes off), so a condition seen true once is enough.
- Only items whose `condition` is met are auto-checked. Notes are never checked.

#### 12.2 Manual wins

- Each checklist item carries, besides `checked`, two marks in `ChecklistProgress` (gap-fill): `autoChecked` (the last change was made by the evaluator, so the UI can show it and a reset can clear it) and `manuallyUnchecked` (the pilot unchecked it by hand).
- Tapping a checked item unchecks it and sets `manuallyUnchecked`. An item with `manuallyUnchecked` is **never auto-checked again** until its checklist is reset (`reset`, `resetAll`, or an `attach` that resets). The pilot can still check it by hand, which clears `manuallyUnchecked`.
- Tapping an unchecked item checks it by hand (not `autoChecked`).
- An auto-checked item that the pilot unchecks follows the same rule: it stays unchecked.

#### 12.3 Only on trustworthy data

- Auto-check runs only while the connection is `connected`, the stream is not stale (3 s without a frame is stale), and every dataref the condition needs has a value. Anything else is `unknown`, which is "not met".
- A connection that is lost freezes auto-check; marks stay and keep being saved (as in AC-27). On reconnect, evaluation resumes from the current values; there is no replay of what was missed.
- Restored progress (the restore rule) is applied first; evaluation then runs on top and may check more items, never fewer.
- Auto-check evaluates only the checklist the pilot has open (13.2), plus nothing else.

#### 12.4 Show conditions and continue

- **Amended (2026-11-04):** `sw_show` does not hide items. It is a condition on the whole checklist; the real plugin pops the checklist up when it holds (`GRAMMAR.md` 8.6). The app marks such a checklist *suggested* in the list and opens nothing by itself; every item always counts. The two bullets below describe the old reading and are replaced after the user confirms.
- ~~**`sw_show` (old reading):** the item is hidden when its `showWhen` is `notMet` and shown when `met`. `unknown` shows the item (a missing value must not hide something the pilot needs; gap-fill, Q18). A hidden item is not auto-checked. Progress already recorded on a hidden item is kept.~~ **Dropped by D-70.**
- ~~**Hidden items and completion (D-54):** a hidden item does not count toward done/total. A checklist is complete when every *visible* check item is checked, so the pilot is done when all the other items are complete, whatever is hidden.~~ **Dropped by D-70:** no item is hidden.
- **How `sw_continue` really works (verified 2026-10-27 in the manual, `ChangeLog.txt` 1.12, 1.16, 1.26, 1.27, and the plugin source `parser.cpp`, `Xchecklist.cpp`):**
  - The `sw_continue` lines of a checklist are collected into one ordered list. **Their position among the items does not matter.** There is no "return to the next item": a `sw_continue` in the middle of a checklist does nothing at that point. The checklist's items all run first, and the list is looked at once, when the checklist is finished.
  - At that moment the links are tried **from top to bottom and the first one that has no condition, or whose condition is true, is followed**. If none matches, the plugin stays on the page.
  - Conditions are checked only at that moment, so the change-since-activation operators (`+>`, `-<`, `><`) can never be true there; the manual says so.
  - A conditional detour rejoins the main flow because the **target page ends with its own `sw_continue`** to the next page. Example, `ATR42_clist.txt`: the conditional link at line 339 jumps from one page to `PUSHBACK/STARTUP`, skipping `RIGHT ENGINE START`, and the pages `RIGHT ENGINE START` (line 393) and the others each end with a `sw_continue` of their own.
  - Corpus check (27 files): 521 `sw_continue` lines, 44 of them conditional, and **none is followed by an item or note**. They are all at the end of their checklist. The rule F3 (warn when a `sw_continue` is not at the end, keep the link and the items) is therefore right, and nothing more is needed for the middle case: it behaves exactly like one at the end.
- **What the app does (D-53, D-56):**
  - The links are evaluated **once, at the moment the checklist becomes complete** (and once when a checklist that is already complete is opened). Top to bottom; the first link with no condition, or with a `met` condition, is the result. `unknown` is not a match.
  - The result is kept (latched) until the pilot follows it, resets the checklist, or leaves it. It is not re-evaluated every frame, because the plugin does not either and because a transient condition must not make the button flicker.
  - **Default (`autoContinue` off):** a persistent "Continue: <checklist name>" button; nothing navigates by itself (helper, not driver). Tapping it opens the target.
  - **Option on:** the app navigates to the target by itself, once per completion (no loop if the pilot goes back), like the real plugin.
  - An unconditional link is the same rule with no condition, as before.

#### 12.5 Persistence

`autoChecked` and `manuallyUnchecked` are saved with the rest of the progress (storage format version 2, one file per aircraft). A version 1 file loads with both sets empty; an unknown version is "no saved progress" as before. The fingerprint rule applies to both sets.

#### 12.6 Baselines for change-since-activation conditions (gap-fill, Q25)

~~The real plugin works through a checklist one item at a time and captures the baseline when an item becomes the current one. The app shows every item at once and the pilot may check them in any order, so there is no "current item".~~ **Superseded by D-71 (2026-11-05):** the app now keeps a cursor and a pointer item and takes the baseline when an item becomes the pointer.

- **Default:** the baseline of a dataref is its value at the first frame seen after the checklist is opened (or after it is reset). An item with a change-since-activation condition is checked when the value then moves by more than the amount, in the stated direction.
- Baselines live in the detail cubit's session (not persisted); a restart takes new baselines. This is cheap and keeps the use case pure.
- A different rule (baseline when the previous item is checked, as the plugin does) is possible by changing what the cubit passes in; the evaluator does not change. Q25 is decided by the parity run.
- ~~The real plugin also auto-checks only the current item, in order. The app checks any item whose condition holds. This is a deliberate difference (the pilot is not forced into file order) and it is the main thing the parity run (AC-47) compares.~~ **Superseded by D-71:** the app now also checks only the pointer item, in order.

### 13. App side of auto-check

All of this follows `ARCHITECTURE.md` sections 5 to 9.

#### 13.1 Services and repositories

- `data/parsers/`: `XChecklistTextParser` is extended, not replaced. The condition text is handed to a new pure `ConditionExpressionParser` (`data/parsers/condition_expression_parser.dart`, no I/O) that returns an `ItemCondition` or a reason string. File-format knowledge stays in `data/parsers/`; the tree it builds lives in `domain/`.
- `data/repositories/flight_sim/flight_sim_repository.dart` (abstract) gains `Stream<Map<Dataref, DatarefValue>> watch(Set<Dataref>)`-style access (exact shape in the task list) and a way to read the current rate option. `FlightSimRepositoryRemote` implements it with the reference counting of 4.3 and the throttle seam, **inside the repository** (never in a widget or cubit): values are coalesced to the selected rate, latest wins, before they reach a cubit. `FlightSimRepositoryLocal` implements the same interface with scripted and simulated values.
- `data/services/flight_sim/`: `FlightSimConnectionService` already speaks subscribe, unsubscribe and the stale rule; it is extended for a dynamic subscription set and the larger cap. No new service folder.
- `data/repositories/settings/`: `SettingsRepository` gains the options mechanism (section 14).
- `data/repositories/checklist/checklist_progress_repository(_impl).dart`: gains `autoCheck(checklistName, indexes)`, and `toggle` is extended with the `manuallyUnchecked` rule. The `AttachOutcome`/restore rules are unchanged.

#### 13.2 Cubits and screens

- `ChecklistDetailCubit` (existing) takes `FlightSimRepository` and the use case. On open it asks the document for `signalsFor(checklist)`, calls `watch`, and on each throttled batch calls the use case and writes the result to the progress repository. On close it releases the names. Auto-check therefore runs only for the open checklist (D-52): the list screen's counts for other checklists change only when they are opened. The cubit never sees sockets, ids or the rate.
- The detail screen shows an auto-checked item with a small distinct marker and the same tap behaviour as any item (12.2); hidden items (`sw_show`) are not built. A "Continue" action appears per 12.4.
- A short notice on the detail screen when some of the checklist's conditions cannot be watched (unknown names, or the subscription cap): "N items stay manual". It uses the existing warning/banner widgets from `ui/core/widgets/`.
- The connection panel and banner are unchanged. A stale or lost stream already shows its message there; the detail screen adds nothing for it.
- `HomeCubit` is unchanged.
- No screen for options (section 14).

#### 13.3 Wiring

- `dependencies_development.dart`: `network` and `fake` wire the extended `FlightSimRepository` (Remote and Local) and `SettingsRepositoryImpl` with the options. `file` and `sample` provide no flight sim and behave as before; auto-check does nothing for them.
- `dependencies_production.dart` wires the network source, discovery, the plugin session, the cache and the settings (D-69).

### 14. User options and the stream rate

The stream rate is a user-selectable option. The mechanism and the default come first, and the options screen only adds a screen on top (D-49).

- **A general options mechanism, not a rate setting (gap-fill).** `SettingsRepository` exposes an immutable, equatable `UserOptions` value and a stream of it, plus `update(...)`. Each option has a typed field, a default, a valid range and a stored key. New options (later: voice settings, auto-continue, theme) add a field and a key; nothing else changes. The repository clamps and defaults on read, so a corrupt or out-of-range stored value never reaches the rest of the app.
- **Storage:** `PreferencesService` writes one key per option. The existing manual-IP setting stays where it is; moving it into `UserOptions` is allowed if it simplifies the code but is not required.
- **The first options:**
  - `streamRateHz`, an integer, range 1 to 60 (the protocol's cap), **default 10**. The default lives in one named constant in the repository layer.
  - `autoContinue`, a boolean, **default false** (show the Continue button; true navigates by itself, 6.4).
- **Who reads it:** `FlightSimRepositoryRemote` depends on the abstract settings source (a stream of options, wired in `config/`) and applies the rate to every condition subscription. A change re-subscribes the current set at the new rate without dropping the connection. The two fixed signals keep their own fixed rates (1 Hz and 2 Hz).
- **Throttling stays in the data layer.** If the plugin delivers faster than the selected rate (it should not), the repository coalesces; cubits and widgets never see more than one batch per interval.
- **Without the screen:** the options can be changed in development by `--dart-define=STREAM_RATE_HZ=<n>` and `--dart-define=AUTO_CONTINUE=true|false` (read in `config/`, passed through `update`), and in tests through the fake settings repository. Nothing else in the app depends on the screen existing.
- **Bounds:** values outside 1 to 60 are clamped with no error. Measurement may lower the default; it does not change the mechanism.

---

## All parts: testing, acceptance, risks, open items

### 15. Testing strategy

#### 15.1 Layers of test

| Level | What | Needs |
|---|---|---|
| Parser unit tests | minimal valid file counts, labels and results; menu text versus name; CRLF and BOM; leading `@` and extra spaces; an item with no `|`; an item with a dataref suffix; `sw_itemvoid` as a note; an item before any checklist; an unknown keyword; empty and comment-only files; a very long label | `flutter test` |
| Grammar tests | `ConditionExpressionParser`: every condition fixture, every malformed form, every census form; warning text | `flutter test` |
| Evaluator tests | `evaluate` over the fixtures' `*.values.json` and expected results; tolerance table; `unknown` propagation through `and`/`or` | `flutter test` |
| Use case tests | Table tests for `EvaluateItemConditionsUseCase`: check, never uncheck, manual wins, continue suggestion | `flutter test` |
| Plugin core unit tests | cache, JSON output, ETag formatting, mtime rule, address filter, request routing and method/path rules, 413/404/304 behaviour; array-index names, cap and `limit`, rate limiter at 60 Hz, kinds as JSON numbers | C++ compiler, no X-Plane |
| Plugin stream tests | Subscription table, rate limiter, expiry, codec and caps with an injected clock; loopback WebSocket tests against `core_test_server` with a fake `ValueSource` | C++ compiler, no X-Plane |
| Protocol contract tests | One script drives any server implementation (the real plugin, `core_test_server`, or the Dart fake) with the same HTTP and stream cases and compares to shared golden responses | Dart |
| Dart service tests | `CompanionPluginService`, `FlightSimConnectionService`, cache and storage services over real loopback sockets/HTTP and a temp directory | `flutter test` |
| Repository tests | mapping, plugin-not-detected rule, race rule, cache decision, restore execution, persistence, corrupt files; progress `autoCheck`, `manuallyUnchecked`, persistence format 2, loading format 1, fingerprint interplay | fakes |
| Flight sim repository tests | reference counting, throttle to the selected rate, rate change, `unknown_name` memory, reconnect resubscribe, stale freeze | fake transport and fake clock |
| Cubit tests (`bloc_test`) | connection states, manual IP, popup flow, home flow with `attach`; detail cubit with a scripted fake sim: open, values, auto-check, manual uncheck, close | fake repositories |
| Widget tests | the detail screen renders notes without checkboxes; tapping a row updates the progress count; connection panel, manual IP dialog, popup, messages, auto-checked marker, continue action, "N items stay manual" notice; no `build()`-time async | fake repositories |
| Real-sim tests | everything marked **SIM** below | X-Plane and devices |

#### 15.2 Fakes and fixtures (in `testing/`, per the project convention)

- `testing/fakes/plugin/fake_companion_plugin_server.dart`: a Dart `HttpServer` on loopback, ephemeral port, implementing the section 5.4 contract: aircraft JSON, checklist bytes, ETag and `If-None-Match` to `304`, `404` (no checklist), `413`, `405`, `Last-Modified`, `X-Aircraft-Generation`. Scriptable: change aircraft (bumps generation), edit the file (new mtime/size, same generation), delay or drop responses, return malformed JSON, wrong `protocolVersion`, change aircraft between the two requests (race rule), restart (port changes). It also serves `/v1/hello` and the `/v1/stream` WebSocket per section 5.3 (scripted values, `unknown_name`, `limit`, heartbeat, dropped connection, restart on a new port, a refused fifth client), with array-index names, kinds and the larger cap mirroring the plugin. It is the specification of the stream.
- `testing/fakes/plugin/fake_beacon_sender.dart`: builds and emits `BECN` packets into the listener's injectable datagram stream. Multicast itself is not exercised in unit tests: the decoder and selection logic are tested and the group join is a SIM test.
- `testing/fixtures/protocol/`: the golden JSON and header examples. The **same files** are used by the Dart fake's tests and by the plugin core tests, so the two implementations cannot drift apart silently.
- `testing/fixtures/conditions/`: the condition checklists with their values and expected-results files. They are the specification of the grammar's behaviour, in the way `testing/fixtures/protocol/` is the specification of the wire.
- `testing/fakes/repositories/`: fake `FlightSimRepository` (scriptable, feeds value maps on a fake clock), `SettingsRepository` with the options, extended fake progress repository.
- `testing/fakes/services/`: fake `PluginSessionSource`, in-memory cache and storage services.

#### 15.3 What needs a real sim (SIM)

Multicast on real networks and phones (iOS prompt, Android lock); the plugin inside X-Plane (XPLM calls, flight loop, dataref reads by kind and index, aircraft and livery change, clean shutdown, coexistence with the real XChecklist plugin); the on-ground dataref values in flight; the stream rate and gaps at the selected rates over Wi-Fi; flight-loop cost under load; auto-check of a real aircraft's checklist while operating switches in the sim; the comparison of our evaluator with the real XChecklist plugin on the same aircraft. **DEV** (device, no X-Plane, against `core_test_server`): cleartext `http://` and `ws://` on the tablet and iPhone, the Windows Firewall behaviour of the core test server, and the stream rate over Wi-Fi. Release builds on devices need the real plugin. These are recorded, dated, in `Documentation/Testing/MANUAL_TEST.md`.

#### 15.4 Rules

Test-first (red, green), one commit per task, `tools/verify.sh` green after every task, shared fakes in `testing/`. Coverage gates cover the parser, the domain, the repositories, the cubits, the evaluator, the use case, the condition parser and the extended repositories (`tools/check_coverage.sh`). Each acceptance criterion gets a tagged automated test (`// AC-n`) where automation can reach it; `tools/check_acceptance_tags.sh` checks them. SIM-only criteria are tagged in the manual test file instead.

#### 15.5 Mapping of risky behaviours to tests

| Behaviour | Test |
|---|---|
| Cache hit, no body fetched | service test over fake server: second `load()` sends no `GET /v1/checklist` |
| Older file (restored backup) refetches | fake server mtime goes down, expect refetch |
| `304` keeps cache | `If-None-Match` sent, `304`, cached text returned |
| Race between aircraft and checklist | fake server changes aircraft between requests, expect restart then success |
| Plugin absent | no port in the range answers `/v1/hello`, expect `pluginNotDetected` within 2 to 3 s (fake clock) |
| Wrong protocol version | `/v1/hello` with another version gives `versionMismatch`, no `/v1/aircraft` or stream request |
| Stale stream, sim restart | fake drops the connection, service reconnects with back-off and resubscribes; 3 s of silence marks stale |
| Subscription caps | fifth client gets 503, 33rd subscription gets `limit` (cap now 128, section 10.2) |
| Path traversal and non-GET | contract test: `/v1/checklist/../..`, `?path=`, `POST`, `PUT` return 404/405, never file contents |
| Corrupt cache or progress file | treated as miss, no throw |
| Changed checklist file vs saved marks | fingerprint mismatch drops that checklist's marks only |
| Restore rule, all five branches plus idempotent attach | pure policy table test, then repository and cubit tests |
| Unknown signal or dataref never checks | `error` `unknown_name` reaches the repository as an unavailable value, not a crash; evaluator test; cubit test |
| A transient condition (true then false) leaves the item checked | use case table test: met, then notMet, mark stays |
| Manual uncheck is respected | use case and repository tests: unchecked item with a met condition is not re-checked until reset |
| Manual check clears the suppression | repository test |
| Stale stream freezes evaluation | repository test on a fake clock; cubit test |
| Same dataref in two items uses one subscription | repository test counting subscribe frames on the fake server |
| Leaving a checklist releases names | repository test: unsubscribe after the delay |
| Rate option clamps and re-subscribes | options test; repository test with a changed stream |
| Subscription cap reached | repository test: the extra names stay manual and the notice shows |
| Condition on an array element | grammar fixture, evaluator test, plugin core test, contract case |
| Progress file format 1 | storage test loads it with empty new sets |
| Restore then evaluate | repository test: restored marks stay, evaluation only adds |
| Production wiring | gate scripts and a wiring test for `dependencies_production.dart` |

### 16. Acceptance criteria

Tags: **[A]** automated, **[SIM]** needs X-Plane and/or devices, **[retired]** no longer applies. `tools/check_acceptance_tags.sh` reads this section: every **[A]** criterion needs a test tagged `// AC-n`, every **[SIM]** one needs a line mentioning it in `Documentation/Testing/MANUAL_TEST.md`.

**Checklist viewer (AC-1 to AC-6)**

1. **AC-1 [A]** A checklist file shows all of its checklists with correct titles.
2. **AC-2 [A]** Every item shows its label and result, and notes show as headers.
3. **AC-3 [A]** Tapping toggles items, and progress and reset work.
4. **AC-4 [A]** Dataref text in the file never appears on screen.
5. **AC-5 [A]** A malformed file never crashes the app, and the app reports what was skipped.
6. **AC-6 [A]** All parser tests pass.

*AC-1 to AC-6 were first checked by hand on a real aircraft file. That step is retired, because the app no longer opens files; the automated tests, which read fixtures directly, remain (`Documentation/Testing/ACCEPTANCE.md`).*

**Connection and companion plugin (AC-7 to AC-30)**

7. **AC-7 [SIM]** With the sim running the plugin on the same Wi-Fi, the app on desktop and on a phone shows the sim's IP without any typing within 10 s (where multicast is available; iOS may be manual-only per the early measurements).
8. **AC-8 [A + SIM]** Manual IP works with multicast unavailable: an invalid address is rejected with a clear message, a valid one connects, and it is remembered after restart. Clearing it returns to automatic discovery.
9. **AC-9 [A + SIM]** With the sim running and no plugin (no port in the range answers `/v1/hello`), the app shows "plugin not detected" within 3 s of reaching the sim, never crashes, and recovers by itself when the plugin appears.
10. **AC-10 [A]** A protocol version other than 1 in `/v1/hello` shows "update the plugin" and makes no further request (no `/v1/aircraft`, no stream).
11. **AC-11 [A + SIM]** The loaded aircraft's ICAO and description are shown. When another aircraft is loaded in X-Plane, the app informs the user within 3 s, names the new aircraft, and leaves the current checklist usable; Switch loads the new checklist.
12. **AC-12 [A + SIM]** The checklist shown for an aircraft equals what the parser produces from that aircraft's `clist.txt` read directly (compare to the parse of the same file).
13. **AC-13 [A + SIM]** Cache: reconnecting with an unchanged checklist file transfers no checklist body; a changed file (newer or older mtime, or different size) is refetched; Reload picks up an edit made while connected.
14. **AC-14 [A + SIM]** An aircraft without a checklist file shows "no checklist for this aircraft" and the app stays usable.
15. **AC-15 [A]** Cache and progress files that are corrupt, truncated or from an unknown version are ignored without a crash or an error screen.
16. **AC-16 [A + SIM]** Airborne with saved progress: killing and relaunching the app restores the marks and reopens the last viewed checklist silently.
17. **AC-17 [A + SIM]** On the ground with saved progress and the shutdown checklist (per Q10) complete: progress is reset silently.
18. **AC-18 [A + SIM]** On the ground with saved progress otherwise: the popup appears; "use saved progress" restores, "reset" clears, and the choice persists.
19. **AC-19 [A]** On-ground state unreadable: the popup appears.
20. **AC-20 [A]** Saved marks for a checklist whose items changed are dropped for that checklist only; other checklists keep their marks; counts are never out of range.
21. **AC-21 [retired]** The file and sample sources no longer exist, so their behaviour is no longer a criterion. AC-1 to AC-6 still pass through the network source.
22. **AC-22 [A + SIM]** Plugin security: only `GET` (and `HEAD`) on the two endpoints work; traversal-style URLs and query parameters never return file contents; non-private source addresses are refused (address filter unit-tested; observed on the LAN where possible); the plugin opens only the current aircraft's `<acf name>_clist.txt` or `clist.txt`.
23. **AC-23 [SIM]** Release builds on one iOS and one Android device reach the sim over cleartext LAN `http://` and `ws://` and (Android) receive the beacon with the multicast lock.
24. **AC-24 [SIM]** Plugin health: loads on XP12 with clean `Log.txt`; flight-loop cost averages under 1 ms; X-Plane exits cleanly; coexists with the real XChecklist plugin loaded at the same time.
25. **AC-25 [A]** Architecture gates: `check_layers`, `check_structure` and `check_temporary_isolation` pass; no `dart:io` socket or `package:http` use outside `data/services/`; no UDP/socket code in any widget.
26. **AC-26 [retired]** *(retired when the project moved to its public repository: the early experiment write-ups are not published. The conclusions are in `Documentation/Architecture/DECISIONS.md`.)*
27. **AC-27 [A + SIM]** The app informs the user when the network is lost ("No network connection") and when X-Plane is not answering ("X-Plane is not responding", with the last seen time), on the home, list and detail screens. The checklist stays usable and marks keep being saved; the message clears on recovery; a recovery with the same aircraft does not re-run the restore rule or show a popup. Verified by switching the phone's Wi-Fi off, and by quitting X-Plane, while a checklist is open.
28. **AC-28 [A + SIM]** New-flight gap: after more than 30 minutes without a connection (app restart or a long drop), saved progress is reset silently when on the ground, kept when airborne, and prompts when on-ground is unknown. Within 30 minutes a drop or sim restart with the same aircraft keeps the marks. SIM check uses `--dart-define=NEW_FLIGHT_GAP_MINUTES=1`. *(Superseded 2026-11-01 by D-35: the restore rule uses the plugin's run id; there is no 30-minute gap and no `NEW_FLIGHT_GAP_MINUTES` any more.)*
29. **AC-29 [A]** Stream contract: the handshake, subscribe, `unknown_name`, `limit`, `unsupported`, heartbeat, disconnect on close and the client cap give the same answers from the Dart fake, `core_test_server` and (SIM) the real plugin, from the shared cases.
30. **AC-30 [SIM]** The on-ground value reaches the app through the real plugin on XP12: 1 parked, 0 airborne, and the app's restore rule uses it.

**Live data and auto-check (AC-31 to AC-57)**

31. **AC-31 [A]** Grammar: every fixture checklist in `testing/fixtures/conditions/` parses to the conditions its expected-results file describes, and every malformed fixture produces the documented warning and leaves the item manual.
32. **AC-32 [A]** Evaluator: for every fixture values file, the set of met items equals the expected-results file, including tolerance forms, arrays, `&&`, `||` and grouping.
33. **AC-33 [A + SIM]** With the sim running and a real aircraft's checklist open, operating a control in the sim that satisfies an item's condition checks that item (the item the pointer is on, D-71) within two stream intervals of the selected rate, and the item is shown as auto-checked.
34. **AC-34 [A]** Auto-check never unchecks: a condition that turns true and then false again leaves the item checked. A pilot who ticks an item by hand while its condition is false gets a red warning dialog that needs an acknowledge press, and the item keeps a red mark (D-71).
35. **AC-35 [A + SIM]** Manual wins: an item the pilot unchecks stays unchecked while its condition is met, until the checklist is reset; checking it by hand clears the suppression. *(Amended by D-71: an unchecked item behind the pointer is never ticked again by auto, and a manual untick does not move the pointer. The cursor follows the pilot's ticks, forward or back.)*
36. **AC-36 [A]** An unknown dataref, a missing value, a stale stream or a lost connection never checks an item. Marks stay and keep being saved while the connection is lost.
37. **AC-37 [retired]** *(retired by D-70, 2026-11-05: `sw_show` is not supported and the parser ignores it like a comment. There is nothing to test but that a `sw_show` line gives no warning and no effect, which the parser tests do.)*
38. **AC-38 [A + SIM]** Conditional `sw_continue`: the links are evaluated once, when the checklist becomes complete (and once when opened already complete), top to bottom, and the first link with no condition or a met condition is offered as "Continue: <name>"; nothing navigates by itself (default). A `sw_continue` placed before the last item behaves exactly like one at the end. With the `autoContinue` option on, the app navigates to the target once per completion. Verified on the ATR42 conditional links with scripted values.
39. **AC-39 [A]** The stream rate is a user option with a default of 5 Hz, clamped to 1 to 60, persisted, observable, and applied by the repository to all condition subscriptions; changing it re-subscribes without dropping the connection. No cubit or widget handles the rate or a throttle.
40. **AC-40 [A]** The options mechanism is general: `autoContinue` was added as a second option with only a field, a default, a range and a key, and a test shows a third (throwaway) option needs nothing else; a corrupt stored value yields the default.
41. **AC-41 [A]** Subscriptions: the same dataref in several items uses one subscription; leaving the checklist releases its names; a reconnect resubscribes the current set; names the plugin rejects are not retried every tick.
42. **AC-42 [A]** Protocol: the new array-index, kind and cap cases give the same answers from the Dart fake, `core_test_server` and (SIM, task) the real plugin, from the shared cases. `protocolVersion` is still 1 and an earlier client still works against the new plugin.
43. **AC-43 [A]** Progress persistence: `autoChecked` and `manuallyUnchecked` survive an app restart; a format 1 file loads as before with both empty; corrupt files are ignored; the fingerprint rule applies to both sets.
44. **AC-44 [A]** Restore then evaluate: after the restore rule runs, evaluation only adds checks; it never removes a restored mark.
45. **AC-45 [A + SIM]** Subscription scale: a checklist whose names exceed the plugin's cap keeps the extra items manual and shows the "N items stay manual" notice; a normal checklist subscribes fully at the default rate with the flight-loop average under 1 ms.
46. **AC-46 [SIM]** Rate: the app receives batches at the selected rate at the default rate over Wi-Fi to the tablet, with the largest real checklist open; the measured gaps are recorded (no stress test at higher rates: amended 2026-11-04, a checklist is not an instrument).
47. **AC-47 [SIM]** Parity: on one real aircraft, the set of items our app auto-checks for a scripted sequence of sim states matches the set the real XChecklist plugin shows as complete, or every difference is explained in the manual test file.
48. **AC-48 [A]** Viewer and connection behaviour holds: AC-1 to AC-6 (through the network source), AC-10 to AC-15, AC-20 and AC-27 to AC-29 still pass.
49. **AC-49 [A]** Production wiring: no `temporary/` folder, no `file_picker` and no bundled sample remain; `main.dart` runs through `dependencies_production.dart`; `check_layers`, `check_structure` and `check_temporary_isolation` pass.
50. **AC-50 [SIM]** The production build starts on Windows and on one phone, finds the sim, loads the checklist and auto-checks an item, with no development flag.
51. **AC-51 [A]** Architecture gates: no `dart:io` socket or `package:http` use outside `data/services/`; no stream, socket or throttle code in any widget; `domain/` imports only Dart core and `equatable`.
52. **AC-52 [A]** `Reference/GRAMMAR.md` section 8 has no rule without a status and evidence. *(The earlier part of this criterion, that early experiment write-ups exist with measured numbers, was retired when the project moved to its public repository: the write-ups are not published.)*
53. **AC-53 [A]** Plugin health (no regression): loads on XP12 with a clean `Log.txt`, exits cleanly, coexists with the real XChecklist plugin; macOS and Linux still compile in CI.
54. **AC-54 [A + SIM]** Switches (D-82, `GRAMMAR.md` section 5b): `sw_switch:Label|id|ON/OFF` shows a switch row with a check circle (counted, skippable; auto-check stops at it until the pilot ticks it; its tick and its switch are separate); the items before `sw_else` are shown while the switch is on and the items after it while it is off, and the items of the other branch are hidden (not shown, not counted, passed over by Check, Skip and auto-check, not part of completion); blocks written `sw_if|id|ON/OFF` in any checklist follow the same switch and show no row; moving the switch swaps the branches, changes the total and clears the marks of the items it hides; Reset keeps the position, a reset of every checklist puts it back to the default; the position is saved with the progress.
55. **AC-55 [A]** Lookup tables, the parsing part (D-83, `GRAMMAR.md` section 5c): `sw_table`, `sw_row` and `sw_table_end` define a table whose input columns are datarefs or expressions of datarefs and whose rows form a complete grid; the table adds no item and no checklist and is never shown; `sw_calculate:table|column|label|unit|step` attaches to the check item above it (details lines may stand between) and keeps that item's gate and condition; a bad start line, a row with the wrong count, a grid with a missing or doubled point, an unclosed table, an unknown table or column and a `sw_calculate` under no check item each give the documented warning and break nothing else.
56. **AC-56 [A]** Lookup tables, the value (D-83, `GRAMMAR.md` L7 to L9): a `sw_calculate` line's value is the multilinear interpolation of its table at the current values of the input sources (a dataref or an expression of datarefs); an input beyond the table is held at the edge and flagged; an input with no value, a link that is down or stale, or an unknown column gives no value; the value is rounded to the line's step; the input datarefs are watched exactly while the checklist is open; the detail rows carry the values and emit again only when a rounded value changes.
57. **AC-57 [A + SIM]** Lookup tables, the display (D-83, `GRAMMAR.md` L10): the `sw_calculate` lines of an item are shown in a band under it that is not an item (the total and the completion do not change, a tap on it ticks nothing); a warning on an amber pill with the caution icon comes first for each input beyond the table, naming the input with its label and unit, the limit and the value used; the first line is large and the others are rows; a line with no value shows `no data`; and in the sim the values follow the aircraft (altitude, outside temperature, weight).
58. **AC-58 [A]** Challenge rows, the parsing part (D-84, `GRAMMAR.md` section 5d): `sw_challenge: ON` and `sw_challenge: OFF` make the rows between them challenge rows (check items, notes, headings, details and switch rows) and every other row a flow row, the lines themselves make no item, the value and keyword ignore case, a block left open ends at the next checklist or the end of the file, a stray OFF, a nested ON, a bad value and a line before any checklist each warn and change nothing, a block that crosses a switch block is closed at the boundary, and the `sw_continue` look-ahead skips the line.
59. **AC-59 [A]** Spoken answers (D-84): a phrase is read after dropping case and punctuation; `check`, `set`, `on`, `off`, `closed` and the item's own result are answers, `skip` skips, `pause checklist` (also `hold` or `stop`) pauses, `resume checklist` (also `continue`, `unpause` or `start`) resumes, `yes` and `no` answer a question, and a bare `continue` or `pause` is not a command; a phrase within one slip (a word of up to five letters) or two (a longer one) of any of these, and of at least three letters, is a close match that names what it would mean, so the voice can ask "Did you mean ...?"; anything else is not understood.
60. **AC-60 [A]** The voice prompt (D-84): after a step the voice reads the next enabled, unticked, unskipped row, passing headings, notes, details and rows hidden by a switch; a flow row is read as its label and result and a challenge row as its challenge only, and the voice waits on it; one or two challenge rows ticked by auto-check in the step are said as the challenge, a pause and the response, and more than two as how many are verified; flow rows ticked by auto-check are not spoken; "Checklist complete" is said when nothing is left; a kind of row the voice is off for is not spoken and not waited on; all-capital words of four or more letters are read as words; "Double check <item>" and "Did you mean <phrase>?" are available.
61. **AC-61 [A]** Voice settings (D-84): the options `voice_flows` and `voice_challenges` are off by default, kept one key each, read back on the next start and given the default when the stored value is damaged; the Voice page under Settings shows one switch for each, a tap turns it on or off and keeps it, and a change made elsewhere shows on the page.
62. **AC-62 [A]** The voice repository (D-84): it speaks the utterances of a prompt in order and waits out each pause; a new prompt or `stopSpeaking` cuts off the one in progress; the microphone is switched off while it speaks and back on after, if listening is wanted, so the voice does not hear itself; phrases pass through; and with no microphone `startListening` gives a `SpeechUnavailable` error while speech still works.

**Voice (D-84), planned.** Not numbered yet (AC-58 to AC-62 are built and numbered above), because `tools/check_acceptance_tags.sh` fails an `[A]` criterion with no test. Each gets its number (from AC-58) and its test in the step that builds it.
- Waiting: the voice moves on when the dataref of the row changes to the wanted state (auto on), when the pilot ticks it or when the pilot says an answer `[A]`.
- Auto off: a true dataref does not advance the list `[A]`.
- Disagreement: a tick or an answer that disagrees with the dataref says "Double check <item name>" `[A]`.
- Pause: `pause checklist` and the Pause button stop the voice and flash PAUSED (icon and text); `resume checklist` and `continue checklist` carry on `[A + SIM]`.
- The real speech and microphone on Android (Windows best effort, problems noted) `[SIM]`.

### 17. Risks

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R-1 | iOS multicast entitlement not granted or slow | Likely / medium | Manual IP always available; behaviour recorded early on (beacon worked without the entitlement on one iPhone); entitlement added to the project only when approved |
| R-2 | Android needs the multicast lock and some vendors still drop multicast in power-save | Medium / medium | Lock held only while listening; manual IP; test on the actual phone |
| R-3 | Stream loss, latency or low rate over Wi-Fi (TCP adds latency instead of dropping) | Medium / low for the fixed signals, high for auto-check | The fixed signals need 2 Hz only; measured against `core_test_server`; `RREF` numbers are evidence only |
| R-4 | Multicast blocked on guest or isolated Wi-Fi / client-isolation routers | Likely in some homes / low | Manual IP; message explains it |
| R-5 | (Closed by D-36) X-Plane's unknown-dataref behaviour | n/a | Our plugin answers `unknown_name`; plugin absence is decided by the handshake alone |
| R-6 | Windows Firewall blocks inbound HTTP to the plugin | Likely first run / medium | Recorded early on; setup note in `plugin/README.md` telling the user to allow X-Plane on private networks |
| R-7 | Multiple adapters (VPN, Hyper-V, WSL) break beacon join or pick the wrong IP | Medium on dev PCs / medium | Join per interface; show the packet source IP; manual IP |
| R-8 | Cleartext HTTP or WebSocket blocked on a platform in release builds | Medium / high | on devices against `core_test_server`; mobile config; release-build test AC-23 |
| R-9 | Plugin crashes or stalls X-Plane | Low / very high | No XPLM from server threads; flight loop does bounded work; clean unload checked early on; AC-24 |
| R-10 | Plugin cannot be built or verified on macOS/Linux by us | Certain / medium | Labelled untested; GitHub Actions compile job (6.4), MacBook as backup; keep platform code minimal and isolated |
| R-11 | mtime precision or timezone mismatch makes the cache thrash or go stale | Medium / medium | One timestamp rule (5.4), millisecond APIs, same golden files on both sides |
| R-12 | Aircraft changes between the app's dataref read and HTTP fetch | Medium / medium | `generation` in JSON and header, race rule with bounded retries |
| R-13 | Unauthenticated, cleartext LAN API exposes aircraft path and checklist to anyone on the LAN | Certain on shared LANs / low | Read-only, private-range ACL, no secrets served; documented as a known limitation |
| R-14 | Progress marks misapplied after the user edits the checklist | Medium / medium | Per-checklist fingerprint (8.2); out-of-range indexes never applied |
| R-15 | Last-in-file is not the shutdown checklist (flight order is defined by `sw_continue`, not file order) | Likely / medium | Q10; wrongly resetting is mitigated by only applying it on the ground |
| R-16 | iOS suspends sockets in the background, so the app is stale on return | Certain / low | Stop on pause, rediscover and resubscribe on resume |
| R-17 | CivetWeb or SDK licensing/vendoring problems | Low / medium | Vendor a pinned CivetWeb (MIT) with its licence; SDK not redistributed |
| R-18 | Scope creep (more signals, writes) | Medium / medium | Section 1 non-goals; review against the subscription list in 5.3 |
| R-19 | Stream clients exhaust CivetWeb's worker threads and starve HTTP | Medium / medium | Pool of 8, at most 4 stream clients, `503` on the fifth; `ctest` case |
| R-20 | More code in the sim process (sender thread, subscription table, expiry) crashes or slows X-Plane | Low / very high | Core tested without the sim; no XPLM from server threads; bounded work per flight-loop tick; AC-24 |
| R-21 | The plugin is required for live data; no stock-sim fallback | Certain / accepted | Recorded consequence of D-36; the checklist itself already needs the plugin |
| R-22 | Format assumptions: the comment syntax and the `@` prefix were the least certain | not rated | Pinned against real files and the real parser; `Documentation/Reference/GRAMMAR.md` |
| R-23 | Some community files are not UTF-8 | not rated | If decoding fails, fall back to Latin-1 instead of erroring (D-8) |
| R-24 | The full grammar has forms the manual and the real checker disagree on, or that cannot be reproduced from text alone | Medium / medium | Test checklists run through the real checker; **Assumed** rules flagged; a comparison with the real plugin runs in the sim |
| R-25 | Wrongly auto-checking an item is worse than not checking | Medium / high | One-way helper only; manual always wins; `unknown` never checks; parity run (AC-47) |
| R-26 | A real checklist needs more datarefs than the cap | Low for one checklist (largest seen about 51 against 128), certain for a whole file (about 440) / medium | Only the open checklist is subscribed; the count is redone over all files; the extra items stay manual with a notice |
| R-27 | String or byte-array datarefs do not fit the numeric stream | Medium / low | Those conditions stay manual with a warning; protocol extension only if measurement shows it is cheap |
| R-28 | The sim frame rate caps the delivered stream rate (values are sampled on the flight loop) | Likely at low FPS / low | it is measured; the option is a request, not a promise; the notice is not needed for rate |
| R-29 | Higher rates or many subscriptions slow X-Plane | Low / very high | Bounded work per tick; default 5 Hz; the earlier budget (under 1 ms) re-measured with load; caps stay |
| R-30 | Wi-Fi gaps at 60 Hz on the tablet (311 to 423 ms seen on the tablet) | Medium / low | Coalescing, latest wins; auto-check is level-triggered so a missed frame does not lose a true condition |
| R-31 | Transient conditions are missed between frames at 1 Hz or on a lost connection | Medium / low | One-way latch only on frames seen; the default of 5 Hz; the pilot can always tap |
| R-32 | `sw_show` hiding items changes counts and completion in surprising ways | Medium / medium | Rule in 12.4, tested; unknown shows the item; hidden marks are kept |
| R-33 | Auto-check masks a missed manual step (the pilot trusts it) | Medium / medium | Auto-checked items carry a distinct marker; the app never claims verification beyond "condition was seen true" |
| R-34 | Retired: deleting the temporary code broke nothing the seam protects | Done | Done in the migration; the gate keeps a `temporary/` folder from returning |
| R-35 | Retired: retiring the file-based acceptance tests lost coverage | Done | The tests that read fixtures directly stay; the criteria were re-expressed for the network source (`Documentation/Architecture/DECISIONS.md`) |
| R-36 | Progress format 2 migration corrupts or loses saved marks | Low / high | Format 1 loads with empty sets; corrupt or unknown files are a miss; storage tests with real v1 files |
| R-37 | Scope creep into writes, voice beyond D-84 or the options UI | Medium / medium | Section 1 non-goals; review against them |
| R-38 | The cubit-orchestrated use case makes the detail cubit large | Medium / low | The rule stays in the use case and the policy in domain; the cubit only wires; split a coordinator inside `ui/checklist_detail/cubit/` if needed |

### 18. Open items and questions

#### 18.1 Still open

1. **Extra checklist search locations** (config-file format and lookup order). The app looks in the aircraft folder only, `<acf name>_clist.txt` then `clist.txt`; the lookup is isolated so a later addition is additive. *Deferred: aircraft folder only.*
2. **On-ground dataref in flight.** `sim/flightmodel/failures/onground_any` reads 1 parked on 12.4.1 through the real plugin (D-47); the airborne value is still open (`Documentation/TODO.md`).
3. **Baseline for change-since-activation conditions (Q25).** The default in section 12.6 is the value when the checklist is opened or reset. The change operators' baseline was not compared live with the real plugin (D-58, D-72).
4. **Where the evaluation runs (Q21).** The detail cubit wires streams to the pure use case, and the repository executes the result. An alternative is a coordinator object in `data/` that runs while any checklist is open; revisit it if the detail cubit grows too large (R-38).
5. **Moving the manual IP into `UserOptions` (Q24).** Optional tidy-up; the default is to leave it.

Settled since the first version of this plan: the unknown `sw_show` condition (Q18) is moot because `sw_show` is not supported (D-70); the evaluation scope is the open checklist only (D-52); the subscription cap is 128 (D-66). The decisions for live data are D-48 to D-80 in `Documentation/Architecture/DECISIONS.md`.

#### 18.2 Questions where the architecture is ambiguous, and their answers

Not guessed: the plan's working default is stated, and later answers are marked.

- **Q1.** (Closed by D-36.) There are no plugin datarefs; the handshake and the reserved stream signal replace them.
- **Q2.** How is the plugin's port chosen? *Decided by D-38:* preferred port 18086, then 18087 to 18093, no OS-assigned fallback, found by the app's probe of `/v1/hello`. **Q2b:** LAN-only binding by source-address ACL on all interfaces (the default) versus binding to one chosen interface.
- **Q3.** Answered: X-Plane over the network is the single owner of the aircraft identity. `PluginSessionService` (behind `PluginSessionSource`) fetches it once per generation change; the network source and `FlightSimRepository` both read that session; the home flow passes the identity and `onGround` from `FlightSimRepository` into `progressRepository.attach(...)` after verifying the live aircraft did not change during the load.
- **Q4.** How does the developer run the network path? *Answered:* the network path is the only path; there is no development wiring.
- **Q5.** Should the app show the cached checklist when the sim is unreachable? The architecture only describes the cache on connect or aircraft change, and the app cannot know the aircraft without the sim. *Default:* no offline use.
- **Q6.** Answered: X-Plane 11 is not supported (D-46); only XP12 is verified.
- **Q7.** Answered: the repo is on GitHub, so a compile-only GitHub Actions job is in scope (6.4). A MacBook is the backup for macOS builds.
- **Q8.** Additions to `GET /v1/aircraft` beyond the architecture's list: `protocolVersion`, `generation`, `checklistPath`. Needed for the race rule and the cache entry. *Default:* add them.
- **Q9.** "Last viewed checklist" needs a write on `ChecklistProgressRepository` (for example `setLastViewed`), which the architecture sketch does not list. *Default:* add it as an extension, as `resetAll` was before.
- **Q10.** "Last checklist **in the file**" versus the early finding that file order is not flight order (`ChecklistSequence.ordered` follows `sw_continue`). *Default:* implement the architecture as written (last in file), keep the choice in one function, and decide after checking real files whether to use the last element of the sequence order.
- **Q11.** What does "marks that no longer match the current file" mean precisely? Marks are keyed by checklist name and item index, and an edit that inserts an item shifts indexes. *Default:* per-checklist label fingerprint (8.2).
- **Q12.** UI for the restore popup when the app is not in the foreground at connect time. *Default:* the rule runs when the app is foreground; the popup is shown on the next resume.
- **Q13.** More than one X-Plane on the LAN (several beacons). *Default:* list them for the user to choose when more than one is seen; remember the last choice.
- **Q14.** Answered: the restore rule runs at the first successful connect after the app starts and when the user switches aircraft. A reconnect with the same aircraft keeps the marks unless the connection was down more than 30 minutes (then: reset on the ground, keep airborne, prompt if unknown). *(Superseded 2026-11-01 by D-35: the restore rule uses the plugin's run id; there is no 30-minute gap and no `NEW_FLIGHT_GAP_MINUTES` any more.)*
- **Q15.** Answered: include a manual **Reload** action (the plugin does not bump the generation on file edits, so without it an edited checklist is only noticed on reconnect).
