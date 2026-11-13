library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.WM_pkg.ALL;

-- ============================================================
-- Washing_Machine_FSM : Top-level entity
--
-- Instantiates:
--   4x WM_Debouncer  — one per button (btnc, btnl, btnu, btnr)
--   1x WM_Timer      — sec_tick + blink_tick
--   1x WM_FSM_Core   — state machine logic
--   1x WM_Display    — 7-seg + LED output
--
-- Button Assignment:
--   btnc = Confirm / Yes
--   btnl = Cancel / No / Back
--   btnu = Skip (skip countdown)
--   btnr = Hard Reset → S0_IDLE
--
-- SW Layout:
--   sw(15)      = Auto(1) / Manual(0)
--   sw(14:13)   = [Auto]   Program: 00=Quick, 01=Normal, 10=Heavy
--   sw(12:11)   = [Auto]   Laundry weight
--                 [Manual] Wash time: 00=15, 01=30, 10=45, 11=60 min
--   sw(10:9)    = Water level
--   sw(8:7)     = Temperature
--   sw(6)       = Re-wash threshold: 0=strict(<=5), 1=loose(<=3)
--   sw(5)       = Spin/Redo Yes(1) / No(0)
--   sw(4)       = Door: 1=closed
--   sw(3)       = Pause: 1=pause
--   sw(2)       = Cleanliness + Re-wash: 1=enabled
--   sw(1)       = Dry: 1=requested
--   sw(0)       = Dry time: 1=long(20min), 0=short(10min)
--
-- Error Codes:
--   E01 = door open before start
--   E02 = door open during wash/spin/dry
-- ============================================================
entity Washing_Machine_FSM is
    Port (
        clk  : in  STD_LOGIC;
        btnc : in  STD_LOGIC;
        btnl : in  STD_LOGIC;
        btnu : in  STD_LOGIC;
        btnr : in  STD_LOGIC;
        sw   : in  STD_LOGIC_VECTOR(15 downto 0);
        led  : out STD_LOGIC_VECTOR(15 downto 0);
        seg  : out STD_LOGIC_VECTOR(6 downto 0);
        dp   : out STD_LOGIC;
        an   : out STD_LOGIC_VECTOR(7 downto 0)
    );
end Washing_Machine_FSM;

architecture Structural of Washing_Machine_FSM is

    -- ── Component declarations ──────────────────────────────

    component WM_Debouncer is
        generic (STABLE_COUNT : integer := 2000000);
        port (
            clk   : in  std_logic;
            btn   : in  std_logic;
            pulse : out std_logic
        );
    end component;

    component WM_Timer is
        port (
            clk        : in  std_logic;
            sec_tick   : out std_logic;
            blink_tick : out std_logic
        );
    end component;

    component WM_FSM_Core is
        port (
            clk             : in  std_logic;
            btnc_pulse      : in  std_logic;
            btnl_pulse      : in  std_logic;
            btnu_pulse      : in  std_logic;
            btnr_pulse      : in  std_logic;
            sw              : in  std_logic_vector(15 downto 0);
            sec_tick        : in  std_logic;
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
    end component;

    component WM_Display is
        port (
            clk             : in  std_logic;
            current_state   : in  state_type;
            sw              : in  std_logic_vector(15 downto 0);
            timer_min       : in  integer range 0 to 99;
            timer_sec       : in  integer range 0 to 59;
            clean_score     : in  integer range 0 to 9;
            locked_wash_min : in  integer range 0 to 99;
            locked_spin_min : in  integer range 0 to 99;
            locked_water_lvl: in  std_logic_vector(1 downto 0);
            locked_temp     : in  std_logic_vector(1 downto 0);
            blink_tick      : in  std_logic;
            seg             : out std_logic_vector(6 downto 0);
            dp              : out std_logic;
            an              : out std_logic_vector(7 downto 0);
            led             : out std_logic_vector(15 downto 0)
        );
    end component;

    -- ── Internal wires ──────────────────────────────────────

    -- Button pulses
    signal btnc_pulse : std_logic;
    signal btnl_pulse : std_logic;
    signal btnu_pulse : std_logic;
    signal btnr_pulse : std_logic;

    -- Timing
    signal sec_tick   : std_logic;
    signal blink_tick : std_logic;

    -- FSM → Display
    signal current_state    : state_type;
    signal timer_min        : integer range 0 to 99;
    signal timer_sec        : integer range 0 to 59;
    signal clean_score      : integer range 0 to 9;
    signal locked_wash_min  : integer range 0 to 99;
    signal locked_spin_min  : integer range 0 to 99;
    signal locked_water_lvl : std_logic_vector(1 downto 0);
    signal locked_temp      : std_logic_vector(1 downto 0);
    signal error_code       : integer range 1 to 2;

begin

    -- ── 4x Button Debouncers ────────────────────────────────
    U_DBC : WM_Debouncer port map (clk => clk, btn => btnc, pulse => btnc_pulse);
    U_DBL : WM_Debouncer port map (clk => clk, btn => btnl, pulse => btnl_pulse);
    U_DBU : WM_Debouncer port map (clk => clk, btn => btnu, pulse => btnu_pulse);
    U_DBR : WM_Debouncer port map (clk => clk, btn => btnr, pulse => btnr_pulse);

    -- ── Timer ───────────────────────────────────────────────
    U_TIMER : WM_Timer port map (
        clk        => clk,
        sec_tick   => sec_tick,
        blink_tick => blink_tick
    );

    -- ── FSM Core ────────────────────────────────────────────
    U_FSM : WM_FSM_Core port map (
        clk              => clk,
        btnc_pulse       => btnc_pulse,
        btnl_pulse       => btnl_pulse,
        btnu_pulse       => btnu_pulse,
        btnr_pulse       => btnr_pulse,
        sw               => sw,
        sec_tick         => sec_tick,
        current_state    => current_state,
        timer_min        => timer_min,
        timer_sec        => timer_sec,
        clean_score      => clean_score,
        locked_wash_min  => locked_wash_min,
        locked_spin_min  => locked_spin_min,
        locked_water_lvl => locked_water_lvl,
        locked_temp      => locked_temp,
        error_code       => error_code
    );

    -- ── Display ─────────────────────────────────────────────
    U_DISP : WM_Display port map (
        clk              => clk,
        current_state    => current_state,
        sw               => sw,
        timer_min        => timer_min,
        timer_sec        => timer_sec,
        clean_score      => clean_score,
        locked_wash_min  => locked_wash_min,
        locked_spin_min  => locked_spin_min,
        locked_water_lvl => locked_water_lvl,
        locked_temp      => locked_temp,
        blink_tick       => blink_tick,
        seg              => seg,
        dp               => dp,
        an               => an,
        led              => led
    );

end Structural;
