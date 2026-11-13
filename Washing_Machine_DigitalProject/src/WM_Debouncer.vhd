library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- ============================================================
-- WM_Debouncer : Single-button debounce + rising-edge pulse
--
-- Usage: instantiate once per button (4x in top-level)
--
-- Parameters:
--   STABLE_COUNT : number of clock cycles btn must stay high
--                  before being considered stable (default 2,000,000 = 20ms @ 100MHz)
--
-- Outputs:
--   pulse : single-cycle HIGH on each confirmed button press
-- ============================================================
entity WM_Debouncer is
    generic (
        STABLE_COUNT : integer := 2000000
    );
    port (
        clk   : in  std_logic;
        btn   : in  std_logic;
        pulse : out std_logic
    );
end WM_Debouncer;

architecture Behavioral of WM_Debouncer is
    signal cnt    : integer range 0 to 2000000 := 0;
    signal stable : std_logic := '0';
    signal reg    : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            -- Debounce: count consecutive high cycles
            if btn = '1' then
                if cnt < STABLE_COUNT then
                    cnt <= cnt + 1;
                else
                    stable <= '1';
                end if;
            else
                cnt    <= 0;
                stable <= '0';
            end if;

            -- Rising-edge pulse detection
            reg   <= stable;
            pulse <= stable and not reg;
        end if;
    end process;
end Behavioral;
