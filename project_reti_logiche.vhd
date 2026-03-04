library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL; -- Fondamentale per usare il tipo 'unsigned' e fare calcoli aritmetici

entity project_reti_logiche is
    port (
        -- Segnali di controllo globali
        i_clk : in std_logic;
        i_rst : in std_logic;      -- Reset asincrono: riporta il sistema a uno stato noto
        i_start : in std_logic;    -- Avvia l'elaborazione del modulo
        
        -- Dati in ingresso dal Test Bench
        i_task_id : in std_logic_vector(5 downto 0);      -- ID del task da gestire
        i_task_priority : in std_logic_vector(1 downto 0); -- Priorità associata al task
        i_op : in std_logic_vector(1 downto 0);           -- Codice operazione (00, 01, 10, 11)
        
        -- Segnali verso l'esterno
        o_done : out std_logic;                           -- Segnala la fine dell'operazione
        o_task_id : out std_logic_vector(5 downto 0);     -- Eventuale ID in uscita (per OP01)
        
        -- Interfaccia Memoria (Bus Dati e Indirizzi)
        o_mem_addr: out std_logic_vector(15 downto 0);    -- Indirizzo di memoria (16 bit)
        i_mem_data : in std_logic_vector(7 downto 0);     -- Dato letto dalla memoria
        o_mem_data: out std_logic_vector(7 downto 0);     -- Dato da scrivere in memoria
        o_mem_we : out std_logic;                         -- Write Enable (1=Scrittura, 0=Lettura)
        o_mem_en : out std_logic                          -- Memory Enable (attiva la RAM)
    );
end project_reti_logiche;

architecture Behavioral of project_reti_logiche is

    -- DICHIARAZIONE DEGLI STATI
    type state_type is (RESET, INIT_MEM, IDLE, FETCH_SIZE, DECODE, 
                        OP00_CHECK_EMPTY, OP00_READ, OP00_MODIFY,
                        OP01_CHECK_EMPTY, OP01_FORCE_ZERO, OP01_READ_FIRST, OP01_SAVE, OP01_SHIFT_READ, OP01_SHIFT_WRITE, OP01_UPDATE,
                        OP11_CLEAR,
                        OP10_CHECK_EMPTY, OP10_FIND_READ, OP10_FIND_EVAL, OP10_CHECK_SHIFT, OP10_SHIFT_READ, OP10_SHIFT_WRITE, OP10_INSERT, OP10_UPDATE_SIZE,
                        DONE);
    
    signal current_state, next_state: state_type;

    -- REGISTRI E SEGNALI "NEXT" (DATAPATH)
    signal num_tasks,    next_num_tasks    : unsigned(7 downto 0);
    signal current_addr, next_current_addr : unsigned(15 downto 0);
    signal target_addr,  next_target_addr  : unsigned(15 downto 0);
    signal extracted_id, next_extracted_id : std_logic_vector(5 downto 0);
    signal data_buffer,  next_data_buffer  : std_logic_vector(7 downto 0);
    
    -- Filo combinatorio per unire ID e Priority in un unico byte da scrivere
    signal concatenation : std_logic_vector(7 downto 0);

begin

    -- ASSEGNAMENTO COMBINATORIO CONTINUO
    concatenation <= i_task_id & i_task_priority;

    -- 1. PROCESSO: REGISTRO DI STATO (SEQUENZIALE)
    state_reg: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            current_state <= RESET;
        elsif rising_edge(i_clk) then
            current_state <= next_state;
        end if;
    end process;

    -- 2. PROCESSO: REGISTRI DEL DATAPATH (SEQUENZIALE)
    datapath_regs: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            num_tasks    <= (others => '0');
            current_addr <= (others => '0');
            target_addr  <= (others => '0');
            extracted_id <= (others => '0');
            data_buffer  <= (others => '0');
        elsif rising_edge(i_clk) then
            num_tasks    <= next_num_tasks;
            current_addr <= next_current_addr;
            target_addr  <= next_target_addr;
            extracted_id <= next_extracted_id;
            data_buffer  <= next_data_buffer;
        end if;
    end process;

    -- 3. PROCESSO: LOGICA DELLA FSM (COMBINATORIO)
    fsm_logic: process(current_state, i_start, i_op, num_tasks, i_mem_data, current_addr, target_addr, i_task_id, i_task_priority)
    begin
        next_state <= current_state;
        
        o_mem_en <= '0';
        o_mem_we <= '0';
        o_done   <= '0';

        case current_state is
            when RESET =>
                o_done     <= '0';
                next_state <= INIT_MEM;

            when INIT_MEM =>
                o_done     <= '1';
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                next_state <= IDLE;

            when IDLE =>
                if i_start = '1' then
                    next_state <= FETCH_SIZE;
                end if;

            when FETCH_SIZE =>
                o_mem_en   <= '1';
                next_state <= DECODE;

            when DECODE =>
                if    i_op = "00" then next_state <= OP00_CHECK_EMPTY;
                elsif i_op = "01" then next_state <= OP01_CHECK_EMPTY;
                elsif i_op = "10" then next_state <= OP10_CHECK_EMPTY;
                elsif i_op = "11" then next_state <= OP11_CLEAR;
                else                   next_state <= DONE;
                end if;

