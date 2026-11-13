# TODO

Things that are known, wanted and not done yet. The plan (`Documentation/Plan/PLAN.md`) says what is in scope; this file is for what had to wait, why, and what unblocks it. Remove a line when it is done (note the commit in the commit message), and move a line to `Documentation/Architecture/DECISIONS.md` if it is waived on purpose.

Last reviewed: 2026-11-05.

## 1. Connection tests deferred (2026-10-27)

The connection work was closed on 2026-10-27 with the tests below not run (D-47 in `Documentation/Architecture/DECISIONS.md`). Each one needs the owner at the PC, a flight, a device or a clean machine. None needs code, except where a row says so. Do them at a later date and record each result in `Documentation/Testing/MANUAL_TEST.md`. The release went out with these still open, so treat them as **unverified** until done.

Tasks that need the PC come first, then those that need a Mac.

| Task | What | Needs | Why it matters | Done when |
|---|---|---|---|---|
| 4.3a | On-ground dataref in every situation: parked, taxi, takeoff roll, airborne, touchdown, rollout, water/carrier (XP12) | An aircraft in flight | Closes open item 3 (final dataref name and meaning); the restore policy depends on it | Values written to `Documentation/Testing/MANUAL_TEST.md` and `ARCHITECTURE.md` 16.y item 3 |
| 11.2 (airborne variants) | Desktop AC-16 and the other scripts with on-ground = 0 | An aircraft in flight (same flight as 4.3a) | Restore-policy behaviour while airborne | Recorded |
| 11.3 (AC-16) | Phone run of AC-16, tablet and iPhone | An aircraft in flight, a phone | Same as above, on a phone | Recorded |
| 11.2 (parked leftovers) | Wi-Fi-off variant of AC-27; unchanged-file reconnect in AC-13 (no `GET /v1/checklist`); a start with no plugin in AC-9 | The PC with X-Plane | Reconnect and cache behaviour on the desktop | Recorded |
| 11.3 (AC-13 leftovers) | Unchanged-file reconnect, older-mtime restore, edit while the app is closed (tablet and iPhone) | A phone | Cache rules on devices | Recorded |
| 11.3 (AC-8, 11) | Ticking while the aircraft-change banner shows, and its 3 s limit (tablet); the red message for `300.1.1.1` on the tablet (section 4) | The tablet | Two partial acceptance criteria | Recorded; the IP message needs a screenshot of the dialog with the keyboard open |
| 10.7 | Android: server stop/start (disable and enable the plugin in Plugin Administration, not a second server) and a full one-minute background | The tablet | Last open part of the lifecycle task; the iPhone half passed | Recorded |
| 4.14 | Follow the `plugin/README.md` install section on a clean X-Plane 12 install | A clean X-Plane 12 install | Proves the install notes | Recorded; fix the README where it was wrong |

Also not done: re-check the no-cleartext finding on a newer Android (section 3), and re-run `dart run tools/protocol_contract.dart <url> --live` after any plugin change (last run 2026-10-27: 40 of 40).

Until these are done, treat as **unverified**: the on-ground value while airborne and everything that depends on it (the restore policy in flight), the unchanged-file cache path on a device, and the install notes on a clean machine. Verified and no longer deferred (2026-10-26 and 27): the iOS Info.plist keys (10.3), the iOS release build (10.6), the iPhone lifecycle run (10.7), the iPhone acceptance run (11.3), the denied Local Network message.

## 2. Connection work in progress (not deferred, just not finished)

- 3.12: optional Android release-build row (the iOS rows are 3.12a). 3.12 and 3.13 are done for Android; 3.12a is tracked on its own above.
- The `--synthetic` counter rises once per server tick, so duplicate and skipped sequence numbers in the rate test reflect tick/frame timing, not network loss (TCP does not drop frames). Consider a per-frame counter in the hub if cleaner numbers are wanted.
- ~~Measure the stream rate that reaches the app with the real plugin: the values are sampled on the sim's flight loop, so a slow sim frame rate can lower it.~~ **Closed 2026-11-04** by a measurement (write-up not published): the rate holds at the sim's frame rate; the low-fps case was dropped by the user.

- Plugin shell: loaded and tested in XP12 on Windows (layouts A and B). All plugin SIM tasks are done. The 4.12 builds and the 4.13 workflow were done on 2026-10-26; only the 4.14 clean-install walkthrough is still open (section 1).

