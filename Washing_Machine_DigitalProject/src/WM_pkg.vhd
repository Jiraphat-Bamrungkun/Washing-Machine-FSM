library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- WM_pkg : Shared package for Washing Machine FSM
--   - State type
--   - 7-seg character constants
--   - Calculation functions (wash, spin, clean score)
-- ============================================================
package WM_pkg is

    -- ===== FSM STATES =====
    type state_type is (
        S0_IDLE,
        S1_SELECT_MODE,
        S2_CHECK_DOOR,
        S3_AUTO_SELECT,
        S4_AUTO_SET,
        S5_AUTO_WASH,
        S6_AUTO_SPIN,
        S7_DRY_SEL,
        S8_MANUAL_SELECT,
        S9_SET_WATER_LEVEL,
        S10_SET_WATER_TEMP,
        S11_SET_WASH_TIME,
        S11B_SET_SPIN_TIME,
        S11C_SPIN_SEL,
        S12_WASH_RUN,
        S13_SPIN_RUN,
        S14_SET_DRY,
        S15_DRY_RUN,
        S16_FINISH,
        S17_ERROR,
        S17B_RESUME_DOOR,
        S18_SHOW_CLEAN,
        S19_REWASH_SUGGEST
    );

    -- ===== 7-SEG SEGMENT ARRAY TYPE =====
    type seg_array is array (0 to 7) of std_logic_vector(6 downto 0);

    -- ===== 7-SEG CHARACTER CONSTANTS =====
    -- Active-low encoding (0 = segment ON)
    constant C_A    : std_logic_vector(6 downto 0) := "0001000";
    constant C_B    : std_logic_vector(6 downto 0) := "0000011";
    constant C_C    : std_logic_vector(6 downto 0) := "1000110";
    constant C_D    : std_logic_vector(6 downto 0) := "0100001";
    constant C_E    : std_logic_vector(6 downto 0) := "0000110";
    constant C_F    : std_logic_vector(6 downto 0) := "0001110";
    constant C_G    : std_logic_vector(6 downto 0) := "0010000";
    constant C_H    : std_logic_vector(6 downto 0) := "0001001";
    constant C_I    : std_logic_vector(6 downto 0) := "1111001";
    constant C_L    : std_logic_vector(6 downto 0) := "1110001";
    constant C_N    : std_logic_vector(6 downto 0) := "1001000";
    constant C_O    : std_logic_vector(6 downto 0) := "0100011";
    constant C_P    : std_logic_vector(6 downto 0) := "0001100";
    constant C_Q    : std_logic_vector(6 downto 0) := "0011000";
    constant C_R    : std_logic_vector(6 downto 0) := "0101111";
    constant C_S    : std_logic_vector(6 downto 0) := "0010010";
    constant C_T    : std_logic_vector(6 downto 0) := "0111001";
    constant C_U    : std_logic_vector(6 downto 0) := "1100011";
    constant C_Y    : std_logic_vector(6 downto 0) := "0010001";
    constant C_DASH : std_logic_vector(6 downto 0) := "0111111";
    constant C_BLK  : std_logic_vector(6 downto 0) := "1111111";

    -- ===== 7-SEG DIGIT DECODE =====
    function decode_num(d : integer) return std_logic_vector;

    -- ===== WASH TIME CALCULATION =====
    -- prog: 00=Quick(20), 01=Normal(30), 1x=Heavy(50) base minutes
    -- wt  : laundry weight modifier
    function calc_wash_min(prog : std_logic_vector(1 downto 0);
                           wt   : std_logic_vector(1 downto 0))
        return integer;

    -- ===== AUTO SPIN TIME CALCULATION =====
    function calc_spin_auto(prog : std_logic_vector(1 downto 0);
                            wt   : std_logic_vector(1 downto 0))
        return integer;

    -- ===== MANUAL SPIN TIME CALCULATION =====
    -- Based on water level + temperature
    function calc_spin_manual(wlvl : std_logic_vector(1 downto 0);
                              temp : std_logic_vector(1 downto 0))
        return integer;

    -- ===== CLEANLINESS SCORE CALCULATION =====
    -- Inputs: temperature, water level, wash duration
    -- Output: score 1–9
    function calc_clean(temp   : std_logic_vector(1 downto 0);
                        wlvl   : std_logic_vector(1 downto 0);
                        wash_m : integer)
        return integer;

end package WM_pkg;

-- ============================================================
package body WM_pkg is

    function decode_num(d : integer) return std_logic_vector is
    begin
        case d is
            when 0 => return "1000000"; when 1 => return "1111001";
            when 2 => return "0100100"; when 3 => return "0110000";
            when 4 => return "0011001"; when 5 => return "0010010";
            when 6 => return "0000010"; when 7 => return "1111000";
            when 8 => return "0000000"; when 9 => return "0010000";
            when others => return "1111111";
        end case;
    end function;

    function calc_wash_min(prog : std_logic_vector(1 downto 0);
                           wt   : std_logic_vector(1 downto 0))
        return integer is
        variable base_t, result : integer;
    begin
        case prog is
            when "00"   => base_t := 20;
            when "01"   => base_t := 30;
            when others => base_t := 50;
        end case;
        case wt is
            when "00"   => result := (base_t * 8)  / 10;
            when "01"   => result :=  base_t;
            when "10"   => result := (base_t * 13) / 10;
            when others => result := (base_t * 16) / 10;
        end case;
        if result < 1 then result := 1; end if;
        return result;
    end function;

    function calc_spin_auto(prog : std_logic_vector(1 downto 0);
                            wt   : std_logic_vector(1 downto 0))
        return integer is
        variable base_t : integer;
    begin
        case prog is
            when "00"   => base_t := 10;
            when "01"   => base_t := 15;
            when others => base_t := 20;
        end case;
        case wt is
            when "00"   => return (base_t * 8)  / 10;
            when "01"   => return  base_t;
            when "10"   => return (base_t * 12) / 10;
            when others => return (base_t * 15) / 10;
        end case;
    end function;

    function calc_spin_manual(wlvl : std_logic_vector(1 downto 0);
                              temp : std_logic_vector(1 downto 0))
        return integer is
        variable base_t, bonus, result : integer;
    begin
        case wlvl is
            when "00"   => base_t := 5;
            when "01"   => base_t := 10;
            when "10"   => base_t := 15;
            when others => base_t := 20;
        end case;
        case temp is
            when "00"   => bonus := 0;
            when "01"   => bonus := 2;
            when "10"   => bonus := 4;
            when others => bonus := 6;
        end case;
        result := base_t + bonus;
        if result > 99 then result := 99; end if;
        return result;
    end function;

    function calc_clean(temp   : std_logic_vector(1 downto 0);
                        wlvl   : std_logic_vector(1 downto 0);
                        wash_m : integer)
        return integer is
        variable ts, ls, ws, raw, score : integer;
    begin
        case temp is
            when "00"   => ts := 1;
            when "01"   => ts := 2;
            when "10"   => ts := 3;
            when others => ts := 4;
        end case;
        case wlvl is
            when "00"   => ls := 1;
            when "01"   => ls := 2;
            when "10"   => ls := 3;
            when others => ls := 4;
        end case;
        if    wash_m <= 15 then ws := 1;
        elsif wash_m <= 30 then ws := 2;
        elsif wash_m <= 45 then ws := 3;
        else                    ws := 4;
        end if;
        raw   := ts + ls + ws;            -- range 3–12
        score := ((raw - 3) * 8) / 9 + 1; -- scale → 1–9
        if score < 1 then score := 1; end if;
        if score > 9 then score := 9; end if;
        return score;
    end function;

end package body WM_pkg;
