-- ============================================================================
-- tb_ecg_filter.vhd
-- Testbench para modulo ecg_filter (Modulo 2)
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Simulador: ModelSim-Altera Starter Edition
-- Verifica: promedio movil 8 puntos + out_valid despues de 8 muestras
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ecg_filter is
end entity tb_ecg_filter;

architecture sim of tb_ecg_filter is

    constant CLK_PERIOD : time := 20 ns;

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal ecg_in       : std_logic_vector(11 downto 0) := (others => '0');
    signal in_valid     : std_logic := '0';
    signal ecg_filtered : std_logic_vector(11 downto 0);
    signal out_valid    : std_logic;

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

    uut: entity work.ecg_filter
        port map(
            clk          => clk,
            rst          => rst,
            ecg_in       => ecg_in,
            in_valid     => in_valid,
            ecg_filtered => ecg_filtered,
            out_valid    => out_valid
        );

    clk <= not clk after CLK_PERIOD / 2;

    stim_proc: process
    begin
        -- 1) reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- 2) enviar 10 muestras con valor constante 400
        --    primeras 7: out_valid debe ser '0'
        --    muestra 8 en adelante: out_valid debe ser '1'
        --    con valor constante, salida filtrada = 400
        for i in 1 to 10 loop
            send_sample(ecg_in, in_valid, 400);
        end loop;

        wait for CLK_PERIOD * 3;

        -- 3) reset y enviar rampa: 100, 200, 300, 400, 500, 600, 700, 800
        --    promedio esperado = (100+200+300+400+500+600+700+800)/8 = 450
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        send_sample(ecg_in, in_valid, 100);
        send_sample(ecg_in, in_valid, 200);
        send_sample(ecg_in, in_valid, 300);
        send_sample(ecg_in, in_valid, 400);
        send_sample(ecg_in, in_valid, 500);
        send_sample(ecg_in, in_valid, 600);
        send_sample(ecg_in, in_valid, 700);
        send_sample(ecg_in, in_valid, 800);

        wait for CLK_PERIOD * 5;
        assert false report "Simulacion ecg_filter completada" severity note;
        wait;
    end process;

end architecture sim;