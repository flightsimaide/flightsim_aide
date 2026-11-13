# Companion plugin protocol, version 1

This is the wire contract between the FlightSim Aide app and a simulator companion (the X-Plane plugin in this folder, or any other implementation). The Dart fake (`testing/fakes/plugin/`), the plugin core and the real plugin must all answer the shared cases in `testing/fixtures/protocol/` identically (`tools/protocol_contract.dart`). If this file and the plan disagree, this file is corrected from the fixtures and the plan follows (`Documentation/Plan/PLAN.md` section 5).

Everything is plain `http://` and `ws://` on one TCP port, read-only, on a trusted LAN. There is no authentication and no TLS.

## 1. Compatibility

- `protocolVersion` is the integer `1`. The app requires **equality**: any other value means "update the plugin" (or the app) and the app makes no further request.
- Unknown JSON fields are ignored by every reader. Required fields that are missing are a protocol error.
- Adding an optional field or a new `op` the peer may ignore does not change the version. Changing the meaning of anything below does.

## 2. Handshake: `GET /v1/hello`

The app learns the sim's IP from X-Plane's multicast beacon (or a manual entry), then probes this endpoint to find the plugin.

- **Port.** The plugin prefers `18086` and walks `18087` to `18093`. There is no OS-assigned fallback. If no port binds the plugin serves nothing and logs why. The app probes all eight ports in parallel (about 1 s timeout), takes the first valid answer and remembers the port.
- **Response** `200`, `Content-Type: application/json; charset=utf-8`, `Cache-Control: no-store`:

```json
{"protocolVersion":1,"sim":{"kind":"xplane","version":"12.1.4"},"os":"windows","pluginVersion":"0.1.0","runId":"a1b2c3d4e5f60718","port":18086,"streamPath":"/v1/stream"}
```

| Field | Type | Required | Meaning |
|---|---|---|---|
| `protocolVersion` | integer | yes | See section 1 |
| `sim.kind` | string | no | `xplane` for this plugin; another sim's companion says something else |
| `sim.version` | string | no | The simulator's version, informational |
| `os` | string | no | The OS of the computer the sim runs on: `windows`, `macos` or `linux`. Added after the first release; the app shows it in the computer list and works without it |
| `pluginVersion` | string | no | The companion's own version, informational |
| `runId` | string | yes | Random text the plugin picks when X-Plane loads it (16 hex characters). It is the same for the whole X-Plane run and changes when X-Plane is restarted, so the app can tell a restart from a dropped link. A hello without it is a protocol error |
| `port` | integer | yes | The port that answered (equals the port in the request URL) |
| `streamPath` | string | yes | Path of the WebSocket stream, `/v1/stream` |

- **Not detected rule.** No valid answer from any port within about 2 s of the sim IP being known is "plugin not detected" (never "not installed": X-Plane still loading looks the same). The app keeps probing.

## 3. HTTP rules (all endpoints)

- Served paths: `/v1/hello`, `/v1/aircraft`, `/v1/checklist` and the WebSocket `/v1/stream`. Query strings are ignored. No request value ever selects a file; the only file the plugin opens is the current aircraft's checklist, chosen by the plugin.
- A served path accepts `GET` and `HEAD`; any other method on it gives `405` with `Allow: GET, HEAD`. Any other path gives `404`, whatever the method (this includes `//v1/aircraft`, `/v1/checklist/..%2f..` and `/`).
- `HEAD` returns the headers of the matching `GET` (including `Content-Length`) and no body.
- Errors are small JSON bodies `{"error":"<code>","message":"<text>"}` with the right status. Codes used: `not_found` (404), `method_not_allowed` (405), `upgrade_required` (400, plain `GET` on the stream path), `no_checklist` (404 on `/v1/checklist`), `too_large` (413), `limit` (503, see section 7).
- The LAN-only rule: the plugin admits only private-range and loopback source addresses (10/8, 172.16/12, 192.168/16, 169.254/16, 127/8). Others are refused at the connection.

## 4. `GET /v1/aircraft`

`200`, `application/json; charset=utf-8`, `Cache-Control: no-store`. Field order is fixed and the output is compact (no spaces), so implementations can be compared byte for byte:

