-- ============================================================================
-- top_ecg.vhd
-- Modulo 7: Top-level — integracion completa del sistema ECG
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Conecta: ecg_input → ecg_filter → qrs_detector → rr_calculator
--          → classifier → output_ctrl
-- Incluye divisor de reloj 50 MHz → 360 Hz (sample_tick)
-- Incluye ROM interna (ecg_rom) con datos MIT-BIH para modo demo
-- KEY1 suelto = demo (ROM), KEY1 pulsado = entrada externa (ADC)
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_ecg is
    port(
        -- entradas DE1-SoC
        CLOCK_50   : in  std_logic;                     -- reloj 50 MHz
        KEY        : in  std_logic_vector(3 downto 0);  -- botones (activo bajo)
        -- entrada ECG (desde HPS o fuente externa)
        ecg_data   : in  std_logic_vector(11 downto 0); -- muestra ECG 12 bits
        data_valid : in  std_logic;                     -- pulso dato valido
        -- salidas DE1-SoC
        HEX0       : out std_logic_vector(6 downto 0);  -- 7seg unidades BPM
        HEX1       : out std_logic_vector(6 downto 0);  -- 7seg decenas BPM
        HEX2       : out std_logic_vector(6 downto 0);  -- 7seg centenas BPM
        HEX3       : out std_logic_vector(6 downto 0);  -- 7seg codigo arritmia
        HEX4       : out std_logic_vector(6 downto 0);  -- apagado
        HEX5       : out std_logic_vector(6 downto 0);  -- apagado
        LEDR       : out std_logic_vector(9 downto 0)   -- LEDs rojos alerta
    );
end entity top_ecg;

architecture structural of top_ecg is

    -- senal de reset (KEY0 activo bajo, sistema usa activo alto)
    signal rst : std_logic;

    -- divisor de reloj: 50 MHz → 360 Hz
    -- 50_000_000 / 360 = 138_889 ciclos
    constant DIV_COUNT  : unsigned(17 downto 0) := to_unsigned(138889, 18);
    signal div_counter  : unsigned(17 downto 0) := (others => '0');
    signal sample_tick  : std_logic := '0';

    -- senales entre modulos
    -- ecg_input → ecg_filter
    signal inp_ecg_out   : std_logic_vector(11 downto 0);
    signal inp_out_valid : std_logic;

    -- ecg_filter → qrs_detector
    signal flt_ecg_out   : std_logic_vector(11 downto 0);
    signal flt_out_valid : std_logic;

    -- qrs_detector → rr_calculator
    signal qrs_r_peak    : std_logic;
    signal qrs_energy    : std_logic_vector(15 downto 0);

    -- rr_calculator → classifier
    signal rr_bpm_out    : std_logic_vector(7 downto 0);
    signal rr_bpm_valid  : std_logic;
    signal rr_interval   : std_logic_vector(15 downto 0);
    signal rr_mean_out   : std_logic_vector(15 downto 0);
    signal rr_max_out    : std_logic_vector(15 downto 0);
    signal rr_min_out    : std_logic_vector(15 downto 0);

    -- classifier → output_ctrl
    signal cls_code      : std_logic_vector(1 downto 0);
    signal cls_alert     : std_logic_vector(1 downto 0);
    signal cls_valid     : std_logic;

    -- ROM demo mode
    signal rom_ecg_out   : std_logic_vector(11 downto 0);
    signal rom_valid     : std_logic;

    -- mux: seleccion entre ROM (demo) y entrada externa
    signal mux_ecg_data  : std_logic_vector(11 downto 0);
    signal mux_valid     : std_logic;
    signal demo_mode     : std_logic;  -- '1' = ROM, '0' = externo

