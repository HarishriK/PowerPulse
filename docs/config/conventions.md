# PowerPulse conventions
- All addresses/widths/sizes/clock/baud/tool paths come from `config/soc_config.yaml`.
- Never hardcode; regenerate via `make gen`.
- Never modify `rtl/core/veer_el2` or vendor RTL.
