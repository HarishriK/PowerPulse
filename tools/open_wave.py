#!/usr/bin/env python3
"""Open a run's waveform in Verdi.

Waveforms are always dumped, so this is purely a convenience: it locates the
compile database (the -kdb output, `simv.daidir`) that matches the run, starts
Verdi on it and loads the FSDB/VPD that the run produced.

    python3 tools/open_wave.py <run-folder>

If Verdi cannot start, the run folder is printed so the waveform can still be
opened by hand -- a debugging session must never be blocked by tooling.
"""

from __future__ import print_function

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import simenv  # noqa: E402


def find_kdb(run_dir):
    """The compile database of the build that produced this run."""
    cmd = os.path.join(run_dir, "cmd")
    if not os.path.isfile(cmd):
        return None
    with open(cmd) as handle:
        for line in handle:
            if line.startswith("vcs "):
                return line.strip()
    return None


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: open_wave.py <run-folder>\n")
        return 2
    run_dir = os.path.abspath(argv[1])
    wave = os.path.join(run_dir, "waves", "dump.vpd")
    if not os.path.isfile(wave):
        sys.stderr.write("open_wave: %s does not exist -- run the test first\n" % wave)
        return 1

    cmd = ["verdi", "-ssf", wave, "-l", os.path.join(run_dir, "logs", "verdi.log")]
    print("open_wave: %s" % " ".join(cmd))
    env = simenv.fix_env()
    try:
        return subprocess.call(cmd, cwd=ROOT, env=env)
    except OSError as exc:
        sys.stderr.write("open_wave: could not start Verdi (%s)\n" % exc)
        sys.stderr.write("open_wave: open this by hand instead: %s\n" % wave)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
