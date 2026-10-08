-- ============================================================================
-- tb_top_ecg.vhd
-- Testbench Etapa 3 — Simulacion virtual con datos MIT-BIH reales
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Simulador: ModelSim-Altera Starter Edition
--
-- Estrategia: B1 — replica divisor 50 MHz -> 360 Hz internamente,
--             top_ecg.vhd NO se modifica.
--
-- VERSION 2 (Etapa 3 - FIX): correcciones aplicadas
--   Fix Bug 1: captura de r_peak con latch (qrs_writer)
--   Fix Bug 3: cambio de "now/1 ns" a "now/1 us" para evitar overflow
--              despues de 2.147 segundos simulados
--
-- Entradas:
--   ecg_test_vectors.txt   (10,800 muestras, 12 bits binario, 30 seg @ 360 Hz)
--
-- Salidas:
--   vhdl_qrs_output.txt    (r_peak por muestra: '0' o '1')
--   vhdl_bpm_output.txt    (BPM cada vez que bpm_valid='1', tiempo en us)
--   vhdl_class_output.txt  (codigo + alerta cuando class_valid='1', tiempo us)
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_top_ecg is
end entity tb_top_ecg;

architecture sim of tb_top_ecg is

    constant CLK_PERIOD : time     := 20 ns;
    constant DIV_COUNT  : integer  := 138889;
    constant N_SAMPLES  : integer  := 10800;

    signal CLOCK_50   : std_logic := '0';
    signal KEY        : std_logic_vector(3 downto 0) := "1111";
    signal ecg_data   : std_logic_vector(11 downto 0) := (others => '0');
    signal data_valid : std_logic := '0';
    signal HEX0       : std_logic_vector(6 downto 0);
    signal HEX1       : std_logic_vector(6 downto 0);
    signal HEX2       : std_logic_vector(6 downto 0);
    signal HEX3       : std_logic_vector(6 downto 0);
    signal HEX4       : std_logic_vector(6 downto 0);
    signal HEX5       : std_logic_vector(6 downto 0);
    signal LEDR       : std_logic_vector(9 downto 0);

    signal tb_div_counter : integer range 0 to DIV_COUNT := 0;
    signal tb_sample_tick : std_logic := '0';

    signal sh_inp_ecg     : std_logic_vector(11 downto 0);
    signal sh_inp_valid   : std_logic;
    signal sh_flt_ecg     : std_logic_vector(11 downto 0);
    signal sh_flt_valid   : std_logic;
    signal sh_r_peak      : std_logic;
    signal sh_energy      : std_logic_vector(15 downto 0);
    signal sh_bpm         : std_logic_vector(7 downto 0);
    signal sh_bpm_valid   : std_logic;
    signal sh_rr_interval : std_logic_vector(15 downto 0);
    signal sh_rr_mean     : std_logic_vector(15 downto 0);
    signal sh_rr_max      : std_logic_vector(15 downto 0);
    signal sh_rr_min      : std_logic_vector(15 downto 0);
    signal sh_code        : std_logic_vector(1 downto 0);
    signal sh_alert       : std_logic_vector(1 downto 0);
    signal sh_class_valid : std_logic;

    signal rst_tb : std_logic;

    -- Fix Bug 1: latch de captura de pico R
    signal r_peak_latched : std_logic := '0';

    signal sim_done : boolean := false;