```json
{"protocolVersion":1,"generation":12,"icao":"C172","description":"Cessna Skyhawk 172SP","aircraftPath":"Aircraft/Laminar Research/Cessna 172SP/Cessna_172SP.acf","checklistPath":"Aircraft/Laminar Research/Cessna 172SP/clist.txt","checklistModified":1761206400123,"checklistSize":267}
```

(267 is the byte length of `checklist_sample.txt`; it is the value in the golden file `aircraft_with_checklist.json`.)

| Field | Type | Required | Meaning |
|---|---|---|---|
| `protocolVersion` | integer | yes | Equal to the handshake's |
| `generation` | integer | yes | Incremented on every aircraft load, not on file edits; wraps at 2^31. The app compares for inequality |
| `icao` | string | no | Aircraft ICAO, may be empty |
| `description` | string | no | Human-readable aircraft name |
| `aircraftPath` | string | yes | Path of the `.acf` as the sim reports it (POSIX separators). Opaque to the app, which only hashes it |
| `checklistPath` | string | when a checklist exists | Path of the file the plugin used (`<acf name>_clist.txt` first, then `clist.txt`, next to the `.acf`) |
| `checklistModified` | integer | when a checklist exists | Last-write time, epoch **milliseconds** UTC |
| `checklistSize` | integer | when a checklist exists | Size in bytes |

An aircraft without a checklist file omits `checklistPath`, `checklistModified` and `checklistSize` (golden: `aircraft_no_checklist.json`).

## 5. `GET /v1/checklist`

- `200`: body is the **raw bytes** of the file (no re-encoding, CRLF, CR-only and Latin-1 files arrive unchanged; the app decodes). Headers: `Content-Type: text/plain` (no charset), `ETag: "<mtime>-<size>"` (quotes included), `Last-Modified` (HTTP date, informational), `X-Aircraft-Generation: <n>`, `Content-Length`.
- `304` (with the `ETag`, no body) when `If-None-Match` matches the current ETag. The header may hold a comma-separated list, weak `W/"..."` values, or `*`; matching is exact string equality of the quoted value.
- `404` `no_checklist` when the aircraft has no checklist file.
- `413` `too_large` when the file is larger than 2 MB (2 097 152 bytes). Real files are tens of KB.

**Fresh file facts.** Before it answers `/v1/aircraft`, the plugin asks the sim thread to look at the checklist file now (a stat, and a re-read if the time or size changed) and waits up to 500 ms for that. So a Reload right after saving an edit sees the new `checklistModified` and `checklistSize`. If the sim thread does not get to it in time (the sim is paused or loading), the answer carries the values from the last look; the sim thread also looks every 3 s by itself, so they catch up. `/v1/hello`, `/v1/checklist` and the stream never wait for this. A plugin build with no sim thread (`core_test_server`) answers at once.

**Timestamp rule (one definition, tested on both sides).** The modification time is the file's last-write time as integer epoch milliseconds UTC, from a platform API with millisecond resolution. The ETag is `"` + mtime + `-` + size + `"`, the same two numbers as in `/v1/aircraft`. The app compares by exact equality, never ordering: an older file means a restored backup and must also refetch.

**Race rule (client side).** After a fetch, the app checks that the response's ETag equals the aircraft JSON's `checklistModified`-`checklistSize` and that `X-Aircraft-Generation` equals the JSON's `generation`. If either differs, the aircraft or file changed between the two requests: re-fetch `/v1/aircraft` and start over, at most 3 times, then report a protocol error.

## 6. Signals

A signal is a named number. Names are opaque strings. For the X-Plane plugin a name is an X-Plane dataref name (for example `sim/flightmodel/failures/onground_any`, 1 on the ground and 0 airborne). One name is reserved:

- `flightsim_aide/aircraft_generation` (integer): the same counter as `generation` in `/v1/aircraft`.

A name the companion does not know is `unknown_name`; one it knows but cannot read as a single number (a whole array, a string) is `unsupported`. An array **element** is named `name[n]` (section 9). Both are deterministic: the same name always gets the same answer.

## 7. Stream: `GET /v1/stream` (WebSocket)