begin

    -- reset: KEY0 es activo bajo en DE1-SoC, invertimos
    rst <= not KEY(0);

    -- ================================================================
    -- divisor de reloj: genera pulso sample_tick a 360 Hz
    -- ================================================================
    process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            if rst = '1' then
                div_counter <= (others => '0');
                sample_tick <= '0';
            elsif div_counter >= DIV_COUNT - 1 then
                div_counter <= (others => '0');
                sample_tick <= '1';
            else
                div_counter <= div_counter + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    -- ================================================================
    -- Modo demo: KEY1 no presionado (='1') = ROM interna
    --            KEY1 presionado   (='0') = entrada externa (ADC)
    -- ================================================================
    demo_mode <= KEY(1);  -- activo bajo: '1' = no presionado = demo

    -- ================================================================
    -- ROM interna con datos MIT-BIH record 100 (modo demo)
    -- ================================================================
    u_rom: entity work.ecg_rom
        port map(
            clk     => CLOCK_50,
            rst     => rst,
            tick    => sample_tick,
            ecg_out => rom_ecg_out,
            valid   => rom_valid
        );

    -- ================================================================
    -- Mux: seleccion de fuente de datos ECG
    -- demo_mode='1' (KEY1 suelto) → ROM; demo_mode='0' (KEY1 pulsado) → externo
    -- ================================================================
    mux_ecg_data <= rom_ecg_out when demo_mode = '1' else ecg_data;
    mux_valid    <= rom_valid   when demo_mode = '1' else data_valid;

    -- ================================================================
    -- Modulo 1: ecg_input — sincronizacion de entrada
    -- ================================================================
    u_input: entity work.ecg_input
        port map(
            clk        => CLOCK_50,
            rst        => rst,
            ecg_data   => mux_ecg_data,
            data_valid => mux_valid,
            ecg_out    => inp_ecg_out,
            out_valid  => inp_out_valid
        );

    -- ================================================================
    -- Modulo 2: ecg_filter — filtro promedio movil 8 puntos
    -- ================================================================
    u_filter: entity work.ecg_filter
        port map(
            clk          => CLOCK_50,
            rst          => rst,
            ecg_in       => inp_ecg_out,
            in_valid     => inp_out_valid,
            ecg_filtered => flt_ecg_out,
            out_valid    => flt_out_valid
        );

    -- ================================================================
    -- Modulo 3: qrs_detector — deteccion pico R
    -- ================================================================
    u_qrs: entity work.qrs_detector
        port map(
            clk        => CLOCK_50,
            rst        => rst,
            ecg_in     => flt_ecg_out,
            in_valid   => flt_out_valid,
            r_peak     => qrs_r_peak,
            energy_out => qrs_energy
        );

    -- ================================================================
    -- Modulo 4: rr_calculator — intervalo RR y BPM
    -- ================================================================
    u_rr: entity work.rr_calculator
        port map(
            clk         => CLOCK_50,
            rst         => rst,
            sample_tick => sample_tick,
            r_peak      => qrs_r_peak,
            bpm_out     => rr_bpm_out,
            bpm_valid   => rr_bpm_valid,
            rr_interval => rr_interval,
            rr_mean     => rr_mean_out,
            rr_max      => rr_max_out,
            rr_min      => rr_min_out
        );

    -- ================================================================
    -- Modulo 5: classifier — clasificacion de arritmias
    -- ================================================================
    u_class: entity work.classifier
        port map(
            clk          => CLOCK_50,
            rst          => rst,
            bpm_in       => rr_bpm_out,
            bpm_valid    => rr_bpm_valid,
            arrhyth_code => cls_code,
            alert_level  => cls_alert,
            class_valid  => cls_valid
        );

    -- ================================================================
    -- Modulo 6: output_ctrl — displays y LEDs
    -- ================================================================
    u_output: entity work.output_ctrl
        port map(
            clk          => CLOCK_50,
            rst          => rst,
            bpm_in       => rr_bpm_out,
            arrhyth_code => cls_code,
            alert_level  => cls_alert,
            data_valid   => cls_valid,
            hex0         => HEX0,
            hex1         => HEX1,
            hex2         => HEX2,
            hex3         => HEX3,
            ledr         => LEDR
        );

    -- displays no usados apagados (activo bajo)
    HEX4 <= "1111111";
    HEX5 <= "1111111";

end architecture structural;