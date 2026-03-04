library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity project_reti_logiche is
    port (
        i_clk           : in  std_logic;
        i_rst           : in  std_logic;
        i_start         : in  std_logic;
        i_task_id       : in  std_logic_vector(5 downto 0);
        i_task_priority : in  std_logic_vector(1 downto 0);
        i_op            : in  std_logic_vector(1 downto 0);
        o_done          : out std_logic;
        o_task_id       : out std_logic_vector(5 downto 0);
        o_mem_addr      : out std_logic_vector(15 downto 0);
        i_mem_data      : in  std_logic_vector(7 downto 0);
        o_mem_data      : out std_logic_vector(7 downto 0);
        o_mem_we        : out std_logic;
        o_mem_en        : out std_logic
    );
end project_reti_logiche;

architecture Behavioral of project_reti_logiche is

    type state_type is (
        S_RESET, S_INIT_MEM, S_IDLE,
        S_FETCH_SIZE, S_WAIT_FETCH, S_DECODE,
        -- OP00
        S_OP00_READ, S_OP00_WAIT, S_OP00_MODIFY, S_OP00_CHECK_EMPTY,
        -- OP01
        S_OP01_CHECK_EMPTY, S_OP01_FORCE_ZERO,
        S_OP01_READ_FIRST, S_OP01_WAIT_FIRST, S_OP01_SAVE,
        S_OP01_SHIFT_READ, S_OP01_WAIT_SHIFT, S_OP01_SHIFT_WRITE,
        S_OP01_UPDATE,
        -- OP10
        S_OP10_CHECK_EMPTY,
        S_OP10_FIND_READ, S_OP10_FIND_WAIT, S_OP10_FIND_EVAL,
        S_OP10_CHECK_SHIFT,
        S_OP10_SHIFT_READ, S_OP10_SHIFT_WAIT, S_OP10_SHIFT_WRITE,
        S_OP10_INSERT, S_OP10_UPDATE_SIZE,
        -- OP11
        S_OP11_CLEAR,
        S_DONE
    );

    signal current_state : state_type;
    signal next_state    : state_type;

    -- Registri del datapath
    signal num_tasks    : unsigned(7 downto 0);
    signal current_addr : unsigned(15 downto 0);
    signal target_addr  : unsigned(15 downto 0);
    signal extracted_id : std_logic_vector(5 downto 0);
    signal mem_latch    : std_logic_vector(7 downto 0);

    -- Segnali "next" del datapath
    signal next_num_tasks    : unsigned(7 downto 0);
    signal next_current_addr : unsigned(15 downto 0);
    signal next_target_addr  : unsigned(15 downto 0);
    signal next_extracted_id : std_logic_vector(5 downto 0);
    signal next_mem_latch    : std_logic_vector(7 downto 0);

