# Real Xchecklist checker (reference oracle)

The Xchecklist project ships `checker/`, a command-line build of the plugin's own flex/bison parser. Running it on a checklist file reports exactly the errors the real plugin would. We use it to cross-check our Dart parser. The checker parses dataref expressions, which the Dart line parser ignores, so errors inside `|...:(dataref:value)` expressions have no counterpart there.

This is an optional developer tool. It does not run in CI, and it needs files that are not in this repository.

## What you need to download first

Put these in `external/` (git-ignored, see `BUILDING.md`):

| Path | What | Where from |
|---|---|---|
| `external/xchecklist/` | The Xchecklist source, with its `checker/` and `src/` folders | the Xchecklist project on GitHub (MIT licence) |
| `external/aircraft/*.txt` | Optional: real aircraft checklist files to check | your own copies; respect each author's terms, do not commit them |

Without `external/xchecklist/` the scripts stop with a message saying so.

## Reproduce (Windows, via WSL)

Needs `g++`, `flex`, `bison` in WSL. No cmake or MinGW needed.

```bash
wsl -d <distro> -- bash Documentation/Testing/real_checker/build_checker.sh   # once; binary lands in external/checker_build/
wsl -d <distro> -- bash Documentation/Testing/real_checker/run_checker.sh     # writes external/checker_results/
```

Run from the repository root. In Git Bash set `MSYS_NO_PATHCONV=1` first so paths are not rewritten. WSL may clear `/tmp` between calls, which is why the binary is built under `external/`.

## Output

`run_checker.sh` writes to `external/checker_results/` (never committed):

- `summary.txt` lists checklists, errors and warnings per file.
- `errors.txt` lists every ERROR and WARNING line with its file name.
- `<file>.out` has the full output.

The checker prints `dataref dictionary not found` on every run; it is harmless without X-Plane.

## Condition fixtures

`run_real_checker.py` runs the fixtures in `testing/fixtures/conditions/` through the same checker, to confirm what the real plugin does with each condition form. Run it from the repository root with `WSL_DISTRO` set to your WSL distribution:

```bash
MSYS_NO_PATHCONV=1 python Documentation/Testing/real_checker/run_real_checker.py [fixture ...]
```

## Probes

`probes/` holds fourteen one-line files (`q1.txt` to `q14.txt`, listed in `probes/index.tsv`), each a single odd line such as a stray word, a comment style or an empty label, to see whether the real parser accepts it. `Reference/GRAMMAR.md` (sections 1 to 5) records what the probes showed.
