library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.WM_pkg.ALL;

-- ============================================================
-- WM_FSM_Core : Washing Machine state machine (logic only)
--
-- Responsibilities:
--   - State transitions based on button pulses and switch inputs
--   - Countdown timer management (load, decrement, pause)
--   - Locking parameters when user confirms settings
--   - Error detection (E01: door open at start, E02: door open during run)
--   - Resume logic after E02 (save/restore state + timer)
--
-- Does NOT handle:
--   - Debouncing (done by WM_Debouncer)
--   - Display logic (done by WM_Display)
--   - Clock generation (done by WM_Timer)
-- ============================================================
entity WM_FSM_Core is
    port (
        clk       : in  std_logic;

        -- Debounced button pulses (single-cycle HIGH on press)
        btnc_pulse : in  std_logic;
        btnl_pulse : in  std_logic;
        btnu_pulse : in  std_logic;
        btnr_pulse : in  std_logic;  -- hard reset

        -- Switches
        sw        : in  std_logic_vector(15 downto 0);

        -- Timing
        sec_tick  : in  std_logic;  -- 1-second pulse from WM_Timer

        -- State & parameter outputs (to WM_Display)
        current_state   : out state_type;
        timer_min       : out integer range 0 to 99;
        timer_sec       : out integer range 0 to 59;
        clean_score     : out integer range 0 to 9;
        locked_wash_min : out integer range 0 to 99;
        locked_spin_min : out integer range 0 to 99;
        locked_water_lvl: out std_logic_vector(1 downto 0);
        locked_temp     : out std_logic_vector(1 downto 0);
        error_code      : out integer range 1 to 2
    );
end WM_FSM_Core;

architecture Behavioral of WM_FSM_Core is

    -- Internal FSM state
    signal state_r    : state_type := S0_IDLE;
    signal is_auto    : boolean    := true;
    signal do_spin    : boolean    := true;
    signal err_code_r : integer range 1 to 2 := 1;

    -- Timer registers
    signal t_min : integer range 0 to 99 := 0;
    signal t_sec : integer range 0 to 59 := 0;

    -- Locked parameters
    signal lk_wash_min  : integer range 0 to 99         := 30;
    signal lk_spin_min  : integer range 0 to 99         := 15;
    signal lk_water_lvl : std_logic_vector(1 downto 0)  := "01";
    signal lk_temp      : std_logic_vector(1 downto 0)  := "01";
    signal lk_score     : integer range 0 to 9          := 0;

    -- E02 resume snapshot
    signal prev_state   : state_type         := S0_IDLE;
    signal prev_t_min   : integer range 0 to 99 := 0;
    signal prev_t_sec   : integer range 0 to 59 := 0;

