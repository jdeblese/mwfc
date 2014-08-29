library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity counter is
    Generic ( Tlen : integer;
              Ilen : integer;
              measureinterval : integer );
    Port ( timer : in STD_LOGIC;
           input : in STD_LOGIC;
           tcount : out UNSIGNED (Tlen-1 downto 0);
           icount : out UNSIGNED (Ilen-1 downto 0);
--           overflow : out STD_LOGIC;
           enable : in STD_LOGIC;
           strobe : out STD_LOGIC;
           rst : in  STD_LOGIC);
end counter;

architecture Behavioral of counter is
    type states is (ST_WAIT, ST_COUNTING, ST_FINISHING, ST_OVERFLOW);

    -- *** input-based signals ***
    signal input_en, input_en_next : std_logic;
    signal M : unsigned (icount'range);
    signal icount_int, icount_next : unsigned (icount'range);  -- Main counter

    signal iover, iover_next : std_logic;  -- Overflow of the 'input' counter

    signal istate, istate_next : states;

    -- *** timer-based signals ***
    signal timer_en, timer_en_next : std_logic;
    signal N : unsigned (tcount'range);
    signal tcount_int, tcount_next : unsigned (tcount'range);  -- Main counter
    signal sync_ien : std_logic_vector(1 downto 0);  -- Synchronizer for 'input_en'
    signal tover, tover_next: std_logic;  -- Overflow of the 'timer' counter

    signal tstate, tstate_next : states;

    signal done, done_next : std_logic;
    signal strobe_next : std_logic;

begin

    icount <= icount_int;
    tcount <= tcount_int;

--    overflow <= tover or iover;

    -- 'input_en' needs to be available in the 'timer' domain so that
    -- the 'timer' counter knows when to start and stop counting
    process(rst,timer)
    begin
        if rst = '1' then
            sync_ien <= (others => '0');
        elsif rising_edge(timer) then
            sync_ien <= sync_ien(0) & input_en;
        end if;
    end process;

    -- Main FSM-type programming of the counter
    comb : process(enable, input_en, sync_ien, icount_int, timer_en, tcount_int, done, M, N, tover, iover, istate, tstate)
        variable input_en_new, timer_en_new, done_new : std_logic;
        variable tover_new, iover_new : std_logic;
        variable istate_new, tstate_new : states;
    begin
        input_en_new := input_en;
        timer_en_new := timer_en;
        done_new := done;
        
        tcount_next <= tcount_int;
        icount_next <= icount_int;

        tover_new := tover;
        iover_new := iover;

        strobe_next <= '0';

        istate_new := istate;
        tstate_new := tstate;
        
        case istate is
            when ST_WAIT =>
                -- DANGER: crosses clock domain
                --     'timer_en' and 'done' is in the 'timer' domain
                if timer_en = '0' and done = '0' then
                    istate_new := ST_COUNTING;
                    -- 'input' couter is started on rising edge of 'input'
                    input_en_new := '1';
                end if;
            when ST_COUNTING =>
                -- On overflow, turn off counter and wait for timer to stop
                if M + "1" = "0" then
                    istate_new := ST_OVERFLOW;
                end if;
                -- DANGER: crosses clock domain
                --     input done is in the 'timer' domain
                if done = '1' then
                    istate_new := ST_WAIT;
                    input_en_new := '0';     -- Disable the counter
                    icount_next <= M + "1";  -- Latch out the counter result
                    iover_new := '0';        -- Clear any overflow
                end if;
            when ST_OVERFLOW =>
                iover_new := '1';
                input_en_new := '0';     -- Disable the counter
                istate_new := ST_WAIT;
            when others =>
        end case;

        case tstate is
            when ST_WAIT =>
                done_new := '0';
                if sync_ien(1) = '1' then
                    tstate_new := ST_COUNTING;
                    -- 'timer' couter is started on rising edge of 'timer'
                    timer_en_new := '1';
                end if;
            when ST_COUNTING =>
                if N + "1" = "0" then
                    tstate_new := ST_OVERFLOW;
                end if;
                -- Indicate when the minimum measurement interval has been reached
                -- Subtract 2 tics to compensate for the 'input_en' synchronizer
                if N = to_unsigned(measureinterval - 2, N'length) then
                    tstate_new := ST_FINISHING;
                    done_new := '1';
                end if;
            when ST_FINISHING =>
                if N + "1" = "0" then
                    tstate_new := ST_OVERFLOW;
                end if;
                -- If the timer's off, signal done and valid output
                if timer_en = '0' then
--                  done_new := '0';
                    strobe_next <= '1';
                    tstate_new := ST_WAIT;
                -- Otherwise, turn off the timer when the input counter is off
                elsif sync_ien(1) = '0' then
                    timer_en_new := '0';     -- Disable the counter
                    tcount_next <= N + "1";  -- Latch out the counter result
                    tover_new := '0';        -- Clear any overflow
                end if;
            when ST_OVERFLOW =>
                timer_en_new := '0';     -- Disable the counter
                tover_new := '1';
                done_new := '1';
                if sync_ien(1) = '0' then
                    strobe_next <= '1';
                    tstate_new := ST_WAIT;
                end if;
            when others =>
        end case;

        input_en_next <= input_en_new;
        timer_en_next <= timer_en_new;
        done_next <= done_new;
        tover_next <= tover_new;
        iover_next <= iover_new;
        istate_next <= istate_new;
        tstate_next <= tstate_new;
    end process;

    -- Processes synchronous to the 'timer' clock
    tmem : process(rst, timer)
    begin
        if rst = '1' then
            timer_en <= '0';
            done <= '0';
            N <= (others => '0');
            tcount_int <= (others => '1');  -- Nonzero, avoids 1/0 fault
            tover <= '0';
            strobe <= '0';
            tstate <= ST_WAIT;
        elsif rising_edge(timer) then
            if timer_en = '1' then
                N <= N + "1";
            else
                N <= (others => '0');
            end if;
            timer_en <= timer_en_next;
            done <= done_next;
            tcount_int <= tcount_next;
            tover <= tover_next;
            strobe <= strobe_next;
            tstate <= tstate_next;
        end if;
    end process;

    -- Processes synchronous to the 'input' clock
    imem : process(rst, input)
    begin
        if rst = '1' then
            input_en <= '0';
            M <= (others => '0');
            icount_int <= (others => '0');
            iover <= '0';
            istate <= ST_WAIT;
        elsif rising_edge(input) then
            if input_en = '1' then
                M <= M + "1";
            else
                M <= (others => '0');
            end if;
            input_en <= input_en_next;
            icount_int <= icount_next;
            iover <= iover_next;
            istate <= istate_next;
        end if;
    end process;

end Behavioral;
