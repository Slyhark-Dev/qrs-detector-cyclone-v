-- ============================================================================
-- ecg_filter.vhd
-- Modulo 2: Filtro promedio movil de 8 puntos (pasa-bajas)
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Elimina ruido de alta frecuencia (> 40 Hz)
-- Mejora 1: out_valid solo activo despues de 8 muestras recibidas
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ecg_filter is
    port(
        clk          : in  std_logic;                     -- reloj 50 MHz DE1-SoC
        rst          : in  std_logic;                     -- reset activo alto
        ecg_in       : in  std_logic_vector(11 downto 0); -- entrada ECG 12 bits
        in_valid     : in  std_logic;                     -- pulso dato valido
        ecg_filtered : out std_logic_vector(11 downto 0); -- salida filtrada
        out_valid    : out std_logic                      -- pulso salida valida
    );
end entity ecg_filter;

architecture rtl of ecg_filter is

    -- registro de desplazamiento: 8 muestras de 12 bits
    type shift_reg_t is array (0 to 7) of unsigned(11 downto 0);
    signal sr : shift_reg_t := (others => (others => '0'));

    -- suma acumulada (12 bits + 3 bits = 15 bits maximo)
    signal suma     : unsigned(14 downto 0) := (others => '0');
    signal count    : unsigned(3 downto 0)  := (others => '0');
    signal valid_r  : std_logic := '0';

begin

    process(clk)
        variable suma_temp : unsigned(14 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sr      <= (others => (others => '0'));
                suma    <= (others => '0');
                count   <= (others => '0');
                valid_r <= '0';
            elsif in_valid = '1' then
                -- desplazar muestras en el registro
                sr(1 to 7) <= sr(0 to 6);
                sr(0)      <= unsigned(ecg_in);

                -- calcular suma de las 8 muestras
                suma_temp := (others => '0');
                for i in 0 to 6 loop
                    suma_temp := suma_temp + resize(sr(i), 15);
                end loop;
                suma_temp := suma_temp + resize(unsigned(ecg_in), 15);

                suma    <= suma_temp;
                valid_r <= '1';

                -- contador de muestras recibidas (satura en 8)
                if count < 8 then
                    count <= count + 1;
                end if;
            else
                valid_r <= '0';
            end if;
        end if;
    end process;

    -- division por 8 = shift right 3 bits
    -- salida valida solo cuando el registro tiene 8 muestras
    ecg_filtered <= std_logic_vector(suma(14 downto 3));
    out_valid    <= valid_r when count = 8 else '0';

end architecture rtl;