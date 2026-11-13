#!/usr/bin/env python3
"""Runs the condition fixtures through the real Xchecklist checker (a developer tool, not part of the app).

The real checker (Documentation/Testing/real_checker/) is the plugin's own parser plus a regression harness: special comments declare
datarefs (`#?#d name value`) and script assignments per item (`#!#<tag>name v:name v` where `:` starts the next time
slot). This script turns a fixture (testing/fixtures/conditions/<name>.txt + .values.json) into such a file:

  * every check item with a condition gets a tag `<k>` in its label,
  * every dataref with a value gets a declaration, arrays (`name[i]`) become `#?#F` (float arrays),
  * each step of the values file becomes one time slot of the item's script.

The output of the walkthrough says per item whether the real code accepted the item ("....CHECK") or had to give up
("Safety triggered, checking manually") and which checklists were visited, which is what the fixtures record.

Usage (repo root, Git Bash):  MSYS_NO_PATHCONV=1 python Documentation/Testing/real_checker/run_real_checker.py [fixture ...]
Needs the checker binary built by Documentation/Testing/real_checker/build_checker.sh (inside WSL, distro in $WSL_DISTRO).
"""
import json
import os
import re
import subprocess
import sys

FIX = 'testing/fixtures/conditions'
OUT = 'external/checker_runs'   # git-ignored scratch output
DISTRO = os.environ.get('WSL_DISTRO', 'Ubuntu')
BIN = 'external/checker_build/checker'


def load(name):
    text = open('%s/%s.txt' % (FIX, name), encoding='utf-8').read().split('\n')
    values = json.load(open('%s/%s.values.json' % (FIX, name), encoding='utf-8'))
    steps = values['steps'] if 'steps' in values else [values]
    expected = json.load(open('%s/%s.expected.json' % (FIX, name), encoding='utf-8'))
    return text, steps, expected


def case_prefix(expr):
    m = re.search(r'fx/[a-z_]+/(\d\d)', expr)
    return m.group(0) if m else None


def build(name):
    """Returns (checker input text, {tag: (check index, label, expression)})."""
    text, steps, _ = load(name)
    out = ['#?#d fx/dummy 0']
    tags = {}
    check_index = 0
    arrays = {}
    for st in steps:
        for k, v in st.items():
            m = re.match(r'(.*)\[(\d+)\]$', k)
            if m and v is not None:
                arrays.setdefault(m.group(1), {})[int(m.group(2))] = v
    for k, v in steps[0].items():
        if '[' not in k and v is not None:
            out.append('#?#d %s %s' % (k, v))
    for base, elems in arrays.items():
        # the checker's array accessor throws on an index past the end, so declare room; its float accessor
        # truncates to int whatever the declared kind (main.cpp get_float_array_dataref)
        kind = 'I' if all(float(v).is_integer() for v in elems.values()) else 'F'
        vals = [steps[0].get('%s[%d]' % (base, i)) or 0 for i in range(10)]
        out.append('#?#%s %s %s' % (kind, base, ' '.join(str(v) for v in vals)))
    for line in text:
        m = re.match(r'^(sw_item(?:_c)?):(.*?)\|([^:|]*)(?::(.*))?$', line)
        if m and not line.startswith('#'):
            kw, label, result, expr = m.groups()
            k = 'k%d' % check_index
            if expr:
                pre = case_prefix(expr)
                used = [i for i, st in enumerate(steps) if any(n.startswith(pre) for n in st)] if pre else []
                n_slots = (used[-1] + 1) if used else 1
                slots = []
                for st in steps[:n_slots]:
                    assigns = ['%s %s' % (n, v) for n, v in st.items() if pre and n.startswith(pre) and v is not None]
                    slots.append(','.join(assigns) or 'fx/dummy 0')   # an empty slot still takes one time step
                out.append('#!#<%s>%s' % (k, ':'.join(slots)))
                tags[k] = (check_index, label, expr)
                out.append('%s:<%s>%s|%s:%s' % (kw, k, label, result, expr))
            else:
                out.append(line)
            check_index += 1
        else:
            out.append(line)
    return '\n'.join(out) + '\n', tags


def wsl_cwd(env):
    """The current folder (the repo root) as a path inside WSL."""
    r = subprocess.run(['wsl', '-d', DISTRO, '--', 'wslpath', '-a', os.getcwd()],
                       capture_output=True, env=env)
    return r.stdout.decode('utf-8', 'replace').strip()


def run_checker(path, debug=4):
    env = dict(os.environ, MSYS_NO_PATHCONV='1')
    cmd = ['wsl', '-d', DISTRO, '--', 'bash', '-c',
           'cd "%s" && timeout 60 %s %s %d 2>&1' % (wsl_cwd(env), BIN, path, debug)]
    r = subprocess.run(cmd, capture_output=True, env=env)
    return r.stdout.decode('utf-8', 'replace')


def summarize(name, tags, out, expected):
    """One row per tagged item: expected (from the fixture) and what the real checker did."""
    walk = out.split('Checklist walkthrough', 1)[-1]
    rows = []
    exp = {}
    for key in ('met', 'not_met', 'unknown'):
        for i in expected.get(key, []):
            exp[i] = key
    for k, (idx, label, expr) in tags.items():
        m = re.search(r'<%s>[^\n]*\n(?:\.[^\n]*\n)?' % k, walk)
        line = m.group(0) if m else ''
        if not m:
            real = 'not run'
        elif 'Safety triggered' in line:
            real = 'gave up'
        elif 'unexpectedly' in line:
            real = 'checked early'   # met before the last scripted step
        elif 'ERROR' in line:
            real = 'error'
        else:
            real = 'checked'
        rows.append((idx, label, expr, exp.get(idx, ''), real))
    return rows


def main():
    names = sys.argv[1:] or sorted(f[:-4] for f in os.listdir(FIX) if f.endswith('.txt'))
    os.makedirs(OUT, exist_ok=True)
    for name in names:
        src, tags = build(name)
        path = '%s/%s.txt' % (OUT, name)
        open(path, 'w', encoding='utf-8', newline='\n').write(src)
        out = run_checker(path)
        open('%s/%s.out' % (OUT, name), 'w', encoding='utf-8').write(out)
        print('%s: %d lines of output' % (name, out.count('\n')))
        _, _, expected = load(name)
        rows = summarize(name, tags, out, expected)
        with open('%s/%s.rows.tsv' % (OUT, name), 'w', encoding='utf-8') as f:
            for r in rows:
                f.write('\t'.join(str(x) for x in r) + '\n')
        tail = re.search(r'Encountered \d+ errors? and \d+ warnings?\.', out)
        print('   ', tail.group(0) if tail else 'no summary line')
        for idx, label, expr, exp, real in rows:
            agree = (exp == 'met' and real in ('checked', 'checked early')) or (exp == 'not_met' and real == 'gave up')
            flag = '' if agree else '   <-- differs' if exp else ''
            print('   %2d %-8s %-8s %s%s' % (idx, exp, real, label, flag))


if __name__ == '__main__':
    main()