## 3. Open design items

- iOS Local Network denied (early test, write-up not published): beacon silent and every LAN connect fails at once with errno 65. **Built; seen on the iPhone 2026-10-27 (10.6):** with the permission off, the app showed "X-Plane is not responding" for the 2 s window, then the message below; turning it on again recovered without a restart. `HttpCompanionPluginService` flags errno 65 (`PluginUnreachable.noRouteToHost`), `FlightSimConnectionService` reports a probe round where every port failed that way (`PluginStateNotDetected.noRoute`), the repository maps it to `ConnectionLocalNetworkDenied`, and the UI shows "Local Network access may be off." with Retry and Enter IP address. Tests use fakes that fail with errno 65. It only fires once a sim address is known (manual IP), because the denied beacon is silent. 
- Testing with two servers on one network (for example the real plugin in X-Plane and `core_test_server` on the same PC, or two X-Planes): the app connects to only one of them, which is correct. The plugin in X-Plane already holds port 18086, so a test server must use another `--port`, and stopping it does not affect an app connected to the plugin. For a server stop/start test, disable and re-enable the plugin in X-Plane (Plugins > Plugin Administration) instead.

- Reload right after saving a checklist edit showed no change (tablet and iPhone): the plugin re-stat the file only every 3 s. **Fixed in the plugin and seen in the sim on 2026-10-27 (Reload right after saving showed the edit at once):** `/v1/aircraft` now asks the sim thread to re-check the file first and waits up to 500 ms (`Cache::requestRefresh`, PROTOCOL.md).- Extra checklist search locations (config file format and lookup order). Only the aircraft folder is searched now.
- Which checklist counts as the shutdown checklist (the last one in the file is assumed; confirm against real files).
- Re-check the no-cleartext finding (D-43) on a newer Android (14 or 15): it was measured on Android 9 only. Also re-check beacon reception there (multicast lock, newer Wi-Fi permissions).

## 4. Housekeeping

- `.claude/settings.json` allow list is mostly redundant with auto mode; trim if wanted.
- Intermittent failures in `test/data/services/flight_sim/flight_sim_connection_service_test.dart` (real sockets, 500 ms probe timeouts) when the whole suite runs in parallel: seen twice on 2026-10-25 (`reconnect leaves one active subscription per signal`; `remembers the working port` and `resubscribes after reconnect`), green when run alone and on the next full run. Raised the probe and HTTP timeouts in that test file from 500 ms to 3 s on 2026-10-25 (two clean full runs after); if it flakes again, switch those tests to a fake transport before the CI run in 4.12. It flaked again on 2026-10-26 in a fresh clone (3 of 3 full runs): the cause was the fake server writing to a WebSocket that had just closed (`Bad state: StreamSink is closed`, an unhandled error in its stream timer). `fake_companion_plugin_server.dart` now catches that; 3 of 3 full runs in the fresh clone then passed.
- (Fixed: beacons of one computer name are merged and the addresses are probed in turn.) Sim chooser lists one X-Plane several times when the app runs on the sim PC (one beacon per network adapter, found 2026-10-25: SIMPC at 192.168.1.10, 172.23.0.1 and 172.27.112.1). A phone sees one entry. Consider collapsing same-name, same-port entries and preferring the address the plugin answers on.
- The red "no checklist" error banner stays after the user loads an aircraft that has a checklist; it clears only when dismissed with X (found 2026-10-25 in AC-14). Consider clearing a failure banner when the connection moves to an aircraft that loads.
- On the tablet, `300.1.1.1` in Enter IP address disables Save but shows no red message (found 2026-10-26, AC-8); the desktop shows "Enter four numbers like 192.168.1.20". 2026-10-27: not reproduced in a widget test (1024x600 window, 360 px keyboard inset; the error stays above the keyboard), so the cause is not the dialog logic or the keyboard overlap. Guard test added; the tablet needs another look (screenshot of the dialog with the keyboard open).
- `--dart-define=SIM_IP=<ip>` does not drive the connection UI: `NetworkLink.start()` connects the raw service but never starts `FlightSimRepositoryRemote`, so the card stays on Searching and times out with "X-Plane not found" although the plugin answers (found 2026-10-25 in the AC-9 wrong-version run). Use beacon discovery or Enter IP address until fixed; or pass the host to the repository's start.
- When the aircraft's checklist file changes while the detail page of a checklist is open and the new file has fewer checklists (found 2026-11-05: five lists, then one), the detail page stays on a checklist number that no longer exists and misbehaves until the user backs out to Home. Decide what the page should do (go back to the list, or show "this checklist is gone"), add a red-first test, fix.