-- OP11
            when OP11_CLEAR =>
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                next_state <= DONE;

-- OP01
            when OP01_CHECK_EMPTY =>
                if num_tasks = "00000000" then
                    next_state <= OP01_FORCE_ZERO;
                else
                    next_state <= OP01_READ_FIRST;
                end if;
            
            when OP01_FORCE_ZERO =>
                next_state <= DONE;

            when OP01_READ_FIRST =>
                o_mem_we   <= '0';
                o_mem_en   <= '1';
                next_state <= OP01_SAVE;
                
            when OP01_SAVE =>
                if num_tasks = "00000001" then
                    next_state <= OP01_UPDATE;
                else
                    next_state <= OP01_SHIFT_READ;
                end if;

            when OP01_SHIFT_READ =>
                o_mem_we   <= '0';
                o_mem_en   <= '1';
                next_state <= OP01_SHIFT_WRITE;

            when OP01_SHIFT_WRITE =>
                o_mem_we <= '1';
                o_mem_en <= '1';
                if current_addr <= resize(num_tasks, 16) then
                    next_state <= OP01_SHIFT_READ;
                else
                    next_state <= OP01_UPDATE;
                end if;
                
            when OP01_UPDATE =>
                o_mem_we   <= '1';
                o_mem_en   <= '1';
                next_state <= DONE;

-- OP00
            when OP00_CHECK_EMPTY =>
                if num_tasks = "00000000" then
                    next_state <= DONE;
                else
                    next_state <= OP00_READ;
                end if;
                        
            when OP00_READ =>
                o_mem_we   <= '0';
                o_mem_en   <= '1';
                next_state <= OP00_MODIFY;

            when OP00_MODIFY =>
                o_mem_en <= '1';
                o_mem_we <= '1';
                if current_addr <= resize(num_tasks, 16) then
                    next_state <= OP00_READ;
                else
                    next_state <= DONE;
                end if;

-- OP10
            when OP10_CHECK_EMPTY =>
                
                if num_tasks = "00000000" then
                    next_state <= OP10_INSERT;
                else
                    next_state <= OP10_FIND_READ;
                end if;
                
            when OP10_FIND_READ =>
                
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                next_state <= OP10_FIND_EVAL;
            
            when OP10_FIND_EVAL =>
                -- 
                if current_addr > resize(num_tasks, 16) then
                    -- Scorsa tutta la lista senza trovare un task a priorità inferiore:
                    -- il nuovo task va in coda (target_addr sarà num_tasks+1, calcolato nel dp)
                    next_state <= OP10_CHECK_SHIFT;
                elsif i_mem_data(1 downto 0) > i_task_priority then
                    -- Trovato il primo task con priorità INFERIORE (valore numerico maggiore):
                    -- il nuovo task va prima di questo
                    next_state <= OP10_CHECK_SHIFT;
                else
                    -- Priorità uguale o superiore: continua a scorrere
                    next_state <= OP10_FIND_READ;
                end if;
                
            when OP10_CHECK_SHIFT =>
                if target_addr > resize(num_tasks, 16) then
                    next_state <= OP10_INSERT;
                else
                    
                    next_state <= OP10_SHIFT_READ;
                end if;
            
            when OP10_SHIFT_READ =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                next_state <= OP10_SHIFT_WRITE;
            
            when OP10_SHIFT_WRITE =>
                o_mem_en <= '1';
                o_mem_we <= '1';
                if current_addr >= target_addr then
                    next_state <= OP10_SHIFT_READ;
                else
                    next_state <= OP10_INSERT;
                end if;         
                    
            when OP10_INSERT =>
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                next_state <= OP10_UPDATE_SIZE;
                
            when OP10_UPDATE_SIZE =>
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                next_state <= DONE;        

            when DONE =>
                o_done <= '1';
                if i_start = '0' then
                    next_state <= IDLE;
                end if;

            when others =>
                next_state <= RESET;
        end case;
    end process;

    -- 4. PROCESSO: LOGICA DEL DATAPATH (COMBINATORIO)
    datapath_logic: process(current_state, i_mem_data, num_tasks, current_addr, target_addr, extracted_id, data_buffer, concatenation, i_task_priority)
    begin
        next_num_tasks    <= num_tasks;
        next_current_addr <= current_addr;
        next_target_addr  <= target_addr;
        next_extracted_id <= extracted_id;
        next_data_buffer  <= data_buffer;
        
        o_mem_addr <= (others => '0');
        o_mem_data <= (others => '0');
        o_task_id  <= extracted_id;

        case current_state is
            when INIT_MEM =>
                o_mem_addr <= (others => '0');
                o_mem_data <= (others => '0');

            when FETCH_SIZE =>
                o_mem_addr <= (others => '0');

            when DECODE =>
                next_num_tasks <= unsigned(i_mem_data);

