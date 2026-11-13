library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.WM_pkg.ALL;

-- ============================================================
-- WM_Display : All display logic
--
-- Responsibilities:
--   1. Determine seg_data[0..7] from current FSM state
--   2. Multiplex 8-digit 7-segment display (refresh ~762 Hz per digit)
--   3. Drive decimal point during countdown states
--   4. Drive 16 LEDs (wash/spin/dry indicators, progress, blink)
--
-- Inputs from FSM:
--   current_state  : which state the machine is in
--   sw             : raw switch vector (for real-time display previews)
--   timer_min/sec  : current countdown value
--   clean_score    : computed cleanliness score (1–9)
--   locked_*       : confirmed parameter values
--   blink_tick     : ~1 Hz toggle from WM_Timer
-- ============================================================
entity WM_Display is
    port (
        clk            : in  std_logic;

        -- FSM state & parameters
        current_state  : in  state_type;
        sw             : in  std_logic_vector(15 downto 0);
        timer_min      : in  integer range 0 to 99;
        timer_sec      : in  integer range 0 to 59;
        clean_score    : in  integer range 0 to 9;
        locked_wash_min: in  integer range 0 to 99;
        locked_spin_min: in  integer range 0 to 99;
        locked_water_lvl: in std_logic_vector(1 downto 0);
        locked_temp    : in  std_logic_vector(1 downto 0);
        blink_tick     : in  std_logic;

        -- Hardware outputs
        seg            : out std_logic_vector(6 downto 0);
        dp             : out std_logic;
        an             : out std_logic_vector(7 downto 0);
        led            : out std_logic_vector(15 downto 0)
    );
end WM_Display;

architecture Behavioral of WM_Display is

    signal seg_data        : seg_array := (others => C_BLK);
    signal refresh_counter : unsigned(19 downto 0) := (others => '0');
    signal active_digit    : std_logic_vector(2 downto 0);