## 5. Auto-check: deferred or open (2026-11-05)

- **8.7 airborne readings** (needs a flight, and a joystick): the same flight closes 4.3a and the 11.2 airborne variants listed in section 1. Waived for the release; unverified until done.
- **8.9 iPhone script** and every `[MAC]` task: deferred until the user decides to support Apple products (the iPhone test scripts are in the old development repository, written and not all run; bring them back when Apple support starts).
- **Change operators on a live run:** the amended baseline of D-58 (`+>`, `-<`, `><`) was never compared with XChecklist in the sim; write a short list with one such item and compare when wanted.
- **Options have no Settings page:** `stream_rate_hz` and `auto_continue` are set only by `--dart-define` (`STREAM_RATE_HZ`, `AUTO_CONTINUE`).
- **No Continue button without a sim:** the old "Next:" buttons were removed, so an offline checklist has no way to jump to the next one except the list.
- **XChecklist 1.52 and a 140-item checklist:** X-Plane crashed right after XChecklist read the file. Not proven to be XChecklist's fault. The app and our plugin did not crash with XChecklist disabled.
- **Two bugs kept from section 4** (not fixed): the `SIM_IP` wiring and the stale detail page after the checklist count drops.

## 6. Idea for later: choose aircraft, airport and start position from the app (2026-11-07)

Not decided, not scheduled; recorded so it is not lost. From a conversation with the user. Facts about the X-Plane SDK are from memory and must be checked against the headers before any design.

**Goal:** the app lists the aircraft that have a checklist, loads one in the sim, and places it at an airport and a start position.

**Steps, in the order proposed (each can be tried in the sim before the next):**
1. **Aircraft list and load.** The plugin scans the `Aircraft` folder for `.acf` files with a checklist and sends the list; loading uses `XPLMSetUsersAircraft` (full path to the `.acf`; it reinitialises the user at the nearest airport). Start it from a flight loop callback, not inside another callback. A global plugin is not unloaded by the change.
2. **Airport search.** Nav database search for airports (id, name, lat/lon), then `XPLMPlaceUserAtAirport`.
3. **Start-location list.** From the airport's `apt.dat` block: type 1300 records (lat/lon, heading, name, aircraft kinds). The app shows "Gate A1, Ramp 3"; `XPLMPlaceUserAtLocation` places the aircraft. Fallback for step 4 and for small screens.
4. **Airport map.** X-Plane's own picker is a schematic, not a full map: runways as thick lines with end numbers (type 100 records), grey dots for start locations, a blue pin for the selection, a text block (name, lat/lon, elevation, magnetic variation, contributors), zoom +/-. Taxiway outlines (type 110) can wait. Flutter: `CustomPainter` in an `InteractiveViewer`, a lat/lon projection, a hit test on the dots (generous hit area, the dots are dense), and a "Place aircraft here" button. The plugin parses the one airport and sends a small JSON, so the app never reads `apt.dat`. Estimated as moderate (days), not a large project.
5. **Aircraft configuration** (fuel, payload, switches, cold-and-dark or ready-to-start presets). Last and hardest: each aircraft needs different datarefs, and it needs write operations.

**Risks and open questions:**
- **Custom scenery:** an airport in a custom pack overrides the default `apt.dat`; the plugin must read `scenery_packs.ini` and look in the packs in order. Where the contributor names are stored in `apt.dat` is unchecked.
- **Writes and security:** the protocol only reads today. Loading an aircraft or writing datarefs lets anything on the Wi-Fi change the sim, so it needs some pairing or confirmation on the sim side. Decide before any write operation.
- **Version rule:** each new operation is a functional change, so the plugin minor version rises (`0.x.0`); the new operations are probably optional for `protocolVersion`.
- **Layering:** `XPLM` calls only under `plugin/src/xplane`; the app side stays behind `FlightSimService` / `ChecklistSourceService` or a new service pair.
