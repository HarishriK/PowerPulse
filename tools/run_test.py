#!/usr/bin/env python3
"""Build and run one PowerPulse test.  This is what `make run` calls.

Responsibilities
----------------
  1. regenerate derived files if the config or a generator changed (`make gen`);
  2. build the simulator into `sim/build/<key>/simv`, shared between tests and
     rebuilt only when the RTL, the config or this test's file set changes;
  3. build the software image, if the test has one, into `<run>/sw/`, and only
     when its sources changed;
  4. run it with the waveform dumped into `<run>/waves/` (always, no switch);
  5. decide PASS/FAIL from the simulation log and write `<run>/result`;
  6. record the exact commands in `<run>/cmd` and update `sim/latest`.

PASS/FAIL rule (deliberately strict -- a test must be able to fail)
------------------------------------------------------------------
  FAIL if any of:
    * the simulator exits non-zero
    * the log contains an Error- / $error / assertion failure
    * no `PP_RESULT:` line was printed (a test that forgets to report is a
      failure, not a pass)
    * the reported verdict differs from the test's `expected` field
    * the run hit the timeout (the testbench watchdog reports it)
  PASS otherwise.

Usage:
    python3 tools/run_test.py --test <name> [--seed N] [--hex <path>]
                              [--force] [--keep-going]
"""

from __future__ import print_function

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import swbuild                                   # noqa: E402
import testenv                                   # noqa: E402
from soc_config import load_config, ConfigError   # noqa: E402
import simenv                                    # noqa: E402

RESULT_RE = re.compile(r"PP_RESULT:\s*(PASS|FAIL)(.*)$", re.M)
ERROR_PATTERNS = [
    re.compile(r"^\s*Error-", re.M),
    re.compile(r"^\s*Error:", re.M),
    re.compile(r"\$error", re.I),
    re.compile(r"Assertion failed", re.I),
    re.compile(r"FATAL", re.I),
    re.compile(r"protocol violation", re.I),
]


class RunError(Exception):
    pass


# --------------------------------------------------------------------------
# generation
# --------------------------------------------------------------------------

GEN_STAMP = os.path.join(ROOT, "sim", "gen", ".stamp")

GEN_INPUTS = [
    "config/soc_config.yaml",
    "tools/gen_interconnect.py",
    "tools/soc_config.py",
    "tools/map_checker.py",
    "tools/gen_veer_config.py",
    "tools/gen_uart_defines.py",
    os.path.join("rtl", "core", "veer_el2", "configs", "veer.config"),
    os.path.join("rtl", "core", "veer_el2", "design", "flist"),
    os.path.join("rtl", "vendor", "axi-lite-uart", "src", "include", "axi_uart.vh"),
]


def gen_inputs_hash():
    parts = []
    for rel in GEN_INPUTS:
        path = os.path.join(ROOT, rel)
        if os.path.isfile(path):
            parts.append(_hash_file(path))
    for rel in ("config", "tools"):
        pass
    # every RTL and TB file is *not* an input to generation, but a change to a
    # generator's imports is, so hash the whole tools directory too
    for name in sorted(os.listdir(os.path.join(ROOT, "tools"))):
        if name.endswith(".py"):
            parts.append(_hash_file(os.path.join(ROOT, "tools", name)))
    return hashlib.sha256("|".join(parts).encode()).hexdigest()[:16]


def generate(force=False, quiet=False):
    want = gen_inputs_hash()
    if not force and os.path.isfile(GEN_STAMP):
        with open(GEN_STAMP) as handle:
            if handle.read().strip() == want:
                return False
    for script in ("gen_interconnect.py", "gen_veer_config.py", "gen_uart_defines.py"):
        cmd = [sys.executable, os.path.join(ROOT, "tools", script)]
        proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        out = proc.communicate()[0].decode("utf-8", "replace")
        if proc.returncode != 0:
            sys.stderr.write(out)
            raise RunError("generator %s failed" % script)
        if not quiet:
            sys.stdout.write(out)
    with open(GEN_STAMP, "w") as handle:
        handle.write(want)
    return True


def _hash_file(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


# --------------------------------------------------------------------------
# simulator build
# --------------------------------------------------------------------------

def build_key(cfg, test):
    """Shared-build key: design + this test's file set."""
    parts = [cfg.raw_digest(), test.top]
    files = list(test.all_sources())
    # Everything that is compiled but is not the test itself must take part in the
    # build key: hand-written RTL, the generated RTL, and the shared testbench
    # library.  Missing any of them would let a stale simulator be reused after a
    # real change -- which is exactly the kind of bug that makes a regression lie.
    for tree in ("rtl", "sim/gen"):
        base = os.path.join(ROOT, tree)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in ("__pycache__", ".git")]
            for name in sorted(filenames):
                if name.endswith((".sv", ".v", ".vh", ".svh", ".f")):
                    files.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
    common = os.path.join(ROOT, "tb", "common")
    if os.path.isdir(common):
        for name in sorted(os.listdir(common)):
            if name.endswith((".sv", ".svh")):
                files.append(os.path.join("tb", "common", name))
    for rel in files:
        path = os.path.join(ROOT, rel)
        if os.path.isfile(path):
            parts.append(_hash_file(path))
    return hashlib.sha256("|".join(parts).encode()).hexdigest()[:12]


