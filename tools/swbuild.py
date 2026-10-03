#!/usr/bin/env python3
"""Build a software test image into a run folder.

Chain (every step's log goes into <run>/sw/ so a failure is diagnosable):

    *.c  --gcc-->  *.o  --gcc -T <generated linker script>-->  *.elf
         --objcopy -O binary-->  *.bin
         --objcopy -O verilog --verilog-data-width=<HEX_WORD_BYTES>-->  *.hex
         --objdump -d-->  *.dis        --gcc -Wl,-Map--> *.map

The compiler flags, ISA string, ABI and load address all come from
`config/soc_config.yaml` via the generated `sim/gen/config.mk` values, so
changing a memory size in the config changes the linker script and the header
without any manual edit.

Usage:
    python3 tools/swbuild.py --test <name> --run-dir <dir> [--sw-dir sw/tests/<name>]
"""

from __future__ import print_function

import argparse
import hashlib
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from soc_config import load_config, ConfigError  # noqa: E402


class BuildError(Exception):
    pass


def _run(cmd, cwd, logfile, env=None):
    """Run a command, teeing output into logfile.  Raise on failure."""
    with open(logfile, "ab") as log:
        log.write(("\n$ %s\n" % " ".join(cmd)).encode())
        log.flush()
        proc = subprocess.Popen(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                                env=env)
        proc.communicate()
    if proc.returncode != 0:
        raise BuildError("command failed (exit %d): %s\n  see %s"
                         % (proc.returncode, " ".join(cmd),
                            os.path.relpath(logfile, ROOT)))


def build(test, run_dir, verbose=False):
    cfg = load_config(os.path.join(ROOT, "config", "soc_config.yaml"))

    sw_root = os.path.join(ROOT, "sw")
    sw_dir = os.path.join(ROOT, test.sw or os.path.join("sw", "tests", test.name))
    if not os.path.isdir(sw_dir):
        raise BuildError("software test folder not found: %s"
                         % os.path.relpath(sw_dir, ROOT))

    out_dir = os.path.join(run_dir, "sw")
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)

    gen_inc = os.path.join(ROOT, "sim", "gen")
    common_src = os.path.join(sw_root, "common")
    sources = []
    for folder in (common_src, sw_dir):
        for name in sorted(os.listdir(folder)):
            if name.endswith(".c") or name.endswith(".S"):
                sources.append(os.path.join(folder, name))
    if not sources:
        raise BuildError("no C or assembly sources in %s or %s"
                         % (os.path.relpath(common_src, ROOT), os.path.relpath(sw_dir, ROOT)))

    cc = os.path.join(cfg.sw_toolchain_path, cfg.sw_toolchain_prefix + "gcc")
    objcopy = os.path.join(cfg.sw_toolchain_path, cfg.sw_toolchain_prefix + "objcopy")
    objdump = os.path.join(cfg.sw_toolchain_path, cfg.sw_toolchain_prefix + "objdump")
    for tool in (cc, objcopy, objdump):
        if not os.path.isfile(tool):
            raise BuildError("toolchain binary not found: %s\n"
                             "  check software.toolchain_path / toolchain_prefix in "
                             "config/soc_config.yaml" % tool)

    linker = os.path.join(gen_inc, "powerpulse.ld")
    if not os.path.isfile(linker):
        raise BuildError("generated linker script missing: %s (run `make gen`)"
                         % os.path.relpath(linker, ROOT))

    elf = os.path.join(out_dir, "%s.elf" % test.name)
    binary = os.path.join(out_dir, "%s.bin" % test.name)
    hexfile = os.path.join(out_dir, "%s.hex" % test.name)
    disasm = os.path.join(out_dir, "%s.dis" % test.name)
    mapfile = os.path.join(out_dir, "%s.map" % test.name)
    buildlog = os.path.join(out_dir, "build.log")
    if os.path.isfile(buildlog):
        os.remove(buildlog)

    cflags = ["-march=%s" % cfg.sw_march, "-mabi=%s" % cfg.sw_mabi,
              cfg.sw_opt, "-Wall", "-Wextra", "-Werror",
              "-ffreestanding", "-fno-builtin", "-nostdlib",
              "-fdata-sections", "-ffunction-sections",
              "-I", common_src, "-I", gen_inc, "-I", sw_dir]

    objects = []
    for src in sources:
        obj = os.path.join(out_dir, os.path.basename(src).rsplit(".", 1)[0] + ".o")
        if src.endswith(".S"):
            cmd = [cc] + cflags + ["-c", src, "-o", obj]
        else:
            cmd = [cc] + cflags + ["-c", src, "-o", obj]
        _run(cmd, ROOT, buildlog)
        objects.append(obj)

    link = [cc, "-march=%s" % cfg.sw_march, "-mabi=%s" % cfg.sw_mabi, cfg.sw_opt,
            "-nostdlib", "-nostartfiles", "-T", linker,
            "-Wl,--gc-sections", "-Wl,-Map=%s" % mapfile,
            "-Wl,--print-memory-usage"] + objects + ["-o", elf, "-lgcc"]
    _run(link, ROOT, buildlog)

    _run([objcopy, "-O", "binary", elf, binary], ROOT, buildlog)
    _run([objcopy, "-O", "verilog", "--verilog-data-width=%d" % cfg.hex_word_bytes,
          elf, hexfile], ROOT, buildlog)
    _run([objdump, "-d", "-S", elf], ROOT, disasm)

    size = os.path.getsize(binary)
    print("swbuild: %s -> %s (%d bytes of image)"
          % (test.name, os.path.relpath(hexfile, ROOT), size))
    return hexfile


def fingerprint(test, run_dir):
    """Hash of everything the image depends on, for rebuild decisions."""
    cfg = load_config(os.path.join(ROOT, "config", "soc_config.yaml"))
    parts = [cfg.sw_march, cfg.sw_mabi, cfg.sw_opt, cfg.hex_word_bytes,
             cfg.toolchain_signature(), cfg.sw_load_addr]
    gen = os.path.join(ROOT, "sim", "gen")
    for name in ("powerpulse.ld", "pp_memmap.h"):
        path = os.path.join(gen, name)
        if os.path.isfile(path):
            parts.append(_hash_file(path))
    sw_dir = os.path.join(ROOT, test.sw or os.path.join("sw", "tests", test.name))
    for folder in (os.path.join(ROOT, "sw", "common"), sw_dir):
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            if name.endswith(".c") or name.endswith(".S"):
                parts.append(_hash_file(os.path.join(folder, name)))
    return hashlib.sha256("|".join(parts).encode()).hexdigest()[:16]


def _hash_file(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


def is_fresh(test, run_dir):
    marker = os.path.join(run_dir, "sw", ".stamp")
    hexfile = os.path.join(run_dir, "sw", "%s.hex" % test.name)
    if not (os.path.isfile(marker) and os.path.isfile(hexfile)):
        return False
    with open(marker) as handle:
        return handle.read().strip() == fingerprint(test, run_dir)


def stamp(test, run_dir):
    marker = os.path.join(run_dir, "sw", ".stamp")
    with open(marker, "w") as handle:
        handle.write(fingerprint(test, run_dir))


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", required=True)
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args(argv[1:])

    import testenv
    try:
        test = testenv.get(args.test)
        if is_fresh(test, args.run_dir) and "--force" not in argv:
            print("swbuild: %s is up to date" % test.name)
            return 0
        build(test, args.run_dir)
        stamp(test, args.run_dir)
    except (BuildError, ValueError, ConfigError) as exc:
        sys.stderr.write("swbuild: %s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
