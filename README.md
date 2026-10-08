# Causal QRS detector and heart-rate classifier on a Cyclone V FPGA

Source code accompanying the manuscript "VHDL Implementation of a Causal QRS
Detector and Heart-Rate Classifier on a Cyclone V FPGA: Inter-Patient
Validation on MIT-BIH", submitted to IEEE Latin America Transactions.

Submission ID: 11130, IEEE Latin America Transactions.

Authors: Pedro Martin Quiroz Tapia (corresponding author, ORCID 0000-0003-3846-1606), Marcos Pedro Carpio Meza (ORCID 0009-0006-2928-1653) and Jesus Antonio Calderon Sinti (ORCID 0009-0009-2533-8183).

Escuela de Ingeniería Mecatrónica, Universidad Tecnológica del Perú (UTP),
Lima, Perú.

The system detects QRS complexes with a fixed-point adaptation of the
Pan-Tompkins algorithm and classifies each beat as bradycardia, normal rhythm
or tachycardia from the instantaneous heart rate. It is written in native
VHDL, targets the Intel Cyclone V 5CSEMA5F31C6 of the DE1-SoC board, and is
validated by RTL simulation against the complete MIT-BIH Arrhythmia Database.

## Contents

    ecg_arrhythmia/     VHDL sources, timing constraints, pin assignment
      top_ecg.vhd           root entity
      ecg_input.vhd         input register and valid pulse
      ecg_filter.vhd        8-sample moving average, the synthesised path
      ecg_filter_bp.vhd     rescaled Pan-Tompkins bandpass cascade (ablation)
      qrs_detector.vhd      derivative, squaring, integration, thresholds
      rr_calculator.vhd     RR interval and heart rate
      classifier.vhd        three-state rate classifier
      output_ctrl.vhd       seven-segment displays and LEDs
      ecg_rom.vhd           optional demonstration memory
      tb_*.vhd              testbenches, one per module plus the batch bench
      ecg_timing.sdc        timing constraints, including the multicycle path
      ecg_input.qsf         pin assignment and project settings
      ecg_arrhythmia.qpf    Quartus project file
      run_batch.do          ModelSim script for the 48-record batch

    ecg_matlab/         MATLAB scripts for data preparation, validation,
                        ablation studies and figures

## Requirements

    Quartus Prime 19.1 Lite Edition
    ModelSim-Altera Starter Edition 10.5b
    MATLAB R2025b
    DE1-SoC board with Intel Cyclone V 5CSEMA5F31C6 (physical deployment only)

## Data

The MIT-BIH Arrhythmia Database is not included. It is distributed by
PhysioNet under its own terms. Run download_mitbih_records.m to obtain the
48 records before anything else. The script is idempotent and skips records
already present.

## Reproducing the results

Run the steps in this order from the ecg_matlab directory, except step 3,
which runs from the Quartus project directory.

1. download_mitbih_records.m
   Downloads the 48 records from PhysioNet.

2. generate_vhdl_vectors_batch.m
   Exports channel 1 of every record as ModelSim-readable test vectors under
   the fixed calibration constant, together with the cardiologist annotations
   used as reference.

3. vsim -c -do run_batch.do
   Simulates the 48 records on tb_batch_ecg and writes the detected peaks and
   the classified beats of each record. Takes about 40 minutes.

4. compare_vhdl_batch.m
   Matches detections against annotations with the 150 ms tolerance of
   ANSI/AAMI EC57 and produces the per-record counts.

5. report_table3.m
   Aggregates those counts into the four evaluation protocols: DS1, DS2,
   DS1 plus DS2, and the full database.

6. validate_rate_classifier.m
   Confusion matrix and per-class metrics of the rate classifier.

7. bland_altman_bpm.m
   Agreement between the heart rate computed in hardware and the one derived
   from the annotated RR intervals.

## Ablation studies and figures

These do not need ModelSim. They run on the vectors written in step 2 and
reproduce the figures and the numbers reported in the discussion.

    emulate_rtl.m
      Reproduces the RTL sample by sample in MATLAB and checks it against the
      ModelSim output of step 3. Every study below rests on that equivalence.

    sweep_floor_fixed_cal.m  ->  fig7_floor_sweep.m
      Threshold-floor sweep on DS1 under fixed calibration, and the figure
      that shows the selected value at an interior optimum.

    ablation_bandpass_v2.m   ->  fig6_bandpass_ablation.m
      Substitution of the bandpass cascade by the moving average, evaluated
      under three floor protocols with the group delay of each path
      compensated by its design-time constant. Writes
      bandpass_ablation_v2.mat and draws the per-record figure.

    ma_per_record.m
      The moving average swept over the same relative grid under a per-record
      floor, so both filters are compared under equal treatment instead of an
      oracle against a non-oracle.

    window_ds1_ds2.m
      Integration window widths of 8, 16, 27 and 54 samples, on DS1 and on
      DS2, with the threshold floor scaled in proportion to the width.

    window_delay_comp.m
      The same width sweep run twice, with and without compensating the
      (N-1)/2 delay of the integrator, which separates the loss caused by the
      T wave from the loss caused by the shift in alignment.

The remaining ablation_*.m and sweep_*.m scripts cover the earlier parameter
studies: secondary threshold, decay rate, vulnerable window and global gain.

For the hardware cost of the filter substitution, compile the project twice
with top_ecg.vhd instantiating ecg_filter.vhd and then ecg_filter_bp.vhd, and
read the ALM and register counts of the filter entity in the Quartus fitter
report. Both compilations include the optional memory module.

For physical deployment, generate_ecg_rom.m rebuilds ecg_rom.vhd with ten
seconds of record 100 embedded as internal memory, which lets the board run
without an external analog front end.

## Citation

Cite the article once published. Until then, cite this deposit by its DOI.

## License

MIT. See the LICENSE file.
