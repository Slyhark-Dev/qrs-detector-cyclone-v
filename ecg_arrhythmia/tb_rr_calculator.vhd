-- ============================================================================
-- tb_rr_calculator.vhd
-- Testbench para modulo rr_calculator (Modulo 4)
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Simulador: ModelSim-Altera Starter Edition
-- Verifica: conteo RR, calculo BPM, buffer 4 latidos, estadisticas
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rr_calculator is
end entity tb_rr_calculator;

architecture sim of tb_rr_calculator is

    constant CLK_PERIOD : time := 20 ns;

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal r_peak      : std_logic := '0';
    signal bpm_out     : std_logic_vector(7 downto 0);
    signal bpm_valid   : std_logic;
    signal rr_interval : std_logic_vector(15 downto 0);
    signal rr_mean     : std_logic_vector(15 downto 0);
    signal rr_max      : std_logic_vector(15 downto 0);
    signal rr_min      : std_logic_vector(15 downto 0);

    -- procedimiento: generar N pulsos de sample_tick (simula N muestras a 360 Hz)
    procedure wait_samples(
        signal   tick  : out std_logic;
        constant count : in  integer
    ) is
    begin
        for i in 1 to count loop
            tick <= '1';
            wait for CLK_PERIOD;
            tick <= '0';
            wait for CLK_PERIOD;
        end loop;
    end procedure;

    -- procedimiento: generar pulso de pico R
    procedure send_peak(
        signal peak : out std_logic
    ) is
    begin
        peak <= '1';
        wait for CLK_PERIOD;
        peak <= '0';
        wait for CLK_PERIOD;
    end procedure;

begin

    uut: entity work.rr_calculator
        port map(
            clk         => clk,
            rst         => rst,
            sample_tick => sample_tick,
            r_peak      => r_peak,
            bpm_out     => bpm_out,
            bpm_valid   => bpm_valid,
            rr_interval => rr_interval,
            rr_mean     => rr_mean,
            rr_max      => rr_max,
            rr_min      => rr_min
        );

    clk <= not clk after CLK_PERIOD / 2;

    stim_proc: process
    begin
        -- 1) reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- 2) primer pico R (referencia, no genera BPM)
        send_peak(r_peak);

        -- 3) 300 muestras → segundo pico R
        --    BPM esperado = 21600 / 300 = 72 BPM (bradicardia)
        wait_samples(sample_tick, 300);
        send_peak(r_peak);
        wait for CLK_PERIOD * 5;

        -- 4) 200 muestras → tercer pico R
        --    BPM esperado = 21600 / 200 = 108 BPM (taquicardia)
        wait_samples(sample_tick, 200);
        send_peak(r_peak);
        wait for CLK_PERIOD * 5;

        -- 5) 250 muestras → cuarto pico R
        --    BPM esperado = 21600 / 250 = 86 BPM (normal)
        wait_samples(sample_tick, 250);
        send_peak(r_peak);
        wait for CLK_PERIOD * 5;

        -- 6) 220 muestras → quinto pico R
        --    BPM esperado = 21600 / 220 = 98 BPM (normal)
        --    buffer lleno → estadisticas activas
        wait_samples(sample_tick, 220);
        send_peak(r_peak);
        wait for CLK_PERIOD * 10;

        assert false report "Simulacion rr_calculator completada" severity note;
        wait;
    end process;

end architecture sim;