A request with the WebSocket upgrade headers is upgraded; a plain `GET` gets `400` `upgrade_required`. At most **4** stream clients at once: a fifth upgrade gets `503` with `{"error":"limit",...}`. Every frame is a JSON text frame, at most 4 096 bytes, with an `op` field. Subscriptions belong to the connection; when it closes (either side) they end. Nothing survives a disconnect.

### Client to server

| Frame | Meaning |
|---|---|
| `{"op":"subscribe","id":1,"name":"sim/flightmodel/failures/onground_any","hz":2}` | `id`: integer, 0 or more, chosen by the client. `name`: 1 to 200 characters, no control characters. `hz`: integer 1 to 60. A repeated `id` replaces the old subscription. At most **128** subscriptions per connection (32 in the first version, see section 9) |
| `{"op":"unsubscribe","id":1}` | Ends it. An unknown `id` is ignored |
| `{"op":"ping"}` | Optional liveness probe |
| `{"op":"set","id":1,"name":"...","value":0}` | Reserved for a later version; always answered `unsupported` in version 1 |

### Server to client

| Frame | Meaning |
|---|---|
| `{"op":"subscribed","id":1}` | The name resolved. Sent after the plugin's next flight-loop tick (at most about 1 s), because server threads never call the simulator |
| `{"op":"error","id":1,"code":"unknown_name"}` | `id` is present when the offending frame had a readable `id`. Codes: `unknown_name`, `unsupported`, `bad_request` (malformed frame, unknown `op`, invalid field), `limit` (the 129th subscription). An optional `message` string may be present |
| `{"op":"values","t":1761206400123,"v":{"1":1}}` | At most one frame per tick per connection with the latest value of every subscription that is due (latest wins; a late sender sends one frame, never a burst). `t` is the sample time, epoch ms. `v` maps the subscription id (as a string) to a JSON number; integers print as integers; a non-finite value is `null`. A value is sent every period, changed or not |
| `{"op":"hb"}` | Sent about once a second when no `values` frame was sent |
| `{"op":"pong"}` | Answer to `ping` |

- **Rate.** A subscription never produces frames faster than `hz`. The first `values` frame for a subscription follows its `subscribed` frame at once.
- **Generation.** `flightsim_aide/aircraft_generation` is delivered at subscribe time and again immediately at every change, in addition to its periodic frames.
- **Staleness.** The client treats 3 s without any frame (values, `hb`, `pong`) as stale and reconnects with back-off 1 s, 2 s, 5 s (then every 5 s), re-probing the port range and re-subscribing everything. Staleness is judged by frame arrival, never by value change (a paused sim keeps sending frozen values).
- **Dead peers.** The server closes a connection that sent nothing and did not answer its ping for 15 s.

## 8. Shared test cases

`testing/fixtures/protocol/` holds the golden files and the case lists. A server under test is started in a **scenario** that fixes its state:

| Scenario | State |
|---|---|
| `default` | Aircraft `C172`, generation 12, checklist `checklist_sample.txt`, mtime 1761206400123, signals from `stream_values.json` |
| `no_checklist` | The same aircraft without a checklist file (golden `aircraft_no_checklist.json`) |
| `oversize` | A checklist of 3 MB |

- `cases.json`: HTTP cases `{name, scenario?, pluginOnly?, method, path, headers?, expect:{status, headers?, bodyFile?, jsonSubset?, jsonIgnore?}}`. `bodyFile` is compared byte for byte; `jsonIgnore` names fields that must be present but are not compared (`port`, `sim`, `pluginVersion`, `runId` in the hello); `jsonSubset` must be contained in the JSON body. `pluginOnly` cases are skipped with `--no-plugin-only` (the Dart fake has its own test for them).
- `stream_cases.json`: stream scripts `{name, scenario?, steps:[...]}` with the steps `send`, `sendRaw`, `expect` (the next frame containing the given fields, within `withinMs`), `expectNone` (no matching frame for `forMs`), `collect` (count matching frames over `forMs`, between `min` and `max`), `wait`, `subscribeMany`, `openExtraClients` and `expectUpgradeStatus`.
- `stream_values.json`: the signals the test servers serve, and the names that are `unsupported`.
- `tools/protocol_contract.dart <baseUrl> [--scenario name] [--no-plugin-only]` plays them.

## 9. Extensions

