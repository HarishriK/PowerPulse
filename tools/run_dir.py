#!/usr/bin/env python3
"""Print the run folder for a test (and optional seed).  Used by `make wave`."""

from __future__ import print_function

import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import testenv  # noqa: E402

if __name__ == "__main__":
    name = sys.argv[1]
    seed = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else None
    try:
        print(testenv.get(name).run_dir(seed))
    except ValueError as exc:
        sys.stderr.write("%s\n" % exc)
        sys.exit(1)
