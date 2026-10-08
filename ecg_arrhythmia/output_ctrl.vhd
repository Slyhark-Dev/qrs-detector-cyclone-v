-- ============================================================================
-- output_ctrl.vhd
-- Modulo 6: Control de salidas DE1-SoC — displays 7seg + LEDs
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- HEX0-HEX2: BPM en decimal (unidades, decenas, centenas)
-- HEX3: codigo arritmia (n/b/t/F)
-- LEDR: patron de alerta visual
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity output_ctrl is
    port(
        clk          : in  std_logic;                     -- reloj 50 MHz
        rst          : in  std_logic;                     -- reset activo alto
        bpm_in       : in  std_logic_vector(7 downto 0);  -- BPM (0-255)
        arrhyth_code : in  std_logic_vector(1 downto 0);  -- 00=norm,01=bradi,10=taqui,11=fib
        alert_level  : in  std_logic_vector(1 downto 0);  -- nivel de alerta
        data_valid   : in  std_logic;                     -- pulso dato nuevo
        hex0         : out std_logic_vector(6 downto 0);  -- 7seg unidades BPM
        hex1         : out std_logic_vector(6 downto 0);  -- 7seg decenas BPM
        hex2         : out std_logic_vector(6 downto 0);  -- 7seg centenas BPM
        hex3         : out std_logic_vector(6 downto 0);  -- 7seg codigo arritmia
        ledr         : out std_logic_vector(9 downto 0)   -- LEDs rojos alerta
    );
end entity output_ctrl;

architecture rtl of output_ctrl is

    -- conversion BCD
    signal bpm_val   : unsigned(7 downto 0)  := (others => '0');
    signal centenas  : unsigned(3 downto 0)  := (others => '0');
    signal decenas   : unsigned(3 downto 0)  := (others => '0');
    signal unidades  : unsigned(3 downto 0)  := (others => '0');

    -- registros de salida
    signal hex0_reg  : std_logic_vector(6 downto 0) := "1111111"; -- apagado
    signal hex1_reg  : std_logic_vector(6 downto 0) := "1111111";
    signal hex2_reg  : std_logic_vector(6 downto 0) := "1111111";
    signal hex3_reg  : std_logic_vector(6 downto 0) := "1111111";
    signal ledr_reg  : std_logic_vector(9 downto 0) := (others => '0');

    -- funcion: convertir digito BCD a 7 segmentos (activo bajo DE1-SoC)
    function bcd_to_7seg(digit : unsigned(3 downto 0))
        return std_logic_vector is
        variable seg : std_logic_vector(6 downto 0);
    begin
        case to_integer(digit) is
            when 0 => seg := "1000000"; -- 0
            when 1 => seg := "1111001"; -- 1
            when 2 => seg := "0100100"; -- 2
            when 3 => seg := "0110000"; -- 3
            when 4 => seg := "0011001"; -- 4
            when 5 => seg := "0010010"; -- 5
            when 6 => seg := "0000010"; -- 6
            when 7 => seg := "1111000"; -- 7
            when 8 => seg := "0000000"; -- 8
            when 9 => seg := "0010000"; -- 9
            when others => seg := "1111111"; -- apagado
        end case;
        return seg;
    end function;

    -- funcion: codigo arritmia a 7 segmentos
    -- n = normal, b = bradicardia, t = taquicardia, F = fibrilacion
    function arrhyth_to_7seg(code : std_logic_vector(1 downto 0))
        return std_logic_vector is
        variable seg : std_logic_vector(6 downto 0);
    begin
        case code is
            when "00" => seg := "1001000"; -- n (normal)
            when "01" => seg := "0000011"; -- b (bradicardia)
            when "10" => seg := "0000111"; -- t (taquicardia)
            when "11" => seg := "0001110"; -- F (fibrilacion)
            when others => seg := "1111111"; -- apagado
        end case;
        return seg;
    end function;

begin

    process(clk)
        variable bpm_temp : unsigned(7 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                hex0_reg <= "1111111";
                hex1_reg <= "1111111";
                hex2_reg <= "1111111";
                hex3_reg <= "1111111";
                ledr_reg <= (others => '0');
                bpm_val  <= (others => '0');
                centenas <= (others => '0');
                decenas  <= (others => '0');
                unidades <= (others => '0');
            elsif data_valid = '1' then
                -- capturar BPM
                bpm_val <= unsigned(bpm_in);
                bpm_temp := unsigned(bpm_in);

                -- conversion binario a BCD (simple, BPM maximo 255)
                centenas <= resize(bpm_temp / 100, 4);
                decenas  <= resize((bpm_temp mod 100) / 10, 4);
                unidades <= resize(bpm_temp mod 10, 4);

                -- actualizar displays BPM
                hex0_reg <= bcd_to_7seg(resize(bpm_temp mod 10, 4));
                hex1_reg <= bcd_to_7seg(resize((bpm_temp mod 100) / 10, 4));
                hex2_reg <= bcd_to_7seg(resize(bpm_temp / 100, 4));

                -- display codigo arritmia
                hex3_reg <= arrhyth_to_7seg(arrhyth_code);

                -- LEDs segun nivel de alerta
                case alert_level is
                    when "00" => ledr_reg <= "0000000000"; -- sin alerta
                    when "01" => ledr_reg <= "0000000011"; -- baja: 2 LEDs
                    when "10" => ledr_reg <= "0000011111"; -- media: 5 LEDs
                    when "11" => ledr_reg <= "1111111111"; -- alta: 10 LEDs
                    when others => ledr_reg <= "0000000000";
                end case;
            end if;
        end if;
    end process;

    -- asignacion de salidas
    hex0 <= hex0_reg;
    hex1 <= hex1_reg;
    hex2 <= hex2_reg;
    hex3 <= hex3_reg;
    ledr <= ledr_reg;

end architecture rtl;