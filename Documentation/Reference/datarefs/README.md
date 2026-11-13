# Dataref lists (local)

A place for lists of dataref names that you read from your own running X-Plane 12, to look names up when you write conditions in a checklist (`Documentation/Reference/GRAMMAR.md`, section 8). **Git ignores everything in this folder except this README**, so a list you save here cannot be committed by accident. The names and values belong to Laminar Research, to the authors of the aircraft and plug-ins you have installed, and to others; they are not part of this repository.

The author keeps two lists here, read on 2026-11-06 from X-Plane 12.4.4 with the Thranda PC-12/47 loaded: every dataref name with its type and whether it is writable (8,639 names), and the `thranda/` datarefs with several `sim/` groups and their values at the time of the read.

## Make a list

With X-Plane running and its web API reachable on port 8086 (the same one `BUILDING.md` uses for the live tests):

```
curl -s -g "http://127.0.0.1:8086/api/v2/datarefs" -o datarefs.json
```

The answer is JSON: `data` is a list with one entry per dataref, each with `name`, `value_type`, `is_writable` and `id`. The list depends on the X-Plane version, the loaded aircraft and the installed plug-ins, so make it again after any of them change. To read one value, use `tools/sim_set.sh --get <name>`.
