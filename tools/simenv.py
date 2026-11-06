#!/usr/bin/env python3
"""Make the Synopsys tools runnable from this machine's shell.

VCS and Verdi are installed for a different base OS than the one this container
runs, so their dynamically-linked helper binaries occasionally cannot find
`libelf.so.1` or `libnsl.so.1`.  Rather than hardcoding a machine-specific path
in the Makefile, this module probes for the missing libraries and appends the
directories that contain them to `LD_LIBRARY_PATH`.

The result is cached in `sim/build/env.cache` so the (slow) filesystem search
happens once.  Delete that file, or pass `--refresh`, to re-probe.

If the tools work as they are, nothing is changed.
"""

from __future__ import print_function

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "sim", "build", "env.cache")

# Directories that are worth searching.  Kept short on purpose: a full filesystem
# scan would be far too slow, and these are where EDA installs live in practice.
SEARCH_ROOTS = ["/usr/lib64", "/usr/lib", "/usr/lib/x86_64-linux-gnu",
                "/lib64", "/lib", "/opt", "/home/install", "/home"]

LIBS = ["libelf.so.1", "libnsl.so.1"]


def _tool(name):
    for entry in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(entry, name)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def _missing(tool):
    """Names of shared libraries the tool cannot resolve."""
    if not tool:
        return []
    try:
        out = subprocess.check_output(["ldd", tool], stderr=subprocess.STDOUT)
    except (OSError, subprocess.CalledProcessError):
        return []
    missing = []
    for line in out.decode("utf-8", "replace").splitlines():
        if "not found" in line:
            name = line.strip().split(" ")[0]
            if name:
                missing.append(name)
    return missing


def _find(name):
    for root in SEARCH_ROOTS:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            # Do not descend into unrelated trees once we are deep enough, and
            # skip obviously huge caches.
            depth = dirpath[len(root):].count(os.sep)
            if depth > 6:
                dirnames[:] = []
                continue
            if name in filenames:
                return dirpath
            if depth >= 3 and len(dirnames) > 200:
                dirnames[:] = []
    return None


def fix_env(refresh=False, verbose=False):
    """Return an environment dict in which VCS/Verdi can actually start."""
    env = dict(os.environ)

    if os.path.isfile(CACHE) and not refresh:
        with open(CACHE) as handle:
            for line in handle:
                line = line.strip()
                if line:
                    env["LD_LIBRARY_PATH"] = line + os.pathsep + env.get("LD_LIBRARY_PATH", "")
            return env

    vcs = _tool("vcs")
    extra = []
    for name in _missing(vcs) or LIBS:
        # only look for libraries that are genuinely unavailable
        if _found_in_ldpath(name, env):
            continue
        where = _find(name)
        if where:
            extra.append(where)
            if verbose:
                print("simenv: %s -> %s" % (name, where), file=sys.stderr)

    if extra:
        joined = os.pathsep.join(extra)
        env["LD_LIBRARY_PATH"] = joined + os.pathsep + env.get("LD_LIBRARY_PATH", "")
        parent = os.path.dirname(CACHE)
        if not os.path.isdir(parent):
            os.makedirs(parent)
        with open(CACHE, "w") as handle:
            handle.write(joined + "\n")
    return env


def _found_in_ldpath(name, env):
    for entry in env.get("LD_LIBRARY_PATH", "").split(os.pathsep):
        if entry and os.path.isfile(os.path.join(entry, name)):
            return True
    for entry in ("/usr/lib64", "/usr/lib", "/lib64", "/lib"):
        if os.path.isfile(os.path.join(entry, name)):
            return True
    return False


if __name__ == "__main__":
    result = fix_env(refresh="--refresh" in sys.argv, verbose=True)
    if result.get("LD_LIBRARY_PATH"):
        print(result["LD_LIBRARY_PATH"])
