# Manual test record

> These records were made during development, before the first public release, under the project's earlier names and commit ids. Names, paths and addresses below have been updated to the current ones. Results describe the builds that were tested then, not necessarily the current code.

Everything here needs a running X-Plane and/or a physical device (tag SIM in `Documentation/Plan/PLAN.md` section 16), so it cannot be automated. Step-by-step scripts follow; results are recorded as the work proceeds.

**How to record a result.** Under the criterion, add a line: `Result: <PASS|FAIL> | <YYYY-MM-DD> | <device> | <X-Plane version> | <notes or issue>`. A FAIL gets a follow-up task. `tools/check_acceptance_tags.sh` checks that every SIM criterion has an entry here.

## Setups used by the scripts

Run `. .\tools\env_windows.ps1` once per terminal. "App" means `flutter run -d <device>` (it finds the sim by its beacon). "Test aircraft" are the copies of the stock C172 under `Aircraft/XChecklist Test/` (not in the repo): `C172 With Checklist` has `Cessna_172SP_clist.txt`; `C172 No Checklist` has no checklist file. The plugin goes in `Resources/plugins/flightsim_aide/` (layout A `64/win.xpl` or layout B `win_x64/flightsim_aide.xpl`).

- **S-plugin**: plugin installed and enabled; test aircraft `C172 With Checklist` loaded, parked on a runway.
- **S-no-plugin**: the `flightsim_aide` folder removed from `Resources/plugins/` (or the plugin disabled in Plugins > Plugin Admin) with X-Plane running. Plugin disabled mid-session: start in S-plugin, then disable it in Plugin Admin.
- **S-wrong-version**: no sim needed. Save this as `wrong_version.py` outside the repo and run `python wrong_version.py`; then start the app with `--dart-define=SIM_IP=<this PC's LAN IP>` (the app probes 18086 to 18093):
  `import http.server as h; B=b'{"protocolVersion":99,"sim":{"kind":"xplane","version":"12.1.4"},"pluginVersion":"9.9.9","port":18086,"streamPath":"/v1/stream"}'`
  `class H(h.BaseHTTPRequestHandler):`
  `    def do_GET(s): s.send_response(200); s.send_header("Content-Type","application/json"); s.send_header("Content-Length",str(len(B))); s.end_headers(); s.wfile.write(B)`
  `h.HTTPServer(("0.0.0.0",18086),H).serve_forever()`
  (`core_test_server` has no wrong-version option; the unit tests cover it with a Dart fake.)
