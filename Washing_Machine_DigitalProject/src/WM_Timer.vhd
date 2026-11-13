library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- ============================================================
-- WM_Timer : Timing signal generator
--
-- Outputs:
--   sec_tick  : single-cycle HIGH pulse every 1 second
--               (based on 100 MHz clock → MAX_COUNT = 99,999,999)
--   blink_tick: toggles at ~1 Hz (period = 2 × 0.5s)
--               used for LED blinking on finish/error states
-- ============================================================
entity WM_Timer is
    port (
        clk        : in  std_logic;
        sec_tick   : out std_logic;
        blink_tick : out std_logic
    );
end WM_Timer;

architecture Behavioral of WM_Timer is
    constant MAX_COUNT  : integer := 99999999; -- 1 second @ 100 MHz
    constant BLINK_MAX  : integer := 49999999; -- 0.5 second @ 100 MHz

    signal sec_counter  : integer range 0 to 99999999 := 0;
    signal blink_cnt    : integer range 0 to 49999999 := 0;
    signal blink_reg    : std_logic := '0';
begin

    -- 1-second tick
    process(clk)
    begin
        if rising_edge(clk) then
            if sec_counter = MAX_COUNT then
                sec_counter <= 0;
                sec_tick    <= '1';
            else
                sec_counter <= sec_counter + 1;
                sec_tick    <= '0';
            end if;
        end if;
    end process;

    -- Blink toggle (~1 Hz)
    process(clk)
    begin
        if rising_edge(clk) then
            if blink_cnt = BLINK_MAX then
                blink_cnt <= 0;
                blink_reg <= not blink_reg;
            else
                blink_cnt <= blink_cnt + 1;
            end if;
        end if;
    end process;

    blink_tick <= blink_reg;

end Behavioral;
