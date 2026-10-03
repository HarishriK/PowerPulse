# hap — Phase 2 placeholder

Reserved interconnect slot.  No RTL yet.

* Enable it by setting `enabled: true` for the `hap` entry in
  `config/soc_config.yaml`, dropping the module in this folder, and wiring it in
  `rtl/top/powerpulse_soc.sv`.  Nothing else changes: the slot, its address
  decode and the bridge are already generated.  See `docs/interconnect_generator/`.