- **S-no-checklist**: load `C172 No Checklist`.
- **S-edit**: with `C172 With Checklist` loaded, keep a copy of `Cessna_172SP_clist.txt` (for example `Cessna_172SP_clist.txt.orig`); edit the original in a text editor and save; restore from the copy at the end of the test.
- **S-ground / S-air**: ground = parked on a runway, `sim/flightmodel/failures/onground_any` = 1. Air = in flight, value 0. Read the value with `dart run tools/stream_watch.dart http://<sim ip>:18086`. The airborne variants need an aircraft in flight and are recorded as not run until then.
- **S-gap**: add `--dart-define=NEW_FLIGHT_GAP_MINUTES=1` to the app command so the 30 minute gap becomes 1 minute. *(Superseded 2026-11-01 by D-35: the restore rule uses the plugin's run id; there is no 30-minute gap and no `NEW_FLIGHT_GAP_MINUTES` any more.)*
- **S-app-data**: the saved progress is in the application support folder (Windows: `%APPDATA%\FlightSim Aide contributors\FlightSim Aide`). Delete its `progress` files to start from nothing.

## Setup common to the later sections

**Setup common to every section.**
- X-Plane 12 on the PC with the plugin (`plugin/README.md` install section) and the real XChecklist 1.52 where a section says so. The plugin answers on port 18086; `curl -s http://127.0.0.1:18086/v1/hello` prints its version.
- The test aircraft: copy `Aircraft/Laminar Research/Cessna 172SP` to `Aircraft/XChecklist Test/C172 With Conditions` and put `testing/fixtures/manual/c172_before_start_clist.txt` beside the `.acf` as `Cessna_172SP_clist.txt`. Sections that name another list say which file to swap in (keep a backup of the original and put it back after).
- Load the aircraft in X-Plane, then check `curl -s http://127.0.0.1:18086/v1/aircraft`: `checklistPath` must be the file you expect. XChecklist reads the file when the aircraft loads, so reload the aircraft after swapping a file.
- Sim state is set by script, not by hand: `tools/sim_set.sh sim/cockpit2/switches/beacon_on=1 "sim/cockpit2/electrical/battery_on[0]=1"` writes datarefs through X-Plane's web API (port 8086); `tools/sim_set.sh --get <name>` reads one back. Reset the lights to 0 between runs.
- App on Windows: `flutter build windows --release -t lib/main.dart`, run `build\windows\x64\runner\Release\flightsim_aide.exe`. The app needs no flag; it finds the sim by beacon. Tablet: `flutter run -d <id> --release` (keep the tablet awake and unlocked: the app stops on the lock screen).

## AC-7

With the sim running the plugin on the same Wi-Fi, the app on desktop and on a phone shows the sim's IP without any typing within 10 s (where multicast is available; iOS may be manual-only per the early measurements).

Steps:

Setup: S-plugin; sim PC and device on the same Wi-Fi; app started without `SIM_IP`.
1. Start the app on the desktop. Note the time.
2. Expected: within 10 s the home screen shows the sim, with no typing; the aircraft ICAO and description appear (C172, "Cessna 172 SP Skyhawk - 180HP").
3. Repeat on the phone (Android). On iPhone, if nothing appears in 10 s, record "manual-only" and continue with AC-8.
4. Record the seconds to connect on each device.

Result: PASS (desktop only) | 2026-10-25 | Windows desktop, app on the sim PC | X-Plane 12.4.1 | Beacon found the sim without typing; the chooser listed SIMPC three times (192.168.1.10, 172.23.0.1, 172.27.112.1: one beacon per adapter on the sim PC). Choosing 192.168.1.10 connected in about 1 s or less and showed C172 with 2 checklists. First launch was delayed by the Windows firewall prompt, so the time from launch to first list was not measured. Phone part not run. On later launches the chooser showed for a split second and the app then went to the connected view on its own.

Result: PASS (Android tablet) | 2026-10-26 | Samsung SM-T380 tablet (Android 9, API 28), release APK, PC 192.168.1.10 on the same Wi-Fi | X-Plane 12.4.1, real plugin | Beacon found the sim with no typing in about 5 s or less (the tester's estimate, not measured) and the checklist showed. iPhone not run.

Result: PASS (iPhone) | 2026-10-27 | iPhone 16, release build, PC 192.168.1.10 | X-Plane 12.4.1, real plugin | Beacon found the sim with no typing; Local Network dialog accepted (10.6).

## AC-8

Manual IP works with multicast unavailable: an invalid address is rejected with a clear message, a valid one connects, and it is remembered after restart. Clearing it returns to automatic discovery.

Steps:

Setup: S-plugin; start the app with discovery on, then use the Manual IP action.
1. Open Manual IP. Enter `300.1.1.1`. Expected: rejected with a clear message ("not a valid address" style text), the dialog stays open, no connection attempt.
2. Enter `abc`. Expected: same rejection.
3. Enter the sim's real IPv4 address and save. Expected: the app connects within 3 s and shows the aircraft.
4. Quit the app (swipe it away on the phone) and start it again. Expected: it connects to the saved address without prompting.
5. To prove it does not rely on multicast, block multicast first: turn off the sim PC's beacon (X-Plane > Settings > Network > uncheck "Send multicast beacon" if present) or use a network without multicast, then repeat step 4.
6. Open Manual IP and Clear. Expected: the app returns to automatic discovery and finds the sim again (if the beacon is on).

Result: PASS (desktop; multicast not blocked) | 2026-10-25 | Windows desktop | X-Plane 12.4.1 | `300.1.1.1` and `abc` show the red message "Enter four numbers like 192.168.1.20" and Save stays disabled (the rejection is the disabled button plus the message); `192.168.1.10` enables Save and the card stays connected; after closing and relaunching the dialog is pre-filled with the saved address and the app connects; Clear closes the dialog and the app reconnects by discovery. Two defects found and fixed during the run: the Enter IP address button was hidden while connected, and Back from the list left no way to reopen it (aedbd66). Not run: with multicast actually blocked, and on a phone.

Result: PARTIAL (Android tablet) | 2026-10-26 | Samsung SM-T380 tablet (Android 9), release APK, real plugin | X-Plane 12.4.1 | `300.1.1.1`: Save stayed disabled but the tester saw **no red message** (the desktop run showed "Enter four numbers like 192.168.1.20"; open question whether the tablet build or layout hides it). `abc` could not be typed (numeric keyboard has no letters). The real IP connected, a swipe-away relaunch reconnected to the saved address, and Clear returned to discovery and found the sim. Multicast-blocked variant not run.

Result: PASS (iPhone) | 2026-10-27 | iPhone 16, release build, PC 192.168.1.10 | X-Plane 12.4.1, real plugin | Invalid address rejected, valid IP connected, saved address used after a relaunch, Clear returned to discovery. Reported as passed; multicast-blocked variant not run. The tablet's missing red message was not separately reported for the iPhone.

## AC-9

With the sim running and no plugin (no port of 18086 to 18093 answers `/v1/hello`), the app shows "plugin not detected" within 3 s of reaching the sim, never crashes, and recovers by itself when the plugin appears.

Steps:

Setup: S-no-plugin (sim running, no plugin). App started with `SIM_IP=<sim ip>`.
1. Start the app. Expected: within 3 s of reaching the sim it shows "plugin not detected"; no crash, no spinner that never ends.
2. Without closing the app, install or enable the plugin (Plugin Admin > enable; the plugin must be in `Resources/plugins/`). Expected: the app recovers by itself within a few seconds and shows the aircraft; no restart.
3. Disable the plugin in Plugin Admin while connected. Expected: the app reports that the sim is not responding or the plugin is missing (no crash); enable it again and it recovers.
4. S-wrong-version: start `wrong_version.py`, start the app against it. Expected: a version-mismatch message that names an update, and probing stops (no retry storm: the script receives about one request per port, not a continuous stream).

Result: PARTIAL | 2026-10-25 | Windows desktop | X-Plane 12.4.1 | Plugin disabled in Plugin Admin while the app was connected: the app reported it in under 1 s, stayed usable and did not crash; enabling the plugin again recovered by itself in under 1 s. NOT run: starting the app with no plugin installed. Wrong-version server (protocolVersion 99 on 18086, plugin disabled): the card said "Update the plugin to continue. The plugin speaks version 99; this app needs version 1. Your progress is kept" with Retry only; the server saw one /v1/hello in two minutes and exactly one more after Retry. Beacon discovery was used because the SIM_IP wiring does not drive the UI (Documentation/TODO.md).

Result: PASS (steps 1 to 3) | 2026-10-26 | Samsung SM-T380 tablet (Android 9), release APK, real plugin | X-Plane 12.4.1 | Start with the plugin disabled, enabling it while the app ran, and disabling it while connected all behaved as expected, per the tester ("all steps passed"). Timings were not measured. Step 4 (wrong version) not run on the tablet; the desktop run covers it.

Result: PASS (iPhone) | 2026-10-27 | iPhone 16, release build, PC 192.168.1.10 | X-Plane 12.4.1, real plugin | Plugin disabled and re-enabled in X-Plane: banner shown, recovered by itself (see also 10.7). Wrong-version server not run.

## AC-11

The loaded aircraft's ICAO and description are shown. When another aircraft is loaded in X-Plane, the app informs the user within 3 s, names the new aircraft, and leaves the current checklist usable; Switch loads the new checklist.

Steps:

Setup: S-plugin, `C172 With Checklist` loaded, app connected, a checklist open with at least one item ticked.
1. Expected: the home screen shows ICAO `C172` and the description.
2. In X-Plane load a different aircraft (`C172 No Checklist` or the Thranda PC-12). Start a stopwatch at the moment the aircraft finishes loading.
3. Expected within 3 s: a banner names the new aircraft and offers Switch. The old checklist is still open and ticks still work.
4. Tick one more item, then press Switch. Expected: the new aircraft's checklist loads (or the "no checklist for this aircraft" text if it has none), the banner clears.
5. Change only the livery. Expected: no banner (same aircraft).

Result: PARTIAL | 2026-10-25 | Windows desktop | X-Plane 12.4.1 | After loading `C172 No Checklist` a banner appeared in under 1 s (limit 3 s); Switch worked. NOT confirmed: that the banner names the new aircraft, and that ticking still worked while the banner showed (not asked/observed). Loading `C172 With Checklist` again cleared the banner by itself. The livery-only case was not run.

Result: PARTIAL (Android tablet) | 2026-10-26 | Samsung SM-T380 tablet (Android 9), release APK, real plugin | X-Plane 12.4.1 | Loading another aircraft showed the banner. Pressing Switch showed the red banner "the loaded aircraft has no checklist" (expected for `C172 No Checklist`), and it cleared only with X (the known finding in Documentation/TODO.md, seen again). A livery-only change showed no banner. The tester confirmed the banner names the new aircraft. NOT confirmed: the 3 s limit (not timed) and that ticking still worked while the banner showed.

Result: PASS (iPhone) | 2026-10-27 | iPhone 16, release build, PC 192.168.1.10 | X-Plane 12.4.1, real plugin | Aircraft-change banner named the new aircraft, the old checklist stayed usable, Switch loaded the new one. Seconds not measured.

## AC-12

The checklist shown for an aircraft equals what the parser produces from that aircraft's `clist.txt` read directly (compare to the parse of the same file).

Steps:

Setup: S-plugin, `C172 With Checklist` loaded.
1. In the app open the checklist and note the list names and item counts.
2. In a terminal: `dart run tools/parse_cli.dart "<X-Plane>/Aircraft/XChecklist Test/C172 With Checklist/Cessna_172SP_clist.txt"` (the parser on the same file).
3. Expected: the same checklists, the same order, the same items (text, check text, kind) as the app shows.
4. Repeat with the Thranda PC-12 (`Thranda_PC12_clist.txt`, a real-world file).

Result: PASS (C172 With Checklist only) | 2026-10-25 | Windows desktop | X-Plane 12.4.1 | App showed Before start checklist (heading note, Parking brake SET, Battery ON, Avionics OFF) and Shutdown checklist (Throttle IDLE, Mixture CUTOFF, Battery OFF); the parser gives the same. /v1/checklist is byte-identical to the file. The Thranda PC-12 file was not compared.

Result: PASS (C172 With Checklist only) | 2026-10-26 | Samsung SM-T380 tablet (Android 9), release APK, real plugin | X-Plane 12.4.1 | `parse_cli` on the restored file (267 bytes) gives 2 checklists: Before start checklist 4 items (1 note, 3 checks) and Shutdown checklist 3 items. The tablet shows the same two checklists with the same counts. The same held earlier the same day for the edited file left over from AC-13: `parse_cli` gave Before start checklist 6 items (the 2 added items included) and Shutdown 3, and the tester confirmed the tablet matched. `/v1/checklist` serves the same content as the restored file. Item text was compared by count only. The Thranda PC-12 file was not compared.

Result: PASS (iPhone) | 2026-10-27 | iPhone 16, release build, PC 192.168.1.10 | X-Plane 12.4.1, real plugin | Matches the parser on `C172 With Checklist` (2 checklists, 4 and 3 items). Compared against the file as served by the plugin (`/v1/checklist`, 267 bytes = `checklistSize`), not read from disk on the PC. PC-12 not run.

## AC-13

Cache: reconnecting with an unchanged checklist file transfers no checklist body; a changed file (newer or older mtime, or different size) is refetched; Reload picks up an edit made while connected.

Steps:

Setup: S-plugin and S-edit; read the plugin log or run `dart run tools/stream_watch.dart` for context if needed. To see transfers, watch the request log (`curl -sI http://<sim ip>:18086/v1/aircraft` shows `checklistModified` and `checklistSize` in the JSON).
1. Connect once. Expected: the checklist is fetched (one `GET /v1/checklist`).
2. Quit and restart the app with the file unchanged. Expected: `GET /v1/aircraft` happens, `GET /v1/checklist` does not (cache hit). Observe it with the Dart-side test `test/e2e_network_slice_test.dart` as a reference, and on the sim side by the missing checklist request in a packet capture or the plugin's verbose log.
3. S-edit: with the app connected, append a line to the checklist file in the editor and save. Expected: `checklistModified` and `checklistSize` change as soon as the app asks (`/v1/aircraft` makes the plugin re-check the file first; before that change, in plugin builds up to 2026-10-27, it took up to 3 s, so Reload right after saving showed nothing) (`/v1/aircraft`). Press Reload in the app. Expected: the edited checklist appears in place and your ticks on unchanged checklists remain.
4. Restore the original file (older mtime variant: copy the `.orig` back with its original timestamp preserved). Expected: the file is refetched (a different mtime or size is enough).
5. Quit, edit the file while the app is closed, start the app. Expected: the new content is shown.

Result: PARTIAL | 2026-10-25 | Windows desktop | X-Plane 12.4.1 | Reload picks up an edit made while connected: after appending `Flaps UP` (size 267 to 285, new mtime) Reload showed the fourth item in Shutdown checklist and kept the Parking brake tick; after restoring the original file with an older mtime (size 267, mtime 1790866800000) Reload dropped the item and the tick stayed. NOT run: that a reconnect with an unchanged file transfers no checklist body (no request log was watched; the unit tests cover it). The app was not checked for a banner during the edit.

Result: PARTIAL (Android tablet) | 2026-10-26 | Samsung SM-T380 tablet (Android 9), release APK, real plugin | X-Plane 12.4.1 | After editing the checklist file while connected, **the first Reload did not change the checklist on screen** (the desktop run did). After killing and relaunching, the new item showed and a tick was cleared; after a second edit with the app closed, a relaunch showed both new items. The cleared tick is expected if it was on the edited checklist: marks are kept only while that checklist's fingerprint is unchanged (`checklist_progress_repository_impl.dart`, `_restorable`). Reload (and Enter IP address) exist only on the home screen, so Reload was pressed there. Retry the same day: staying on the home screen, Reload picked up the edit, and after removing the added item and pressing Reload the item count went from 4 to 3. The first Reload that showed no change could not be reproduced: a later attempt with a checklist open (add an item, go home, Reload) worked. Which checklist held the cleared tick is not recorded. Unchanged-file reconnect not run.

Result: PARTIAL (iPhone) | 2026-10-27 | iPhone 16, release build, real plugin | X-Plane 12.4.1 | Reload after an edit: pressing it right after saving showed no change (the plugin re-checks the file only every 3 s, so `/v1/aircraft` still had the old size and time and the app correctly did nothing); after waiting longer, Reload showed the edit. This also explains the tablet's first no-change Reload. Restarting the app showed the edit. Not run: the unchanged-file reconnect (no `GET /v1/checklist`), the older-mtime restore, and the edit while the app is closed. Reload right after saving is a design question in `Documentation/TODO.md` section 3.

Result: PASS for step 3 only (Reload right after saving) | 2026-10-27 | app on a device on the LAN (device not recorded), real plugin rebuilt and installed in X-Plane (`64/win.xpl`) | X-Plane 12.4.1 | After saving an edit to the checklist file, the first Reload showed the edit at once, with no 3 s wait (the fix in `/v1/aircraft`, `Cache::requestRefresh`). The live contract also passes 40 of 40 against this build. Not run: the unchanged-file reconnect, the older-mtime restore, the edit while the app is closed.

## AC-14

An aircraft without a checklist file shows "no checklist for this aircraft" and the app stays usable.

Steps:

Setup: S-plugin; load `C172 No Checklist`.
1. Connect (or press Switch). Expected: "no checklist for this aircraft" text; the aircraft ICAO and description are shown.
2. Expected: the app stays usable: Manual IP, Reload and Open still respond; no crash.
3. Load `C172 With Checklist`. Expected: the banner offers Switch and the checklist loads.

Result: PARTIAL | 2026-10-25 | Windows desktop | X-Plane 12.4.1 | Switch to `C172 No Checklist` showed a red banner saying the loaded aircraft has no checklist; the app stayed usable. Finding: the red banner stayed after `C172 With Checklist` was loaded again, until the user dismissed it with X (see Documentation/TODO.md). NOT confirmed: the exact text, and what the connection card said. Fresh start on `C172 No Checklist`: the card says the aircraft has no checklist ("Load an aircraft with a checklist file, then reload") with Reload and Enter IP address; loading `C172 With Checklist` updated the card to connected quickly.

## AC-16

Airborne with saved progress: killing and relaunching the app restores the marks and reopens the last viewed checklist silently.

Steps:

Setup: S-plugin, S-air (aircraft in flight). Not run until an airborne session is possible.
1. Connect, open a checklist, tick three items, open a second checklist and leave it showing.
2. Kill the app (swipe away / close the window), start it again.
3. Expected: no popup; the marks are restored; the last viewed checklist opens.
Parked variant (on-ground = 1) is AC-17 and AC-18.

Result: 

Result: NOT RUN (iPhone) | 2026-10-27 | Needs an aircraft in the air; do it in the 4.3a / 11.2 flight.

## AC-17

On the ground with saved progress and the shutdown checklist (per Q10) complete: progress is reset silently.

Steps:

Setup: S-plugin, S-ground, with saved progress in which the shutdown checklist (the last checklist in the file, D-22) is fully ticked.
1. Tick the whole shutdown checklist and one item elsewhere. Kill the app, start it again.
2. Expected: no popup; progress is reset silently (every item unticked).

Result: PASS (parked) | 2026-10-25 | Windows desktop | X-Plane 12.4.1 | With all three Shutdown checklist items ticked plus two in Before start checklist, closing and relaunching gave no popup and every item unticked.

## AC-18

On the ground with saved progress otherwise: the popup appears; "use saved progress" restores, "reset" clears, and the choice persists.

Steps:

Setup: S-plugin, S-ground, saved progress where the shutdown checklist is not complete.
1. Tick some items. Kill the app, start it again (within 30 minutes). *(Superseded 2026-11-01 by D-35: the restore rule uses the plugin's run id; there is no 30-minute gap and no `NEW_FLIGHT_GAP_MINUTES` any more.)*
2. Expected: a popup (not dismissible) asks whether to use the saved progress or reset.
3. Choose "use saved progress". Expected: marks restored. Kill and restart again: the choice persists (the popup does not return for the same state, or returns once per the rule; record what happens).
4. Repeat, choosing "reset". Expected: all marks cleared; the choice persists after another restart.

Result: PASS (parked) | 2026-10-25 | Windows desktop | X-Plane 12.4.1 | With Parking brake ticked and the shutdown checklist incomplete, relaunch showed the popup; Use saved progress kept the tick; after another relaunch the popup came again and Reset cleared the marks; the next relaunch showed no popup. Not run: the on-ground value was read from the real plugin (1, parked), no airborne case.

Result: PASS (Android tablet) | 2026-10-26 | Samsung SM-T380 tablet (Android 9, API 28), release APK, PC 192.168.1.10 on the same Wi-Fi | X-Plane 12.4.1, real plugin, aircraft on the ground | Ticked items, force stopped the app, reopened with the checklist aircraft loaded: the popup appeared; Use saved progress brought the ticks back; after another force stop the popup came again and Reset cleared them; one more force stop and reopen left them cleared (the choice persisted). Starting the app with C172 No Checklist loaded gave no popup (no checklist, nothing to restore); the popup came once the checklist aircraft was loaded. Backgrounding the app without killing it gave no popup, as expected.

## AC-22

Plugin security: only `GET` (and `HEAD`) on the HTTP endpoints work and the stream accepts only read-only subscriptions; traversal-style URLs and query parameters never return file contents; non-private source addresses are refused (address filter unit-tested; observed on the LAN where possible); the plugin opens only the current aircraft's `clist.txt`.

Steps:

Setup: S-plugin, from the sim PC and then from another LAN machine (replace 127.0.0.1 with the sim's IP).
1. `curl -i -X POST http://127.0.0.1:18086/v1/aircraft` -> 405 with `Allow: GET, HEAD`. `curl -I` works and has no body. `curl -i -X POST .../v1/checklist` -> 405.
2. `curl -i http://127.0.0.1:18086/` , `//v1/aircraft`, `/v1/checklist/..%2f..%2fLog.txt`, `/v1/checklist?path=../../Log.txt`, `/v1/aircraft?file=C:/Windows/win.ini` -> 404 or the normal JSON; never any file other than the current aircraft's `clist.txt`.
3. Stream: subscribe over `ws://.../v1/stream` with `dart run tools/stream_watch.dart`; a write-style op or an unknown name gets `unsupported` / `unknown_name`.
4. Non-private addresses are refused at the connection; the address filter is unit-tested. Observe from a public address only if one is reachable (record "not observed" otherwise).
5. `dart run tools/protocol_contract.dart http://127.0.0.1:18086 --live` -> all cases pass.

Result: PASS (sim PC only) | 2026-10-25 | Windows desktop, curl | X-Plane 12.4.1 | POST gives 405 with `Allow: GET, HEAD`; HEAD has no body; `/`, `//v1/aircraft`, `/v1/checklist/..%2f..%2fLog.txt` give 404; `?path=../../Log.txt` and `?file=C:/Windows/win.ini` are ignored and return the normal checklist/aircraft; `protocol_contract --live` 40 passed, 0 failed. Not observed: another LAN machine this run (done earlier in 4.9), a non-private source, a stream write op by hand (covered by the contract).

## AC-23

Release builds on one iOS and one Android device reach the sim over cleartext LAN `http://` and `ws://` and (Android) receive the beacon with the multicast lock.

Steps:

Setup: S-plugin; release builds: `flutter build apk --release` (Android) and an iOS release build on a Mac. Install each on its device (not through the debugger).
1. Android: start the app on Wi-Fi without `SIM_IP`. Expected: the beacon is received (the multicast lock) and the aircraft shows; the checklist loads over cleartext `http://`; live on-ground works over `ws://` (the restore rule uses it).
2. iPhone: the same, or manual IP only. Expected: `http://` and `ws://` work with the cleartext settings.
3. Note any cleartext error (`Cleartext HTTP traffic not permitted` on Android; App Transport Security on iOS) as a FAIL.

Result: PASS (Android only) | 2026-10-26 | Samsung SM-T380 tablet (Android 9, API 28), release APK, PC 192.168.1.10 on the same Wi-Fi | X-Plane 12.4.1, real plugin | Beacon received in the release build (about 5 s or less), aircraft and checklist loaded over cleartext `http://`, the stream followed an aircraft change over `ws://` (a notice appeared when C172 No Checklist was loaded), and the restore rule read the on-ground value (AC-18 above). No cleartext error. Not observed: the multicast lock itself, and whether the beacon would arrive without it. The iPhone half (10.6) is open.

iPhone half (10.6), Result: PASS | 2026-10-27 | iPhone 16, release build (`--fresh` install), PC 192.168.1.10 | real plugin | The Local Network dialog appeared and Allow was accepted; the beacon found the sim without typing (no multicast entitlement); aircraft and checklist loaded over cleartext `http://`/`ws://` with no App Transport Security error. A mistyped IP showed "not found"; after fixing the typo it connected. With Local Network turned off in Settings the app first showed "X-Plane is not responding" (the link had been up), then "Local Network access may be off." (first sighting of that message on an iPhone). After turning it back on the app reconnected by itself in a few seconds and the banner cleared, with no restart.

## AC-24

Plugin health: loads on XP12 with clean `Log.txt`; flight-loop cost averages under 1 ms; X-Plane exits cleanly; coexists with the real XChecklist plugin loaded at the same time.

Steps:

Setup: S-plugin on X-Plane 12; the real XChecklist plugin also installed.
1. `Log.txt` after start: no errors from `flightsim_aide`; start line, `listening on port`.
2. Flight-loop cost: leave it running; the plugin logs `flight loop: N calls, average X us` once a minute. Expected: average under 1000 us with and without stream clients.
3. Quit X-Plane normally (also once with a stream client connected). Expected: `server stopped`, `stopped`, no crash dialog, the X-Plane process exits.
4. With the real XChecklist plugin loaded at the same time: no errors in `Log.txt` from either plugin, both menu entries work.

Result: 

## AC-27

The app informs the user when the network is lost ("No network connection") and when X-Plane is not answering ("X-Plane is not responding", with the last seen time), on the home, list and detail screens. The checklist stays usable and marks keep being saved; the message clears on recovery; a recovery with the same aircraft does not re-run the restore rule or show a popup. Verified by switching the phone's Wi-Fi off, and by quitting X-Plane, while a checklist is open.

Steps:

Setup: S-plugin, app connected, a checklist open with an item ticked. Test on the home, list and detail screens.
1. Switch the phone's Wi-Fi off (or unplug the PC). Expected: the banner "No network connection" appears; the checklist stays usable; ticking an item still works.
2. Switch Wi-Fi on. Expected: the banner clears (a short "Reconnected" notice); the marks are still there; no restore popup.
3. Quit X-Plane (leave Wi-Fi on). Expected: "X-Plane is not responding", with the last seen time, within about 10 s; ticks still work and are saved (kill and restart the app to confirm).
4. Start X-Plane again with the same aircraft. Expected: the banner clears; no restore popup (the same aircraft does not re-run the rule).
5. Repeat step 1 on each of the home, list and detail screens.

Result: PARTIAL | 2026-10-25 | Windows desktop | X-Plane 12.4.1 | Quitting X-Plane while the app was on the home screen: in under 1 s the card said "X-Plane is not responding. Last seen 17:51. Retrying... Your progress is kept"; ticking still worked; after X-Plane was started again the banner cleared before the aircraft finished loading and the ticks were still there. NOT confirmed: that no popup appeared on recovery (not asked directly), the list and detail screens, and "No network connection" (Wi-Fi off was not run).

## AC-28

New-flight gap: after more than 30 minutes without a connection (app restart or a long drop), saved progress is reset silently when on the ground, kept when airborne, and prompts when on-ground is unknown. Within 30 minutes a drop or sim restart with the same aircraft keeps the marks. SIM check uses `--dart-define=NEW_FLIGHT_GAP_MINUTES=1`. *(Superseded 2026-11-01 by D-35: the restore rule uses the plugin's run id; there is no 30-minute gap and no `NEW_FLIGHT_GAP_MINUTES` any more.)*

Steps:

Setup: S-plugin and S-gap (`NEW_FLIGHT_GAP_MINUTES=1`).
1. S-ground, saved progress with the shutdown checklist incomplete. Quit the app; wait 2 minutes; start it. Expected: progress reset silently (no popup).
2. S-air (when possible): the same wait; Expected: progress kept, no popup.
3. On-ground unknown (stop the stream: start the app against `core_test_server` without the on-ground signal, or disable the plugin before the first start): Expected: the popup.
4. Within the gap: tick items; drop Wi-Fi for 20 s; reconnect with the same aircraft. Expected: the marks remain.
5. Restart X-Plane (same aircraft) within a minute while the app stays up. Expected: the marks remain.

Result: PARTIAL | 2026-10-25 | Windows desktop | X-Plane 12.4.1 | Parked, shutdown checklist incomplete, items ticked; app closed 17:58 and relaunched 18:00 with `NEW_FLIGHT_GAP_MINUTES=1`: no popup, all items unticked (silent reset after the gap). NOT run: airborne (kept), on-ground unknown (popup), and the within-gap keeps (a drop or sim restart with the same aircraft); the X-Plane restart earlier today ran under the default 30 minutes and kept the ticks, which is related but not the scripted case.

## AC-30

The on-ground value reaches the app through the real plugin on XP12: 1 parked, 0 airborne, and the app's restore rule uses it.

Steps:

Setup: S-plugin; `dart run tools/stream_watch.dart http://<sim ip>:18086` in a terminal.
1. Parked: the value of `sim/flightmodel/failures/onground_any` is 1. In the app the restore rule behaves as AC-17/AC-18 (ground).
2. In flight: the value is 0 and the restore rule behaves as AC-16 (airborne). Not run until an airborne session is possible.

Result: PASS (parked only) | 2026-10-25 | Windows desktop, stream_watch | X-Plane 12.4.1 | `sim/flightmodel/failures/onground_any` = 1 over the stream. NOT RUN: value 0 in flight, and the app's restore rule using it (needs the app and a flight).

## AC-33

**Steps (auto-check on a real aircraft).**
1. Load the Thranda PC-12 (or any aircraft whose checklist has datarefs). Open its first checklist (Cockpit Preparation) in the app.
2. Set the parking brake: `tools/sim_set.sh sim/flightmodel/controls/parkbrake=1`.
3. Look: the matching item is ticked with the auto marker (a small badge on the row). Items after a manual item (one with no dataref) stay open.
4. Tick the first manual item by hand. Look: auto goes on and ticks the following items whose controls are already set, in order, and stops at the next manual one.
5. Tick an item by hand whose control is off. Look: a red dialog "The simulation value for <item> <result> is false." with Cancel and Acknowledge buttons, and the item keeps a red mark. Untick it, set the control, and look: auto ticks it.

Pass line: steps 3 to 5 show exactly what is described, and no item is ticked ahead of an unticked one.

Result: PASS | 2026-11-05 | Windows 11 desktop, development build | X-Plane 12.4.4 | Task 8.1 on the Thranda PC-12, checklist Cockpit Preparation: Parking Brake auto-ticked with the auto marker; auto waited at the manual Flight Control Lock and went on after the pilot ticked it; the following items with a dataref (up to and including Oxygen Lever) ticked when their controls were set; Trim Intr Switch and Flap Intr Switch have no dataref, so auto correctly waited at them. A manual tick of the Oxygen Lever while it was off gave the red dialog and mark; unticking and setting the lever let auto tick it. The tablet's earlier stall on a waiting screen was not the app: see AC-46.

## AC-35

**Steps (manual wins, one way).** Aircraft `C172 With Conditions`, checklist Before start; all four items off (`tools/sim_set.sh "sim/cockpit2/electrical/battery_on[0]=0" sim/cockpit2/switches/avionics_power_on=0 sim/cockpit2/switches/beacon_on=0 sim/flightmodel/controls/parkbrake=0`).
1. Open Before start: nothing ticked (0/5).
2. Avionics on: nothing ticks (Battery is the first item and is still off).
3. Battery on: Battery and Avionics master tick.
4. Tap Flight plan (an item with no dataref), then a skipped item above it: the pointer follows the tap; a skipped item stays open.
5. Tick Parking brake by hand while the brake is off: the red Acknowledge dialog opens and the mark stays. Tap it again: only the tick is removed.

Pass line: each step shows exactly that, and an auto tick never un-ticks.

Result: PASS | 2026-11-05 | Windows 11 desktop, development build | X-Plane 12 | Task 8.2 on `C172 With Conditions` after D-71: clean start leaves everything unticked while Battery is off; avionics first does nothing; battery ticks and auto moves on; tapping a skipped or later item moves the pointer; ticking an item whose switch is off opens the red Acknowledge dialog and keeps the red mark; a second tap removes only the tick.

## AC-37

Retired (D-70, 2026-11-05): `sw_show` is ignored.

## AC-38

**Steps (conditional links).** Swap `testing/fixtures/manual/continue_cases_clist.txt` in as the aircraft's `Cessna_172SP_clist.txt` and reload the aircraft. Before each case set `beacon_on` and `navigation_lights_on` (under `sim/cockpit2/switches/`) to 1 so ticking raises no warning, and set the link lights as below. Open the case, tick its items, and read the one **Continue** button.
- Case 1: `landing_lights_on=0 taxi_light_on=0` -> `Continue: Fallback path`.
- Case 2: `taxi_light_on=1 landing_lights_on=0` -> `Continue: Taxi path`.
- Case 3: both `=1` -> `Continue: Landing path` (the link nearest the top wins).
- Case 4 (listed as `Link before the last item`; tick Beacon, then Nav lights last) with taxi on -> `Continue: Taxi path`.
- Auto-continue: run the app as `flutter run -d windows --dart-define=AUTO_CONTINUE=true`; untick one item of Case 2 and tick it again. The app opens `Taxi path` by itself, once.

Pass line: the button text is as listed in every case, there is only one button, and auto-continue opens the target without a press and only once. Restore the original checklist file afterwards.

Result: PASS | 2026-11-05 | Windows 11 desktop (release build, then a debug build with `--dart-define=AUTO_CONTINUE=true`) | X-Plane 12.4.4, plugin 0.2.0 | Task 8.3 on a hand-made list in `C172 With Conditions` (original restored): Case 1 (landing and taxi off) offered `Continue: Fallback path`; Case 2 (taxi on) `Continue: Taxi path`; Case 3 (landing and taxi on) `Continue: Landing path` (the link nearest the top wins); Case 4 (a `sw_continue` placed before the last item) `Continue: Taxi path`, the same as a link at the end. With auto-continue on, completing Case 2 opened Taxi path by itself. Finding: the earlier "Next:" buttons showed beside Continue (three buttons), so they were removed; a completed checklist now shows only the one Continue button. With no sim connected there is no Continue button.

## AC-42

**Steps (contract against the real plugin).** Load `C172 With Checklist` (the aircraft whose list is `testing/fixtures/protocol/checklist_sample.txt`, 267 bytes) with the plugin loaded.
1. `dart run tools/protocol_contract.dart http://127.0.0.1:18086 --live`. It first sets the datarefs the stream cases read through X-Plane's web API (`tools/live_setup.dart`, port 8086), so nothing is set by hand. `--no-setup` skips that.
2. Look: the last line.

Pass line: `54 passed, 0 failed` (the count grows if cases are added; failures must be 0). Add `--require-fixture-aircraft` for this record, so a wrong aircraft fails instead of skipping 10 cases. The same cases must pass against the fake and `core_test_server`: `tools/verify.sh`.

Result: PASS | 2026-11-13 | Windows 11 desktop | X-Plane 12.4.4, plugin 0.1.0 (the new `flightsim_aide` folder, `Resources/plugins/flightsim_aide/64/win.xpl`) | Plugin loaded: `Log.txt` shows `started, version 0.1.0` and `listening on port 18086`; `/v1/hello`, `/v1/aircraft` and `/v1/checklist` answer. Contract `--live` on `C172 With Checklist`: 54 passed, 0 failed, with the state set by `tools/live_setup.dart`, and again with `--require-fixture-aircraft`: 54 passed, 0 failed. Plugin Admin shows "FlightSim Aide 0.1.0" enabled.

Result: PASS (add-on aircraft, 10 cases skipped) | 2026-11-13 | Windows 11 desktop | X-Plane 12.4.4, plugin 0.1.0 | Thranda PC-12 (`PC12 Pilatus PC-12/47`, its own 25,251-byte checklist) loaded instead of the test aircraft: `dart run tools/protocol_contract.dart http://127.0.0.1:18086 --live` gave 44 passed, 0 failed, 10 skipped. The 10 skipped cases are the ones that compare the aircraft and the checklist text with the fixtures (`aircraft 200`, `aircraft query ignored`, `HEAD aircraft`, the six `checklist 200`/`304`/query cases and `HEAD checklist`); each printed `SKIP ... loaded: PC12 Pilatus PC-12/47`. The stream cases passed with their expected values read from the sim through the web API, and the setup put the throttle and ignition datarefs back. With `--require-fixture-aircraft` the same run gives 44 passed, 10 failed, as intended. This is a smaller check than the one above, not a replacement for it.

Result: PASS | 2026-11-04 | Windows 11 desktop | X-Plane 12.4.4, plugin 0.2.0 (still the version running on 2026-11-05) | Task 4.9: `dart run tools/protocol_contract.dart http://127.0.0.1:18086 --live` 49 passed, 0 failed, with the array-index, kind and cap cases from the shared fixtures; `protocolVersion` is still 1. The same cases pass against the Dart fake and `core_test_server` (`tools/verify.sh`). Not re-run on 2026-11-05: the loaded aircraft is `C172 With Conditions`, and `--live` compares the checklist text with the fixtures, which needs `C172 With Checklist`.

## AC-45

**Steps (scale).**
1. Normal list: open the largest real checklist (PC-12 Cockpit Preparation, 52 names) on the tablet. Look: no "stay manual" notice.
2. Flight-loop cost: the plugin writes one line a minute into X-Plane's `Log.txt`: `grep "flight loop" "<X-Plane>/Log.txt"`. Pass line: every `average` is under 1000 us.
3. Over-cap list: build a checklist with 140 conditioned items on different datarefs, plus one manual item: `{ echo "sw_checklist:Big:Big"; for i in $(seq 0 127); do echo "sw_item:L$i|ON:sim/cockpit2/switches/generic_lights_switch[$i]:1"; done; for i in $(seq 0 11); do echo "sw_item:S$i|ON:sim/cockpit2/switches/custom_slider_on[$i]:1"; done; echo "sw_item:Manual|done"; } > big_clist.txt`, swap it in, reload the aircraft, open it.
4. Look: paging to the end shows the amber caution icon and `14 items stay manual` (140 minus 126).

Pass line: no notice in step 1, flight-loop averages under 1000 us, and the exact notice in step 4. Known risk: with XChecklist enabled, X-Plane crashed on this 140-item list; run step 3 with XChecklist disabled.

Result: PASS | 2026-11-05 | Samsung SM-T380 (Android 9) and X-Plane 12.4.4 on the PC, plugin 0.2.0, debug build | Task 8.5. Normal checklist: the Thranda PC-12 Cockpit Preparation list (the largest checklist tested; 52 names) subscribed fully on the tablet at 5 Hz (see AC-46). Flight-loop average in `Log.txt`: all lines under 63 us across the PC-12 session (highest 62.4 us, worst single call 386 us); with the over-cap list open the lines were 5 to 57 us, one minute with an average of 26 us and a worst call of 6.6 ms. Over cap: a hand-made checklist with 140 conditioned items, every one on a different dataref (`generic_lights_switch[0..127]`, `custom_slider_on[0..11]`), plus one manual item: paging to the end showed the amber caution icon `14 items stay manual` (140 minus the 126 the app may watch: 128 plugin subscriptions minus 2 built-in signals). X-Plane did not crash with XChecklist disabled; with the same 140-item checklist and the real XChecklist 1.52 enabled, X-Plane crashed right after XChecklist read the file (`Log.txt` ends with `Forwarding exception to previous handler...`); the fault is not proven to be XChecklist's. The test file was removed and the original checklist restored. Side finding: the detail page misbehaved after the checklist count changed from 5 to 1 while it was open (recorded in `Documentation/TODO.md`).

## AC-46

**Steps (rate on the tablet).** Tablet on Wi-Fi, PC-12 Cockpit Preparation open (52 names), default 5 Hz. Run a debug build with temporary timing code that prints the arrival time of each value for one signal over three 15 s windows (the code is removed afterwards; the shipped app has none).
1. Collect the gaps between arrivals for each window.
2. Compute the median, p95, p99 and maximum.

Pass line: the median gap is near 200 ms (5 Hz) and the maximum is recorded; gaps near 0.5 to 1 s must be rare. Record the numbers in the result line.

Result: PASS | 2026-11-05 | Samsung SM-T380 (Android 9, Wi-Fi), debug build with temporary timing code (removed) | X-Plane 12.4.4 on the PC | Task 8.4 on the Thranda PC-12, checklist Cockpit Preparation open (33 items, 52 subscribed names), default 5 Hz, three 15 s windows: each signal arrived every 201 ms at the median (p95 207 to 210 ms, p99 496 to 497 ms, max 1006 to 1010 ms, no gap under 150 ms), about 253 values/s in about 17 frames/s (the plugin batches the signals on different phases, so frames come more often than 5 per second). Gaps of about 0.5 to 1 s are rare (about 1% of gaps). Also found: the tablet app does not run while the tablet is on its lock screen, and a build started with `--dart-define=SIM_IP` never leaves `Waiting for connection` because that mode does not give the repository a target; neither is a fault of the shipped beacon mode, which connected and showed the aircraft within seconds.

## AC-47

**Steps (parity with XChecklist).** `C172 With Conditions`, checklist Before start, XChecklist 1.52 and the plugin both loaded; open Before start in the app and in XChecklist's window. Reset: all four items off (see AC-35). Then, one at a time, run the command and compare the ticks in both windows:
1. `tools/sim_set.sh sim/cockpit2/switches/avionics_power_on=1` -> nothing ticked in either.
2. `tools/sim_set.sh "sim/cockpit2/electrical/battery_on[0]=1"` -> Battery and Avionics master in both.
3. `tools/sim_set.sh sim/flightmodel/controls/parkbrake=1` (beacon still off) -> Parking brake stays open in both.
4. `tools/sim_set.sh sim/cockpit2/switches/beacon_on=1` -> Beacon and Parking brake tick in both; Flight plan (no dataref) stays open in both.
5. `tools/sim_set.sh "sim/cockpit2/electrical/battery_on[0]=0"` -> no tick is removed in either.

Pass line: the set of ticked items is the same in both windows after every step, or each difference is written in the result line with its reason.

Result: PASS | 2026-11-05 | Windows 11 desktop (release build) | X-Plane 12.4.4 with the real XChecklist 1.52 and plugin 0.2.0 loaded together | Task 8.6 on `C172 With Conditions`, checklist Before start (Battery, Avionics master, Beacon light, Parking brake, Flight plan). States set from a script through the sim's web API, the user read both windows after each: (1) avionics on, battery off: nothing ticked; (2) battery on: Battery and Avionics master ticked; (3) parking brake on with the beacon off: Beacon and Parking brake stayed open; (4) beacon on: Beacon and Parking brake ticked, Flight plan (no dataref) stayed open; (5) battery off again: no tick was removed. The user gave one answer per step for both windows, and no difference was reported. No difference needed an explanation. Not exercised: the change operators (`+>`, `-<`, `><`), so D-58 (the baseline) is neither confirmed nor amended by this run.

## AC-50

**Steps (production build).** No development flag anywhere.
1. Windows: `flutter build windows --release -t lib/main.dart`, run the exe.
2. Tablet: `flutter build apk --release -t lib/main.dart` and install it fresh.
3. X-Plane running with `C172 With Conditions`, parking brake set (`tools/sim_set.sh sim/flightmodel/controls/parkbrake=1`).
4. Look on each device: the app finds the sim, shows the checklist, and Parking brake ticks by itself. Then `tools/sim_set.sh "sim/cockpit2/electrical/battery_on[0]=1"`: Battery ticks.

Pass line: both devices do step 4 with no flag and no manual IP.

Result: PASS | 2026-11-05 | Windows 11 desktop and Samsung SM-T380 (Android 9) | X-Plane 12.4.4, plugin 0.2.0 | Task 9.10 on `C172 With Conditions`: `flutter build windows --release -t lib/main.dart` and `flutter build apk --release -t lib/main.dart`, no development flag, tablet freshly installed. Both found the sim, loaded the checklist and auto-checked an item (Parking brake at once because the brake was already set; Battery when switched on). Plugin log: no error lines. Recorded from the user's report.

## AC-53

**Steps (plugin health).**
1. Start X-Plane with the plugin; `grep -n "flightsim_aide" "<X-Plane>/Log.txt"` shows `started, version` and `listening on port 18086`, and `grep -n -i "flightsim_aide.*\(error\|fail\|warn\|exception\)" "<X-Plane>/Log.txt"` prints nothing.
2. Keep XChecklist enabled in the same session (it is loaded when `Log.txt` has `Xchecklist: ver`), and run the AC-47 steps.
3. Quit X-Plane from its menu. Read the end of `Log.txt`: `flightsim_aide: server stopped`, `Unloading plugin FlightSim Aide`, `flightsim_aide: stopped`, `Clean exit from threads`, `X-Plane has shut down`.
4. CI: `gh run list --workflow plugin.yml --limit 1` shows success; its jobs ran on Windows, macOS and Linux.

Pass line: all four hold.

Result: PASS | 2026-11-05 | Windows 11 desktop | X-Plane 12.4.4, plugin 0.2.0 | Loads clean: `flightsim_aide: started, version 0.2.0` and `listening on port 18086`, and no flightsim_aide error, fail or warning line in the whole session. Exits clean: after File > Exit, `Log.txt` ends with `flightsim_aide: server stopped`, `Unloading plugin FlightSim Aide 0.2.0`, `flightsim_aide: stopped`, `Clean exit from threads` and `X-Plane has shut down`. Coexists with the real XChecklist 1.52, loaded in the same session through the 8.6 parity run. CI run 42022932150 was green on Windows, macOS and Linux (task 4.11). Known: with XChecklist enabled, a 140-item single checklist crashed X-Plane (see AC-45); not proven to be XChecklist.

## AC-54

**Steps (switch).** Aircraft with a checklist that has a switch, for example the Thranda PC-12 with `sw_switch:Using GPU|gpu|OFF` in Before start and an `sw_if|gpu|ON` block in a later checklist.
1. Open the checklist with Auto on. The `Using GPU` row has a check circle at the left, a `manual item` pill and a switch that is off; auto-check stops there and does not tick it or pass it. The ON branch is not shown at all (no grey rows) and the count (`n/N`) includes the row and the OFF branch but not the ON branch.
2. Press Check until the hidden items would be next: it passes over them. Tapping the row ticks it; the switch does not move.
3. Turn the switch on: the OFF branch disappears, the ON branch appears and the total changes. Tick one of the ON items (or let auto tick it).
4. Turn the switch off: the tick of the ON items is gone and the total changes back.
5. Open the later checklist with the `sw_if|gpu|ON` block: it shows the branch for the position of the switch and no switch row. Change the switch in the first checklist, come back: the later checklist follows.
6. With the switch row open, press Skip: the row is skipped (amber) and the pointer moves past the block. Tap an item below the block: the pointer follows. Tick the row by hand: auto carries on.
7. Turn the switch on, press Reset and confirm: the ticks clear, the switch stays on.
8. Close the app and open it again (same X-Plane run): the switch position is as it was when some item was ticked.

Pass line: all eight hold, in the dark and the light theme.

Result: NOT RUN | 2026-11-15 | Needs the owner at the PC with the Thranda PC-12 checklist copied to X-Plane (rewritten to `sw_switch`, `sw_if`, `sw_else` and `sw_end`; the blocks are in the local example file).

## AC-57

**Steps (calculated values).** The Thranda PC-12 with a checklist that has an item followed by `sw_calculate` lines and a `sw_table` for them (the local example file after the max cruise power step), X-Plane running with the plugin.
1. Open the checklist. Under the item there is a band with the first line large (torque) and the other lines as rows. The total (`n/N`) is the same as without the band, and tapping the band ticks nothing.
2. Fly level at an altitude and weight inside the chart. Compare each value with the chart in the flight manual for the same ISA deviation, pressure altitude and weight: they agree to the rounding of the line.
3. Climb and descend: the values change smoothly while you move, and the band does not flicker.
4. Climb above the highest altitude in the table (or use a weight or temperature beyond it): an amber warning at the top of the band says which input is beyond the limit and which value is used; the values below it are those of the limit.
5. Stop the plugin or close X-Plane: every line shows `no data`; start it again: the values come back.
6. Check the band in the dark and the light theme and with a long warning on a narrow window.

Pass line: all six hold.

Result: DEFERRED (not run) | 2026-11-16 | The owner tried the PC-12 file with the table and reported that it works, but the six steps were not gone through: the chart comparison at altitude (step 2), the warning above the table (step 4) and the loss of the plugin (step 5) are unchecked. Deferred by the owner.

## AC-65

**Steps (real speech and microphone).** The app on an Android phone (the main target; on Windows it is best effort: write down what fails in `BUILDING.md` and do not work around it), X-Plane running with the plugin and an aircraft whose checklist has a `sw_challenge: ON` ... `sw_challenge: OFF` block, a headset or the phone's speaker in a quiet room.
1. Settings > Voice: both switches are off. Open a checklist: nothing is spoken and there is no Pause button.
2. Turn on Voice for flows and open a checklist. The system asks for the microphone: allow it. The first item is read as its label and result, and a Pause button shows.
3. Say "set": the item ticks and the next one is read. Say "chek": it asks "Did you mean check?"; say "yes": the item ticks. Say "skip": the item is skipped.
4. Say "pause checklist": the voice stops and PAUSED flashes with an icon. Say something else: nothing happens. Say "resume checklist" (also try "continue checklist"): it reads the item to do now.
5. With auto on, do the action in the sim: the item ticks by itself and the next one is read. With auto off, a true dataref does not move on, but a tick or "set" does.
6. Tick an item the sim says is not set: the voice says "Double check" and the item name.
7. Turn on Voice for challenges, open a challenge block with two items the sim already agrees with: each is said as the challenge, a pause, then the response. With more than two in a row: "N verified", then the first open item. Answer it by voice.
8. The voice never ticks an item by hearing itself, and a phrase that is not an answer does nothing.
9. Turn the microphone permission off and reopen the checklist: a microphone-off icon shows and the voice still speaks.
10. Check PAUSED in the dark and the light theme, and with the system's animations turned off (steady, not flashing).

Pass line: all ten hold.

Result: NOT RUN | 2026-11-17 | Needs the owner with a phone (or the PC) and the sim; nothing about the real speech engine or the microphone has been tried yet.

## Plugin runs on the simulator (SIM)

Results for the plugin shell in X-Plane 12.4.1 (`sim.version` 12441), Windows, layout A (`plugins/flightsim_aide/64/win.xpl`), 2026-10-24. An early experiment plugin was also loaded.

### 4.1 Plugin loads

- Layout A loads on XP12; `Log.txt` has `flightsim_aide: started, version 0.1.0` and `listening on port 18086` after a plugin reload as well.
- Not yet done: layout B, the stop line at quit.

### 4.2 Values over XPLM

Through `tools/stream_watch.dart` (not the log): `sim/flightmodel/failures/onground_any` = 1 (parked); `sim/time/total_running_time_sec` rising (153.24, 153.75); `sim/does/not_exist` gives `unknown_name`; `sim/cockpit2/engine/actuators/throttle_ratio` gives `unsupported`; `xchecklist/aircraft_generation` = 1. PASS.

### 4.3 Aircraft info

- C172 SP: ICAO `C172`, description `Cessna 172 SP Skyhawk - 180HP`, no checklist file, `/v1/checklist` is 404 `no_checklist`.
- Thranda PC-12: ICAO `PC12`, description `Pilatus PC-12/47`, checklist `Thranda_PC12_clist.txt` found.
- Open: the case with `<acf name>_clist.txt` next to a `clist.txt` (needs a test aircraft folder, task 4.9).

### 4.4 Aircraft change

First build bumped the generation in `XPluginReceiveMessage`; the flight loop does not run while the sim loads, so `/v1/aircraft` showed the new generation with the old ICAO for 64 s (PC-12) and 8 s (C172). Fixed: the bump now happens after the cache rebuild. With the fix, polling `/v1/aircraft` every 0.1 s over C172, PC12, C172 showed generation and ICAO changing in the same step, +1 each (0 to 1 to 2). A livery message arrives after every aircraft load; it rebuilds without a bump. Open: the exact "within 2 s" timing (the sim's load time dominates) and a livery change on its own.

### 4.3 (second run) and 4.9, X-Plane 12.4.1, 2026-10-24

Test aircraft (copies of the stock C172 under `Aircraft/XChecklist Test/`, not in the repo): `C172 With Checklist` has `Cessna_172SP_clist.txt` (= `checklist_sample.txt`, 267 bytes) next to a decoy `clist.txt`, with ICAO `C172` and description `Cessna Skyhawk 172SP`; `C172 No Checklist` has neither file.

- 4.3: three aircraft checked: C172 SP (stock, no checklist), Thranda PC-12 (`Thranda_PC12_clist.txt`) and the test aircraft, where `/v1/checklist` equals `checklist_sample.txt` byte for byte, so the named file wins over `clist.txt`. ICAO, description, aircraft path and checklist path are correct in `Log.txt` and `/v1/aircraft`. PASS.
- 4.9, contract: `dart run tools/protocol_contract.dart http://127.0.0.1:18086 --live` with the test aircraft loaded: 40 passed, 0 failed (HTTP and stream cases, the stream value cases use the real on-ground dataref, 1 while parked). `--live` takes generation, aircraft path and checklist time from the server and still compares ICAO, description and checklist text.
- 4.9, file edit (checklist appended to while the sim ran): `checklistModified` and `checklistSize` changed after 795 ms (267 to 291 bytes), generation stayed 1. Restoring an older copy (mtime 2026-10-01) was seen after 2031 ms (mtime went down, size back to 267), generation still 1. Log line: `checklist file changed on disk, reread (generation unchanged)`.
- 4.9, `POST /v1/aircraft` gives 405, an unknown path 404 (from the sim PC itself).
- Open for 4.9: `curl` including `-X POST` from another LAN machine.
- 4.9, no-checklist aircraft (`C172 No Checklist`, generation 2): `dart run tools/protocol_contract.dart http://127.0.0.1:18086 --scenario no_checklist --live`: 19 passed, 0 failed (the 404 `no_checklist` cases). 2026-10-24.
- 4.9, from another LAN machine (a Mac, 192.168.1.x to 192.168.1.10:18086): `curl /v1/hello` returned the hello JSON (port 18086, sim 12441); `curl -X POST /v1/aircraft` returned 405 `method_not_allowed` ("Only GET and HEAD are allowed."). 2026-10-24. 4.9 complete.

### 4.1 layout B and 4.8 partial, X-Plane 12.4.1, 2026-10-24

- 4.1: layout B (`plugins/flightsim_aide/win_x64/flightsim_aide.xpl`) loads on XP12 after Plugins > Reload plugins: start line, `listening on port 18086`, `/v1/hello` answers. Layout A (`64/win.xpl`) loaded earlier. Both work on XP12. The stop line of layout B is not yet seen (unload only).
- 4.8, disable then enable in Plugin Admin: after disable `/v1/hello` is refused (curl exit 7), `Log.txt` shows `server stopped`, the X-Plane thread count fell from 120 to 109; after enable `/v1/hello` answers again and the threads are 118 (not exactly 120; X-Plane's own threads vary, so this is "about the same", not an exact match).
- 4.8, occupied port: with `python -m http.server 18086` holding 18086 and an early experiment plugin holding 18087, the plugin bound **18088** (`listening on port 18088`), and `/v1/hello` on 18088 reports port 18088. The next free port is taken, as designed.
- Open for 4.8: three normal quits, a quit with a stream client connected, and a quit during a `curl --limit-rate 1k` download.

### 4.8 quits and 4.1 stop line, X-Plane 12.4.1, layout B, 2026-10-25

Each quit read from `Log.txt` before the next start: `flightsim_aide: server stopped`, `Unloading plugin FlightSim Aide`, `flightsim_aide: stopped`, `Clean exit from threads.`, `----- X-Plane has shut down -----`, and no X-Plane process left.

- Quits 1, 2 and 3: normal quits. PASS.
- Quit 4: a `tools/stream_watch.dart` client subscribed at 10 Hz when X-Plane quit; its last frame came at the quit and the client ended. PASS.
- Quit 5: `curl --limit-rate 1k http://127.0.0.1:18086/v1/checklist` mid-transfer (a 1,499,973-byte test checklist, about 25 minutes at that rate). X-Plane exited cleanly. The curl process stayed alive on its own afterwards (it was still draining data it had already received) and was ended by hand by process id. PASS.
- The test aircraft's checklist file was restored to the 267-byte sample afterwards.
- 4.1: the layout-B stop line is in the quit logs. `grep -rln XPLM plugin/src` lists only files under `src/xplane`.

### 4.11 Flight-loop cost, X-Plane 12.4.1, 2026-10-25

The plugin logs one line a minute (`flight loop: N calls, average X us, worst Y us`, `steady_clock` around the whole callback, including the hub tick). Parked aircraft (test C172), sim unpaused, about 71 calls per second, real XChecklist plugin loaded in the same install. Ten consecutive minutes per case:

| Case | Average per call | Worst call |
|---|---|---|
| No stream client | 3.9 to 4.2 us | 211 us |
| 1 client, 2 signals at 10 Hz | 5.8 to 6.2 us | 270 us |
| 4 clients, 2 signals each at 10 Hz | 6.2 to 6.8 us | 211 us |

All averages are far below the 1 ms limit of AC-24. The window boundaries are not aligned with the moment each client was started, so the first line of a case may include part of the previous case. A parked aircraft with a small panel is the cheap case; a flight with a heavy aircraft was not measured. The user confirmed that the real XChecklist plugin worked normally during the runs.

### 4.4 livery change, X-Plane 12.4.1, 2026-10-25

A livery change on its own (same aircraft): `Log.txt` shows `user livery loaded, generation unchanged`, then the cache rebuild line for the same C172 test aircraft; `/v1/aircraft` polled every 0.1 s stayed at generation 1 with unchanged data. A livery message also arrives after every aircraft load (early log), so it never needs its own bump. PASS.

"Within 2 s": the cache is rebuilt in the first flight-loop call after the message, and the loop runs every frame (about 71 per second). The load time of the sim itself cannot be separated from that, so no stopwatch figure is claimed; what was measured is that generation and ICAO change together.

### 4.12 Linux build, WSL (Ubuntu 24.04, g++ 13.3, cmake 3.28.3), 2026-10-26

Run with `tools/platform/linux/task_4.12_plugin_build.sh --sdk external/XPSDK430/SDK` from a clone on the Linux file system (`~/flightsim_aide`). Result: PASS (configure, build and ctest 3 of 3 for the core; configure and build of the X-Plane shell; `flightsim_aide.xpl` is an x86-64 ELF shared object). Not run: the shell inside a Linux X-Plane, the contract runner (CI, 4.13).

Two Linux-only defects found and fixed on the way:

- `stream_codec_test.cpp`: `std::stod` throws `out_of_range` on the denormal 5e-324 with glibc (MSVC accepts it). The test now uses `std::strtod`. Red seen: core_tests failed 1 of 161.
- `CMakeLists.txt`: the static libraries were not position-independent, so linking `flightsim_aide.xpl` failed ("recompile with -fPIC"). Now `CMAKE_POSITION_INDEPENDENT_CODE ON`. Red seen: the shell link failed.

macOS half of 4.12, MacBook (Darwin arm64, Apple clang, cmake 4.4.4), 2026-10-26: run with `tools/platform/mac/task_4.12_plugin_build.sh --sdk ~/dev/xplane-sdk/SDK` (SDK 4.3.0). Result: PASS (configure, build and ctest 3 of 3 for the core; configure and build of the X-Plane shell; `flightsim_aide.xpl` is universal, x86_64 and arm64). Not run: the shell inside a macOS X-Plane, the contract runner (CI, 4.13).

One macOS-only defect found and fixed on the way: `plugin/third_party/civetweb/VERSION` and `plugin/third_party/doctest/VERSION` are on the include path, and the case-insensitive macOS file system resolved `#include <version>` (a C++ standard header) to them, so the core build failed. Both are now `VERSION.txt`. Red seen: core build failed with "unknown type name 'civetweb'" / "'doctest'".

macOS rerun of 4.12, MacBook (Darwin arm64), 2026-11-02 (after the package rename): `tools/platform/mac/task_4.12_plugin_build.sh --sdk ~/dev/xplane-sdk/SDK` PASS (core ctest 3 of 3; `flightsim_aide.xpl` universal, x86_64 and arm64). The first run failed on a stale CMake cache copied from the old folder path (`plugin/build/4.12-darwin/{tests,shell}`); deleting those two folders fixed it. Runtime check by the user: the ad hoc signed build was installed as `Resources/plugins/flightsim_aide/64/mac.xpl` (layout A) in a macOS X-Plane 12, appears enabled as "FlightSim Aide" in Plugin Admin, and `GET /v1/hello` answers with `os` macos and a `runId`. So layout A loads on macOS. Not run: the contract runner against it, the app on this plugin.

## Device runs

### Android tablet run, 2026-10-26 (10.2, 10.5, 8.8a, 8.11, 10.7, 6.9)

Device: Samsung SM-T380 tablet (Android 9, API 28), release APK, PC 192.168.1.10 on the same Wi-Fi. X-Plane 12.4.1 with the real plugin on 18086 (not `core_test_server`, which the task text names for 10.5 and 10.7; the real plugin was already running). The device is a tablet, not a phone.

- 10.5 release build: PASS. Plugin detected by the beacon, aircraft and checklist shown, the stream followed an aircraft change (banner within a few seconds). R8 and the network config behaved.
- 10.2 beacon with the multicast lock: PASS for the beacon (about 5 s or less). The lock is not observable in a release build.
- 8.8a banner against the status bar and app bar: PASS on the list screen, no overlap with the status bar or the app bar. The detail screen was not reported separately.
- 8.11 dark mode: PASS, looked fine.
- 10.7 lifecycle (Android): PASS. Backgrounding for a short time kept the banner and the ticks; lock for about 20 s and unlock came back to the same state; Wi-Fi off showed "reconnecting" and Wi-Fi on reconnected by itself. Not run: a full one-minute background, and a stop/start of the server. The iPhone half is open.
- 6.9 phone against the server: done with the real plugin instead of `core_test_server` and the beacon instead of `SIM_IP`; the checklist showed in a release build and there was no cleartext or firewall problem.
- Observed, already in `Documentation/TODO.md` section 3: the red no-checklist banner stayed after the checklist aircraft was loaded until dismissed.

### iPhone lifecycle run, 2026-10-27 (10.7, iPhone half)

Device: iPhone 16, release build, PC 192.168.1.10, X-Plane 12 with the real plugin on 18086.

- Background for one minute: PASS. Lock and unlock: PASS. Wi-Fi off and on: PASS. Each reconnected by itself with the two ticks kept.
- Server stop/start: the script's step used `core_test_server`, but the plugin in X-Plane already held 18086 and the app stayed connected to it, so the script recorded FAIL (did not disconnect). That is correct behaviour for one app and two servers, not a bug. Redone by disabling the plugin in X-Plane for 15 s and enabling it again: PASS (the app showed disconnected, reconnected by itself, ticks kept).
- Note for testing: with two servers on one network the app connects to only one; use Plugin Administration to simulate a sim restart (`Documentation/TODO.md` section 3).
