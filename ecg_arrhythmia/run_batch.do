# ============================================================================
# run_batch.do
# Simulacion en lote de la base MIT-BIH completa sobre tb_batch_ecg
# Proyecto: ECG Arritmias FPGA DE1-SoC
#
# Uso desde el directorio del proyecto Quartus:
#   vsim -c -do run_batch.do
#
# Para cada registro copia batch/vectors_<rec>.txt a batch_input.txt,
# ejecuta la simulacion y guarda las salidas como
# batch/vhdl_qrs_<rec>.txt y batch/vhdl_beats_<rec>.txt
# ============================================================================

set records {100 101 102 103 104 105 106 107 108 109 \
             111 112 113 114 115 116 117 118 119 \
             121 122 123 124 \
             200 201 202 203 205 207 208 209 210 \
             212 213 214 215 217 219 \
             220 221 222 223 228 \
             230 231 232 233 234}

set batch_dir "batch"

vlib work
vmap work work

vcom -quiet ecg_input.vhd
vcom -quiet ecg_filter.vhd
vcom -quiet qrs_detector.vhd
vcom -quiet rr_calculator.vhd
vcom -quiet classifier.vhd
vcom -quiet tb_batch_ecg.vhd

set t_global [clock seconds]
set n 0

foreach rec $records {
    incr n
    set t0 [clock seconds]

    set src "$batch_dir/vectors_$rec.txt"
    if {![file exists $src]} {
        echo "AVISO: falta $src, registro $rec omitido"
        continue
    }
    file copy -force $src batch_input.txt

    vsim -quiet -c work.tb_batch_ecg
    run -all
    quit -sim

    file rename -force batch_qrs.txt   "$batch_dir/vhdl_qrs_$rec.txt"
    file rename -force batch_beats.txt "$batch_dir/vhdl_beats_$rec.txt"

    set dt [expr {[clock seconds] - $t0}]
    echo "[format %2d $n]/48  registro $rec  ${dt}s"
}

file delete -force batch_input.txt

set total [expr {[clock seconds] - $t_global}]
echo "Lote completo: $n registros en ${total}s"
quit -f
