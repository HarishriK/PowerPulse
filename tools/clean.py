#!/usr/bin/env python3
"""Remove build and run output.  `make clean T=<test>` / `make clean-all`."""

from __future__ import print_function

import argparse
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import testenv  # noqa: E402


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", default=None)
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args(argv[1:])

    sim = os.path.join(ROOT, "sim")
    if args.all:
        if os.path.isdir(sim):
            shutil.rmtree(sim, ignore_errors=True)
            print("clean: removed sim/")
        return 0

    if not args.test:
        sys.stderr.write("clean: give --test <name> or --all\n")
        return 2

    removed = 0
    try:
        test = testenv.get(args.test)
    except ValueError as exc:
        sys.stderr.write("clean: %s\n" % exc)
        return 1
    runs = os.path.join(sim, "runs")
    if os.path.isdir(runs):
        for name in os.listdir(runs):
            if name == test.name or name.startswith(test.name + "_s"):
                shutil.rmtree(os.path.join(runs, name), ignore_errors=True)
                print("clean: removed sim/runs/%s" % name)
                removed += 1
    if not removed:
        print("clean: nothing to remove for %s" % test.name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
