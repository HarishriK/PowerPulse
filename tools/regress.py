#!/usr/bin/env python3
"""Regression runner: `make regress G=<group>`.

Runs every test in a group (or in `all`) and prints a summary table.  Each test
is simulated by tools/run_test.py, which writes its own `result` file; this
script only collects them, so a regression can also be assembled from results
of earlier individual runs.

Seeds: with `SEEDS=1,2,3` each test is run once per seed into
`sim/runs/<test>_s<seed>/`, and a test counts as passing only if every seed
passed.  The seed of every run is recorded in the run folder, so a failure is
always reproducible.

Exit status is non-zero if any test failed, so `make regress` is usable as a
pre-commit gate.

Usage:
    python3 tools/regress.py --group smoke [--seeds 1,2,3] [--jobs 1]
"""

from __future__ import print_function

import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import testenv                                     # noqa: E402
from soc_config import load_config, ConfigError   # noqa: E402


def run_one(name, seed, force):
    cmd = [sys.executable, os.path.join(ROOT, "tools", "run_test.py"), "--test", name]
    if seed is not None:
        cmd += ["--seed", str(seed)]
    if force:
        cmd.append("--force")
    proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    out = proc.communicate()[0].decode("utf-8", "replace")
    return proc.returncode, out


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--group", default="all")
    parser.add_argument("--seeds", default=None)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv[1:])

    try:
        cfg = load_config(os.path.join(ROOT, "config", "soc_config.yaml"))
        table = testenv.groups()
    except (ConfigError, ValueError) as exc:
        sys.stderr.write("regress: %s\n" % exc)
        return 1

    group = args.group
    if group == "all":
        names = [t.name for t in testenv.discover()]
    elif group in table:
        names = table[group]
    else:
        sys.stderr.write("regress: unknown group '%s'. Known groups: %s\n"
                         % (group, ", ".join(sorted(table))))
        return 1

    seeds = None
    if args.seeds:
        seeds = [int(s) for s in args.seeds.replace(" ", "").split(",") if s]

    print("regress: group=%s  tests=%d  seeds=%s"
          % (group, len(names), ",".join(str(s) for s in seeds) if seeds else "default"))
    print("")

    rows = []
    failures = 0
    for name in names:
        seed_list = seeds if seeds else [None]
        for seed in seed_list:
            code, out = run_one(name, seed, args.force)
            test = testenv.get(name)
            run_dir = test.run_dir(seed)
            verdict, summary = _read_result(run_dir)
            if code != 0 or verdict != "PASS":
                failures += 1
            rows.append((name, seed if seed is not None else cfg.sim_default_seed,
                         verdict, summary))
            # echo the runner's own line(s) so the user sees why
            for line in out.rstrip().splitlines():
                if line.startswith(("PASS", "FAIL", "run:", "build:", "swbuild:")):
                    print("  %s" % line)
            if verdict == "FAIL" and not line_is_shown(out):
                print(out.rstrip())

    width = max([len(r[0]) for r in rows] + [4])
    print("")
    print("%-*s  %-5s  %-6s  %s" % (width, "TEST", "SEED", "RESULT", "SUMMARY"))
    print("%s  %s  %s  %s" % ("-" * width, "-" * 5, "-" * 6, "-" * 24))
    for name, seed, verdict, summary in rows:
        print("%-*s  %-5s  %-6s  %s" % (width, name, seed, verdict, summary[:60]))

    print("")
    total = len(rows)
    passed = total - failures
    print("regress: %d/%d passed" % (passed, total))

    # machine-readable summary for later inspection
    outdir = os.path.join(ROOT, "sim", "regress")
    if not os.path.isdir(outdir):
        os.makedirs(outdir)
    with open(os.path.join(outdir, "summary.txt"), "w") as handle:
        for name, seed, verdict, summary in rows:
            handle.write("%-24s seed=%-4s %-6s %s\n" % (name, seed, verdict, summary))

    return 0 if failures == 0 else 1


def line_is_shown(out):
    return any(line.startswith(("PASS", "FAIL")) for line in out.splitlines())


def _read_result(run_dir):
    path = os.path.join(run_dir, "result")
    if not os.path.isfile(path):
        return "FAIL", "no result file"
    with open(path) as handle:
        text = handle.read().strip()
    parts = text.split(" ", 1)
    return parts[0], (parts[1] if len(parts) > 1 else "")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
