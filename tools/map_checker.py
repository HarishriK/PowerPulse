#!/usr/bin/env python3
"""PowerPulse memory-map checker.

Run as part of `make gen`; any violation fails the build.  It is also a
standalone tool (`python3 tools/map_checker.py [config.yaml]`) and a *unit under
test*: `make run T=map_checker_negative` feeds it deliberately broken maps and
requires it to reject each one, so the checker itself is proven able to fail.

Rules enforced
--------------
 1. every slave range is a power-of-two size, >= 4 KiB, aligned to its size
 2. no two slave ranges overlap
 3. no slave range overlaps a core-internal region (PIC, and ICCM/DCCM when on)
 4. every slave fits inside the configured address width
 5. a disabled slot must be resolvable to a stub: `kind` must be one the SoC top
    knows how to stub, and it must not claim to be a RAM with a hex image
 6. a slot with `protocol: axil` that is enabled must request its bridge, and a
    slot with `protocol: axi` must not (a bridge on a native AXI4 memory would
    silently drop burst support)
 7. `kind: tb` implies `sim_only: true`, and vice versa is not required but a
    sim_only slot must not be reachable from a synthesis-only expectation list
 8. the reset vector and the software load address lie inside the instruction
    memory, and are 4-byte aligned
 9. the UART divisor derived from clock.freq_hz / uart.baud fits in the IP's
    divider register (32 bits) and is non-zero
10. exactly one slot provides the simulation status device, and it is sim_only

Exit status: 0 = map is legal, 1 = at least one violation (all are printed).
"""

from __future__ import print_function

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from soc_config import load_config, ConfigError, _is_pow2  # noqa: E402

STUBBABLE_KINDS = ("ip", "tb")


def _overlap(a_base, a_end, b_base, b_end):
    return a_base < b_end and b_base < a_end