begin

    uut: entity work.top_ecg
        port map(
            CLOCK_50   => CLOCK_50,
            KEY        => KEY,
            ecg_data   => ecg_data,
            data_valid => data_valid,
            HEX0       => HEX0,
            HEX1       => HEX1,
            HEX2       => HEX2,
            HEX3       => HEX3,
            HEX4       => HEX4,
            HEX5       => HEX5,
            LEDR       => LEDR
        );

    clk_proc: process
    begin
        while not sim_done loop
            CLOCK_50 <= '0';
            wait for CLK_PERIOD / 2;
            CLOCK_50 <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    rst_tb <= not KEY(0);

    div_proc: process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            if rst_tb = '1' then
                tb_div_counter <= 0;
                tb_sample_tick <= '0';
            elsif tb_div_counter >= DIV_COUNT - 1 then
                tb_div_counter <= 0;
                tb_sample_tick <= '1';
            else
                tb_div_counter <= tb_div_counter + 1;
                tb_sample_tick <= '0';
            end if;
        end if;
    end process;

    sh_input: entity work.ecg_input
        port map(
            clk        => CLOCK_50,
            rst        => rst_tb,
            ecg_data   => ecg_data,
            data_valid => data_valid,
            ecg_out    => sh_inp_ecg,
            out_valid  => sh_inp_valid
        );

    sh_filter: entity work.ecg_filter
        port map(
            clk          => CLOCK_50,
            rst          => rst_tb,
            ecg_in       => sh_inp_ecg,
            in_valid     => sh_inp_valid,
            ecg_filtered => sh_flt_ecg,
            out_valid    => sh_flt_valid
        );

    sh_qrs: entity work.qrs_detector
        port map(
            clk        => CLOCK_50,
            rst        => rst_tb,
            ecg_in     => sh_flt_ecg,
            in_valid   => sh_flt_valid,
            r_peak     => sh_r_peak,
            energy_out => sh_energy
        );

    sh_rr: entity work.rr_calculator
        port map(
            clk         => CLOCK_50,
            rst         => rst_tb,
            sample_tick => tb_sample_tick,
            r_peak      => sh_r_peak,
            bpm_out     => sh_bpm,
            bpm_valid   => sh_bpm_valid,
            rr_interval => sh_rr_interval,
            rr_mean     => sh_rr_mean,
            rr_max      => sh_rr_max,
            rr_min      => sh_rr_min
        );

    sh_class: entity work.classifier
        port map(
            clk          => CLOCK_50,
            rst          => rst_tb,
            bpm_in       => sh_bpm,
            bpm_valid    => sh_bpm_valid,
            arrhyth_code => sh_code,
            alert_level  => sh_alert,
            class_valid  => sh_class_valid
        );

    stim_proc: process
        file     vec_file     : text;
        variable vec_line     : line;
        variable bit_str      : string(1 to 12);
        variable sample_vec   : std_logic_vector(11 downto 0);
        variable open_status  : file_open_status;
        variable samples_sent : integer := 0;
    begin
        KEY(0)     <= '0';
        ecg_data   <= (others => '0');
        data_valid <= '0';
        wait for CLK_PERIOD * 20;
        KEY(0)     <= '1';
        wait for CLK_PERIOD * 10;

        file_open(open_status, vec_file, "ecg_test_vectors.txt", read_mode);
        if open_status /= open_ok then
            report "ERROR: no se pudo abrir ecg_test_vectors.txt" severity failure;
        end if;
        report "Archivo ecg_test_vectors.txt abierto correctamente" severity note;

        while (not endfile(vec_file)) and (samples_sent < N_SAMPLES) loop
            readline(vec_file, vec_line);
            read(vec_line, bit_str);

            for i in 1 to 12 loop
                if bit_str(i) = '1' then
                    sample_vec(12 - i) := '1';
                elsif bit_str(i) = '0' then
                    sample_vec(12 - i) := '0';
                else
                    sample_vec(12 - i) := '0';
                    report "Caracter no binario en linea " & integer'image(samples_sent + 1)
                        severity warning;
                end if;
            end loop;

            wait until rising_edge(CLOCK_50) and tb_sample_tick = '1';

            ecg_data   <= sample_vec;
            data_valid <= '1';
            wait until rising_edge(CLOCK_50);
            data_valid <= '0';

            samples_sent := samples_sent + 1;

            if (samples_sent mod 1080) = 0 then
                report "Progreso: " & integer'image(samples_sent) & " / "
                    & integer'image(N_SAMPLES) & " muestras enviadas"
                    severity note;
            end if;
        end loop;

        file_close(vec_file);
        report "Lectura completa: " & integer'image(samples_sent)
            & " muestras enviadas" severity note;

        wait for 50 ms;

        sim_done <= true;
        report "Simulacion Etapa 3 completada correctamente" severity note;
        wait;
    end process;

    -- ========================================================================
    -- LATCH DE PICO R (Fix Bug 1)
    -- Setea r_peak_latched cuando sh_r_peak='1' en CUALQUIER ciclo.
    -- Se limpia despues de que qrs_writer lo registre (en flt_valid).
    -- ========================================================================
    r_peak_latch_proc: process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            if rst_tb = '1' then
                r_peak_latched <= '0';
            elsif sh_r_peak = '1' then
                r_peak_latched <= '1';
            elsif sh_flt_valid = '1' then
                r_peak_latched <= '0';
            end if;
        end if;
    end process;

    -- ------------------------------------------------------------------------
    -- Salida 1: vhdl_qrs_output.txt
    -- Fix Bug 1: reporta '1' si r_peak_latched o sh_r_peak estan activos
    -- ------------------------------------------------------------------------
    qrs_writer: process
        file     out_file    : text;
        variable out_line    : line;
        variable sample_idx  : integer := 0;
        variable open_status : file_open_status;
    begin
        file_open(open_status, out_file, "vhdl_qrs_output.txt", write_mode);
        if open_status /= open_ok then
            report "ERROR: no se pudo crear vhdl_qrs_output.txt" severity failure;
        end if;

        write(out_line, string'("# indice_muestra r_peak"));
        writeline(out_file, out_line);

        while not sim_done loop
            wait until rising_edge(CLOCK_50);
            if sh_flt_valid = '1' then
                write(out_line, sample_idx);
                write(out_line, string'(" "));
                if r_peak_latched = '1' or sh_r_peak = '1' then
                    write(out_line, string'("1"));
                else
                    write(out_line, string'("0"));
                end if;
                writeline(out_file, out_line);
                sample_idx := sample_idx + 1;
            end if;
        end loop;

        file_close(out_file);
        wait;
    end process;

    -- ------------------------------------------------------------------------
    -- Salida 2: vhdl_bpm_output.txt
    -- Fix Bug 3: tiempo en microsegundos (now/1 us) para evitar overflow
    -- ------------------------------------------------------------------------
    bpm_writer: process
        file     out_file    : text;
        variable out_line    : line;
        variable open_status : file_open_status;
    begin
        file_open(open_status, out_file, "vhdl_bpm_output.txt", write_mode);
        if open_status /= open_ok then
            report "ERROR: no se pudo crear vhdl_bpm_output.txt" severity failure;
        end if;

        write(out_line, string'("# tiempo_us bpm rr_interval rr_mean rr_max rr_min"));
        writeline(out_file, out_line);

        while not sim_done loop
            wait until rising_edge(CLOCK_50);
            if sh_bpm_valid = '1' then
                write(out_line, now / 1 us);
                write(out_line, string'(" "));
                write(out_line, to_integer(unsigned(sh_bpm)));
                write(out_line, string'(" "));
                write(out_line, to_integer(unsigned(sh_rr_interval)));
                write(out_line, string'(" "));
                write(out_line, to_integer(unsigned(sh_rr_mean)));
                write(out_line, string'(" "));
                write(out_line, to_integer(unsigned(sh_rr_max)));
                write(out_line, string'(" "));
                write(out_line, to_integer(unsigned(sh_rr_min)));
                writeline(out_file, out_line);
            end if;
        end loop;

        file_close(out_file);
        wait;
    end process;

    -- ------------------------------------------------------------------------
    -- Salida 3: vhdl_class_output.txt
    -- Fix Bug 3: tiempo en microsegundos (now/1 us)
    -- ------------------------------------------------------------------------
    class_writer: process
        file     out_file    : text;
        variable out_line    : line;
        variable open_status : file_open_status;
    begin
        file_open(open_status, out_file, "vhdl_class_output.txt", write_mode);
        if open_status /= open_ok then
            report "ERROR: no se pudo crear vhdl_class_output.txt" severity failure;
        end if;

        write(out_line, string'("# tiempo_us code alert"));
        writeline(out_file, out_line);

        while not sim_done loop
            wait until rising_edge(CLOCK_50);
            if sh_class_valid = '1' then
                write(out_line, now / 1 us);
                write(out_line, string'(" "));
                write(out_line, sh_code);
                write(out_line, string'(" "));
                write(out_line, sh_alert);
                writeline(out_file, out_line);
            end if;
        end loop;

        file_close(out_file);
        wait;
    end process;

end architecture sim;
