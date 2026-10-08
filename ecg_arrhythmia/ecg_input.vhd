
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ecg_input is
    port(
        clk        : in  std_logic;                     -- reloj 50 MHz DE1-SoC
        rst        : in  std_logic;                     -- reset activo alto
        ecg_data   : in  std_logic_vector(11 downto 0); -- muestra ECG 12 bits (MIT-BIH)
        data_valid : in  std_logic;                     -- indica muestra lista
        ecg_out    : out std_logic_vector(11 downto 0); -- salida sincronizada
        out_valid  : out std_logic                      -- pulso de dato valido
    );
end entity ecg_input;

architecture rtl of ecg_input is
    -- registros internos para sincronizar la entrada
    signal ecg_reg   : std_logic_vector(11 downto 0) := (others => '0');
    signal valid_reg : std_logic := '0';
begin

    -- proceso principal: captura dato ECG en flanco de subida del reloj
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                ecg_reg   <= (others => '0');
                valid_reg <= '0';
            elsif data_valid = '1' then
                ecg_reg   <= ecg_data;  -- captura muestra
                valid_reg <= '1';       -- indica dato nuevo
            else
                valid_reg <= '0';       -- pulso de un solo ciclo
            end if;
        end if;
    end process;

    -- asignacion de salidas
    ecg_out   <= ecg_reg;
    out_valid <= valid_reg;

end architecture rtl;