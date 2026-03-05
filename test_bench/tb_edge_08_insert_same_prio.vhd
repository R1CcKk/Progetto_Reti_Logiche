-- ============================================================
-- TESTBENCH CASO LIMITE 8: OP=10 inserimento con stessa priorita'
-- Descrizione: Lista [A P=1, B P=1, C P=2]. Si inserisce D P=1.
--   D deve andare in CODA ai task a P=1, cioe' prima di C.
--   Risultato: [A P=1, B P=1, D P=1, C P=2]
-- Encoding:
--   ID=20 P=1 = 010100|01 = 01010001
--   ID=21 P=1 = 010101|01 = 01010101
--   ID=22 P=2 = 010110|10 = 01011010
--   ID=23 P=1 = 010111|01 = 01011101
-- Dopo insert ID=23 P=1:
--   RAM[0]=4
--   RAM[1]=01010001 (ID=20 P=1)
--   RAM[2]=01010101 (ID=21 P=1)
--   RAM[3]=01011101 (ID=23 P=1) <- D in coda ai P=1
--   RAM[4]=01011010 (ID=22 P=2)
-- Perche': La specifica dice "inserendolo in coda ai task a pari
--   priorita'". Questo e' critico per la correttezza dell'ordine FIFO
--   all'interno di una stessa priorita'.
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

    -- Steps:
    -- 0: insert ID=20 P=1
    -- 1: insert ID=21 P=1
    -- 2: insert ID=22 P=2
    -- 3: insert ID=23 P=1  <- must go AFTER ID=20 and ID=21, before ID=22
    constant SCENARIO_SIZE : integer := 4;

    type scenario_config_t is record
        task_id       : std_logic_vector(5 downto 0);
        task_priority : std_logic_vector(1 downto 0);
        op            : std_logic_vector(1 downto 0);
    end record;
    type scenario_config_type is array (0 to SCENARIO_SIZE-1) of scenario_config_t;

    signal scenario_config : scenario_config_type := (
        (task_id => "010100", task_priority => "01", op => "10"), -- Insert ID=20 P=1
        (task_id => "010101", task_priority => "01", op => "10"), -- Insert ID=21 P=1
        (task_id => "010110", task_priority => "10", op => "10"), -- Insert ID=22 P=2
        (task_id => "010111", task_priority => "01", op => "10")  -- Insert ID=23 P=1 (after existing P=1)
    );

    type single_result_t is array (0 to 10) of std_logic_vector(7 downto 0);
    type scenario_result_type is array (0 to SCENARIO_SIZE-1) of single_result_t;
    type int_array_t is array (0 to SCENARIO_SIZE-1) of integer;

    constant CHECK_SIZE_ARRAY : int_array_t := (2, 3, 4, 5);

    signal scenario_result : scenario_result_type := (
        -- [count=1, ID=20|P=1=01010001]
        ("00000001", "01010001", others => "00000000"),
        -- [count=2, ID=20|P=1, ID=21|P=1=01010101]
        ("00000010", "01010001", "01010101", others => "00000000"),
        -- [count=3, ID=20|P=1, ID=21|P=1, ID=22|P=2=01011010]
        ("00000011", "01010001", "01010101", "01011010", others => "00000000"),
        -- [count=4, ID=20|P=1, ID=21|P=1, ID=23|P=1=01011101, ID=22|P=2=01011010]
        ("00000100", "01010001", "01010101", "01011101", "01011010", others => "00000000")
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
            report "EDGE8 FALLITO: dopo reset RAM[0] != 0" severity failure;

        wait until falling_edge(tb_clk);

        for i in 0 to SCENARIO_SIZE - 1 loop
            tb_op            <= scenario_config(i).op;
            tb_i_task_id     <= scenario_config(i).task_id;
            tb_task_priority <= scenario_config(i).task_priority;
            tb_start         <= '1';

            wait until rising_edge(tb_done);

            for j in 0 to CHECK_SIZE_ARRAY(i) - 1 loop
                assert RAM(j) = scenario_result(i)(j)
                    report "EDGE8 FALLITO @ STEP=" & integer'image(i) &
                           " OFFSET=" & integer'image(j) &
                           " expected=" & integer'image(to_integer(unsigned(scenario_result(i)(j)))) &
                           " actual=" & integer'image(to_integer(unsigned(RAM(j))))
                    severity failure;
            end loop;

            tb_start <= '0';
            wait until falling_edge(tb_done);
            wait until falling_edge(tb_clk);
            report "EDGE8 Step " & integer'image(i) & " OK.";
        end loop;

        report "EDGE8 OK: inserimento a pari priorita' va in coda ai pari, preserva ordine";
        assert false report "Simulation Ended! EDGE8 PASSATO" severity failure;
    end process;

end architecture;
