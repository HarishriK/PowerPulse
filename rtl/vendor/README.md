# Vendored third-party RTL

Third-party sources are committed here, unmodified, so that the build never needs
network access.  Each folder carries its own upstream licence file.

| Folder | Upstream | Version / commit | Licence | Used by |
|---|---|---|---|---|
| `veer_el2/` | Chips Alliance / Western Digital **Cores-VeeR-EL2** (EL2) | see `veer_el2/release-notes.md` | Apache-2.0 (`veer_el2/LICENSE`) | `rtl/core/pp_veer_core.sv` — the CPU |
| `verilog-axi/` | Alex Forencich **verilog-axi** | commit `516bd5d` (files downloaded 2026-10-03, byte-identical to the copies originally dropped in the repository root) | MIT (headers retained in every file) | `arbiter.v`, `priority_encoder.v` — round-robin grant primitives used by the generated interconnect |
| `axi-lite-uart/` | BSC / CIC-IPN **axi-lite_uart-ipcore** (`m4j0rt0m/axi-lite_uart-ipcore`) | `develop`, as provided | see `axi-lite-uart/LICENSE` | `rtl/ip/uart/pp_uart.sv` — the UART |

## Rules

* **Never edit** anything in these folders.  Fixes go in `rtl/` wrappers.
* `verilog-axi/axi_interconnect.v` is kept as a **reference only** — it is *not*
  instantiated by the build.  It is retained because it was supplied with the
  project and because it documents the arbitration/decode behaviour that the
  generated interconnect mirrors.  Reasons it is not used are recorded in
  `docs/interconnect_generator/` (notably: it has no decode-error default slave
  and forbids overlapping decode regions, both of which this SoC requires).