def build_simulator(cfg, test, force=False, quiet=False):
    build_dir = os.path.join(ROOT, "sim", "build", build_key(cfg, test))
    if not os.path.isdir(build_dir):
        os.makedirs(build_dir)
    simv = os.path.join(build_dir, "simv")

    filelist = os.path.join(ROOT, "sim", "gen", "filelist.f")
    if not os.path.isfile(filelist):
        raise RunError("generated file list missing; run `make gen`")

    cmd = ["vcs", "-full64", "-sverilog",
           "-timescale=1ns/1ps",
           "+define+PP_SIM",
           "-debug_access+all", "-kdb", "-assert", "svaext",
           "-ntb_opts", "dtm",
           "+incdir+" + os.path.join(ROOT, "tb", "common"),
           "+incdir+" + os.path.join(ROOT, "sw", "common"),
           "+incdir+" + os.path.join(ROOT, "sim", "gen"),
           "-o", simv, "-top", test.top, "-f", filelist]
    for rel in test.all_sources():
        cmd.append(rel)
    for extra in ("pp_sim_status_dev.sv", "pp_clk_rst.sv", "pp_axi_master.sv",
                  "pp_axi_checker.sv", "pp_uart_model.sv", "pp_bus_harness.sv"):
        path = os.path.join(ROOT, "tb", "common", extra)
        if extra not in test.all_sources() and os.path.isfile(path):
            cmd.append(path)

    logfile = os.path.join(build_dir, "compile.log")
    env = simenv.fix_env()
    if force and os.path.isdir(build_dir + ".daidir"):
        shutil.rmtree(build_dir + ".daidir", ignore_errors=True)
    if force or not os.path.isfile(simv):
        with open(logfile, "wb") as log:
            log.write(("$ %s\n\n" % " ".join(cmd)).encode())
            log.flush()
            proc = subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, env=env)
            proc.communicate()
        if proc.returncode != 0 or not os.path.isfile(simv):
            with open(logfile) as handle:
                tail = handle.read()[-4000:]
            raise RunError("VCS compile/elaborate failed for %s\n%s"
                           % (test.name, tail))
        if not quiet:
            print("build: %s -> %s" % (test.name, os.path.relpath(simv, ROOT)))
    return simv


# --------------------------------------------------------------------------
# run
# --------------------------------------------------------------------------

def run(cfg, test, simv, run_dir, seed=None, hexfile=None):
    for sub in ("sw", "logs", "waves"):
        path = os.path.join(run_dir, sub)
        if not os.path.isdir(path):
            os.makedirs(path)

    waves = os.path.join(run_dir, "waves", "dump.vpd")
    logfile = os.path.join(run_dir, "logs", "sim.log")
    cmdfile = os.path.join(run_dir, "cmd")

    timeout_ns = test.timeout_ns(cfg)
    plusargs = list(test.plusargs)
    if hexfile:
        plusargs.append("+hex=%s" % os.path.abspath(hexfile))
    plusargs.append("+timeout=%d" % timeout_ns)
    plusargs.append("+seed=%d" % (seed if seed is not None else cfg.sim_default_seed))
    plusargs.append("+test=%s" % test.name)
    if test.seedable and seed is not None:
        plusargs.append("+seeded_run=1")

    cmd = [simv] + plusargs + ["+dumpfile=%s" % waves]

    with open(cmdfile, "w") as handle:
        handle.write("# PowerPulse run record -- every parameter of this run\n")
        handle.write("test        : %s\n" % test.name)
        handle.write("folder      : %s\n" % test.folder)
        handle.write("type        : %s\n" % test.type)
        handle.write("purpose     : %s\n" % test.purpose)
        handle.write("groups      : %s\n" % ",".join(test.groups))
        handle.write("top         : %s\n" % test.top)
        handle.write("expected    : %s\n" % test.expected)
        handle.write("seed        : %s\n" % (seed if seed is not None else cfg.sim_default_seed))
        handle.write("timeout_ns  : %d\n" % timeout_ns)
        handle.write("plusargs    : %s\n" % " ".join(plusargs))
        handle.write("config      : config/soc_config.yaml (%s)\n" % cfg.raw_digest())
        handle.write("started     : %s\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
        handle.write("\n# simulator build\n")
        handle.write("vcs %s\n" % _build_command_line(test))
        handle.write("\n# simulation\n")
        handle.write("%s\n" % " ".join(cmd))

    env = simenv.fix_env()
    start = time.time()
    with open(logfile, "wb") as log:
        log.write(("$ %s\n\n" % " ".join(cmd)).encode())
        log.flush()
        proc = subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, env=env)
        try:
            proc.wait(timeout=max(60.0, timeout_ns / 1.0e6 * 20.0))
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
            _write_result(run_dir, "FAIL", "simulator did not exit (watchdog hung)")
            return False
    elapsed = time.time() - start

    with open(logfile) as handle:
        log = handle.read()
    with open(cmdfile, "a") as handle:
        handle.write("\nelapsed_s   : %.2f\n" % elapsed)

    ok, summary = judge(log, proc.returncode, test)
    _write_result(run_dir, "PASS" if ok else "FAIL", summary)
    return ok


