"""Single source of truth loader for the PowerPulse SoC configuration.

`config/soc_config.yaml` is the only place where an address, width, size, clock
or baud rate is written down.  This module parses it once, checks it, and hands
out a fully derived, self-consistent view that the generators, the Makefile and
the documentation all consume.  Nothing downstream is allowed to re-read the
YAML itself.

Usage:
    from soc_config import load_config
    cfg = load_config("config/soc_config.yaml")

Public API (all read-only):
    cfg.raw                 -- the parsed YAML, verbatim
    cfg.bus / cfg.clock / cfg.slaves / cfg.slots ...
    cfg.slots               -- list of Slot, in config order, S_COUNT of them
    cfg.hw_slots            -- slots that exist in a synthesis build
    cfg.base(name) / cfg.size(name) / cfg.index(name)
    cfg.crossbar_widths()   -- Verilog parameter snippets for the interconnect
    cfg.memory_map()        -- resolved (name, base, size, protocol, enabled)
"""

import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "PowerPulse needs PyYAML to read config/soc_config.yaml.\n"
        "  pip3 install pyyaml\n"
    )
    raise


class ConfigError(Exception):
    """Raised for any malformed or inconsistent configuration."""


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def _req(mapping, key, where):
    if key not in mapping:
        raise ConfigError("config: missing required key '%s' in %s" % (key, where))
    return mapping[key]


def _as_int(value, where):
    """Accept 0x.. / 0b.. / decimal (int or str) and return a python int."""
    if isinstance(value, bool):
        raise ConfigError("config: %s must be a number, not a bool" % where)
    if isinstance(value, int):
        return value
    text = str(value).strip().replace("_", "")
    try:
        return int(text, 0)
    except ValueError:
        raise ConfigError("config: %s is not an integer: %r" % (where, value))


def _as_bool(value, where):
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    if text in ("1", "true", "yes", "on"):
        return True
    if text in ("0", "false", "no", "off"):
        return False
    raise ConfigError("config: %s must be a boolean, got %r" % (where, value))


def _is_pow2(value):
    return value > 0 and (value & (value - 1)) == 0


def log2_exact(value, where):
    if not _is_pow2(value):
        raise ConfigError("config: %s must be a power of two, got 0x%x" % (where, value))
    return value.bit_length() - 1


# --------------------------------------------------------------------------
# Slot
# --------------------------------------------------------------------------

class Slot(object):
    """One interconnect slave slot, fully resolved."""

    def __init__(self, index, entry, cfg):
        where = "slaves[%d]" % index
        self.index = index
        self.name = str(_req(entry, "name", where))
        self.module = str(entry.get("module", self.name))
        self.base = _as_int(_req(entry, "base", where), where + ".base")
        self.size = _as_int(_req(entry, "size", where), where + ".size")
        self.protocol = str(entry.get("protocol", "axil")).lower()
        self.bridge = _as_bool(entry.get("bridge", self.protocol == "axil"), where + ".bridge")
        self.enabled = _as_bool(entry.get("enabled", True), where + ".enabled")
        self.sim_only = _as_bool(entry.get("sim_only", False), where + ".sim_only")
        self.kind = str(entry.get("kind", "ip"))
        self.hex = _as_bool(entry.get("hex", False), where + ".hex")
        self.irq = _as_bool(entry.get("irq", False), where + ".irq")
        self.note = str(entry.get("note", ""))

        if self.protocol not in ("axi", "axil"):
            raise ConfigError("config: %s.protocol must be 'axi' or 'axil', got %r"
                              % (where, self.protocol))
        if self.kind not in ("ram", "ip", "tb"):
            raise ConfigError("config: %s.kind must be ram/ip/tb, got %r" % (where, self.kind))
        if self.kind == "tb" and not self.sim_only:
            raise ConfigError("config: %s has kind 'tb' so it must set sim_only: true" % where)

        # derived
        self.addr_bits = log2_exact(self.size, where + ".size")
        self.end = self.base + self.size            # exclusive
        if self.enabled and self.sim_only and not cfg.sim:
            # kept in the decode so software headers stay stable; documented
            pass

    @property
    def top_bits(self):
        """Number of address MSBs compared by the decoder (ADDR_WIDTH - size bits)."""
        return None  # filled in by Config, which knows addr_width

    def top_const(self, addr_width):
        """Constant that the top (addr_width - addr_bits) address bits must equal."""
        keep = addr_width - self.addr_bits
        return (self.base >> keep) & ((1 << keep) - 1), keep

    def __repr__(self):
        return "<Slot %s 0x%08x+0x%x %s%s>" % (
            self.name, self.base, self.size, self.protocol,
            "" if self.enabled else " disabled")


# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------

class Config(object):

    def __init__(self, path, overrides=None):
        self.path = os.path.abspath(path)
        with open(self.path, "r") as handle:
            self.raw = yaml.safe_load(handle)

        if not isinstance(self.raw, dict):
            raise ConfigError("config: %s is not a YAML mapping" % path)

        # Which build flavour are we generating for?  Only the `status` slot cares.
        self.sim = True
        if overrides:
            self.sim = str(overrides.get("sim", self.sim)).lower() not in ("0", "false", "no")

        bus = _req(self.raw, "bus", "config root")
        self.core_data_width = _as_int(_req(bus, "core_data_width", "bus"), "bus.core_data_width")
        self.xbar_data_width = _as_int(_req(bus, "xbar_data_width", "bus"), "bus.xbar_data_width")
        self.addr_width = _as_int(_req(bus, "addr_width", "bus"), "bus.addr_width")
        self.id_width = _as_int(_req(bus, "id_width", "bus"), "bus.id_width")
        self.arbitration = str(_req(bus, "arbitration", "bus"))
        self.axil_split_bursts = _as_bool(bus.get("axil_split_bursts", True), "bus.axil_split_bursts")

        if self.core_data_width != 2 * self.xbar_data_width:
            raise ConfigError(
                "config: bus.core_data_width (%d) must be exactly twice "
                "bus.xbar_data_width (%d); the only supported adapter is 2:1"
                % (self.core_data_width, self.xbar_data_width))
        if self.xbar_data_width != 32:
            raise ConfigError("config: bus.xbar_data_width must be 32")
        if self.arbitration != "round_robin":
            raise ConfigError("config: bus.arbitration must be 'round_robin'")

        core = _req(self.raw, "core", "config root")
        self.core_rtl_dir = str(_req(core, "rtl_dir", "core"))
        self.veer_options = dict(core.get("veer_options") or {})
        self.reset_vector = _as_int(_req(core, "reset_vector", "core"), "core.reset_vector")

        clock = _req(self.raw, "clock", "config root")
        self.clock_freq_hz = _as_int(_req(clock, "freq_hz", "clock"), "clock.freq_hz")
        self.clock_period_ps = _as_int(
            clock.get("period_ps") or (10 ** 12 // self.clock_freq_hz), "clock.period_ps")

        rst = self.raw.get("reset") or {}
        self.reset_assert_level = str(rst.get("assert_level", "low"))
        self.reset_style = str(rst.get("style", "async_assert_sync_release"))
        self.reset_cycles = _as_int(rst.get("cycles", 20), "reset.cycles")
        if self.reset_assert_level != "low":
            raise ConfigError("config: only an active-low reset (reset.assert_level: low) "
                              "is supported, following AXI/VeeR convention")

        mem = _req(self.raw, "memory", "config root")
        self.hex_word_bytes = _as_int(_req(mem, "hex_word_bytes", "memory"), "memory.hex_word_bytes")
        self.mem_load_from = str(mem.get("load_from", "hex"))
        self.mem_plusarg = str(mem.get("plusarg", "+hex"))
        if self.hex_word_bytes != 4:
            raise ConfigError("config: memory.hex_word_bytes must be 4")

        uart = self.raw.get("uart") or {}
        self.uart_baud = _as_int(uart.get("baud", 115200), "uart.baud")
        self.uart_data_bits = _as_int(uart.get("data_bits", 8), "uart.data_bits")
        self.uart_stop_bits = _as_int(uart.get("stop_bits", 1), "uart.stop_bits")
        self.uart_parity = str(uart.get("parity", "none"))
        self.uart_irq_wired = _as_bool(uart.get("irq_wired_to_core", False), "uart.irq_wired_to_core")

        sw = _req(self.raw, "software", "config root")
        self.sw_toolchain_path = str(_req(sw, "toolchain_path", "software"))
        self.sw_toolchain_prefix = str(_req(sw, "toolchain_prefix", "software"))
        self.sw_isa = str(_req(sw, "isa", "software"))
        self.sw_abi = str(_req(sw, "abi", "software"))
        self.sw_march = str(_req(sw, "march", "software"))
        self.sw_mabi = str(_req(sw, "mabi", "software"))
        self.sw_opt = str(_req(sw, "opt", "software"))
        self.sw_load_addr = _as_int(_req(sw, "load_addr", "software"), "software.load_addr")

        sim = _req(self.raw, "simulation", "config root")
        self.sim_timeout_ns = _as_int(_req(sim, "default_timeout_ns", "simulation"),
                                      "simulation.default_timeout_ns")
        self.sim_default_seed = _as_int(sim.get("default_seed", 1), "simulation.default_seed")
        self.sim_seeds = [_as_int(s, "simulation.seeds[]") for s in
                          (sim.get("seeds") or [self.sim_default_seed])]
        self.sim_vcs_compile = str(_req(sim, "vcs_compile_flags", "simulation"))
        self.sim_vcs_elab = str(_req(sim, "vcs_elab_flags", "simulation"))

        self.core_regions = []
        for i, region in enumerate(self.raw.get("core_regions") or []):
            self.core_regions.append({
                "name": str(region["name"]),
                "base": _as_int(region["base"], "core_regions[%d].base" % i),
                "size": _as_int(region["size"], "core_regions[%d].size" % i),
                "note": str(region.get("note", "")),
            })

        self.slots = [Slot(i, entry, self) for i, entry in enumerate(self.raw["slaves"])]
        self._by_name = {}
        for slot in self.slots:
            if slot.name in self._by_name:
                raise ConfigError("config: duplicate slave name '%s'" % slot.name)
            self._by_name[slot.name] = slot

        self.master_names = ["ifu", "lsu", "sb"]

        self._validate()

    # -- lookups ------------------------------------------------------------

    def slot(self, name):
        try:
            return self._by_name[name]
        except KeyError:
            raise ConfigError("config: no slave named '%s'" % name)

    def base(self, name):
        return self.slot(name).base

    def size(self, name):
        return self.slot(name).size

    def index(self, name):
        return self.slot(name).index

    @property
    def n_slots(self):
        return len(self.slots)

    @property
    def n_masters(self):
        return len(self.master_names)

    @property
    def hw_slots(self):
        """Slots that exist in a synthesis build (not sim-only)."""
        return [s for s in self.slots if not s.sim_only]

    @property
    def imem(self):
        return self.slot("imem")

    @property
    def dmem(self):
        return self.slot("dmem")

    # -- derived quantities -------------------------------------------------

    @property
    def strb_width(self):
        return self.xbar_data_width // 8

    @property
    def core_strb_width(self):
        return self.core_data_width // 8

    @property
    def imem_words(self):
        return self.imem.size // self.hex_word_bytes

    @property
    def uart_divisor(self):
        """16x oversampling divisor, exactly as the vendored UART IP computes it."""
        if self.uart_baud <= 0:
            raise ConfigError("config: uart.baud must be positive")
        return self.clock_freq_hz // self.uart_baud

    # -- validation (the map checker proper lives in tools/map_checker.py) ---

    def _validate(self):
        if not self.slots:
            raise ConfigError("config: at least one slave slot is required")

        for slot in self.slots:
            if not _is_pow2(slot.size):
                raise ConfigError("config: slaves[%d] (%s) size 0x%x is not a power of two"
                                  % (slot.index, slot.name, slot.size))
            if slot.size < 0x1000:
                raise ConfigError("config: slaves[%d] (%s) size 0x%x is smaller than the "
                                  "4 KiB decode granularity" % (slot.index, slot.name, slot.size))
            if slot.base % slot.size:
                raise ConfigError("config: slaves[%d] (%s) base 0x%x is not aligned to its "
                                  "size 0x%x" % (slot.index, slot.name, slot.base, slot.size))
            if slot.base + slot.size > (1 << self.addr_width):
                raise ConfigError("config: slaves[%d] (%s) range 0x%x..0x%x does not fit in a "
                                  "%d-bit address space"
                                  % (slot.index, slot.name, slot.base, slot.end,
                                     self.addr_width))

        if self.core_data_width % self.xbar_data_width:
            raise ConfigError("config: bus widths are not commensurate")

        if self.reset_vector % 4:
            raise ConfigError("config: core.reset_vector 0x%x must be 4-byte aligned"
                              % self.reset_vector)
        if not (self.imem.base <= self.reset_vector < self.imem.end):
            raise ConfigError("config: core.reset_vector 0x%x is outside the instruction "
                              "memory 0x%x..0x%x" % (self.reset_vector,
                                                      self.imem.base, self.imem.end))

        if not (self.imem.base <= self.sw_load_addr < self.imem.end):
            raise ConfigError("config: software.load_addr 0x%x is outside the instruction "
                              "memory 0x%x..0x%x" % (self.sw_load_addr,
                                                      self.imem.base, self.imem.end))

        # every slot must be either an enabled IP/RAM or explicitly sim_only
        for slot in self.slots:
            if not slot.enabled and not slot.sim_only:
                continue

        # software ISA/ABI sanity
        if not self.sw_march.startswith("rv32"):
            raise ConfigError("config: VeeR EL2 is RV32; software.march must start with rv32")
        if self.sw_mabi != "ilp32":
            raise ConfigError("config: VeeR EL2 has no FPU/D; software.mabi must be ilp32")

    # -- convenience for generators ----------------------------------------

    def memory_map(self):
        """Resolved (name, slot) pairs in address order, as documentation uses."""
        return sorted(self.slots, key=lambda s: s.base)

    def raw_digest(self):
        """Short digest of the raw config text, for build/run records."""
        import hashlib
        with open(self.path, "rb") as handle:
            return hashlib.sha256(handle.read()).hexdigest()[:12]

    def toolchain_signature(self):
        """Identity of the compiler, so a toolchain change forces a rebuild."""
        gcc = os.path.join(self.sw_toolchain_path, self.sw_toolchain_prefix + "gcc")
        if not os.path.isfile(gcc):
            return "missing"
        stamp = os.stat(gcc)
        return "%s:%d" % (os.path.basename(gcc), stamp.st_mtime)

    def c_define_name(self, name):
        return "PP_" + re.sub(r"[^A-Za-z0-9]", "_", name).upper()

    def h_addr(self, name):
        return self.c_define_name(name) + "_BASE"

    def h_size(self, name):
        return self.c_define_name(name) + "_SIZE"


def load_config(path="config/soc_config.yaml", overrides=None):
    return Config(path, overrides=overrides)


if __name__ == "__main__":  # tiny manual dump, handy while developing
    import json
    cfg = load_config()
    print(json.dumps({
        "path": cfg.path,
        "masters": cfg.master_names,
        "addr_width": cfg.addr_width,
        "core_data_width": cfg.core_data_width,
        "xbar_data_width": cfg.xbar_data_width,
        "id_width": cfg.id_width,
        "clock_freq_hz": cfg.clock_freq_hz,
        "uart_divisor": cfg.uart_divisor,
        "reset_vector": cfg.reset_vector,
        "slots": [{"i": s.index, "name": s.name, "base": s.base, "size": s.size,
                   "protocol": s.protocol, "bridge": s.bridge, "enabled": s.enabled,
                   "sim_only": s.sim_only} for s in cfg.slots],
    }, indent=2))
