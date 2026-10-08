-- ============================================================================
-- tb_qrs_detector.vhd
-- Testbench para modulo qrs_detector (Modulo 3)
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Simulador: ModelSim-Altera Starter Edition
-- Verifica: derivada, cuadrado, integracion, umbral adaptivo, pico R
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_qrs_detector is
end entity tb_qrs_detector;

architecture sim of tb_qrs_detector is

    constant CLK_PERIOD : time := 20 ns;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '0';
    signal ecg_in     : std_logic_vector(11 downto 0) := (others => '0');
    signal in_valid   : std_logic := '0';
    signal r_peak     : std_logic;
    signal energy_out : std_logic_vector(15 downto 0);

    -- procedimiento para enviar una muestra
    procedure send_sample(
        signal   data  : out std_logic_vector(11 downto 0);
        signal   valid : out std_logic;
        constant value : in  integer
    ) is
    begin
        data  <= std_logic_vector(to_unsigned(value, 12));
        valid <= '1';
        wait for CLK_PERIOD;
        valid <= '0';
        wait for CLK_PERIOD;
    end procedure;

begin

    uut: entity work.qrs_detector
        port map(
            clk        => clk,
            rst        => rst,
            ecg_in     => ecg_in,
            in_valid   => in_valid,
            r_peak     => r_peak,
            energy_out => energy_out
        );

    clk <= not clk after CLK_PERIOD / 2;

    stim_proc: process
    begin
        -- 1) reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- 2) linea base: 20 muestras con valor bajo (ruido de fondo)
        --    no debe generar r_peak
        for i in 1 to 20 loop
            send_sample(ecg_in, in_valid, 500);
        end loop;

        -- 3) simular complejo QRS: subida rapida
        --    pendiente fuerte = derivada grande = energia alta
        send_sample(ecg_in, in_valid, 600);
        send_sample(ecg_in, in_valid, 900);
        send_sample(ecg_in, in_valid, 1500);
        send_sample(ecg_in, in_valid, 2800);
        send_sample(ecg_in, in_valid, 3500);  -- pico R
        send_sample(ecg_in, in_valid, 2600);
        send_sample(ecg_in, in_valid, 1400);
        send_sample(ecg_in, in_valid, 800);
        send_sample(ecg_in, in_valid, 550);

        -- 4) volver a linea base
        for i in 1 to 30 loop
            send_sample(ecg_in, in_valid, 500);
        end loop;

        -- 5) segundo pico R (verificar periodo refractario)
        send_sample(ecg_in, in_valid, 650);
        send_sample(ecg_in, in_valid, 1000);
        send_sample(ecg_in, in_valid, 1800);
        send_sample(ecg_in, in_valid, 3000);
        send_sample(ecg_in, in_valid, 3600);  -- segundo pico R
        send_sample(ecg_in, in_valid, 2500);
        send_sample(ecg_in, in_valid, 1200);
        send_sample(ecg_in, in_valid, 700);

        -- 6) esperar y terminar
        for i in 1 to 20 loop
            send_sample(ecg_in, in_valid, 500);
        end loop;

        wait for CLK_PERIOD * 10;
        assert false report "Simulacion qrs_detector completada" severity note;
        wait;
    end process;

end architecture sim;