-- ============================================================================
-- tb_batch_ecg.vhd
-- Banco de pruebas para simulacion en lote de la base MIT-BIH completa
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Simulador: ModelSim-Altera Starter Edition
--
-- Divisor de muestreo reducido a 16 ciclos por muestra. El pipeline solo
-- avanza con in_valid / sample_tick, por lo que la secuencia de operaciones
-- es identica a DIV_COUNT = 138889. Equivalencia verificada contra
-- tb_top_ecg sobre el registro 100.
--
-- Entrada  (nombre fijo, el script de lote copia cada registro):
--   batch_input.txt   muestras ECG, 12 bits binario, una por linea
--
-- Salidas (el script de lote las renombra por registro):
--   batch_qrs.txt     indice de muestra de cada pico R detectado
--   batch_beats.txt   indice_muestra bpm rr_interval codigo alerta
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_batch_ecg is
end entity tb_batch_ecg;

architecture sim of tb_batch_ecg is

    constant CLK_PERIOD : time    := 20 ns;
    constant DIV_COUNT  : integer := 16;
    constant N_SAMPLES  : integer := 650000;

    signal CLOCK_50 : std_logic := '0';
    signal rst_tb   : std_logic := '1';

    signal ecg_data   : std_logic_vector(11 downto 0) := (others => '0');
    signal data_valid : std_logic := '0';

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

    -- latch de captura de pico R: sh_r_peak dura un ciclo de 50 MHz y no
    -- coincide necesariamente con sh_flt_valid
    signal r_peak_latched : std_logic := '0';

    -- indice de muestra procesada, compartido por los procesos de escritura
    signal sample_idx : integer := 0;

    signal sim_done : boolean := false;

begin

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

    u_input: entity work.ecg_input
        port map(
            clk        => CLOCK_50,
            rst        => rst_tb,
            ecg_data   => ecg_data,
            data_valid => data_valid,
            ecg_out    => sh_inp_ecg,
            out_valid  => sh_inp_valid
        );

    u_filter: entity work.ecg_filter
        port map(
            clk          => CLOCK_50,
            rst          => rst_tb,
            ecg_in       => sh_inp_ecg,
            in_valid     => sh_inp_valid,
            ecg_filtered => sh_flt_ecg,
            out_valid    => sh_flt_valid
        );

    u_qrs: entity work.qrs_detector
        port map(
            clk        => CLOCK_50,
            rst        => rst_tb,
            ecg_in     => sh_flt_ecg,
            in_valid   => sh_flt_valid,
            r_peak     => sh_r_peak,
            energy_out => sh_energy
        );

    u_rr: entity work.rr_calculator
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

    u_class: entity work.classifier
        port map(
            clk          => CLOCK_50,
            rst          => rst_tb,
            bpm_in       => sh_bpm,
            bpm_valid    => sh_bpm_valid,
            arrhyth_code => sh_code,
            alert_level  => sh_alert,
            class_valid  => sh_class_valid
        );

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

    idx_proc: process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            if rst_tb = '1' then
                sample_idx <= 0;
            elsif sh_flt_valid = '1' then
                sample_idx <= sample_idx + 1;
            end if;
        end if;
    end process;

    stim_proc: process
        file     vec_file     : text;
        variable vec_line     : line;
        variable bit_str      : string(1 to 12);
        variable sample_vec   : std_logic_vector(11 downto 0);
        variable open_status  : file_open_status;
        variable samples_sent : integer := 0;
    begin
        rst_tb     <= '1';
        ecg_data   <= (others => '0');
        data_valid <= '0';
        wait for CLK_PERIOD * 20;
        rst_tb     <= '0';
        wait for CLK_PERIOD * 10;

        file_open(open_status, vec_file, "batch_input.txt", read_mode);
        if open_status /= open_ok then
            report "ERROR: no se pudo abrir batch_input.txt" severity failure;
        end if;

        while (not endfile(vec_file)) and (samples_sent < N_SAMPLES) loop
            readline(vec_file, vec_line);
            read(vec_line, bit_str);

            for i in 1 to 12 loop
                if bit_str(i) = '1' then
                    sample_vec(12 - i) := '1';
                else
                    sample_vec(12 - i) := '0';
                end if;
            end loop;

            wait until rising_edge(CLOCK_50) and tb_sample_tick = '1';

            ecg_data   <= sample_vec;
            data_valid <= '1';
            wait until rising_edge(CLOCK_50);
            data_valid <= '0';

            samples_sent := samples_sent + 1;

            if (samples_sent mod 65000) = 0 then
                report "Progreso: " & integer'image(samples_sent) & " / "
                    & integer'image(N_SAMPLES) severity note;
            end if;
        end loop;

        file_close(vec_file);
        report "Muestras enviadas: " & integer'image(samples_sent) severity note;

        wait for 200 us;

        sim_done <= true;
        wait;
    end process;

    -- ------------------------------------------------------------------------
    -- batch_qrs.txt: un indice de muestra por cada pico R detectado
    -- ------------------------------------------------------------------------
    qrs_writer: process
        file     out_file    : text;
        variable out_line    : line;
        variable open_status : file_open_status;
    begin
        file_open(open_status, out_file, "batch_qrs.txt", write_mode);
        if open_status /= open_ok then
            report "ERROR: no se pudo crear batch_qrs.txt" severity failure;
        end if;

        while not sim_done loop
            wait until rising_edge(CLOCK_50);
            if sh_flt_valid = '1' then
                if r_peak_latched = '1' or sh_r_peak = '1' then
                    write(out_line, sample_idx);
                    writeline(out_file, out_line);
                end if;
            end if;
        end loop;

        file_close(out_file);
        wait;
    end process;

    -- ------------------------------------------------------------------------
    -- batch_beats.txt: una linea por latido con BPM, RR y clasificacion
    -- ------------------------------------------------------------------------
    beat_writer: process
        file     out_file    : text;
        variable out_line    : line;
        variable open_status : file_open_status;
        variable bpm_v       : integer := 0;
        variable rr_v        : integer := 0;
        variable pending     : boolean := false;
    begin
        file_open(open_status, out_file, "batch_beats.txt", write_mode);
        if open_status /= open_ok then
            report "ERROR: no se pudo crear batch_beats.txt" severity failure;
        end if;

        write(out_line, string'("# sample bpm rr code alert"));
        writeline(out_file, out_line);

        while not sim_done loop
            wait until rising_edge(CLOCK_50);

            if sh_bpm_valid = '1' then
                bpm_v   := to_integer(unsigned(sh_bpm));
                rr_v    := to_integer(unsigned(sh_rr_interval));
                pending := true;
            end if;

            -- classifier emite class_valid unos ciclos despues de bpm_valid
            if sh_class_valid = '1' and pending then
                write(out_line, sample_idx);
                write(out_line, string'(" "));
                write(out_line, bpm_v);
                write(out_line, string'(" "));
                write(out_line, rr_v);
                write(out_line, string'(" "));
                write(out_line, sh_code);
                write(out_line, string'(" "));
                write(out_line, sh_alert);
                writeline(out_file, out_line);
                pending := false;
            end if;
        end loop;

        file_close(out_file);
        wait;
    end process;

end architecture sim;
