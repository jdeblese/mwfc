library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package driveseg_pkg is
	component driveseg
	Port(
		data : in STD_LOGIC_VECTOR (15 downto 0);
		seg_c : out STD_LOGIC_VECTOR (7 downto 0);
		seg_a : out std_logic_vector (3 downto 0);
		en : in std_logic_vector(3 downto 0);
		clk : in std_logic;
		rst : in std_logic);
	end component;
end package;


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.driveseg_pkg.all;

entity driveseg is
	Port ( data : in  STD_LOGIC_VECTOR (15 downto 0);
		seg_c : out STD_LOGIC_VECTOR (7 downto 0);
		seg_a : out std_logic_vector (3 downto 0);
		en : in std_logic_vector(3 downto 0);
		clk : in std_logic;
		rst : in std_logic);
end driveseg;

architecture Behavioral of driveseg is
	signal latch : std_logic_vector(data'range);
	signal active, active_new : std_logic_vector(seg_a'range);
	signal cathode, cathode_new : std_logic_vector(seg_c'range);
	signal divider : unsigned(16 downto 0);
begin

	seg_a <= active;
	seg_c <= cathode;

	process(clk,rst)
		variable div,old : std_logic;
	begin
		if rst = '1' then
			latch <= (others => '0');
			active <= "1110";
			cathode <= (others => '0');
			divider <= (others => '0');
			old := '0';
		elsif rising_edge(clk) then
			div := divider(16);
			if old = '0' and div = '1' then
				active <= active_new;
				cathode <= cathode_new;
			end if;

			latch <= data;
			divider <= divider + "1";
			
			old := div;
		end if;
	end process;

	process(en,active,latch,cathode)
		variable digit : std_logic_vector(active'range);
		variable segen : std_logic;
		
		variable active_next : std_logic_vector(active'range);
		variable cathode_next : std_logic_vector(cathode'range);
	begin
	
		active_next := active(active'high-1 downto 0) & active(active'high);
		cathode_next := cathode;
		
		-- Turn off dots
		cathode_next(7) := '1';
		-- Extract the current digit
		case active_next is
			when "1110" => digit := latch( 3 downto  0);
			when "1101" => digit := latch( 7 downto  4);
			when "1011" => digit := latch(11 downto  8);
			when "0111" => digit := latch(15 downto 12);
			when others => digit := "0000";
		end case;
		-- Check if the current digit is active
		segen := (not active_next(3) and en(3)) or (not active_next(2) and en(2)) or (not active_next(1) and en(1)) or (not active_next(0) and en(0));
		-- Drive the segment cathode based on the given digit
		if segen = '1' then
			case digit is
				when "0000" => cathode_next(6 downto 0) := "1000000";
				when "0001" => cathode_next(6 downto 0) := "1111001";
				when "0010" => cathode_next(6 downto 0) := "0100100";
				when "0011" => cathode_next(6 downto 0) := "0110000";
				when "0100" => cathode_next(6 downto 0) := "0011001";
				when "0101" => cathode_next(6 downto 0) := "0010010";
				when "0110" => cathode_next(6 downto 0) := "0000010";
				when "0111" => cathode_next(6 downto 0) := "1111000";
				when "1000" => cathode_next(6 downto 0) := "0000000";
				when "1001" => cathode_next(6 downto 0) := "0010000";
				when "1010" => cathode_next(6 downto 0) := "0001000";
				when "1011" => cathode_next(6 downto 0) := "0000011";
				when "1100" => cathode_next(6 downto 0) := "1000110";
				when "1101" => cathode_next(6 downto 0) := "0100001";
				when "1110" => cathode_next(6 downto 0) := "0000110";
				when "1111" => cathode_next(6 downto 0) := "0001110";
				when others => cathode_next(6 downto 0) := "0111111";
			end case;
		else
			cathode_next(6 downto 0) := "0111111";
		end if;
		
		active_new <= active_next;
		cathode_new <= cathode_next;
	end process;

end Behavioral;

