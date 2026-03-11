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
        S_RESET,       
        S_IDLE,        
        S_LOAD_COUNT,   
        S_DECODE,       

        S_OP00_READ,    
        S_OP00_MODIFY, 

       
        S_OP01_READ_FIRST, 
        S_OP01_SAVE,        
        S_OP01_SHIFT_READ,  
        S_OP01_SHIFT_WRITE, 
        S_OP01_UPDATE,      


        S_OP10_FIND_READ,   
        S_OP10_COMPARE,    
        S_OP10_SHIFT_READ,  
        S_OP10_SHIFT_WRITE, 
        S_OP10_INSERT,     
        S_OP10_UPDATE_SIZE, 

      
        S_OP11_CLEAR,   

        S_WAIT_DONE,


        S_DONE 
    );

    signal current_state : state_type;

    signal next_state    : state_type;


    -- REGISTRI DEL DATAPATH
    -- Ogni segnale "xxx" è il valore attuale (Q del flip-flop).
    -- Ogni segnale "next_xxx" è il valore futuro (D del flip-flop),
    -- calcolato dalla logica combinatoria e caricato al fronte di clock successivo.

    signal num_tasks    : unsigned(7 downto 0);

    signal current_addr : unsigned(15 downto 0);

    signal target_addr  : unsigned(15 downto 0);

    signal extracted_id : std_logic_vector(5 downto 0);

    signal next_num_tasks    : unsigned(7 downto 0);
    signal next_current_addr : unsigned(15 downto 0);
    signal next_target_addr  : unsigned(15 downto 0);
    signal next_extracted_id : std_logic_vector(5 downto 0);

