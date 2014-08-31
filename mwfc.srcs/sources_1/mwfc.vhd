library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity mwfc is
    Generic (
        precision : integer := 13;
        measureinterval : integer := 8191 );  -- FIXME 2**precision - 1
    Port (
        rawfrq : out unsigned(precision downto 0);
        bcdfrq : out std_logic_vector(15 downto 0);
        ord : out signed(7 downto 0);
        overflow : out std_logic;
        clk : in std_logic;
        clk2 : in std_logic;
        rst : in std_logic );
end mwfc;

architecture Behavioral of mwfc is

    constant inputbits : integer := precision + 5;
    constant timerbits : integer := 18;
    constant nscalestages : integer := 6;  -- FIXME log2 of maxscalefactor

    signal tcount, isync1 : unsigned(timerbits-1 downto 0);
    signal icount, isync0 : unsigned(inputbits-1 downto 0);
    
    signal scaling : signed(nscalestages-1 downto 0);

    signal ratio : unsigned(precision-1 downto 0);
    
    signal divbusy, divoverflow, divstrobe : std_logic;

    signal baseconvstrobe : std_logic;

	signal final : unsigned(precision downto 0);
	signal order : signed(7 downto 0);

    type A is array (0 to 31) of integer;
    constant digits : A := (
        0, 0, 0, 0, 0, 0, 0, 0, 0,
        2,           -- 2^9
        3, 3, 3, 3,  -- 2^10 to 2^13
        4, 4, 4,     -- 2^14 to 2^16
        5, 5, 5,     -- 2^17 to 2^19
        6, 6, 6, 6,  -- 2^20 to 2^23
        7, 7, 7,     -- 2^24 to 2^26
        8, 8, 8,     -- 2^27 to 2^29
        9, 9 );      -- 2^30 to 2^31
	type B is array(0 to 31) of unsigned(precision + 2 downto 0);
	constant corrections : B := (
		x"0000", x"0000", x"0000", x"0000", x"0000", x"0000", x"0000", x"0000", x"0000",
		x"3200",
		x"FA00", x"7D00", x"3E80", x"1F40",
		x"9C40", x"4E20", x"2710",
		x"C350", x"61A8", x"30D4",
		x"F424", x"7A12", x"3D09", x"1E85",
		x"9897", x"4C4B", x"2626",
		x"BEBC", x"5F5E", x"2FAF",
		x"EE6B", x"7736" );

    signal bcd : std_logic_vector(15 downto 0);
begin

    ord <= order;
    bcdfrq <= bcd;
    rawfrq <= final;
    overflow <= divoverflow;

    conv : entity work.hex2bcd
        generic map (
            precision => final'length,
            width => 16,
            bits => 4 )
        port map (
            hex => final,
            bcd => bcd,
            strobe => baseconvstrobe,
            rst => rst,
            clk => clk );

	process(clk,rst)
        variable C0 : unsigned(corrections(0)'range);
		variable S0 : integer;
		variable F1, F2, F3 : unsigned(ratio'length + corrections(0)'length - 1 downto 0);
        variable O1, O2 : signed(order'range);
        variable divstate : std_logic;
        variable bcstrobe : std_logic_vector(3 downto 0);  -- 4-stage pipeline
	begin
        if rst = '1' then
            S0 := 0;
            C0 := (others => '0');
            divstate := '0';
            bcstrobe := (others => '0');
            baseconvstrobe <= '0';
        elsif rising_edge(clk) then
            -- Pipeline stage 3
            --   Shift and round the final value
			if divoverflow = '0' then
				F3 := shift_right(F2, 4);
				-- Round based on highest truncated bit
                if F2(0) = '1' then
					final <= F3(final'high+1 downto 1) + "1";
				else
					final <= F3(final'high+1 downto 1);
				end if;
			end if;
            order <= O2;

            -- Pipeline stage 2
            --   Check if an additional scaling factor is needed
			if divoverflow = '0' then
                -- This comparison will give a warning at the start of a simulation due to F1 being unknown
				if F1 < shift_left(to_unsigned(1000, F1'length),5) then
                    -- Five bits, because four bits precision + 1 rounding
                    -- Multiply by 10 (8 + 2)
					F2 := shift_left(F1,1) + shift_left(F1,3);
					O2 := O1 - 1;
                else
                    F2 := F1;
                    O2 := O1;
				end if;
			end if;

            -- Pipeline stage 1
            --   Compute the base-10 exponent and mantissa
            O1 := to_signed(8, order'length) - digits(S0);  -- Get fp base-10 exponent
			if divoverflow = '0' then
                -- the values in 'corrections' are shifted up precision+3 bits
                -- Multiply is a slow operation
				F1 := shift_right(ratio * C0, precision + 3 - 1 - 4);
            end if;

            -- Pipeline stage 0
            --   Look up certain values
            S0 := -to_integer(scaling);  -- Floating-point base-2 exponent
            C0 := corrections(S0);

            -- Misc.
            if divstate = '1' and divbusy = '0' then
                bcstrobe := bcstrobe(bcstrobe'high-1 downto 0) & '1';
            else
                bcstrobe := bcstrobe(bcstrobe'high-1 downto 0) & '0';
            end if;
            divstate := divbusy;
            baseconvstrobe <= bcstrobe(bcstrobe'high);
		end if;
	end process;


	-- Count the number of timer and input tics in the given
	-- measurement interval, taking a whole number of input tics.
    stage1 : entity work.counter
        generic map (
            Tlen => tcount'length,
            ILen => icount'length,
            measureinterval => measureinterval )
        port map (
            timer => clk,
            input => clk2,
            tcount => tcount,
            icount => icount,
            enable => '1',
            strobe => divstrobe,
            rst => rst);

    -- Synchronize the reciprocal counter to the 'clk' clock domain
    process(clk)
    begin
        if rising_edge(clk) then
            isync1 <= (others => '0');
            isync1(isync0'range) <= isync0;
            isync0 <= icount;
        end if;
    end process;

    -- Divide M by N
    stage2 : entity work.fpdiv
        generic map (
            size => tcount'length,
            precision => ratio'length,
            pscale => scaling'length )
        port map (
            dividend => isync1,
            divisor => tcount,
            quotient => ratio,
            scale => scaling,
            busy => divbusy,
            overflow => divoverflow,
            strobe => divstrobe,
            clk => clk,
            rst => rst );

end Behavioral;

