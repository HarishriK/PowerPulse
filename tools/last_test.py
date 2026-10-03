#!/usr/bin/env python3
"""Print the name of the test from the most recent run, for `make run`/`make wave`
without an explicit T=.  Prints nothing if there is no previous run."""

from __future__ import print_function

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import run_test  # noqa: E402

if __name__ == "__main__":
    name = run_test.last_test()
    if name:
        print(name)
