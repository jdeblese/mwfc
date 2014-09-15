library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity fpbaseconv is
	Generic (
		precision : integer := 13;
		exp_precision : integer := 8;
		nscalestages : integer := 7 );
	Port (
		mantissa : out unsigned(precision-1 downto 0);
		exponent : out signed(exp_precision-1 downto 0);
		busy : out std_logic;
		scaling : in signed(nscalestages-1 downto 0);
		ratio : in unsigned(precision-1 downto 0);
		strobe : in std_logic;
		clk : in std_logic;
		rst : in std_logic );
end fpbaseconv;

architecture Behavioral of fpbaseconv is

	type state_type is (ST_WAIT, ST_PRELOAD, ST_MULT, ST_SCALE, ST_ROUND);
	signal state, state_new : state_type;

	type A is array (0 to 35) of integer;
	constant digits : A := (
		0, 0, 0, 0,
		1, 1, 1,     -- 2^4 to 2^6
		2, 2, 2,     -- 2^7 to 2^9
		3, 3, 3, 3,  -- 2^10 to 2^13
		4, 4, 4,     -- 2^14 to 2^16
		5, 5, 5,     -- 2^17 to 2^19
		6, 6, 6, 6,  -- 2^20 to 2^23
		7, 7, 7,     -- 2^24 to 2^26
		8, 8, 8,     -- 2^27 to 2^29
		9, 9, 9, 9,  -- 2^30 to 2^33
		10, 10 );    -- 2^34 to 2^35
	type B is array(0 to 35) of unsigned(precision + 2 downto 0);
	constant corrections : B := (
		x"00000", x"80000", x"40000", x"20000",
		x"A0000", x"50000", x"28000",
		x"C8000", x"64000", x"32000",
		x"FA000", x"7D000", x"3E800", x"1F400",
		x"9C400", x"4E200", x"27100",
		x"C3500", x"61A80", x"30D40",
		x"F4240", x"7A120", x"3D090", x"1E848",
		x"98968", x"4C4B4", x"2625A",
		x"BEBC2", x"5F5E1", x"2FAF1",
		x"EE6B3", x"77359", x"3B9AD", x"1DCD6",
		x"95030", x"4A818" );

		signal corr_out : unsigned(corrections(0)'range);
		signal digit_out : signed(exponent'range);

		signal factor, factor_new : unsigned(ratio'range);
		signal shifter, shifter_new, accumulator, accumulator_new : unsigned(ratio'length + corrections(0)'length - 1 downto 0);
		signal exp, exp_new : signed(exponent'range);

		signal exponent_int, exponent_new : signed(exponent'range);
		signal mantissa_int, mantissa_new : unsigned(mantissa'range);
		signal busy_int, busy_new : std_logic;
begin

	mantissa <= mantissa_int;
	exponent <= exponent_int;
	busy     <= busy_int;

	process(clk,rst)
		variable S0 : integer;
	begin
		if rst = '1' then
			state <= ST_WAIT;
			busy_int <= '0';
		elsif rising_edge(clk) then
			S0 := -to_integer(scaling);  -- Floating-point base-2 exponent
			-- Multiplication factor to convert from base-2 to base-10 for
			-- the given base-2 exponent
			corr_out <= corrections(S0);
			digit_out <= to_signed(8, exponent'length) - digits(S0);  -- Get fp base-10 exponent

			state <= state_new;
			factor <= factor_new;
			shifter <= shifter_new;
			accumulator <= accumulator_new;
			exp <= exp_new;
			mantissa_int <= mantissa_new;
			exponent_int <= exponent_new;
			busy_int <= busy_new;
		end if;
	end process;

	process(state, strobe, ratio, corr_out, digit_out, factor, shifter, accumulator, exp, exponent_int, mantissa_int, busy_int)
		variable state_next : state_type;
		variable factor_next : unsigned(factor'range);
		variable shifter_next, accumulator_next : unsigned(shifter'range);
		variable exp_next : signed(exp'range);
	begin
		state_next       := state;
		factor_next      := factor;
		shifter_next     := shifter;
		accumulator_next := accumulator;
		exp_next         := exp;
		
		exponent_new <= exponent_int;
		mantissa_new <= mantissa_int;
		busy_new     <= busy_int;

		case state is
			when ST_WAIT =>
				if strobe = '1' then
					busy_new <= '1';
					state_next := ST_PRELOAD;
				end if;

			when ST_PRELOAD =>
				factor_next := ratio;
				shifter_next := (others => '0');
				accumulator_next := (others => '0');
				shifter_next(corr_out'range) := corr_out;
				exp_next := digit_out;

				state_next := ST_MULT;

			when ST_MULT =>
				factor_next := shift_right(factor, 1);
				shifter_next := shift_left(shifter, 1);
				if factor(0) = '1' then
					accumulator_next := accumulator + shifter;
				elsif factor = "0" then
					-- 'corrections' is fixed point, shifted over precision+3 bits
					-- Save one extra bit for rounding
					-- Save another four bits for a multiply by 10 if needed?
					-- Multiply is a slow operation
					accumulator_next := shift_right(accumulator, precision + 3 - 1 - 4);
					state_next := ST_SCALE;
				end if;

			when ST_SCALE =>
				-- FIXME this depends on BCD precision!
				if accumulator < shift_left(to_unsigned(10000, accumulator'length),4) then
					-- Five bits, because four bits precision + 1 rounding
					-- Multiply by 10 (8 + 2)
					accumulator_next := shift_left(accumulator,1) + shift_left(accumulator,3);
					exp_next := exp - 1;
				end if;

				state_next := ST_ROUND;

			when ST_ROUND =>
				-- Downshift by 4
				-- Round based on highest truncated bit
				if accumulator(4) = '1' then
					mantissa_new <= accumulator(mantissa'high+5 downto 5) + "1";
				else
					mantissa_new <= accumulator(mantissa'high+5 downto 5);
				end if;
				exponent_new <= exp;

				busy_new <= '0';
				state_next := ST_WAIT;

			when others =>
		end case;

		state_new       <= state_next;
		factor_new      <= factor_next;
		shifter_new     <= shifter_next;
		accumulator_new <= accumulator_next;
		exp_new         <= exp_next;
	end process;

end Behavioral;
