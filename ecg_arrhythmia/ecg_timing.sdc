# ============================================================================
# ecg_timing.sdc
# Restricciones de temporizacion (Synopsys Design Constraints)
# Proyecto: ECG Arritmias FPGA DE1-SoC
# Reloj principal: CLOCK_50 = 50 MHz (periodo 20 ns)
# ============================================================================

# Reloj de entrada de 50 MHz del DE1-SoC
create_clock -name {CLOCK_50} -period 20.000 [get_ports {CLOCK_50}]

# Calcular incertidumbres de reloj (jitter, etc.) derivadas del reloj base
derive_clock_uncertainty

# Entradas y salidas son asincronas respecto al reloj del sistema:
# - ecg_data, data_valid: provienen de la fuente de datos (HPS/MIT-BIH), no
#   estan sincronizadas a CLOCK_50 a nivel de pin.
# - KEY: pulsadores mecanicos (asincronos).
# - HEX0-5, LEDR: salidas a displays/LEDs, sin requisito de timing critico.
# Se declaran como falsos caminos de E/S para no exigir timing a los pines
# externos, que no tienen relacion de fase definida con el reloj interno.
set_false_path -from [get_ports {ecg_data[*]}] -to [all_registers]
set_false_path -from [get_ports {data_valid}]  -to [all_registers]
set_false_path -from [get_ports {KEY[*]}]      -to [all_registers]
set_false_path -from [all_registers] -to [get_ports {HEX0[*]}]
set_false_path -from [all_registers] -to [get_ports {HEX1[*]}]
set_false_path -from [all_registers] -to [get_ports {HEX2[*]}]
set_false_path -from [all_registers] -to [get_ports {HEX3[*]}]
set_false_path -from [all_registers] -to [get_ports {HEX4[*]}]
set_false_path -from [all_registers] -to [get_ports {HEX5[*]}]
set_false_path -from [all_registers] -to [get_ports {LEDR[*]}]

# ----------------------------------------------------------------------------
# Multicycle path para el calculo de BPM (division 21600 / RR)
# ----------------------------------------------------------------------------
# El registro bpm_reg de rr_calculator solo se actualiza cuando llega un pico R
# (r_peak='1'), es decir UNA vez por latido (~800 ms a 75 BPM), no cada ciclo
# de 50 MHz. La division 21600/sample_cnt es el camino combinacional mas largo
# del diseno (~69 ns), pero dispone de cientos de miles de ciclos de reloj
# antes del siguiente latido. Se declara multicycle para reflejar esta realidad
# y permitir que Quartus cierre timing correctamente sin forzar el camino a 20 ns.
set_multicycle_path -setup -from [get_keepers {*rr_calculator*sample_cnt*}] -to [get_keepers {*rr_calculator*bpm_reg*}] 8
set_multicycle_path -hold  -from [get_keepers {*rr_calculator*sample_cnt*}] -to [get_keepers {*rr_calculator*bpm_reg*}] 7