Three extensions were added to the stream after the first version. `protocolVersion` **stays 1**: each is an optional extension of a field that an earlier client already sends or reads, so an earlier client keeps working against a newer plugin (and the other way round, except that an older plugin answers `unknown_name` to an array element and `limit` past 32).

| Change | Before | Now |
|---|---|---|
| Array element name | not available | `name[n]` in the subscribe `name` |
| Subscriptions per connection | 32 | **128** |
| Numeric kinds | int, float, double | int, float, double, and one element of an int array or a float array |

**Array element names.** `base[n]` is a base dataref name followed by a bracketed zero-based index of decimal digits only (no sign, no spaces, at most 6 digits). The plugin resolves the base name once and reads that element on each tick. Example: `{"op":"subscribe","id":4,"name":"sim/cockpit2/engine/actuators/throttle_ratio[1]","hz":5}`, answered `{"op":"subscribed","id":4}` and then `{"op":"values","t":1761206400123,"v":{"4":0.5}}`.

- A malformed bracket form (`x[`, `x[]`, `x[a]`, `x[-1]`, `x[1]y`, `x[1][2]`) is `bad_request`.
- A well-formed index on a name that is not an array, or a base name the sim does not have, is `unknown_name`.
- An index at or past the end of the array is **accepted** (`subscribed`) and every `values` frame carries `null` for it, because the size of an array can change with the aircraft. The app treats `null` as a missing value (the whole condition is `unknown`).
- The whole array without an index (`.../throttle_ratio`) stays `unsupported`. Strings and byte arrays stay `unsupported`.

**Limits.**

| Limit | Value |
|---|---|
| Stream clients at once | 4 |
| Subscriptions per connection | 128 (the 129th is `limit`; a repeated `id` replaces and never counts) |
| Client frame size | 4 096 bytes |
| `hz` | 1 to 60 |
| Name length | 1 to 200 characters |

**Example frames** (the golden cases are in `testing/fixtures/protocol/stream_cases.json`):

| Frame | Meaning |
|---|---|
| `{"op":"subscribe","id":4,"name":"x/y[1]","hz":5}` | element 1 of the float array `x/y` |
| `{"op":"error","id":5,"code":"bad_request"}` | for `x/y[`, `x/y[a]` |
| `{"op":"error","id":6,"code":"unknown_name"}` | for `no/such[0]` or `sim/flightmodel/failures/onground_any[0]` |
| `{"op":"values","t":1761206400123,"v":{"7":null}}` | subscription 7 is `x/y[99]`, past the end |
| `{"op":"error","id":129,"code":"limit"}` | the 129th distinct id on one connection |

## 10. Range subscriptions

`protocolVersion` **stays 1**: a range is an optional extension of the subscribe `name`. A plugin that does not support ranges answers it `bad_request` (a malformed index), and a client then subscribes the elements one by one.

**Range names.** `base[a..b]` is a base dataref name followed by a bracketed range of zero-based indexes, `a` and `b` each 1 to 6 decimal digits (no sign, no spaces), `a <= b`, at most 128 elements. The dataref must be an int array or a float array. One range is **one** subscription and counts once against the 128. Example: `{"op":"subscribe","id":4,"name":"sim/flightmodel2/gear/on_ground[0..3]","hz":5}`, answered `{"op":"subscribed","id":4}` and then `{"op":"values","t":1761206400123,"v":{"4":[1,1,1,0]}}`.

- The value of a range subscription is a **list of numbers** (`null` for a non-finite number), one per element that exists, in index order. The plugin reads the slice in one SDK call (`XPLMGetDatavf` or `XPLMGetDatavi` with an offset and a count).
- If the array ends inside the range the list is **shorter** than `b - a + 1`; if it ends before `a` the list is `[]`. The size of an array can change with the aircraft, so this is not an error. A client that needs every element treats a missing one as no value.
- A malformed range (`x[2..1]`, `x[0..128]`, `x[0..]`, `x[..2]`, `x[a..2]`) is `bad_request`. A range on a name that is not an array, or a base name the sim does not have, is `unknown_name`. A whole array without brackets stays `unsupported`.
- A single element `name[n]` is unchanged and still answers one number.

Golden cases: `testing/fixtures/protocol/stream_cases.json` (the `array range` and `range` cases).