-- OP11
            when OP11_CLEAR =>
                o_mem_addr     <= (others => '0');
                o_mem_data     <= (others => '0');
                next_num_tasks <= (others => '0');

-- OP00 / OP01: reset comune (senza target_addr, gestito separatamente per OP10)
            when OP00_CHECK_EMPTY | OP01_CHECK_EMPTY =>
                next_extracted_id <= (others => '0');
                next_target_addr  <= (others => '0');
                if num_tasks /= "00000000" then
                    next_current_addr <= to_unsigned(1, 16);
                end if;
                
                when OP10_CHECK_EMPTY =>
                next_extracted_id <= (others => '0');
                if num_tasks = "00000000" then
                    -- Lista vuota: inserimento diretto in posizione 1
                    next_target_addr  <= to_unsigned(1, 16);
                else
                    -- Lista non vuota: reset target_addr, parto a scorrere da addr 1
                    next_target_addr  <= (others => '0');
                    next_current_addr <= to_unsigned(1, 16);
                end if;


-- OP01
            when OP01_FORCE_ZERO =>
                next_extracted_id <= (others => '0');

            when OP01_READ_FIRST =>
                o_mem_addr <= "0000000000000001";

            when OP01_SAVE =>
                next_extracted_id <= i_mem_data(7 downto 2);
                next_current_addr <= to_unsigned(2, 16);

            when OP01_SHIFT_READ =>
                o_mem_addr <= std_logic_vector(current_addr);
                
            when OP01_SHIFT_WRITE =>
                o_mem_addr        <= std_logic_vector(current_addr - 1);
                o_mem_data        <= i_mem_data;
                next_current_addr <= current_addr + 1;

            when OP01_UPDATE =>
                o_mem_data     <= std_logic_vector(num_tasks - 1);
                o_mem_addr     <= (others => '0');
                next_num_tasks <= num_tasks - 1;

-- OP00
            when OP00_READ =>
                o_mem_addr <= std_logic_vector(current_addr);
                
            when OP00_MODIFY =>
                o_mem_addr <= std_logic_vector(current_addr);
                if i_mem_data(1 downto 0) = "11" then
                    o_mem_data <= i_mem_data(7 downto 2) & "11";
                else
                    o_mem_data <= i_mem_data(7 downto 2) & std_logic_vector(unsigned(i_mem_data(1 downto 0)) + 1);
                end if;
                next_extracted_id <= i_mem_data(7 downto 2);
                next_current_addr <= current_addr + 1;

-- OP10
            

            when OP10_FIND_READ =>
                
                o_mem_addr <= std_logic_vector(current_addr);

            when OP10_FIND_EVAL =>
                
                if current_addr > resize(num_tasks, 16) then
                    -- Fine lista: inserimento in coda (pos = num_tasks + 1)
                    next_target_addr <= resize(num_tasks, 16) + 1;
                elsif i_mem_data(1 downto 0) > i_task_priority then
                    -- Trovato il punto di inserimento
                    next_target_addr  <= current_addr;
                else
                    -- Continua la scansione
                    next_current_addr <= current_addr + 1;
                end if;
            
            when OP10_CHECK_SHIFT =>
                -- Prepara current_addr per lo shift dall'ultimo elemento verso target
                if target_addr <= resize(num_tasks, 16) then
                    next_current_addr <= resize(num_tasks, 16);
                end if;
                
            when OP10_SHIFT_READ =>
                o_mem_addr <= std_logic_vector(current_addr);
            
            when OP10_SHIFT_WRITE =>
                o_mem_addr <= std_logic_vector(current_addr + 1);
                o_mem_data <= i_mem_data;
                if current_addr >= target_addr then
                    next_current_addr <= current_addr - 1;
                end if;
                
            when OP10_INSERT =>
                o_mem_addr <= std_logic_vector(target_addr);
                o_mem_data <= concatenation;
            
            when OP10_UPDATE_SIZE =>
                o_mem_addr     <= (others => '0');
                o_mem_data     <= std_logic_vector(num_tasks + 1);
                next_num_tasks <= num_tasks + 1;

            when others =>
                null;
        end case;
    end process;

end Behavioral;
