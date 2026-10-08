-- ============================================================================
-- tb_output_ctrl.vhd
-- Testbench para modulo output_ctrl (Modulo 6)
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Simulador: ModelSim-Altera Starter Edition
-- Verifica: displays 7seg BPM, codigo arritmia, LEDs alerta
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_output_ctrl is
end entity tb_output_ctrl;

architecture sim of tb_output_ctrl is

    constant CLK_PERIOD : time := 20 ns;

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal bpm_in       : std_logic_vector(7 downto 0)  := (others => '0');
    signal arrhyth_code : std_logic_vector(1 downto 0)  := "00";
    signal alert_level  : std_logic_vector(1 downto 0)  := "00";
    signal data_valid   : std_logic := '0';
    signal hex0         : std_logic_vector(6 downto 0);
    signal hex1         : std_logic_vector(6 downto 0);
    signal hex2         : std_logic_vector(6 downto 0);
    signal hex3         : std_logic_vector(6 downto 0);
    signal ledr         : std_logic_vector(9 downto 0);

    -- procedimiento para enviar datos al modulo
    procedure send_data(
        signal   bpm   : out std_logic_vector(7 downto 0);
        signal   code  : out std_logic_vector(1 downto 0);
        signal   alert : out std_logic_vector(1 downto 0);
        signal   valid : out std_logic;
        constant b_val : in  integer;
        constant c_val : in  std_logic_vector(1 downto 0);
        constant a_val : in  std_logic_vector(1 downto 0)
    ) is
    begin
        bpm   <= std_logic_vector(to_unsigned(b_val, 8));
        code  <= c_val;
        alert <= a_val;
        valid <= '1';
        wait for CLK_PERIOD;
        valid <= '0';
        wait for CLK_PERIOD * 10;
    end procedure;

begin

    uut: entity work.output_ctrl
        port map(
            clk          => clk,
            rst          => rst,
            bpm_in       => bpm_in,
            arrhyth_code => arrhyth_code,
            alert_level  => alert_level,
            data_valid   => data_valid,
            hex0         => hex0,
            hex1         => hex1,
            hex2         => hex2,
            hex3         => hex3,
            ledr         => ledr
        );

    clk <= not clk after CLK_PERIOD / 2;

    stim_proc: process
    begin
        -- 1) reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- 2) Normal: 75 BPM → HEX2=0, HEX1=7, HEX0=5, HEX3=n, LEDs=off
        send_data(bpm_in, arrhyth_code, alert_level, data_valid,
                  75, "00", "00");

        -- 3) Bradicardia: 48 BPM → HEX2=0, HEX1=4, HEX0=8, HEX3=b, LEDs=5
        send_data(bpm_in, arrhyth_code, alert_level, data_valid,
                  48, "01", "10");

        -- 4) Taquicardia: 130 BPM → HEX2=1, HEX1=3, HEX0=0, HEX3=t, LEDs=5
        send_data(bpm_in, arrhyth_code, alert_level, data_valid,
                  130, "10", "10");

        -- 5) Fibrilacion: 85 BPM → HEX2=0, HEX1=8, HEX0=5, HEX3=F, LEDs=10
        send_data(bpm_in, arrhyth_code, alert_level, data_valid,
                  85, "11", "11");

        -- 6) Normal otra vez: 72 BPM → verificar retorno
        send_data(bpm_in, arrhyth_code, alert_level, data_valid,
                  72, "00", "00");

        wait for CLK_PERIOD * 10;
        assert false report "Simulacion output_ctrl completada" severity note;
        wait;
    end process;

end architecture sim;