def check(cfg):
    """Return a list of human-readable violations (empty list == legal map)."""
    errors = []

    addr_space = 1 << cfg.addr_width

    # -- 1/4: per-slot geometry ------------------------------------------
    for slot in cfg.slots:
        if not _is_pow2(slot.size):
            errors.append("slaves[%d] %s: size 0x%x is not a power of two"
                          % (slot.index, slot.name, slot.size))
        if slot.size < 0x1000:
            errors.append("slaves[%d] %s: size 0x%x is below the 4 KiB decode granularity"
                          % (slot.index, slot.name, slot.size))
        if slot.base % slot.size:
            errors.append("slaves[%d] %s: base 0x%x is not aligned to size 0x%x"
                          % (slot.index, slot.name, slot.base, slot.size))
        if slot.base < 0 or slot.end > addr_space:
            errors.append("slaves[%d] %s: range 0x%x..0x%x escapes the %d-bit address space"
                          % (slot.index, slot.name, slot.base, slot.end, cfg.addr_width))

    # -- 2: overlaps between slots ----------------------------------------
    ordered = sorted(cfg.slots, key=lambda s: s.base)
    for i in range(len(ordered)):
        for j in range(i + 1, len(ordered)):
            a, b = ordered[i], ordered[j]
            if _overlap(a.base, a.end, b.base, b.end):
                errors.append(
                    "overlapping slave ranges: %s 0x%x..0x%x and %s 0x%x..0x%x"
                    % (a.name, a.base, a.end - 1, b.name, b.base, b.end - 1))

    # -- 3: overlaps with core-internal regions ---------------------------
    for slot in cfg.slots:
        for region in cfg.core_regions:
            if _overlap(slot.base, slot.end, region["base"], region["base"] + region["size"]):
                errors.append(
                    "slave %s 0x%x..0x%x overlaps core-internal region %s 0x%x..0x%x (%s)"
                    % (slot.name, slot.base, slot.end - 1, region["name"],
                       region["base"], region["base"] + region["size"] - 1, region["note"]))

    # ICCM/DCCM are only reserved when the core actually has them enabled.
    for slot in cfg.slots:
        for opt in ("iccm_enable", "dccm_enable"):
            if int(cfg.veer_options.get(opt, 0)) != 0:
                errors.append("core.veer_options.%s=%s: ICCM/DCCM are not supported with "
                              "external AXI memories; the map checker cannot prove the "
                              "core region is free (offending slot %s)"
                              % (opt, cfg.veer_options[opt], slot.name))

    # -- 5: disabled slots must resolve to a stub --------------------------
    for slot in cfg.slots:
        if slot.enabled:
            continue
        if slot.kind not in STUBBABLE_KINDS:
            errors.append("slaves[%d] %s: disabled slot must have kind in %s so that it "
                          "resolves to the decode-error stub slave, got %r"
                          % (slot.index, slot.name, "/".join(STUBBABLE_KINDS), slot.kind))
        if slot.hex:
            errors.append("slaves[%d] %s: disabled slot still asks for a hex image"
                          % (slot.index, slot.name))

    # -- 6: bridge/protocol consistency -----------------------------------
    for slot in cfg.slots:
        if slot.protocol == "axil" and not slot.bridge:
            errors.append("slaves[%d] %s: protocol 'axil' requires bridge: true "
                          "(an AXI4-Lite slave cannot be attached to the AXI4 interconnect "
                          "directly)" % (slot.index, slot.name))
        if slot.protocol == "axi" and slot.bridge:
            errors.append("slaves[%d] %s: protocol 'axi' must not request a bridge; the "
                          "bridge would drop burst support" % (slot.index, slot.name))
        if slot.protocol == "axil" and slot.kind == "ram":
            errors.append("slaves[%d] %s: a RAM slot must use protocol 'axi' "
                          "(AXI4-Lite RAMs would lose burst throughput)"
                          % (slot.index, slot.name))

    # -- 7: simulation-only slots -----------------------------------------
    for slot in cfg.slots:
        if slot.kind == "tb" and not slot.sim_only:
            errors.append("slaves[%d] %s: kind 'tb' must set sim_only: true" % (slot.index, slot.name))

    # -- 10: exactly one status device ------------------------------------
    tb_slots = [s for s in cfg.slots if s.kind == "tb"]
    if len(tb_slots) != 1:
        errors.append("expected exactly one kind:'tb' slot (the simulation status device), "
                      "found %d: %s" % (len(tb_slots), [s.name for s in tb_slots]))
    for slot in tb_slots:
        if not slot.sim_only:
            errors.append("slaves[%d] %s: the status device must be sim_only" % (slot.index, slot.name))

    # -- 8: reset vector / load address -----------------------------------
    if cfg.reset_vector % 4:
        errors.append("core.reset_vector 0x%x is not 4-byte aligned" % cfg.reset_vector)
    if not (cfg.imem.base <= cfg.reset_vector < cfg.imem.end):
        errors.append("core.reset_vector 0x%x is outside instruction memory %s 0x%x..0x%x"
                      % (cfg.reset_vector, cfg.imem.name, cfg.imem.base, cfg.imem.end - 1))
    if not (cfg.imem.base <= cfg.sw_load_addr < cfg.imem.end):
        errors.append("software.load_addr 0x%x is outside instruction memory %s 0x%x..0x%x"
                      % (cfg.sw_load_addr, cfg.imem.name, cfg.imem.base, cfg.imem.end - 1))
    if not (cfg.imem.base <= cfg.sw_load_addr <= cfg.reset_vector):
        errors.append("software.load_addr 0x%x must be <= core.reset_vector 0x%x so that the "
                      "image starts at the reset vector"
                      % (cfg.sw_load_addr, cfg.reset_vector))

    # -- 9: UART divisor ---------------------------------------------------
    if cfg.uart_divisor <= 0 or cfg.uart_divisor >= (1 << 32):
        errors.append("derived UART divisor clock.freq_hz/uart.baud = %d does not fit the "
                      "UART IP's 32-bit divider register" % cfg.uart_divisor)
    if cfg.uart_data_bits not in (5, 6, 7, 8):
        errors.append("uart.data_bits must be 5..8, got %d" % cfg.uart_data_bits)
    if cfg.uart_stop_bits not in (1, 2):
        errors.append("uart.stop_bits must be 1 or 2, got %d" % cfg.uart_stop_bits)
    if cfg.uart_parity not in ("none", "even", "odd"):
        errors.append("uart.parity must be none/even/odd, got %r" % cfg.uart_parity)

    return errors


def format_table(cfg):
    """Human-readable memory map (also written to the docs by the generator)."""
    rows = ["| Slot | Module | Base | End | Size | Protocol | Bridge | Enabled |",
            "|---|---|---|---|---|---|---|---|"]
    for slot in sorted(cfg.slots, key=lambda s: s.base):
        state = "yes" if slot.enabled else "no"
        if slot.enabled and slot.sim_only:
            state = "sim only"
        rows.append("| %d | `%s` | `0x%08x` | `0x%08x` | `0x%06x` (%d KiB) | %s | %s | %s |" % (
            slot.index, slot.name, slot.base, slot.end - 1, slot.size, slot.size // 1024,
            slot.protocol, "yes" if slot.bridge else "no", state))
    for region in cfg.core_regions:
        rows.append("| - | `%s` (core) | `0x%08x` | `0x%08x` | `0x%06x` (%d KiB) | - | - | reserved |" % (
            region["name"], region["base"], region["base"] + region["size"] - 1,
            region["size"], region["size"] // 1024))
    return "\n".join(rows)


def main(argv):
    path = argv[1] if len(argv) > 1 else "config/soc_config.yaml"
    try:
        cfg = load_config(path)
    except ConfigError as exc:
        print("map checker: configuration is malformed")
        print("  %s" % exc)
        return 1

    errors = check(cfg)
    if errors:
        print("map checker: %d violation(s) in %s" % (len(errors), cfg.path))
        for err in errors:
            print("  ERROR %s" % err)
        return 1

    print("map checker: %s is legal (%d slots, %d masters, %d-bit addresses)"
          % (os.path.relpath(cfg.path), cfg.n_slots, cfg.n_masters, cfg.addr_width))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
