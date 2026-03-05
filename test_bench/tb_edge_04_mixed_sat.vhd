-- ============================================================
-- TESTBENCH CASO LIMITE 4: OP=00 con mix di priorita' (alcune gia' a 3)
-- Descrizione: Lista con task a P=2 e P=3.
--   Dopo OP=00: i task P=2 diventano P=3, quelli gia' a P=3
--   restano P=3. L'ordine relativo NON cambia (nessun riordino).
-- Encoding: ID=5 P=2 -> 000101|10 = 00010110
--           ID=6 P=3 -> 000110|11 = 00011011
--           ID=7 P=3 -> 000111|11 = 00011111
-- Dopo OP=00:
--   ID=5 P=2->3: 000101|11 = 00010111
--   ID=6 P=3:    invariato = 00011011
--   ID=7 P=3:    invariato = 00011111
-- Perche': Verifica saturazione per-task e assenza di riordino.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity project_tb is
end project_tb;

architecture project_tb_arch of project_tb is
    constant CLOCK_PERIOD : time := 20 ns;
    signal tb_clk : std_logic := '0';
    signal tb_rst, tb_start, tb_done : std_logic;
    signal tb_o_task_id : std_logic_vector(5 downto 0);
    signal tb_task_priority, tb_op : std_logic_vector(1 downto 0);
    signal tb_i_task_id : std_logic_vector(5 downto 0);

    signal tb_o_mem_addr, exc_o_mem_addr, init_o_mem_addr : std_logic_vector(15 downto 0);
    signal tb_o_mem_data, exc_o_mem_data, init_o_mem_data : std_logic_vector(7 downto 0);
    signal tb_i_mem_data : std_logic_vector(7 downto 0);
    signal tb_o_mem_we, tb_o_mem_en, exc_o_mem_we, exc_o_mem_en, init_o_mem_we, init_o_mem_en : std_logic;

    type ram_type is array (65535 downto 0) of std_logic_vector(7 downto 0);
    signal RAM : ram_type := (OTHERS => "00000000");

    type scenario_config_type_t is record
        task_id : std_logic_vector(5 downto 0);
        task_priority : std_logic_vector(1 downto 0);
        op : std_logic_vector(1 downto 0);
    end record scenario_config_type_t;

    constant SCENARIO_SIZE : integer := 4;
    type scenario_config_type is array (0 to SCENARIO_SIZE-1) of scenario_config_type_t;

    signal scenario_config : scenario_config_type := (
        (task_id => "000101", task_priority => "10", op => "10"), -- Insert ID=5 P=2
        (task_id => "000110", task_priority => "11", op => "10"), -- Insert ID=6 P=3
        (task_id => "000111", task_priority => "11", op => "10"), -- Insert ID=7 P=3
        (task_id => "000000", task_priority => "00", op => "00")  -- OP=00: P=2->P=3 (sat), P=3 invariato
    );

    type scenario_single_result_type is array (0 to 32) of std_logic_vector(7 downto 0);
    type scenario_result_type is array (0 to 100) of scenario_single_result_type;
    type int_array_t is array (0 to SCENARIO_SIZE - 1) of integer;
    constant CHECK_SIZE_ARRAY : int_array_t := (
        2, 3, 4, 4
    );

    signal scenario_result : scenario_result_type := (
        -- After insert ID=5 P=2: count=1, RAM[1]=00010110
        ("00000001", "00010110", others => "00000000"),
        -- After insert ID=6 P=3: count=2, RAM[2]=00011011
        ("00000010", "00010110", "00011011", others => "00000000"),
        -- After insert ID=7 P=3: count=3, RAM[3]=00011111
        ("00000011", "00010110", "00011011", "00011111", others => "00000000"),
        -- After OP=00: ID=5 P=2->3=00010111, ID=6 e ID=7 invariati
        ("00000011", "00010111", "00011011", "00011111", others => "00000000"),
        others => (others => "00000000")
    );

    signal memory_control : std_logic := '0';
    signal first_task_queue : std_logic_vector(5 downto 0);

    component project_reti_logiche is
        port (
        i_clk   : in std_logic;
        i_rst   : in std_logic;

        i_start         : in std_logic;
        i_task_id       : in std_logic_vector(5 downto 0);
        i_task_priority : in std_logic_vector(1 downto 0);
        i_op            : in std_logic_vector(1 downto 0);

        o_done    : out std_logic;
        o_task_id : out std_logic_vector(5 downto 0);

        o_mem_addr : out std_logic_vector(15 downto 0);
        i_mem_data : in  std_logic_vector(7 downto 0);
        o_mem_data : out std_logic_vector(7 downto 0);
        o_mem_we   : out std_logic;
        o_mem_en   : out std_logic
        );
    end component project_reti_logiche;

