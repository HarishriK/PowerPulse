# PowerPulse — Project Context

> **Audience:** any coding agent (or new contributor) working in this repository.
> **Read this first.** It explains what the project is, how it is organised, how it is verified, and the rules that keep it consistent.
> The step-by-step work plan lives in `PHASES.md`. This file is the standing context that applies to every task.

---

## 1. What this project is

**PowerPulse** is an adaptive low-power-aware RISC-V System-on-Chip, built in synthesizable RTL and demonstrated entirely through simulation.

It is built around the **VeeR RISC-V EL2** core (provided by the faculty) and connects the core to memories and peripherals over an **AXI interconnect**. The SoC retains the mandatory components — RISC-V core, instruction memory, data memory, bus interconnect, UART, Timer, GPIO — and adds three custom IP blocks that together give autonomous, hardware-driven activity management:

| Custom IP | Role |
|---|---|
| **HAP** — Hardware Activity Profiler | Watches selected peripheral activity, keeps programmable inactivity counters, raises an *idle* indication when a threshold is reached |
| **PPMC** — Peripheral Power Management Controller | Central state machine. Moves selected peripherals between **ACTIVE**, **IDLE** and **LOW-ACTIVITY** by driving peripheral-enable / clock-enable signals |
| **AWEC** — Autonomous Wake-Up Event Controller | Watches enabled wake sources (UART RX activity, GPIO edges, Timer compare), captures the source, and asks the PPMC to restore the affected peripheral |

Functional sequence the SoC demonstrates:

```
Activity Monitoring → Idle Detection → Transition to LOW-ACTIVITY
→ Wake-Up Event Detection → Automatic Peripheral Restoration → Software Status Handling
```

### Scope boundaries (do not overstep)

- Power management is **RTL-level activity management** using enable / clock-enable signals. **Do not** claim or implement technology-dependent physical power gating.
- The VeeR core is third-party. **Never modify core source.** Integrate around it.
- Everything must remain **synthesizable** (outside `tb/`) and **demonstrable through simulation**.
- Toolchain: **Synopsys VCS** (simulation) and **Verdi** (debug), driven by **make**. RISC-V GCC toolchain is installed under `/opt` (path is a parameter, never hardcoded).

---

## 2. Project phases (summary)

| Phase | Goal |
|---|---|
| **Phase 1** | Foundation: repo, config system, generated AXI interconnect, VeeR integration, width adapters, UART through the interconnect, test-aware make flow, end-to-end tests (integration + software via hex loading) |
| **Phase 2** | Custom IPs (HAP, PPMC, AWEC) plus Timer/GPIO prerequisites, each implemented and verified end to end, then full-system scenarios and verification closure |

Details, task IDs and exit criteria are in `PHASES.md`.

---

## 3. System architecture (as planned)

```
                VeeR EL2 core
        ┌────────┬────────┬────────┐
        IFU      LSU       SB            (three 64-bit AXI masters; DMA slave port tied off)
        │        │         │
   [64→32 downsizers — one per master]
        │        │         │
        └────────┼─────────┘
                 │
        32-bit AXI interconnect  (generated, arbitrated)
                 │
   ┌──────┬──────┼──────┬───────┬───────────────┐
 Memory  UART  Timer  GPIO   Custom IP slots   Default/stub
                              (HAP, PPMC, AWEC)  (DECERR / tie-off)
```

Key architectural facts:

- The core's AXI ports are **64-bit**; the interconnect is **32-bit**. A **downsizer** sits between every core master and the interconnect.
- Peripherals and custom IPs are **register-based slaves**. Where a slave is AXI4-Lite, a **protocol bridge** (AXI4 → AXI4-Lite) is placed in front of it. Bridges exist only on slots where the config says so.
- Every slave slot, **including Phase 2 custom IPs, exists in the interconnect from day one**. Unused slots point at a stub slave. Enabling a custom IP later is a config flag plus an RTL drop-in — not a re-architecture.
- **Default memories are external AXI slaves** (simple hex loading, simple adapter testing). Core-internal ICCM/DCCM are disabled in the core config unless the plan is explicitly changed.
- Peripheral activity signals flow to the HAP; enable signals flow from the PPMC to peripherals; wake events flow from sources to the AWEC, then to the PPMC.

---

## 4. Verification ethos

