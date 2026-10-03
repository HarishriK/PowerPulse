#!/usr/bin/env python3
"""Generate the macro prelude the vendored UART IP is compiled with.

`rtl/vendor/axi-lite-uart/src/rtl/axi_uart_top.v` pulls its whole register map
and its baud divider out of two preprocessor headers:

    `include "axi_uart_defines.vh"   // AXI geometry
    `include "axi_uart.vh"            // register offsets, field positions, baud

The baud-related macros in `axi_uart.vh` are *baked in* from a 100 MHz / 115200
assumption, which would put a clock and a baud rate into synthesizable RTL that
is not in `config/soc_config.yaml`.  That breaks the single-source-of-truth rule.

This generator fixes that without editing the IP:

  * it parses the IP's own `axi_uart.vh` and copies **every** macro definition
    verbatim, so the register map is never duplicated by hand and can never
    drift from the IP;
  * it then overrides only the two macros that encode the environment --
    `_UART_MAIN_CLOCK_FREQ_` and `_UART_BAUDRATE_INIT_` -- with the values from
    `config/soc_config.yaml`, so `_UART_BAUDRATE_DIV_INIT_` is recomputed as
    clock / baud;
  * it pre-defines the IP's include guard `_AXI_UART_H_`, so the IP's own copy of
    `axi_uart.vh` expands to nothing and ours is used instead;
  * it writes a one-line prelude that the build compiles *before* the IP.

Output: sim/gen/uart/pp_uart_defines.vh  and  sim/gen/uart/pp_uart_prelude.sv
"""

from __future__ import print_function

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from soc_config import load_config, ConfigError  # noqa: E402

IP_DIR = os.path.join(ROOT, "rtl", "vendor", "axi-lite-uart", "src")
IP_HEADER = os.path.join(IP_DIR, "include", "axi_uart.vh")

DEFINE_RE = re.compile(r"^\s*`define\s+(\S+)\s+(.*?)\s*$")

# macros whose value comes from the environment rather than from the IP
OVERRIDDEN = ("_UART_MAIN_CLOCK_FREQ_", "_UART_BAUDRATE_INIT_")


def parse_header(path):
    """Return an ordered list of (name, value, is_conditional) from a .vh."""
    out = []
    with open(path) as handle:
        for raw in handle:
            line = raw.split("//")[0].rstrip()
            match = DEFINE_RE.match(line)
            if match:
                out.append((match.group(1), match.group(2), line))
    return out


def gen(cfg, gendir):
    if not os.path.isfile(IP_HEADER):
        raise ConfigError("vendored UART header not found at %s" % IP_HEADER)

    defs = parse_header(IP_HEADER)
    if not defs:
        raise ConfigError("no `define found in %s" % IP_HEADER)

    out = []
    out.append("// " + "=" * 74)
    out.append("// GENERATED FILE -- DO NOT EDIT")
    out.append("//")
    out.append("// Produced by tools/gen_uart_defines.py.  Copied verbatim from the")
    out.append("// vendored UART IP's axi_uart.vh, with only the two environment macros")
    out.append("// below replaced by values from config/soc_config.yaml.")
    out.append("//")
    out.append("//   _UART_MAIN_CLOCK_FREQ_ : %d Hz   (config: clock.freq_hz)" % cfg.clock_freq_hz)
    out.append("//   _UART_BAUDRATE_INIT_   : %d baud (config: uart.baud)" % cfg.uart_baud)
    out.append("//   -> _UART_BAUDRATE_DIV_INIT_ = %d" % cfg.uart_divisor)
    out.append("// " + "=" * 74)
    out.append("")
    out.append("// Suppress the IP's own copy of this header so ours is the one used.")
    out.append("`ifndef _AXI_UART_H_")
    out.append("`define _AXI_UART_H_")
    out.append("`endif")
    out.append("")

    seen = set()
    for name, _value, line in defs:
        if name == "_AXI_UART_H_":
            continue
        if name in OVERRIDDEN:
            value = (str(cfg.clock_freq_hz) if name == "_UART_MAIN_CLOCK_FREQ_"
                     else str(cfg.uart_baud))
            out.append("`define %-32s %s" % (name, value))
        else:
            out.append(line.rstrip())
        seen.add(name)

    missing = [n for n in OVERRIDDEN if n not in seen]
    if missing:
        raise ConfigError("vendored UART header does not define %s -- the override "
                          "mechanism needs updating" % ", ".join(missing))

    header = os.path.join(gendir, "uart", "pp_uart_defines.vh")
    if not os.path.isdir(os.path.dirname(header)):
        os.makedirs(os.path.dirname(header))
    with open(header, "w") as handle:
        handle.write("\n".join(out) + "\n")

    prelude = os.path.join(gendir, "uart", "pp_uart_prelude.sv")
    with open(prelude, "w") as handle:
        handle.write("// GENERATED FILE -- DO NOT EDIT (tools/gen_uart_defines.py)\n"
                     "//\n"
                     "// Must be compiled *before* the vendored UART IP so that the IP's\n"
                     "// `include \"axi_uart.vh\" expands to nothing and the config-derived\n"
                     "// macros above are the ones the IP sees.\n"
                     "`include \"pp_uart_defines.vh\"\n")
    return [header, prelude]


def main(argv):
    try:
        cfg = load_config(os.path.join(ROOT, "config", "soc_config.yaml"))
        outputs = gen(cfg, os.path.join(ROOT, "sim", "gen"))
    except ConfigError as exc:
        sys.stderr.write("gen_uart_defines: %s\n" % exc)
        return 1
    print("gen_uart_defines: UART divisor %d (%d Hz / %d baud)"
          % (cfg.uart_divisor, cfg.clock_freq_hz, cfg.uart_baud))
    for path in outputs:
        print("      %s" % os.path.relpath(path, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