begin
    UUT : project_reti_logiche
    port map(
                i_clk           => tb_clk,
                i_rst           => tb_rst,
                i_start         => tb_start,
                i_task_id       => tb_i_task_id,
                i_task_priority => tb_task_priority,
                i_op            => tb_op,

                o_done    => tb_done,
                o_task_id => tb_o_task_id,

                o_mem_addr => exc_o_mem_addr,
                i_mem_data => tb_i_mem_data,
                o_mem_data => exc_o_mem_data,
                o_mem_we   => exc_o_mem_we,
                o_mem_en   => exc_o_mem_en
    );

    -- Clock generation
    tb_clk <= not tb_clk after CLOCK_PERIOD/2;

    -- Process related to the memory
    MEM : process (tb_clk)
    begin
        if tb_clk'event and tb_clk = '1' then
            if tb_o_mem_en = '1' then
                if tb_o_mem_we = '1' then
                    RAM(to_integer(unsigned(tb_o_mem_addr))) <= tb_o_mem_data after 1 ns;
                    tb_i_mem_data <= tb_o_mem_data after 1 ns;
                else
                    tb_i_mem_data <= RAM(to_integer(unsigned(tb_o_mem_addr))) after 1 ns;
                end if;
            end if;
        end if;
    end process;

    memory_signal_swapper : process(memory_control, init_o_mem_addr, init_o_mem_data,
                                    init_o_mem_en,  init_o_mem_we,   exc_o_mem_addr,
                                    exc_o_mem_data, exc_o_mem_en, exc_o_mem_we)
    begin
        tb_o_mem_addr <= init_o_mem_addr;
        tb_o_mem_data <= init_o_mem_data;
        tb_o_mem_en   <= init_o_mem_en;
        tb_o_mem_we   <= init_o_mem_we;

        if memory_control = '1' then
            tb_o_mem_addr <= exc_o_mem_addr;
            tb_o_mem_data <= exc_o_mem_data;
            tb_o_mem_en   <= exc_o_mem_en;
            tb_o_mem_we   <= exc_o_mem_we;
        end if;
    end process;

    create_scenario : process
    begin
        wait for 50 ns;

        tb_start <= '0';
        tb_rst   <= '1';
        wait for 100 ns;
        tb_rst <= '0';
        memory_control <= '1';

        wait until tb_done = '0';

        assert RAM(0) = "00000000" report "TEST FALLITO @ OFFSET=0 expected=0 actual=" & integer'image(to_integer(unsigned(RAM(0)))) severity failure;

        wait until falling_edge(tb_clk);

        for i in 0 to SCENARIO_SIZE - 1 loop
            if i > 0 then
                first_task_queue <= scenario_result(i-1)(1)(7 downto 2);
            end if;
            tb_op            <= scenario_config(i).op;
            tb_i_task_id     <= scenario_config(i).task_id;
            tb_task_priority <= scenario_config(i).task_priority;
            tb_start         <= '1';

            wait until rising_edge(tb_done);

            if scenario_config(i).op = "01" then
                assert first_task_queue = tb_o_task_id report "TEST FALLITO @ STEP=" & integer'image(i) & " expected task_id=" & integer'image(to_integer(unsigned(first_task_queue))) & " actual task_id=" & integer'image(to_integer(unsigned(tb_o_task_id)));
            end if;

            for j in 0 to CHECK_SIZE_ARRAY(i) - 1 loop
                assert RAM(j) = scenario_result(i)(j)
                    report "TEST FALLITO @ STEP=" & integer'image(i) &
                           " OFFSET=" & integer'image(j) &
                           " expected=" & integer'image(to_integer(unsigned(scenario_result(i)(j)))) &
                           " actual=" & integer'image(to_integer(unsigned(RAM(j))));
            end loop;

            tb_start <= '0';
            wait until falling_edge(tb_done);
            wait until falling_edge(tb_clk);

            report "Test step " & integer'image(i) & " OK.";
        end loop;

        assert false report "Simulation Ended! TEST PASSATO (EDGE4: OP=00 mix P=2/P=3 no riordino)" severity failure;
    end process;

end architecture;