Verification is the main product of this project. Code is not "done" until it is verified, documented, and runnable with one make command. These principles apply to every task.

1. **Self-checking, always.** Every test decides PASS or FAIL itself. No test may require a human to look at a waveform to know the result. Waveforms are for *debugging* failures only.
2. **Independent expectations.** Expected values come from the specification or an independent reference model — never copied from what the RTL happens to output.
3. **Bottom-up bring-up.** Unit → integration → system. Never debug the full SoC for a bug a unit test could have caught. Bring up the bus *without* the core first; add the core only when the bus is proven.
4. **Protocol assertions always on.** AXI protocol checkers monitor master and slave ports in every simulation. A protocol violation fails the test.
5. **Negative tests are mandatory.** Unmapped addresses, error responses, illegal accesses, resets mid-transaction, and backpressure are tested, not assumed.
6. **Randomised timing, controlled seeds.** Ready/valid delays are randomisable. Every run logs its seed so any failure is reproducible.
7. **Tests must be able to fail.** A new check should be shown to fail against a deliberately broken DUT or stimulus at least once. A check that cannot fail proves nothing.
8. **Never weaken a test to make it pass.** If a test fails, find the root cause. If the spec and RTL disagree, report it — do not silently change either side.
9. **Every test has a purpose and a timeout.** A one-line purpose in the test's settings file, and a timeout so hangs become failures.
10. **Coverage drives closure (Phase 2).** Functional and code coverage are tracked and merged; the plan defines targets. Uncovered items are either tested or justified in writing.
11. **Regressions stay green.** Every task ends with the relevant regression group passing. Never leave the tree red.
12. **Reproducibility.** Each run records its exact command and parameters. A result that cannot be reproduced does not count.

### Test taxonomy

| Type | What drives it | Purpose |
|---|---|---|
| **Unit** | Standalone testbench per module (adapter, bridge, each custom IP) | Prove one block against its spec |
| **Integration (core-less)** | AXI master model on the real interconnect + real slaves | Prove bus, decode, adapters and slaves without the core |
| **Software (core-in-loop)** | Real VeeR core running a program loaded from a hex file | Prove the system as software sees it |
| **Scenario (Phase 2)** | Core-in-loop, multi-IP | Prove the full activity-management sequence |

Software tests report PASS/FAIL through a **simulation-only status register** in the testbench (testbench-only; never part of synthesizable RTL).

---

## 5. Repository structure

```
powerpulse/
├── Makefile                  single entry point
├── README.md                 project front page (kept current)
├── PROJECT_CONTEXT.md        this file
├── PHASES.md                 phased plan
├── .gitignore                root ignore rules (plus per-directory ones where needed)
├── config/                   single source of truth
│   ├── soc_config.*          memory map, parameters, enabled slaves
│   └── veer/                 pinned VeeR configuration snapshot
├── tools/                    interconnect generator, map checker, hex conversion, make helpers
├── rtl/
│   ├── core/                 VeeR EL2 (pinned, unmodified)
│   ├── bus/                  GENERATED interconnect + adapters/bridges (adapters are hand-written; generated files are marked)
│   ├── common/               reusable pieces (e.g. AXI4-Lite register-slave template)
│   ├── mem/                  AXI memory slaves
│   ├── ip/
│   │   ├── uart/             existing IP (+ AXI wrapper if needed)
│   │   ├── timer/  gpio/
│   │   ├── hap/  ppmc/  awec/   Phase 2 custom IPs (placeholders until built)
│   │   └── stub/             tie-off slave for unused slots
│   └── top/                  SoC top level
├── tb/
│   ├── common/               AXI master model, protocol checkers, UART model, status device, clock/reset
│   ├── unit/                 per-module benches
│   └── soc/                  system-level bench
├── sw/
│   ├── common/               startup, generated linker script, generated memory-map header, drivers
│   └── tests/<test_name>/    one folder per software test (source + settings file)
├── sim/                      ALL build outputs (git-ignored)
│   ├── build/                shared compile
│   ├── runs/<test>/          per-test: sw/, logs/, waves/, cmd record, result
│   ├── latest -> runs/<last>
│   └── regress/              summary and merged coverage
└── docs/<implementation>/    one documentation folder per implementation
```

### Test-aware run directory