begin

    -- ============================================================
    -- 1. Refresh counter for multiplexer (~762 Hz per digit @ 100 MHz)
    -- ============================================================
    process(clk)
    begin
        if rising_edge(clk) then
            refresh_counter <= refresh_counter + 1;
        end if;
    end process;

    active_digit <= std_logic_vector(refresh_counter(19 downto 17));

    -- ============================================================
    -- 2. 7-Segment Content Driver
    --    Combinational: determines what to show on each digit
    -- ============================================================
    process(current_state, sw, timer_min, timer_sec,
            clean_score, locked_wash_min, locked_temp,
            locked_water_lvl, locked_spin_min, blink_tick)
        variable wt           : std_logic_vector(1 downto 0);
        variable tmp          : std_logic_vector(1 downto 0);
        variable wlv          : std_logic_vector(1 downto 0);
        variable num          : integer range 0 to 99;
        variable spin_preview : integer range 0 to 99;
    begin
        seg_data <= (others => C_BLK);
        wt  := sw(12 downto 11);
        tmp := sw(8  downto 7);
        wlv := sw(10 downto 9);

        case current_state is

            -- IDLE ----
            when S0_IDLE =>
                seg_data(7)<=C_I; seg_data(6)<=C_D;
                seg_data(5)<=C_L; seg_data(4)<=C_E;
                seg_data(3)<=C_DASH; seg_data(2)<=C_DASH;
                seg_data(1)<=C_DASH; seg_data(0)<=C_DASH;

            -- SELECT MODE: "AUTO" or "HAND" ----
            when S1_SELECT_MODE =>
                if sw(15) = '1' then
                    seg_data(7)<=C_A; seg_data(6)<=C_U;
                    seg_data(5)<=C_T; seg_data(4)<=C_O;
                else
                    seg_data(7)<=C_H; seg_data(6)<=C_A;
                    seg_data(5)<=C_N; seg_data(4)<=C_D;
                end if;
                seg_data(3)<=C_DASH; seg_data(2)<=C_DASH;
                seg_data(1)<=C_DASH; seg_data(0)<=C_DASH;

            -- DOOR CHECK: "DOOR CLSD" or "DOOR OPEN" ----
            when S2_CHECK_DOOR | S17B_RESUME_DOOR =>
                seg_data(7)<=C_D; seg_data(6)<=C_O;
                seg_data(5)<=C_O; seg_data(4)<=C_R;
                if sw(4) = '1' then
                    seg_data(3)<=C_C; seg_data(2)<=C_L;
                    seg_data(1)<=C_S; seg_data(0)<=C_D;
                else
                    seg_data(3)<=C_O; seg_data(2)<=C_P;
                    seg_data(1)<=C_E; seg_data(0)<=C_N;
                end if;

            -- AUTO PROGRAM SELECT: "PROG QUIS/NOR/HEUY" ----
            when S3_AUTO_SELECT =>
                seg_data(7)<=C_P; seg_data(6)<=C_R;
                seg_data(5)<=C_O; seg_data(4)<=C_G;
                case sw(14 downto 13) is
                    when "00"   => seg_data(3)<=C_Q; seg_data(2)<=C_U; seg_data(1)<=C_I; seg_data(0)<=C_S;
                    when "01"   => seg_data(3)<=C_N; seg_data(2)<=C_O; seg_data(1)<=C_R; seg_data(0)<=C_BLK;
                    when others => seg_data(3)<=C_H; seg_data(2)<=C_E; seg_data(1)<=C_U; seg_data(0)<=C_Y;
                end case;

            -- MANUAL CONFIRM: "HAND ----" ----
            when S8_MANUAL_SELECT =>
                seg_data(7)<=C_H; seg_data(6)<=C_A;
                seg_data(5)<=C_N; seg_data(4)<=C_D;
                seg_data(3)<=C_DASH; seg_data(2)<=C_DASH;
                seg_data(1)<=C_DASH; seg_data(0)<=C_DASH;

            -- WATER LEVEL: "LUL  LO/NID/HI/NA" ----
            when S9_SET_WATER_LEVEL =>
                seg_data(7)<=C_L; seg_data(6)<=C_U;
                seg_data(5)<=C_L; seg_data(4)<=C_BLK;
                case wlv is
                    when "00"   => seg_data(3)<=C_BLK; seg_data(2)<=C_L; seg_data(1)<=C_O; seg_data(0)<=C_BLK;
                    when "01"   => seg_data(3)<=C_BLK; seg_data(2)<=C_N; seg_data(1)<=C_I; seg_data(0)<=C_D;
                    when "10"   => seg_data(3)<=C_BLK; seg_data(2)<=C_H; seg_data(1)<=C_I; seg_data(0)<=C_BLK;
                    when others => seg_data(3)<=C_BLK; seg_data(2)<=C_N; seg_data(1)<=C_A; seg_data(0)<=C_BLK;
                end case;

            -- TEMPERATURE: "TENP COLD/UARN/HOT/SANI" ----
            when S10_SET_WATER_TEMP =>
                seg_data(7)<=C_T; seg_data(6)<=C_E;
                seg_data(5)<=C_N; seg_data(4)<=C_P;
                case tmp is
                    when "00"   => seg_data(3)<=C_C; seg_data(2)<=C_O; seg_data(1)<=C_L; seg_data(0)<=C_D;
                    when "01"   => seg_data(3)<=C_U; seg_data(2)<=C_A; seg_data(1)<=C_R; seg_data(0)<=C_N;
                    when "10"   => seg_data(3)<=C_BLK; seg_data(2)<=C_H; seg_data(1)<=C_O; seg_data(0)<=C_T;
                    when others => seg_data(3)<=C_S; seg_data(2)<=C_A; seg_data(1)<=C_N; seg_data(0)<=C_I;
                end case;

            -- WASH TIME SELECT: "UASH  15/30/45/60" ----
            when S11_SET_WASH_TIME =>
                seg_data(7)<=C_U; seg_data(6)<=C_A;
                seg_data(5)<=C_S; seg_data(4)<=C_H;
                case sw(12 downto 11) is
                    when "00"   => num := 15;
                    when "01"   => num := 30;
                    when "10"   => num := 45;
                    when others => num := 60;
                end case;
                seg_data(3) <= C_BLK; seg_data(2) <= C_BLK;
                seg_data(1) <= decode_num((num / 10) mod 10);
                seg_data(0) <= decode_num( num mod 10);

            -- SPIN TIME PREVIEW: "SPIN  xx" (from locked water/temp) ----
            when S11B_SET_SPIN_TIME =>
                seg_data(7)<=C_S; seg_data(6)<=C_P;
                seg_data(5)<=C_I; seg_data(4)<=C_N;
                spin_preview := calc_spin_manual(locked_water_lvl, locked_temp);
                seg_data(3) <= C_BLK; seg_data(2) <= C_BLK;
                seg_data(1) <= decode_num((spin_preview / 10) mod 10);
                seg_data(0) <= decode_num( spin_preview mod 10);

            -- SPIN YES/NO: "SPIN  YES/NO" ----
            when S11C_SPIN_SEL =>
                seg_data(7)<=C_S; seg_data(6)<=C_P;
                seg_data(5)<=C_I; seg_data(4)<=C_N;
                if sw(5) = '1' then
                    seg_data(3)<=C_BLK; seg_data(2)<=C_Y;
                    seg_data(1)<=C_E;   seg_data(0)<=C_S;
                else
                    seg_data(3)<=C_BLK; seg_data(2)<=C_BLK;
                    seg_data(1)<=C_N;   seg_data(0)<=C_O;
                end if;

            -- AUTO SET PREVIEW: "SET   xx" ----
            when S4_AUTO_SET =>
                seg_data(7)<=C_S; seg_data(6)<=C_E;
                seg_data(5)<=C_T; seg_data(4)<=C_BLK;
                num := calc_wash_min(sw(14 downto 13), sw(12 downto 11));
                seg_data(3) <= C_BLK; seg_data(2) <= C_BLK;
                seg_data(1) <= decode_num((num / 10) mod 10);
                seg_data(0) <= decode_num( num mod 10);

            -- WASH RUNNING: "UASH MMss" ----
            when S5_AUTO_WASH | S12_WASH_RUN =>
                seg_data(7)<=C_U; seg_data(6)<=C_A;
                seg_data(5)<=C_S; seg_data(4)<=C_H;
                seg_data(3) <= decode_num((timer_min / 10) mod 10);
                seg_data(2) <= decode_num( timer_min mod 10);
                seg_data(1) <= decode_num((timer_sec / 10) mod 10);
                seg_data(0) <= decode_num( timer_sec mod 10);

            -- SPIN RUNNING: "SPIN MMss" ----
            when S6_AUTO_SPIN | S13_SPIN_RUN =>
                seg_data(7)<=C_S; seg_data(6)<=C_P;
                seg_data(5)<=C_I; seg_data(4)<=C_N;
                seg_data(3) <= decode_num((timer_min / 10) mod 10);
                seg_data(2) <= decode_num( timer_min mod 10);
                seg_data(1) <= decode_num((timer_sec / 10) mod 10);
                seg_data(0) <= decode_num( timer_sec mod 10);

            -- DRY RUNNING: "DRY  MMss" ----
            when S15_DRY_RUN =>
                seg_data(7)<=C_D; seg_data(6)<=C_R;
                seg_data(5)<=C_Y; seg_data(4)<=C_BLK;
                seg_data(3) <= decode_num((timer_min / 10) mod 10);
                seg_data(2) <= decode_num( timer_min mod 10);
                seg_data(1) <= decode_num((timer_sec / 10) mod 10);
                seg_data(0) <= decode_num( timer_sec mod 10);

            -- DRY YES/NO: "DRY  YES/NO" ----
            when S7_DRY_SEL =>
                seg_data(7)<=C_D; seg_data(6)<=C_R;
                seg_data(5)<=C_Y; seg_data(4)<=C_BLK;
                if sw(1) = '1' then
                    seg_data(3)<=C_BLK; seg_data(2)<=C_Y;
                    seg_data(1)<=C_E;   seg_data(0)<=C_S;
                else
                    seg_data(3)<=C_BLK; seg_data(2)<=C_BLK;
                    seg_data(1)<=C_N;   seg_data(0)<=C_O;
                end if;

            -- DRY TIME SELECT: "DRY  LONG/SHRT" ----
            when S14_SET_DRY =>
                seg_data(7)<=C_D; seg_data(6)<=C_R;
                seg_data(5)<=C_Y; seg_data(4)<=C_BLK;
                if sw(0) = '1' then
                    seg_data(3)<=C_L; seg_data(2)<=C_O;
                    seg_data(1)<=C_N; seg_data(0)<=C_G;
                else
                    seg_data(3)<=C_S; seg_data(2)<=C_H;
                    seg_data(1)<=C_R; seg_data(0)<=C_T;
                end if;

            -- CLEAN SCORE: "CLEN    x" ----
            when S18_SHOW_CLEAN =>
                seg_data(7)<=C_C; seg_data(6)<=C_L;
                seg_data(5)<=C_E; seg_data(4)<=C_N;
                seg_data(3)<=C_BLK; seg_data(2)<=C_BLK;
                seg_data(1)<=C_BLK;
                seg_data(0)<= decode_num(clean_score);

            -- REWASH YES/NO: "REDO YES/NO" ----
            when S19_REWASH_SUGGEST =>
                seg_data(7)<=C_R; seg_data(6)<=C_E;
                seg_data(5)<=C_D; seg_data(4)<=C_O;
                if sw(5) = '1' then
                    seg_data(3)<=C_BLK; seg_data(2)<=C_Y;
                    seg_data(1)<=C_E;   seg_data(0)<=C_S;
                else
                    seg_data(3)<=C_BLK; seg_data(2)<=C_BLK;
                    seg_data(1)<=C_N;   seg_data(0)<=C_O;
                end if;

            -- FINISH: "DONE" ----
            when S16_FINISH =>
                seg_data(7)<=C_D; seg_data(6)<=C_O;
                seg_data(5)<=C_N; seg_data(4)<=C_E;

            -- ERROR: "ERR  E0x" ----
            when S17_ERROR =>
                seg_data(7)<=C_E; seg_data(6)<=C_R;
                seg_data(5)<=C_R; seg_data(4)<=C_BLK;
                seg_data(3)<=C_E; seg_data(2)<=C_BLK;
                -- error_code not passed in; shown externally via sw-driven convention
                -- digits 1-0 left blank here, caller should OR in error digits if needed
                seg_data(1)<=C_O; seg_data(0)<=C_BLK;

            when others =>
                seg_data <= (others => C_BLK);
        end case;
    end process;

    -- ============================================================
    -- 3. 7-Seg Multiplexer
    --    dp ON at digit index 2 during countdown (MM.ss separator)
    -- ============================================================
    process(active_digit, seg_data, current_state)
        variable running : boolean;
    begin
        running := (current_state = S5_AUTO_WASH  or
                    current_state = S6_AUTO_SPIN   or
                    current_state = S12_WASH_RUN   or
                    current_state = S13_SPIN_RUN   or
                    current_state = S15_DRY_RUN);
        an  <= "11111111";
        seg <= "1111111";
        dp  <= '1';
        case active_digit is
            when "000" => an <= "11111110"; seg <= seg_data(0); dp <= '1';
            when "001" => an <= "11111101"; seg <= seg_data(1); dp <= '1';
            when "010" =>
                an <= "11111011"; seg <= seg_data(2);
                if running then dp <= '0'; else dp <= '1'; end if;
            when "011" => an <= "11110111"; seg <= seg_data(3); dp <= '1';
            when "100" => an <= "11101111"; seg <= seg_data(4); dp <= '1';
            when "101" => an <= "11011111"; seg <= seg_data(5); dp <= '1';
            when "110" => an <= "10111111"; seg <= seg_data(6); dp <= '1';
            when "111" => an <= "01111111"; seg <= seg_data(7); dp <= '1';
            when others => an <= "11111111"; dp <= '1';
        end case;
    end process;

    -- ============================================================
    -- 4. LED Driver
    --    led(15)      : blink on finish/error/rewash
    --    led(14)      : dry running
    --    led(13)      : spin running
    --    led(12)      : wash running
    --    led(11)      : pause blink
    --    led(10)      : door status (sw(4))
    --    led(9:8)     : locked temperature
    --    led(7:6)     : locked water level
    --    led(3:0)     : wash/spin progress bar (0–15)
    -- ============================================================
    process(current_state, sw, blink_tick, timer_min, timer_sec,
            locked_wash_min, locked_spin_min, locked_temp,
            locked_water_lvl, clean_score)
        variable total_sec_remain : integer;
        variable total_sec_max    : integer;
        variable prog_val         : integer range 0 to 15;
    begin
        led        <= (others => '0');
        led(10)    <= sw(4);
        led(9 downto 8) <= locked_temp;
        led(7 downto 6) <= locked_water_lvl;

        case current_state is

            when S5_AUTO_WASH | S12_WASH_RUN =>
                led(12) <= '1';
                if sw(3) = '1' then led(11) <= blink_tick; end if;
                total_sec_remain := timer_min * 60 + timer_sec;
                total_sec_max    := locked_wash_min * 60;
                if total_sec_max > 0 then
                    prog_val := (total_sec_remain * 15) / total_sec_max;
                else prog_val := 0; end if;
                led(3 downto 0) <= std_logic_vector(to_unsigned(prog_val, 4));

            when S6_AUTO_SPIN | S13_SPIN_RUN =>
                led(13) <= '1';
                if sw(3) = '1' then led(11) <= blink_tick; end if;
                total_sec_remain := timer_min * 60 + timer_sec;
                total_sec_max    := locked_spin_min * 60;
                if total_sec_max > 0 then
                    prog_val := (total_sec_remain * 15) / total_sec_max;
                else prog_val := 0; end if;
                led(3 downto 0) <= std_logic_vector(to_unsigned(prog_val, 4));

            when S15_DRY_RUN =>
                led(14) <= '1';
                if sw(3) = '1' then led(11) <= blink_tick; end if;

            when S18_SHOW_CLEAN =>
                led(15) <= blink_tick;
                led(3 downto 0) <= std_logic_vector(to_unsigned(clean_score, 4));

            when S19_REWASH_SUGGEST =>
                led(15) <= blink_tick;

            when S16_FINISH =>
                led(15) <= blink_tick;

            when S17_ERROR =>
                led(15) <= blink_tick;
                led(10) <= '0'; -- override door LED during error

            when others => null;
        end case;
    end process;

end Behavioral;