def _build_command_line(test):
    filelist = "sim/gen/filelist.f"
    return ("-full64 -sverilog -timescale=1ns/1ps +define+PP_SIM -debug_access+all -kdb "
            "-top %s -f %s %s" % (test.top, filelist, " ".join(test.all_sources())))


def judge(log, returncode, test):
    matches = RESULT_RE.findall(log)
    problems = []

    for pattern in ERROR_PATTERNS:
        found = pattern.search(log)
        if found:
            line = found.group(0).strip()
            problems.append("simulation reported an error: %s" % line)

    if returncode != 0:
        problems.append("simulator exit status %d" % returncode)

    if not matches:
        problems.append("no PP_RESULT line: the test did not report a verdict")
        return False, "; ".join(problems)

    verdict, detail = matches[-1]
    summary = (detail or "").strip()
    if verdict != test.expected:
        problems.append("expected %s but the test reported %s %s"
                        % (test.expected, verdict, summary))
    if problems:
        return False, "; ".join(problems)
    return True, summary or "reported %s" % verdict


def _write_result(run_dir, verdict, summary):
    with open(os.path.join(run_dir, "result"), "w") as handle:
        handle.write("%s %s\n" % (verdict, summary))


def update_latest(run_dir):
    latest = os.path.join(ROOT, "sim", "latest")
    rel = os.path.relpath(run_dir, ROOT)
    if os.path.islink(latest) or os.path.isfile(latest):
        os.remove(latest)
    if not os.path.isdir(os.path.join(ROOT, "sim")):
        os.makedirs(os.path.join(ROOT, "sim"))
    os.symlink(rel, latest)


def last_test():
    latest = os.path.join(ROOT, "sim", "latest")
    if not os.path.exists(latest):
        return None
    with open(os.path.join(latest, "cmd")) as handle:
        for line in handle:
            if line.startswith("test        : "):
                return line.split(":", 1)[1].strip()
    return None


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", required=True)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--hex", dest="hexfile", default=None)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--keep-going", action="store_true")
    args = parser.parse_args(argv[1:])

    try:
        cfg = load_config(os.path.join(ROOT, "config", "soc_config.yaml"))
    except ConfigError as exc:
        sys.stderr.write("run: %s\n" % exc)
        return 1

    try:
        test = testenv.get(args.test)
    except ValueError as exc:
        sys.stderr.write("run: %s\n" % exc)
        return 1

    seed = args.seed
    if seed is not None and not test.seedable:
        sys.stderr.write("run: test %s is not seedable\n" % test.name)
        return 1

    try:
        generate(force=args.force)
        simv = build_simulator(cfg, test, force=args.force)

        run_dir = test.run_dir(seed)
        if not os.path.isdir(run_dir):
            os.makedirs(run_dir)

        hexfile = args.hexfile
        if hexfile is None and test.type in ("software", "scenario"):
            if not (swbuild.is_fresh(test, run_dir) and args.force):
                swbuild.build(test, run_dir)
                swbuild.stamp(test, run_dir)
            hexfile = os.path.join(run_dir, "sw", "%s.hex" % test.name)
            if not os.path.isfile(hexfile):
                raise RunError("software image missing for %s" % test.name)
        elif hexfile is not None:
            if not os.path.isfile(hexfile):
                raise RunError("hex image not found: %s" % hexfile)
            hexfile = os.path.abspath(hexfile)
            shutil.copyfile(hexfile, os.path.join(run_dir, "sw_external.hex"))

        ok = run(cfg, test, simv, run_dir, seed=seed, hexfile=hexfile)
        update_latest(run_dir)
    except (RunError, swbuild.BuildError, ValueError) as exc:
        sys.stderr.write("run: %s\n" % exc)
        if not os.path.isdir(run_dir if 'run_dir' in dir() else ""):
            pass
        return 1

    with open(os.path.join(run_dir, "result")) as handle:
        verdict, summary = handle.read().strip().split(" ", 1)
    print("%-6s %s%s" % (verdict, test.name, (" -- " + summary) if summary else ""))
    print("      log     %s" % os.path.relpath(os.path.join(run_dir, "logs", "sim.log"), ROOT))
    print("      waves   %s" % os.path.relpath(os.path.join(run_dir, "waves", "dump.vpd"), ROOT))
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