- Every test owns `sim/runs/<test>/` (seeded repeats: `<test>_s<seed>/`). Software artefacts, logs, waveform, command record and result live there.
- The compiled simulator is **shared** in `sim/build/` and rebuilt only when RTL or config changes.
- Software rebuilds only when its sources change (dependency-driven).
- Tests are **discovered by folder** — add a folder with source and a settings file; no Makefile edits.

### Make interface (simple by design)

| Command | Effect |
|---|---|
| `make run T=<test>` | Does whatever is stale (generate, compile, software build) then simulates and prints PASS/FAIL |
| `make wave T=<test>` | Opens that run's waveform in Verdi (waveform is always dumped) |
| `make regress G=<group>` | Runs a group (or everything), prints a summary table |
| `make list` | Lists tests and groups |
| `make hex T=<test> HEX=<path>` | Runs an externally built hex (manual loading) |
| `make clean T=<test>` / `make clean-all` | Cleans one run / everything |
| `make help` | Shows all targets and variables |

Optional: `SEED=`, `CONFIG=`. There is deliberately **no waves on/off switch**.

---

## 6. Working rules for agents

### Single source of truth
- The memory map and parameters live in `config/`. **Never hardcode** addresses, widths, sizes, clock/baud values, tool paths, or ISA flags in RTL, testbenches, scripts or software.
- **Never hand-edit generated files** (interconnect RTL, linker script, memory-map header, register tables). Change the config or the generator and regenerate. Generated files carry a "generated — do not edit" banner.
- Generated outputs are git-ignored; only config and generator are committed.

### Structure and scalability
- One folder per IP; one documentation folder per implementation.
- Adding a slave = config entry + RTL + tests + docs. If it needs anything more, fix the generator rather than working around it.
- Keep module interfaces parameterised (widths, depths, counts) with sensible defaults.
- Keep simulation-only code inside `tb/`.

### Conventions (confirm and then keep consistent)
- lowercase `snake_case` for files, modules and signals; one module per file, file name = module name.
- A single reset polarity and style, defined once in the config documentation (default: active-low, following AXI/VeeR convention).
- Registers documented with address offset, name, access type (RO/RW/W1C…), reset value and description — generated into tables where possible.

### Workflow per task
1. Read the task in `PHASES.md` (note its task ID and exit criteria).
2. Write or update the **spec/doc stub** first.
3. Implement, then write tests, then run them via `make`.
4. Complete the documentation (see below) and update the README if user-visible behaviour changed.
5. Run the relevant regression group; it must be green.
6. Commit small and often with the task ID in the message (e.g. `P1-05: generate AXI crossbar from config`).

### Documentation standard (every implementation)
Each implementation gets `docs/<name>/` containing:
1. **Overview** — purpose and where it fits
2. **Block diagram** — clean and minimal: few labels, no crossing lines, clear grouping
3. **Interface** — ports and parameters
4. **Register map** — if memory-mapped
5. **Behaviour and timing** — state machines, sequences, corner cases
6. **How to run its tests** — exact make commands
7. **Verification summary** — tests, what they prove, results, known gaps
8. **Change notes / open issues**

Documentation is part of "done". Extensive and neatly organised beats brief.

### Do / Don't

| Do | Don't |
|---|---|
| Drive everything through `make` | Run simulator or scripts by hand and forget the flags |
| Add a test with every feature or fix | Merge RTL changes without tests |
| Fix root causes | Loosen checks, widen timeouts, or add waivers to hide failures |
| Ask when the spec is ambiguous | Guess silently and encode the guess |
| Keep generated and hand-written code separate | Edit generated files or the VeeR core |
| Record assumptions in the docs | Leave assumptions only in your head |

---

## 7. Known assumptions and open items

Record changes here as they are decided.

- Peripherals/custom IPs assumed **AXI4-Lite** slaves behind bridges; core and interconnect side treated as AXI4.
- Memories are **external AXI slaves**; VeeR ICCM/DCCM disabled by default.
- DMA slave port of the core **tied off** in Phase 1.
- UART IP's native interface (and whether it needs an AXI4-Lite wrapper) to be confirmed when integrating.
- VeeR AXI ID widths and exact interconnect arbitration policy to be fixed during P1-04/P1-05 and recorded in the config docs.
- Core-internal regions (interrupt controller, ICCM/DCCM if enabled) must be excluded from the user memory map; the map checker enforces this.
