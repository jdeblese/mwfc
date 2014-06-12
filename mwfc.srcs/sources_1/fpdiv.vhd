library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Floating point divider
--
-- quotient * 2^scale = dividend / divisor
--
-- precision - number of bits in quotient
-- size - number of bits in dividiend and divisor
-- pscale - number of bits in scale
--
-- Scales divisor up until it is >= to dividend. Then loops,
-- scaling up dividend and subtracting divisor until precision
-- bits of quotient have been found. Detects overflows.
--
-- Output is valid on the clock edge after busy has gone low
--
-- Strobes are ignored while busy is high

entity fpdiv is
    Generic ( size : integer;
              precision : integer;
              pscale : integer );
    Port ( dividend : in UNSIGNED (size-1 downto 0);
           divisor : in UNSIGNED (size-1 downto 0);
           quotient : out UNSIGNED (precision-1 downto 0);
           scale : out SIGNED (pscale-1 downto 0);
           busy : out STD_LOGIC;
           overflow : out STD_LOGIC;
           strobe : in STD_LOGIC;
           clk : in STD_LOGIC;
           rst : in STD_LOGIC );
end fpdiv;

architecture Behavioral of fpdiv is
    type states is ( ST_WAIT, ST_PRESCALE, ST_DIV );
    signal state, state_new : states;

    signal dividend_int, dividend_new : unsigned (dividend'range);
    signal divisor_int, divisor_new : unsigned (divisor'range);
    signal quotient_int, quotient_new : unsigned (quotient'range);
    signal scale_int, scale_new : signed (scale'range);
    signal overflow_int, overflow_new : std_logic;
begin

--  scale <= scale_int;
--  quotient <= quotient_int;

    sync : process(clk,rst)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                quotient_int <= (others => '0');
                quotient <= (others => '0');
                scale_int <= (others => '0');
                scale <= (others => '0');
                overflow_int <= '0';
                overflow <= '0';
                state <= ST_WAIT;
            else
                state <= state_new;
                dividend_int <= dividend_new;
                divisor_int <= divisor_new;
                quotient_int <= quotient_new;
                scale_int <= scale_new;
                overflow_int <= overflow_new;
                -- Only change outputs when entering or in WAIT
                if state_new = ST_WAIT then
                    scale <= scale_new;
                    quotient <= quotient_new;
                    overflow <= overflow_new;
                end if;
            end if;
        end if;
    end process;

    comb : process(state, strobe, dividend, dividend_int, divisor, divisor_int, quotient_int, scale_int, overflow_int)
        variable dividend_next : unsigned (dividend'range);
        variable divisor_next : unsigned (divisor'range);
        variable quotient_next : unsigned (quotient'range);
        variable scale_next : signed (scale'range);
        variable overflow_next : std_logic;

        variable nextd : unsigned (dividend'range);
        variable nextq : unsigned (quotient'range);
    begin
        dividend_next := dividend_int;
        divisor_next := divisor_int;
        quotient_next := quotient_int;
        scale_next := scale_int;
        overflow_next := overflow_int;

        busy <= '1';

        state_new <= state;

        case state is
            when ST_WAIT =>
                busy <= '0';
                if strobe = '1' then
                    dividend_next := dividend;
                    divisor_next := divisor;
                    quotient_next := (others => '0');
                    scale_next := (others => '0');
                    overflow_next := '0';
                    state_new <= ST_PRESCALE;
                end if;

            -- Increases divisor until it is >= dividend
            when ST_PRESCALE =>
                if dividend_int > divisor_int then
                    -- First check for overflow conditions
                    assert divisor_int(divisor_int'high) /= '1'
                        report "divisor overflow" severity warning;
                    if divisor_int(divisor_int'high) = '1' then
                        overflow_next := '1';
                        state_new <= ST_WAIT;
                    end if;

                    divisor_next := shift_left(divisor_int, 1);

                    -- check for scale overflow
                    assert scale_int(scale_int'high) /= '1'
                        report "Here be dragons" severity error;
                    scale_next := scale_int + "01";
                    assert scale_next(scale_int'high) /= '1'
                        report "scale overflow" severity warning;
                    if scale_next(scale_int'high) = '1' then
                        overflow_next := '1';
                        state_new <= ST_WAIT;
                    end if;
                else
                    state_new <= ST_DIV;
                end if;

            -- Computes quotient by shifting dividend up and subtracting divisor
            WHEN ST_DIV =>
                if quotient_int(quotient_int'high) = '1' then
                    state_new <= ST_WAIT;
                    if dividend_int >= divisor_int then
                        dividend_next := dividend_int - divisor_int;
                        quotient_next(0) := '1';
                    end if;
                else
                    -- determine if subtraction must occur
                    if dividend_int < divisor_int then
                        nextd := dividend_int;
                        nextq := quotient_int;
                    else
                        nextd := dividend_int - divisor_int;
                        nextq := quotient_int + "1";
                    end if;
                    -- quotient can never overflow, due to the test above
                    -- dividend can never overflow, because divisor is always > (dividend / 2)
                    assert nextd(nextd'high) /= '1'
                        report "Here be dragons, dividend should not be able to overflow" severity error;
                    assert nextq(nextq'high) /= '1'
                        report "Here be dragons, quotient should not be able to overflow" severity error;

                    dividend_next := shift_left(nextd, 1);
                    quotient_next := shift_left(nextq, 1);

                    -- FIXME check for scale underflow
                    scale_next := scale_int - "01";
                    assert (scale_int(scale_int'high) /= '1' or scale_next(scale_next'high) = '1')
                        report "Scale underflow" severity warning;
                    if scale_int(scale_int'high) = '1' and scale_next(scale_next'high) = '0' then
                        overflow_next := '1';
                        state_new <= ST_WAIT;
                    end if;
                end if;

            when others =>
                state_new <= ST_WAIT;
        end case;

        dividend_new <= dividend_next;
        divisor_new <= divisor_next;
        quotient_new <= quotient_next;
        scale_new <= scale_next;
        overflow_new <= overflow_next;
    end process;

end Behavioral;
