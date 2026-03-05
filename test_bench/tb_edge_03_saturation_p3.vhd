-- ============================================================
-- TESTBENCH CASO LIMITE 3: OP=00 con tutti i task a priorita' 3
-- Descrizione: Lista con 3 task, tutti a PRIORITY=3.
--   L'incremento di priorita' deve saturare: tutti rimangono
--   a priorita' 3 e i valori in memoria non cambiano (bit bassi).
-- Memoria iniziale (costruita con inserimenti):
--   RAM[0] = 3
--   RAM[1] = ID=1, P=3 -> 00000111
--   RAM[2] = ID=2, P=3 -> 00001011
--   RAM[3] = ID=3, P=3 -> 00001111
-- Dopo OP=00: identica (saturazione a 3)
-- Perche': Verifica che la logica "min(priority+1, 3)" funzioni
--   correttamente e non produca overflow/wrap-around.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
    signal tb_o_mem_we, tb_o_mem_en,
           exc_o_mem_we, exc_o_mem_en,
           init_o_mem_we, init_o_mem_en : std_logic;

    type ram_type is array (65535 downto 0) of std_logic_vector(7 downto 0);
    signal RAM : ram_type := (others => "00000000");
    signal memory_control : std_logic := '0';

    -- Scenario: 4 step
    -- Step 0: insert ID=1 P=3
    -- Step 1: insert ID=2 P=3
    -- Step 2: insert ID=3 P=3
    -- Step 3: OP=00 -> all stay at P=3
    constant SCENARIO_SIZE : integer := 4;

    type scenario_config_t is record
        task_id       : std_logic_vector(5 downto 0);
        task_priority : std_logic_vector(1 downto 0);
        op            : std_logic_vector(1 downto 0);
    end record;
    type scenario_config_type is array (0 to SCENARIO_SIZE-1) of scenario_config_t;

    signal scenario_config : scenario_config_type := (
        (task_id => "000001", task_priority => "11", op => "10"), -- Insert ID=1 P=3
        (task_id => "000010", task_priority => "11", op => "10"), -- Insert ID=2 P=3
        (task_id => "000011", task_priority => "11", op => "10"), -- Insert ID=3 P=3
        (task_id => "000000", task_priority => "00", op => "00")  -- OP=00: saturate at P=3
    );

    type single_result_t is array (0 to 10) of std_logic_vector(7 downto 0);
    type scenario_result_type is array (0 to SCENARIO_SIZE-1) of single_result_t;
    type int_array_t is array (0 to SCENARIO_SIZE-1) of integer;

    constant CHECK_SIZE_ARRAY : int_array_t := (2, 3, 4, 4);

    signal scenario_result : scenario_result_type := (
        -- After insert ID=1 P=3: count=1, [00000111]
        ("00000001", "00000111", others => "00000000"),
        -- After insert ID=2 P=3: count=2, [00000111, 00001011]
        ("00000010", "00000111", "00001011", others => "00000000"),
        -- After insert ID=3 P=3: count=3, [00000111, 00001011, 00001111]
        ("00000011", "00000111", "00001011", "00001111", others => "00000000"),
        -- After OP=00 (saturate): same, all stay P=3
        ("00000011", "00000111", "00001011", "00001111", others => "00000000")
    );

    component project_reti_logiche is
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
    end component project_reti_logiche;

begin
    UUT : project_reti_logiche
        port map (
            i_clk           => tb_clk,
            i_rst           => tb_rst,
            i_start         => tb_start,
            i_task_id       => tb_i_task_id,
            i_task_priority => tb_task_priority,
            i_op            => tb_op,
            o_done          => tb_done,
            o_task_id       => tb_o_task_id,
            o_mem_addr      => exc_o_mem_addr,
            i_mem_data      => tb_i_mem_data,
            o_mem_data      => exc_o_mem_data,
            o_mem_we        => exc_o_mem_we,
            o_mem_en        => exc_o_mem_en
        );

    tb_clk <= not tb_clk after CLOCK_PERIOD / 2;

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

    memory_signal_swapper : process (memory_control,
                                      init_o_mem_addr, init_o_mem_data, init_o_mem_en, init_o_mem_we,
                                      exc_o_mem_addr,  exc_o_mem_data,  exc_o_mem_en,  exc_o_mem_we)
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
        tb_rst   <= '0';
        memory_control <= '1';
        wait until tb_done = '0';

        assert RAM(0) = "00000000"
            report "EDGE3 FALLITO: dopo reset RAM[0] != 0" severity failure;

        wait until falling_edge(tb_clk);

        for i in 0 to SCENARIO_SIZE - 1 loop
            tb_op            <= scenario_config(i).op;
            tb_i_task_id     <= scenario_config(i).task_id;
            tb_task_priority <= scenario_config(i).task_priority;
            tb_start         <= '1';

            wait until rising_edge(tb_done);

            for j in 0 to CHECK_SIZE_ARRAY(i) - 1 loop
                assert RAM(j) = scenario_result(i)(j)
                    report "EDGE3 FALLITO @ STEP=" & integer'image(i) &
                           " OFFSET=" & integer'image(j) &
                           " expected=" & integer'image(to_integer(unsigned(scenario_result(i)(j)))) &
                           " actual=" & integer'image(to_integer(unsigned(RAM(j))))
                    severity failure;
            end loop;

            tb_start <= '0';
            wait until falling_edge(tb_done);
            wait until falling_edge(tb_clk);
            report "EDGE3 Step " & integer'image(i) & " OK.";
        end loop;

        report "EDGE3 OK: OP=00 satura correttamente a priorita' 3";
        assert false report "Simulation Ended! EDGE3 PASSATO" severity failure;
    end process;

end architecture;