begin


    -- PROCESSO 1: state_reg — Registro di Stato
    -- Implementa fisicamente il flip-flop che memorizza lo stato corrente della FSM.
    --
    -- Reset ASINCRONO (primo ramo dell'if): non aspetta il clock. Appena i_rst='1'
    -- la FSM torna in S_RESET immediatamente, indipendentemente dallo stato del clock.
    -- Questo garantisce uno stato noto anche se il clock non è ancora stabile.
    --
    -- Aggiornamento SINCRONO (rising_edge): al fronte di salita, current_state
    -- acquisisce il valore di next_state calcolato dalla logica combinatoria
    -- nell'intervallo precedente. Tra un fronte e l'altro, current_state è congelato.


    state_reg: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            current_state <= S_RESET;
        elsif rising_edge(i_clk) then
            current_state <= next_state;
        end if;
    end process;


    -- PROCESSO 2: datapath_regs — Registri del Datapath
    -- Stessa struttura di state_reg, ma gestisce i quattro registri di supporto.
    -- Separato da state_reg per chiarezza e per garantire un reset esplicito
    -- di ogni registro a un valore noto (tutti zero).


    datapath_regs: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            num_tasks    <= (others => '0');
            current_addr <= (others => '0');
            target_addr  <= (others => '0');
            extracted_id <= (others => '0');
        elsif rising_edge(i_clk) then
            num_tasks    <= next_num_tasks;
            current_addr <= next_current_addr;
            target_addr  <= next_target_addr;
            extracted_id <= next_extracted_id;
        end if;
    end process;


    -- PROCESSO 3: comb — Logica Combinatoria
    -- È l'unico processo puramente combinatorio: nessun fronte di clock,
    -- nessuna memoria. Ricalcola immediatamente tutte le uscite e i valori
    -- next_* ogni volta che uno dei segnali in sensitivity list cambia.
    --
    -- VALORI DI DEFAULT: ogni segnale viene assegnato prima
    -- del case statement. Questo è fondamentale per evitare latch indesiderati:
    -- se un segnale non fosse assegnato in tutti i rami del case, il sintetizzatore
    -- dedurrebbe che il valore deve essere "mantenuto" e inserirebbe un latch.

    comb: process(current_state, i_start, i_op,
                  i_task_id, i_task_priority,
                  num_tasks, current_addr, target_addr,
                  extracted_id, i_mem_data)
    begin

        next_state        <= current_state; 
        next_num_tasks    <= num_tasks;
        next_current_addr <= current_addr;
        next_target_addr  <= target_addr;
        next_extracted_id <= extracted_id;

        o_done     <= '0';
        o_task_id  <= extracted_id;  
        o_mem_en   <= '0';          
        o_mem_we   <= '0';           
        o_mem_addr <= (others => '0');
        o_mem_data <= (others => '0');

        case current_state is

            when S_RESET =>
                o_done         <= '1';
                o_mem_en       <= '1';
                o_mem_we       <= '1';
                o_mem_addr     <= (others => '0');
                o_mem_data     <= (others => '0');
                next_num_tasks <= (others => '0');
                next_state     <= S_IDLE;


            when S_IDLE =>

                if i_start = '1' then
                    next_state <= S_LOAD_COUNT;
                end if;


            when S_LOAD_COUNT =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= (others => '0');
                next_state <= S_DECODE;


            when S_DECODE =>
                -- Salva num_tasks nel registro interno per gli stati successivi.
                -- Usa i_mem_data (non num_tasks) per i confronti qui sotto,
                -- perché num_tasks verrà aggiornato solo al prossimo fronte di clock.

                next_num_tasks    <= unsigned(i_mem_data); -- o_mem_addr è a 0, quindi i_mem_data rappresenta il numero di task
                next_current_addr <= to_unsigned(1, 16); -- la scansione parte sempre da addr 1
                next_target_addr  <= (others => '0');

                next_extracted_id <= (others => '0');

                if i_op = "00" then
                    -- Lista vuota: niente da modificare
                    if unsigned(i_mem_data) = 0 then
                        next_state <= S_DONE;
                    else
                        next_state <= S_OP00_READ;
                    end if;

                elsif i_op = "01" then
                    -- Lista vuota: extracted_id rimane 0 (default), uscita 0
                    if unsigned(i_mem_data) = 0 then
                        next_state <= S_DONE;
                    else
                        next_state <= S_OP01_READ_FIRST;
                    end if;

                elsif i_op = "10" then
                    if unsigned(i_mem_data) = 0 then
                        -- Lista vuota: inserimento diretto in addr 1,
                        -- nessuna ricerca della posizione necessaria.
                        next_target_addr <= to_unsigned(1, 16);
                        next_state       <= S_OP10_INSERT;
                    else
                        next_state <= S_OP10_FIND_READ;
                    end if;

                elsif i_op = "11" then
                    next_state <= S_OP11_CLEAR;

                else
                    next_state <= S_DONE;
                end if;

            when S_OP00_READ =>
                -- Ciclo T: richiesta lettura indirizzo corrente
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP00_MODIFY;

            when S_OP00_MODIFY =>
                -- Ciclo T+1: i_mem_data = byte del task corrente 

                o_mem_en   <= '1';
                o_mem_we   <= '1';  
                o_mem_addr <= std_logic_vector(current_addr);  -- stesso indirizzo della lettura
                if i_mem_data(1 downto 0) = "11" then
                    -- Saturazione: priorità già al minimo (3)
                    o_mem_data <= i_mem_data(7 downto 2) & "11";
                else
                    -- Incremento: i 6 bit alti (ID) rimangono invariati,
                    -- i 2 bit bassi (PRIORITY) vengono incrementati di 1
                    o_mem_data <= i_mem_data(7 downto 2) &
                                  std_logic_vector(unsigned(i_mem_data(1 downto 0)) + 1);
                end if;
                next_current_addr <= current_addr + 1;
                -- resize necessario: num_tasks è 8 bit, current_addr è 16 bit.
                if current_addr = resize(num_tasks, 16) then
                    next_state <= S_WAIT_DONE;  -- ultima scrittura: aspetta un ciclo
                else
                    next_state <= S_OP00_READ; 
                end if;


                    
            when S_OP01_READ_FIRST =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(to_unsigned(1, 16));
                next_state <= S_OP01_SAVE;

            when S_OP01_SAVE =>
                -- Salva solo i 6 bit alti (ID che va restituito in output)
                next_extracted_id <= i_mem_data(7 downto 2);
                -- Lo shift copierà addr[2]→addr[1], addr[3]→addr[2], ecc.
                next_current_addr <= to_unsigned(2, 16);
                if num_tasks = 1 then
                    -- Un solo task: niente shift, aggiorna solo il contatore.
                    next_state <= S_OP01_UPDATE;
                else
                    next_state <= S_OP01_SHIFT_READ;
                end if;

            when S_OP01_SHIFT_READ =>
                -- Ciclo T: legge addr[i], nel ciclo successivo lo scriverà in addr[i-1]
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP01_SHIFT_WRITE;

            when S_OP01_SHIFT_WRITE =>
                -- Ciclo T+1: i_mem_data = contenuto di addr[i]

                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(current_addr - 1);
                o_mem_data <= i_mem_data;
                next_current_addr <= current_addr + 1;  
                if current_addr = resize(num_tasks, 16) then
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
                next_state     <= S_WAIT_DONE;


            when S_OP10_FIND_READ =>
                -- Ciclo T: legge il task a current_addr per confrontarne la priorità
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP10_COMPARE;

            when S_OP10_COMPARE =>
                -- Ciclo T+1: i_mem_data(1:0) = priorità del task a current_addr

                if i_mem_data(1 downto 0) > i_task_priority then

                    next_target_addr  <= current_addr;
                    -- Lo shift parte dall'ultimo task e scende fino a current_addr
                    next_current_addr <= resize(num_tasks, 16);
                    next_state        <= S_OP10_SHIFT_READ;
                elsif current_addr >= resize(num_tasks, 16) then
                    -- Ultimo task raggiunto, priorità <=: inserimento in coda
                    -- Non serve shift: la nuova posizione è num_tasks + 1
                    next_target_addr <= resize(num_tasks, 16) + 1;
                    next_state       <= S_OP10_INSERT;
                else

                    next_current_addr <= current_addr + 1;
                    next_state        <= S_OP10_FIND_READ;
                end if;

            when S_OP10_SHIFT_READ =>
                -- Ciclo T: legge addr[i] per spostarlo in addr[i+1] (shift verso destra)
                -- current_addr parte da num_tasks e decrementa fino a target_addr
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP10_SHIFT_WRITE;

            when S_OP10_SHIFT_WRITE =>
                -- Ciclo T+1: i_mem_data = contenuto di addr[i], lo copia in addr[i+1]
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(current_addr + 1);  
                o_mem_data <= i_mem_data;
                if current_addr = target_addr then
                    next_state <= S_OP10_INSERT;
                else

                    next_current_addr <= current_addr - 1;
                    next_state        <= S_OP10_SHIFT_READ;
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
                next_state     <= S_WAIT_DONE;



            when S_OP11_CLEAR =>
                o_mem_en       <= '1';
                o_mem_we       <= '1';
                o_mem_addr     <= (others => '0');
                o_mem_data     <= (others => '0');
                next_num_tasks <= (others => '0');
                next_state     <= S_WAIT_DONE;

            when S_WAIT_DONE =>
                next_state <= S_DONE;


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