begin

    -- Wire internal registers to outputs
    current_state    <= state_r;
    timer_min        <= t_min;
    timer_sec        <= t_sec;
    clean_score      <= lk_score;
    locked_wash_min  <= lk_wash_min;
    locked_spin_min  <= lk_spin_min;
    locked_water_lvl <= lk_water_lvl;
    locked_temp      <= lk_temp;
    error_code       <= err_code_r;

    -- ============================================================
    -- Main FSM Process
    -- ============================================================
    process(clk)

        -- Load timer helper
        procedure load_timer(min : in integer) is
        begin
            t_min <= min;
            t_sec <= 0;
        end procedure;

        -- Decrement timer helper
        procedure do_countdown is
        begin
            if t_sec > 0 then
                t_sec <= t_sec - 1;
            elsif t_min > 0 then
                t_min <= t_min - 1;
                t_sec <= 59;
            end if;
        end procedure;

        -- Save state + timer for E02 resume
        procedure save_for_resume(s : in state_type) is
        begin
            prev_state <= s;
            prev_t_min <= t_min;
            prev_t_sec <= t_sec;
            err_code_r <= 2;
            state_r    <= S17_ERROR;
        end procedure;

        -- Transition to clean score or finish
        procedure goto_clean_or_finish is
        begin
            if sw(2) = '1' then
                lk_score <= calc_clean(lk_temp, lk_water_lvl, lk_wash_min);
                state_r  <= S18_SHOW_CLEAN;
            else
                state_r  <= S16_FINISH;
            end if;
        end procedure;

        -- Full hard reset
        procedure do_reset is
        begin
            state_r      <= S0_IDLE;
            t_min        <= 0;
            t_sec        <= 0;
            lk_score     <= 0;
            lk_wash_min  <= 30;
            lk_spin_min  <= 15;
            lk_water_lvl <= "01";
            lk_temp      <= "01";
            do_spin      <= true;
            prev_state   <= S0_IDLE;
            prev_t_min   <= 0;
            prev_t_sec   <= 0;
            err_code_r   <= 1;
        end procedure;

        variable v_wash : integer range 0 to 99;
        variable v_spin : integer range 0 to 99;

    begin
        if rising_edge(clk) then

            -- Hard reset (btnr) overrides everything
            if btnr_pulse = '1' then
                do_reset;

            else
                case state_r is

                    -- ── IDLE ─────────────────────────────────────
                    when S0_IDLE =>
                        if btnc_pulse = '1' then state_r <= S1_SELECT_MODE; end if;

                    -- ── SELECT MODE ──────────────────────────────
                    when S1_SELECT_MODE =>
                        if    btnl_pulse = '1' then state_r <= S0_IDLE;
                        elsif btnc_pulse = '1' then
                            if sw(15) = '1' then
                                is_auto <= true;
                                state_r <= S3_AUTO_SELECT;
                            else
                                is_auto <= false;
                                state_r <= S8_MANUAL_SELECT;
                            end if;
                        end if;

                    -- ── AUTO PROGRAM SELECT ──────────────────────
                    when S3_AUTO_SELECT =>
                        if    btnl_pulse = '1' then state_r <= S1_SELECT_MODE;
                        elsif btnc_pulse = '1' then state_r <= S2_CHECK_DOOR;
                        end if;

                    -- ── MANUAL CONFIRM ───────────────────────────
                    when S8_MANUAL_SELECT =>
                        if    btnl_pulse = '1' then state_r <= S1_SELECT_MODE;
                        elsif btnc_pulse = '1' then state_r <= S2_CHECK_DOOR;
                        end if;

                    -- ── DOOR CHECK ───────────────────────────────
                    -- E01: door open at start → error
                    when S2_CHECK_DOOR =>
                        if    btnl_pulse = '1' then state_r <= S0_IDLE;
                        elsif btnc_pulse = '1' then
                            if sw(4) = '1' then
                                if is_auto then state_r <= S4_AUTO_SET;
                                else            state_r <= S9_SET_WATER_LEVEL;
                                end if;
                            else
                                err_code_r <= 1;
                                state_r    <= S17_ERROR;
                            end if;
                        end if;

                    -- ── AUTO SET ─────────────────────────────────
                    -- Lock all parameters; use variable to ensure
                    -- locked_wash_min and timer get same value
                    when S4_AUTO_SET =>
                        v_wash       := calc_wash_min(sw(14 downto 13), sw(12 downto 11));
                        v_spin       := calc_spin_auto(sw(14 downto 13), sw(12 downto 11));
                        lk_water_lvl <= sw(10 downto 9);
                        lk_temp      <= sw(8 downto 7);
                        lk_wash_min  <= v_wash;
                        lk_spin_min  <= v_spin;
                        load_timer(v_wash);
                        state_r      <= S5_AUTO_WASH;

                    -- ── AUTO WASH ────────────────────────────────
                    when S5_AUTO_WASH =>
                        if    sw(4) = '0'      then save_for_resume(S5_AUTO_WASH);
                        elsif btnl_pulse = '1' then state_r <= S0_IDLE;
                        elsif btnu_pulse = '1' then
                            load_timer(lk_spin_min);
                            state_r <= S6_AUTO_SPIN;
                        elsif sw(3) = '0' and sec_tick = '1' then
                            if t_min = 0 and t_sec = 0 then
                                load_timer(lk_spin_min);
                                state_r <= S6_AUTO_SPIN;
                            else do_countdown;
                            end if;
                        end if;

                    -- ── AUTO SPIN ────────────────────────────────
                    when S6_AUTO_SPIN =>
                        if    sw(4) = '0'      then save_for_resume(S6_AUTO_SPIN);
                        elsif btnl_pulse = '1' then state_r <= S0_IDLE;
                        elsif btnu_pulse = '1' then
                            t_min <= 0; t_sec <= 0;
                            state_r <= S7_DRY_SEL;
                        elsif sw(3) = '0' and sec_tick = '1' then
                            if t_min = 0 and t_sec = 0 then state_r <= S7_DRY_SEL;
                            else do_countdown;
                            end if;
                        end if;

                    -- ── DRY SELECT ───────────────────────────────
                    when S7_DRY_SEL =>
                        if    btnl_pulse = '1' then goto_clean_or_finish;
                        elsif btnc_pulse = '1' then
                            if sw(1) = '1' then state_r <= S14_SET_DRY;
                            else goto_clean_or_finish;
                            end if;
                        end if;

                    -- ── MANUAL: WATER LEVEL ──────────────────────
                    when S9_SET_WATER_LEVEL =>
                        if    btnl_pulse = '1' then state_r <= S2_CHECK_DOOR;
                        elsif btnc_pulse = '1' then
                            lk_water_lvl <= sw(10 downto 9);
                            state_r      <= S10_SET_WATER_TEMP;
                        end if;

                    -- ── MANUAL: TEMPERATURE ─────────────────────
                    when S10_SET_WATER_TEMP =>
                        if    btnl_pulse = '1' then state_r <= S9_SET_WATER_LEVEL;
                        elsif btnc_pulse = '1' then
                            lk_temp <= sw(8 downto 7);
                            state_r <= S11_SET_WASH_TIME;
                        end if;

                    -- ── MANUAL: WASH TIME ────────────────────────
                    when S11_SET_WASH_TIME =>
                        if    btnl_pulse = '1' then state_r <= S10_SET_WATER_TEMP;
                        elsif btnc_pulse = '1' then
                            case sw(12 downto 11) is
                                when "00"   => lk_wash_min <= 15; load_timer(15);
                                when "01"   => lk_wash_min <= 30; load_timer(30);
                                when "10"   => lk_wash_min <= 45; load_timer(45);
                                when others => lk_wash_min <= 60; load_timer(60);
                            end case;
                            state_r <= S11B_SET_SPIN_TIME;
                        end if;

                    -- ── MANUAL: SPIN TIME PREVIEW ────────────────
                    when S11B_SET_SPIN_TIME =>
                        if    btnl_pulse = '1' then state_r <= S11_SET_WASH_TIME;
                        elsif btnc_pulse = '1' then
                            lk_spin_min <= calc_spin_manual(lk_water_lvl, lk_temp);
                            state_r     <= S11C_SPIN_SEL;
                        end if;

                    -- ── MANUAL: SPIN YES/NO ──────────────────────
                    when S11C_SPIN_SEL =>
                        if    btnl_pulse = '1' then state_r <= S11B_SET_SPIN_TIME;
                        elsif btnc_pulse = '1' then
                            do_spin <= (sw(5) = '1');
                            load_timer(lk_wash_min);
                            state_r <= S12_WASH_RUN;
                        end if;

                    -- ── MANUAL WASH RUN ──────────────────────────
                    when S12_WASH_RUN =>
                        if    sw(4) = '0'      then save_for_resume(S12_WASH_RUN);
                        elsif btnl_pulse = '1' then state_r <= S0_IDLE;
                        elsif btnu_pulse = '1' then
                            if do_spin then
                                load_timer(lk_spin_min);
                                state_r <= S13_SPIN_RUN;
                            else state_r <= S7_DRY_SEL;
                            end if;
                        elsif sw(3) = '0' and sec_tick = '1' then
                            if t_min = 0 and t_sec = 0 then
                                if do_spin then
                                    load_timer(lk_spin_min);
                                    state_r <= S13_SPIN_RUN;
                                else state_r <= S7_DRY_SEL;
                                end if;
                            else do_countdown;
                            end if;
                        end if;

                    -- ── MANUAL SPIN RUN ──────────────────────────
                    when S13_SPIN_RUN =>
                        if    sw(4) = '0'      then save_for_resume(S13_SPIN_RUN);
                        elsif btnl_pulse = '1' then state_r <= S0_IDLE;
                        elsif btnu_pulse = '1' then
                            t_min <= 0; t_sec <= 0;
                            state_r <= S7_DRY_SEL;
                        elsif sw(3) = '0' and sec_tick = '1' then
                            if t_min = 0 and t_sec = 0 then state_r <= S7_DRY_SEL;
                            else do_countdown;
                            end if;
                        end if;

                    -- ── SET DRY ──────────────────────────────────
                    when S14_SET_DRY =>
                        if    btnl_pulse = '1' then state_r <= S7_DRY_SEL;
                        elsif btnc_pulse = '1' then
                            if sw(0) = '1' then load_timer(20);
                            else               load_timer(10);
                            end if;
                            state_r <= S15_DRY_RUN;
                        end if;

                    -- ── DRY RUN ──────────────────────────────────
                    when S15_DRY_RUN =>
                        if    sw(4) = '0'      then save_for_resume(S15_DRY_RUN);
                        elsif btnl_pulse = '1' then state_r <= S0_IDLE;
                        elsif btnu_pulse = '1' then
                            t_min <= 0; t_sec <= 0;
                            goto_clean_or_finish;
                        elsif sw(3) = '0' and sec_tick = '1' then
                            if t_min = 0 and t_sec = 0 then goto_clean_or_finish;
                            else do_countdown;
                            end if;
                        end if;

                    -- ── SHOW CLEAN SCORE ─────────────────────────
                    when S18_SHOW_CLEAN =>
                        if btnc_pulse = '1' or btnl_pulse = '1' then
                            if sw(2) = '1' then
                                if (sw(6) = '0' and lk_score <= 5) or
                                   (sw(6) = '1' and lk_score <= 3) then
                                    state_r <= S19_REWASH_SUGGEST;
                                else
                                    state_r <= S16_FINISH;
                                end if;
                            else
                                state_r <= S16_FINISH;
                            end if;
                        end if;

                    -- ── REWASH SUGGEST ───────────────────────────
                    when S19_REWASH_SUGGEST =>
                        if    btnl_pulse = '1' then state_r <= S16_FINISH;
                        elsif btnc_pulse = '1' then
                            if sw(5) = '1' then state_r <= S1_SELECT_MODE;
                            else               state_r <= S16_FINISH;
                            end if;
                        end if;

                    -- ── FINISH ───────────────────────────────────
                    when S16_FINISH =>
                        if btnc_pulse = '1' or btnl_pulse = '1' then
                            state_r <= S0_IDLE;
                        end if;

                    -- ── ERROR ────────────────────────────────────
                    -- E01: btnc → retry door check
                    -- E02: btnc → door check before resume
                    when S17_ERROR =>
                        if    btnl_pulse = '1' then state_r <= S0_IDLE;
                        elsif btnc_pulse = '1' then
                            if err_code_r = 2 then state_r <= S17B_RESUME_DOOR;
                            else                   state_r <= S2_CHECK_DOOR;
                            end if;
                        end if;

                    -- ── RESUME DOOR CHECK ────────────────────────
                    -- Must confirm door closed before restoring saved state
                    when S17B_RESUME_DOOR =>
                        if    btnl_pulse = '1' then state_r <= S0_IDLE;
                        elsif btnc_pulse = '1' then
                            if sw(4) = '1' then
                                t_min   <= prev_t_min;
                                t_sec   <= prev_t_sec;
                                state_r <= prev_state;
                            end if;
                            -- door still open: stay (display already shows OPEN)
                        end if;

                    when others => state_r <= S0_IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