begin

    -- PROCESSO 1: Registro di stato
    state_reg: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            current_state <= S_RESET;
        elsif rising_edge(i_clk) then
            current_state <= next_state;
        end if;
    end process;

    -- PROCESSO 2: Registri datapath
    datapath_regs: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            num_tasks    <= (others => '0');
            current_addr <= (others => '0');
            target_addr  <= (others => '0');
            extracted_id <= (others => '0');
            mem_latch    <= (others => '0');
        elsif rising_edge(i_clk) then
            num_tasks    <= next_num_tasks;
            current_addr <= next_current_addr;
            target_addr  <= next_target_addr;
            extracted_id <= next_extracted_id;
            mem_latch    <= next_mem_latch;
        end if;
    end process;

    -- PROCESSO 3: UNICO processo combinatorio
    -- Guida tutti i segnali "next" e tutte le uscite.
    -- Un solo driver per ogni segnale => nessun errore multi-driven.
    comb: process(current_state, i_start, i_op,
                  i_task_id, i_task_priority,
                  num_tasks, current_addr, target_addr,
                  extracted_id, mem_latch, i_mem_data)
    begin
        -- Default
        next_state        <= current_state;
        next_num_tasks    <= num_tasks;
        next_current_addr <= current_addr;
        next_target_addr  <= target_addr;
        next_extracted_id <= extracted_id;
        next_mem_latch    <= i_mem_data; -- aggiorna latch ogni ciclo

        o_done     <= '0';
        o_mem_en   <= '0';
        o_mem_we   <= '0';
        o_mem_addr <= (others => '0');
        o_mem_data <= (others => '0');
        o_task_id  <= extracted_id;

        case current_state is

            when S_RESET =>
                o_done     <= '1';
                next_state <= S_INIT_MEM;

            when S_INIT_MEM =>
                o_done     <= '1';
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= (others => '0');
                o_mem_data <= (others => '0');
                next_state <= S_IDLE;

            when S_IDLE =>
                if i_start = '1' then
                    next_state <= S_FETCH_SIZE;
                end if;

            when S_FETCH_SIZE =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= (others => '0');
                next_state <= S_WAIT_FETCH;

            when S_WAIT_FETCH =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= (others => '0');
                -- mem_latch si aggiorna via default (next_mem_latch <= i_mem_data)
                next_state <= S_DECODE;

            when S_DECODE =>
                -- mem_latch contiene ora il valore di addr=0
                next_num_tasks    <= unsigned(mem_latch);
                next_current_addr <= to_unsigned(1, 16);
                next_target_addr  <= (others => '0');
                next_extracted_id <= (others => '0');
                if    i_op = "00" then next_state <= S_OP00_CHECK_EMPTY;
                elsif i_op = "01" then next_state <= S_OP01_CHECK_EMPTY;
                elsif i_op = "10" then next_state <= S_OP10_CHECK_EMPTY;
                elsif i_op = "11" then next_state <= S_OP11_CLEAR;
                else                   next_state <= S_DONE;
                end if;

            -- -----------------------------------------------
            -- OP00: incrementa valore priorità (satura a 3)
            -- -----------------------------------------------
            when S_OP00_CHECK_EMPTY =>

                next_extracted_id <= (others => '0');
                next_target_addr  <= (others => '0');

                if num_tasks = "00000000" then
                    next_current_addr <= to_unsigned(1, 16);
                    next_state <= S_DONE;
                else
                    next_state <= S_OP00_READ;
                end if;

                    
            when S_OP00_READ =>
                if num_tasks = 0 then
                    next_state <= S_DONE;
                else
                    o_mem_en   <= '1';
                    o_mem_we   <= '0';
                    o_mem_addr <= std_logic_vector(current_addr);
                    next_state <= S_OP00_WAIT;
                end if;

            when S_OP00_WAIT =>
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP00_MODIFY;

            when S_OP00_MODIFY =>
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(current_addr);
                if mem_latch(1 downto 0) = "11" then
                    o_mem_data <= mem_latch(7 downto 2) & "11";
                else
                    o_mem_data <= mem_latch(7 downto 2) &
                                  std_logic_vector(unsigned(mem_latch(1 downto 0)) + 1);
                end if;
                next_current_addr <= current_addr + 1;
                if current_addr >= resize(num_tasks, 16) then
                    next_state <= S_DONE;
                else
                    next_state <= S_OP00_READ;
                end if;

            -- -----------------------------------------------
            -- OP01: rimuovi primo task
            -- -----------------------------------------------

            when S_OP01_CHECK_EMPTY =>
                if num_tasks = 0 then
                    next_state <= S_OP01_FORCE_ZERO;
                else
                    next_state <= S_OP01_READ_FIRST;
                end if;

            when S_OP01_FORCE_ZERO =>
                next_extracted_id <= (others => '0');
                next_state        <= S_DONE;

            when S_OP01_READ_FIRST =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(to_unsigned(1, 16));
                next_state <= S_OP01_WAIT_FIRST;

            when S_OP01_WAIT_FIRST =>
                o_mem_addr <= std_logic_vector(to_unsigned(1, 16));
                next_state <= S_OP01_SAVE;

            when S_OP01_SAVE =>
                next_extracted_id <= mem_latch(7 downto 2);
                next_current_addr <= to_unsigned(2, 16);
                if num_tasks = 1 then
                    next_state <= S_OP01_UPDATE;
                else
                    next_state <= S_OP01_SHIFT_READ;
                end if;

            when S_OP01_SHIFT_READ =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP01_WAIT_SHIFT;

            when S_OP01_WAIT_SHIFT =>
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP01_SHIFT_WRITE;

            when S_OP01_SHIFT_WRITE =>
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(current_addr - 1);
                o_mem_data <= mem_latch;
                next_current_addr <= current_addr + 1;
                if current_addr >= resize(num_tasks, 16) then
                    next_state <= S_OP01_UPDATE;
                else
                    next_state <= S_OP01_SHIFT_READ;
                end if;

            when S_OP01_UPDATE =>
                o_mem_en       <= '1';
                o_mem_we       <= '1';
                o_mem_addr     <= (others => '0');
                o_mem_data     <= std_logic_vector(num_tasks - 1);
                next_num_tasks <= num_tasks - 1;
                next_state     <= S_DONE;

            -- -----------------------------------------------
            -- OP10: inserisci nuovo task
            -- -----------------------------------------------

            when S_OP10_CHECK_EMPTY =>
                if num_tasks = 0 then
                    next_target_addr <= to_unsigned(1, 16);
                    next_state       <= S_OP10_INSERT;
                else
                    next_state <= S_OP10_FIND_READ;
                end if;

            when S_OP10_FIND_READ =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP10_FIND_WAIT;

            when S_OP10_FIND_WAIT =>
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP10_FIND_EVAL;

            when S_OP10_FIND_EVAL =>
                if current_addr > resize(num_tasks, 16) then
                    next_target_addr <= resize(num_tasks, 16) + 1;
                    next_state       <= S_OP10_CHECK_SHIFT;
                elsif mem_latch(1 downto 0) > i_task_priority then
                    next_target_addr <= current_addr;
                    next_state       <= S_OP10_CHECK_SHIFT;
                else
                    next_current_addr <= current_addr + 1;
                    next_state        <= S_OP10_FIND_READ;
                end if;

            when S_OP10_CHECK_SHIFT =>
                if target_addr > resize(num_tasks, 16) then
                    next_state <= S_OP10_INSERT;
                else
                    next_current_addr <= resize(num_tasks, 16);
                    next_state        <= S_OP10_SHIFT_READ;
                end if;

            when S_OP10_SHIFT_READ =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP10_SHIFT_WAIT;

            when S_OP10_SHIFT_WAIT =>
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP10_SHIFT_WRITE;

            when S_OP10_SHIFT_WRITE =>
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(current_addr + 1);
                o_mem_data <= mem_latch;
                if current_addr >= target_addr then
                    next_current_addr <= current_addr - 1;
                    next_state        <= S_OP10_SHIFT_READ;
                else
                    next_state <= S_OP10_INSERT;
                end if;

            when S_OP10_INSERT =>
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(target_addr);
                o_mem_data <= i_task_id & i_task_priority;
                next_state <= S_OP10_UPDATE_SIZE;

            when S_OP10_UPDATE_SIZE =>
                o_mem_en       <= '1';
                o_mem_we       <= '1';
                o_mem_addr     <= (others => '0');
                o_mem_data     <= std_logic_vector(num_tasks + 1);
                next_num_tasks <= num_tasks + 1;
                next_state     <= S_DONE;

            -- -----------------------------------------------
            -- OP11: svuota lista
            -- -----------------------------------------------

            when S_OP11_CLEAR =>
                o_mem_en       <= '1';
                o_mem_we       <= '1';
                o_mem_addr     <= (others => '0');
                o_mem_data     <= (others => '0');
                next_num_tasks <= (others => '0');
                next_state     <= S_DONE;

            -- -----------------------------------------------
            when S_DONE =>
                o_done    <= '1';
                o_task_id <= extracted_id;
                if i_start = '0' then
                    next_state <= S_IDLE;
                end if;

            when others =>
                next_state <= S_RESET;

        end case;
    end process;

end Behavioral;
