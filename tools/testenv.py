#!/usr/bin/env python3
"""Test discovery and run-folder layout for the PowerPulse make flow.

Tests are discovered **by folder**.  A test is any directory under `tb/unit/`
or `tb/soc/` that contains a `test.cfg` settings file.  Adding a test therefore
needs no Makefile edit -- drop in a folder with the sources and the settings
file and `make list` / `make run T=<name>` find it.

Settings file (`test.cfg`, YAML)
--------------------------------
    name:     bus_decode_map           # optional; defaults to the folder name
    type:     integration               # unit | integration | software | scenario
    purpose:  one line: what this test proves
    top:      tb_bus_decode_map         # top module to elaborate
    sources:  [tb/soc/bus_decode_map.sv] # testbench sources (relative to repo root)
    deps:     []                        # extra RTL/TB sources for this test only
    groups:   [smoke, bus]              # regression group tags
    timeout:  2000000                   # ns; exceeding it is a FAIL (default from config)
    plusargs: []                        # extra simulator plusargs
    expected: PASS                      # PASS, or FAIL for deliberate negative tests
    seedable: true                      # default true; false pins the seed to 1

Run folder
----------
    sim/runs/<test>[_s<seed>]/
        sw/     software artefacts (elf, hex, disassembly, map)
        logs/   compile, link, simulation logs
        waves/  waveform (always dumped)
        cmd     the exact commands and parameters of the run
        result  PASS/FAIL plus a one-line summary
    sim/latest -> runs/<last run>
"""

from __future__ import print_function

import os
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write("PowerPulse needs PyYAML (pip3 install pyyaml)\n")
    raise

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from soc_config import load_config, ConfigError  # noqa: E402

TEST_ROOTS = ["tb/unit", "tb/soc"]
SETTINGS_FILE = "test.cfg"

VALID_TYPES = ("unit", "integration", "software", "scenario")


class Test(object):
    """One discovered test."""

    def __init__(self, folder, cfg):
        self.folder = os.path.relpath(folder, ROOT)
        self.name = str(cfg.get("name") or os.path.basename(folder))
        self.type = str(cfg.get("type", "unit"))
        self.purpose = str(cfg.get("purpose", "")).strip()
        self.top = str(cfg.get("top", "tb_" + self.name))
        self.sources = list(cfg.get("sources") or [])
        self.deps = list(cfg.get("deps") or [])
        self.groups = list(cfg.get("groups") or [])
        self.timeout = cfg.get("timeout", None)
        self.plusargs = list(cfg.get("plusargs") or [])
        self.expected = str(cfg.get("expected", "PASS")).upper()
        self.seedable = bool(cfg.get("seedable", True))
        self.sw = cfg.get("sw", None)          # software sub-folder, if any
        self.path = folder

        if self.type not in VALID_TYPES:
            raise ValueError("%s: type must be one of %s, got %r"
                             % (self.folder, "/".join(VALID_TYPES), self.type))
        if not self.purpose:
            raise ValueError("%s: every test needs a one-line 'purpose'" % self.folder)
        if not self.sources:
            raise ValueError("%s: 'sources' must list at least the top module" % self.folder)
        if not self.groups:
            raise ValueError("%s: every test needs at least one group tag" % self.folder)
        for rel in self.sources + self.deps:
            if not os.path.isfile(os.path.join(ROOT, rel)):
                raise ValueError("%s: source not found: %s" % (self.folder, rel))
        if self.expected not in ("PASS", "FAIL"):
            raise ValueError("%s: expected must be PASS or FAIL" % self.folder)

    # -- derived ------------------------------------------------------------

    def timeout_ns(self, cfg):
        if self.timeout is None:
            return cfg.sim_timeout_ns
        return int(str(self.timeout), 0)

    def run_dir(self, seed=None):
        if seed:
            return os.path.join(ROOT, "sim", "runs", "%s_s%s" % (self.name, seed))
        return os.path.join(ROOT, "sim", "runs", self.name)

    def all_sources(self):
        return list(self.sources) + list(self.deps)

    def __repr__(self):
        return "<Test %s type=%s groups=%s>" % (self.name, self.type, ",".join(self.groups))


def discover(only=None):
    """Return every discovered test, sorted by name."""
    tests = {}
    for root in TEST_ROOTS:
        base = os.path.join(ROOT, root)
        if not os.path.isdir(base):
            continue
        for folder in sorted(os.listdir(base)):
            path = os.path.join(base, folder)
            if not os.path.isdir(path):
                continue
            settings = os.path.join(path, SETTINGS_FILE)
            if not os.path.isfile(settings):
                continue
            with open(settings) as handle:
                cfg = yaml.safe_load(handle) or {}
            test = Test(path, cfg)
            if test.name in tests:
                raise ValueError("duplicate test name '%s' in %s and %s"
                                 % (test.name, tests[test.name].folder, test.folder))
            tests[test.name] = test
    if only:
        missing = [name for name in only if name not in tests]
        if missing:
            raise ValueError("unknown test(s): %s\nKnown tests: %s"
                             % (", ".join(missing), ", ".join(sorted(tests))))
        return [tests[name] for name in only]
    return [tests[name] for name in sorted(tests)]


def groups():
    """Map group tag -> list of test names."""
    out = {}
    for test in discover():
        for tag in test.groups:
            out.setdefault(tag, []).append(test.name)
    return out


def get(name):
    return discover(only=[name])[0]


# --------------------------------------------------------------------------
# command line: used by `make list`
# --------------------------------------------------------------------------

def main(argv):
    cfg = load_config(os.path.join(ROOT, "config", "soc_config.yaml"))
    tests = discover()
    if "--json" in argv:
        import json
        print(json.dumps([{
            "name": t.name, "type": t.type, "purpose": t.purpose, "groups": t.groups,
            "top": t.top, "timeout": t.timeout_ns(cfg), "expected": t.expected,
        } for t in tests], indent=2))
        return 0

    if not tests:
        print("no tests found under %s" % ", ".join(TEST_ROOTS))
        return 0

    width = max(len(t.name) for t in tests)
    print("%-*s  %-12s  %-18s  %s" % (width, "TEST", "TYPE", "GROUPS", "PURPOSE"))
    print("%s  %s  %s  %s" % ("-" * width, "-" * 12, "-" * 18, "-" * 20))
    for test in tests:
        print("%-*s  %-12s  %-18s  %s"
              % (width, test.name, test.type, ",".join(test.groups), test.purpose))

    print("")
    print("groups:")
    for tag in sorted(groups()):
        print("  %-10s %s" % (tag, " ".join(groups()[tag])))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (ValueError, ConfigError) as exc:
        sys.stderr.write("test discovery failed: %s\n" % exc)
        sys.exit(1)
