# PMSM Regenerative Braking Simulation

MATLAB/Simulink model and supporting analysis scripts for investigating regenerative braking losses and efficiency in a PMSM-based back-to-back test-rig configuration.

This repository supports the dissertation:

**Analysis of Regenerative Braking Losses and Efficiency in a PMSM-Based Back-to-Back Test Rig**

## Dissertation submission note

This repository is provided as supplementary material for the dissertation. The Simulink model file `Final.slx`, MATLAB scripts and saved sweep results are provided to support transparency and reproducibility of the results reported in the dissertation.

The dissertation PDF should be treated as the authoritative written explanation of the methodology, assumptions, limitations and results.

## Important note

This repository was prepared for academic assessment. No licence is currently applied, so reuse is not granted unless permission is given by the author.

## Overview

This project analyses how regenerative braking efficiency varies with operating torque and rotational speed in a permanent magnet synchronous machine (PMSM) drive system. The simulated rig is based on two mechanically coupled EMRAX 228 equivalent axial-flux PMSMs, two Sevcon Gen4 Size 8 equivalent inverter stages, a bidirectional DC/DC converter, and two 265 V, 50 Ah lithium-ion battery packs.

The model was developed in MATLAB R2025b and Simulink. The post-processing scripts generate torque-speed efficiency maps, loss-decomposition plots, recovered-power maps and power-balance verification results.

## Repository contents

```text
.
├── Final.slx
├── simulink_init_params_CORRECTED.m
├── Test_one.m
├── test_fast.m
├── run_efficiency_sweep.m
├── Plot_efficiency_maps.m
├── postprocess_loss_explorer.m
├── postprocess_loss_bar_table.m
├── Best_eff_loci.m
├── Iron_Copper_crossover.m
├── Pie_chart_comparison.m
├── avg_ts.m
├── std_ts.m
├── sweep_results_fixed_boundaries_full.mat
├── README.md
├── .gitignore
├── figures/
└── docs/
```

## Main objectives
Model a PMSM-based back-to-back regenerative braking rig.
Quantify regenerative braking efficiency across the torque-speed envelope.
Separate copper, iron, inverter, shaft, DC/DC, battery and dump-resistor losses.
Identify the practical high-recovery operating region.
Verify model consistency through per-stage power-balance checks.
Benchmark predicted efficiencies against published literature and manufacturer data.

## Key results

The full sweep covered a 17 × 19 grid of operating points:

Speed range: 1000 to 5000 RPM
Regenerative torque range: −20 to −200 Nm
Total simulated operating points: 323

All 323 sweep points were retained. The −20 Nm and −30 Nm rows are shown in the maps but are not used for headline quantitative conclusions because low through-power makes percentage residuals sensitive to small absolute errors.

Quantity	Result
Peak whole-rig efficiency, eta_rig	81.8%
Peak eta_rig operating point	3000 RPM, −100 Nm
Maximum Battery B stored power	36.4 kW
Reliable-region peak conversion efficiency, eta_regen	approximately 89%
Reliable-region peak eta_regen location	3500–4000 RPM, around −40 Nm
Practical high-recovery torque region	approximately −80 to −130 Nm
Copper-to-iron loss crossover	approximately 2500 to 3000 RPM
Whole-rig power-balance residual	within approximately ±3.1% across about 95% of the envelope

## Main findings

The highest whole-rig efficiency and the maximum stored recovered power both occur at 3000 RPM and −100 Nm. This operating point lies close to the Battery B charge-acceptance boundary, where the rig is recovering nearly the maximum power that the sink battery can accept.

Copper losses dominate at low speed and high torque because of the high stator current required to produce braking torque. Iron losses increase with electrical frequency and become dominant at higher speeds. The iron-equals-copper crossover is therefore not a single fixed speed but varies with torque.

The light-load region gives high conversion efficiency, but the absolute recovered power is small. The practical sweet spot for energy recovery is therefore the moderate-torque region between approximately −80 and −130 Nm, where whole-rig efficiency remains high and recovered power is large.

## How to run
Open MATLAB R2025b.
Clone or download this repository.
Set the repository root folder as the MATLAB current folder.
Run the parameter initialisation script:
simulink_init_params_CORRECTED
To run the baseline verification case:
Test_one
To run a reduced smoke-test sweep:
test_fast
To run the full sweep:
run_efficiency_sweep
To regenerate the dissertation figures from the saved sweep results:
Plot_efficiency_maps

The full sweep contains 323 Simulink runs and may take a substantial amount of time depending on hardware. The saved result file is included so that the main plots can be regenerated without rerunning the complete sweep.

## Verification case

The baseline verification case is:

Speed: 3000 RPM
Regenerative torque command: −100 Nm
Simulation time: 3 s
Steady-state averaging window: 2–3 s

At this operating point:

eta_regen = 89.26%
eta_rig   = 81.84%
eta_b2b   = 83.10%

Whole-rig power-balance residual = −2.3 W

The per-stage power-balance check confirms that the explicit loss channels account for the difference between Battery A output power and Battery B stored power.

## Figures

The main dissertation figures generated from the sweep include:

Top-line efficiency maps: eta_regen, eta_rig, and eta_b2b
Section-by-section efficiency maps
Battery B stored power map
Dump-resistor power map
Whole-rig power-balance residual map
Stacked loss breakdown at the best eta_rig point per speed
Iron-equals-copper crossover plot
Best-efficiency operating loci

If the corresponding images are uploaded to the figures/ folder, they can be linked here using standard Markdown image links.

## Software requirements

Developed using:

MATLAB R2025b
Simulink R2025b

## Limitations

This project is a simulation and benchmarking study rather than a physically validated experimental test programme. The main limitations are:

no direct experimental validation against an instrumented rig;
representative inverter switching and conduction loss parameters;
representative Steinmetz iron-loss coefficients;
fixed DC/DC converter efficiency rather than a load-dependent efficiency map;
simplified battery model using fixed internal resistance;
simplified field-weakening representation;
steady-state operating points rather than complete road-vehicle braking events.

## Author

Barnaby Griffiths
BEng Mechanical Engineering with Automotive
University of Southampton
2026
