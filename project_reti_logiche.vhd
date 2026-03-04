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
        o_task_id : out std_logic_vector(5 downto 0);     -- Eventuale ID in uscita (per OP00)
        
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
    -- Ogni nome rappresenta una specifica fase operativa. Questa astrazione 
    -- permette di mappare direttamente il diagramma a bolle nel codice.
    type state_type is (RESET, INIT_MEM, IDLE, FETCH_SIZE, DECODE, 
                        OP00_CHECK_EMPTY, OP00_READ, OP00_MODIFY,
                        OP01_CHECK_EMPTY, OP01_FORCE_ZERO, OP01_READ_FIRST, OP01_SAVE, OP01_SHIFT_READ, OP01_SHIFT_WRITE, OP01_UPDATE,
                        OP11_CLEAR,
                        OP10_CHECK_EMPTY, OP10_FIND_READ, OP10_FIND_EVAL, OP10_CHECK_SHIFT, OP10_SHIFT_READ, OP10_SHIFT_WRITE, OP10_INSERT, OP10_UPDATE_SIZE,
                        DONE);
    
    signal current_state, next_state: state_type;

    -- REGISTRI E SEGNALI "NEXT" (DATAPATH)
    -- Per ogni registro fisico (es. num_tasks), esiste un segnale "next" (next_num_tasks).
    -- Il segnale "next" calcola il valore combinatoriamente; al clock, il valore passa nel registro.
    signal num_tasks, next_num_tasks     : unsigned(7 downto 0);   -- Numero di task nella lista (letta da addr 0)
    signal current_addr, next_current_addr  : unsigned(15 downto 0); -- Puntatore usato per scorrere la memoria
    signal target_addr, next_target_addr   : unsigned(15 downto 0);  -- Memorizza la destinazione per insert/shift
    signal extracted_id, next_extracted_id  : std_logic_vector(5 downto 0); -- ID letto durante la ricerca
    signal data_buffer, next_data_buffer   : std_logic_vector(7 downto 0);  -- Buffer temporaneo per swap di byte
    
    -- Filo combinatorio per unire ID e Priority in un unico byte da scrivere
    signal concatenation : std_logic_vector(7 downto 0);

begin

    -- ASSEGNAMENTO COMBINATORIO CONTINUO
    -- Questo valore è sempre aggiornato in base agli ingressi, senza aspettare il clock.
    concatenation <= i_task_id & i_task_priority;

    -- 1. PROCESSO: REGISTRO DI STATO (SEQUENZIALE)
    -- Utilità: Gestisce solo la transizione temporale degli stati. 
    -- È il "cuore pulsante" che fa avanzare la FSM ad ogni fronte di salita del clock.
    state_reg: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            current_state <= RESET; -- Ritorno immediato allo stato iniziale se il reset è alto
        elsif rising_edge(i_clk) then
            current_state <= next_state; -- Aggiornamento dello stato al clock
        end if;
    end process;

    -- 2. PROCESSO: REGISTRI DEL DATAPATH (SEQUENZIALE)
    -- Utilità: Isola tutti i componenti di memoria (Flip-Flop) del datapath. 
    -- Tenere i registri separati dalla logica permette al sintetizzatore di creare
    -- circuiti più veloci e puliti.
    datapath_regs: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            -- Reset dei registri: fondamentale per evitare valori casuali all'accensione
            num_tasks <= (others => '0');
            current_addr <= (others => '0');
            target_addr <= (others => '0');
            extracted_id <= (others => '0');
            data_buffer <= (others => '0');
        elsif rising_edge(i_clk) then
            -- Campionamento dei valori calcolati dai processi combinatori
            num_tasks <= next_num_tasks;
            current_addr <= next_current_addr;
            target_addr <= next_target_addr;
            extracted_id <= next_extracted_id;
            data_buffer <= next_data_buffer;
        end if;
    end process;

    -- 3. PROCESSO: LOGICA DELLA FSM (COMBINATORIO)
    -- Utilità: Decide QUALI sono i passi da compiere. Non fa calcoli, decide solo il flusso.
    -- La sensibilità include tutti i segnali che influenzano le decisioni.
    fsm_logic: process(current_state, i_start, i_op, num_tasks, i_mem_data, current_addr, i_task_id)
    begin
        -- Valore di default: resta nello stato attuale se non diversamente specificato
        next_state <= current_state;
        
        -- Uscite di controllo di default (Sicurezza): 
        -- Evita che la memoria venga attivata per sbaglio o che il done resti appeso.
        o_mem_en <= '0';
        o_mem_we <= '0';
        o_done <= '0';

        case current_state is
            when RESET =>
                o_done <= '1'; -- Come da specifica, durante l'init done deve essere 1
                next_state <= INIT_MEM;

            when INIT_MEM =>
                o_done <= '1';
                o_mem_en <= '1';
                o_mem_we <= '1'; -- Scrivo 0 all'indirizzo 0 per resettare la lista
                next_state <= IDLE;

            when IDLE =>
                -- Stato di riposo: aspetta che i_start vada a 1 per iniziare
                if i_start = '1' then
                    next_state <= FETCH_SIZE;
                end if;

            when FETCH_SIZE =>
                o_mem_en <= '1'; -- Attivo lettura della dimensione della lista (addr 0)
                next_state <= DECODE;

            when DECODE =>
                if i_op = "00" then
                    next_state <= OP00_CHECK_EMPTY;
                elsif i_op = "01" then
                    next_state <= OP01_CHECK_EMPTY;
                elsif i_op = "10" then
                    next_state <= OP10_CHECK_EMPTY;
                elsif i_op = "11" then
                    next_state <= OP11_CLEAR;
                else
                    next_state <= DONE;
                end if;

--OP11
            when OP11_CLEAR =>
                o_mem_en <= '1';
                o_mem_we <= '1'; -- Scrittura forzata di 0 per svuotare la lista
                next_state <= DONE;

--OP01
            when OP01_CHECK_EMPTY =>
                if num_tasks = 00000000 then
                    next_state <= OP01_FORCE_ZERO;
                else
                    next_state <= OP01_READ_FIRST;
                end if;
            
            when OP01_FORCE_ZERO =>
            --non serve operare con la memoria, è gia ok di default -> modifico o_task_id nel dp
                next_state <= DONE;

            when OP01_READ_FIRST =>
                o_mem_we <= '0';
                o_mem_en <= '1';
                
                next_state <= OP01_SAVE;
                
            when OP01_SAVE =>
                if num_tasks = 00000001 then
                    next_state <= OP01_UPDATE;
                else
                    next_state <= OP01_SHIFT_READ;
                end if;

            when OP01_SHIFT_READ =>
                o_mem_we <= '0';
                o_mem_en <= '1';
                
                next_state <= OP01_SHIFT_WRITE;

            when OP01_SHIFT_WRITE =>
                o_mem_we <= '1';
                o_mem_en <= '1';
                
                if current_addr < resize(num_tasks, 16) then  --num_tasks è a 8 bit, fortemente tipizzato devo renderlo lungo 16 bit per poter fare il confronto
                    next_state <= OP01_SHIFT_READ;
                else
                    next_state <= OP01_UPDATE;
                end if;
                
            when OP01_UPDATE =>
                o_mem_we <= '1';
                o_mem_en <= '1';
                
                next_state <= DONE;
                
            when OP00_CHECK_EMPTY =>
                if num_tasks = 00000000 then
                        next_state <= DONE;
                    else
                        next_state <= OP00_READ;
                    end if;

--OP00
                        
            when OP00_READ =>
                o_mem_we <= '0';
                o_mem_en <= '1';
                
                next_state <= OP00_MODIFY;

            when OP00_MODIFY =>
                o_mem_en <= '1';
                o_mem_we <= '1';
                
                if current_addr < resize(num_tasks, 16) then
                    next_state <= OP00_READ;
                else
                    next_state <= DONE;
                end if;

-- OP10
            when OP10_CHECK_EMPTY =>
                if  num_tasks = "00000000" and target_addr = "0000000000000001" then
                    next_state <= OP10_INSERT;
                else
                    next_state <= OP10_FIND_READ;
                end if;
                
            when OP10_FIND_READ =>
                next_state <= OP10_FIND_EVAL;
            
            when OP10_FIND_EVAL =>
                if i_mem_data(1 downto 0) <= i_task_priority and current_addr <= resize(num_tasks,16) then
                    next_state <= OP10_FIND_READ;
                else
                    next_state <= OP10_CHECK_SHIFT;
                end if;
                
            when OP10_CHECK_SHIFT =>
                
                if target_addr > resize(num_tasks,16) then
                    next_state <= OP10_INSERT;
                else
                    next_state <= OP01_SHIFT_READ;
                end if;
            
            when OP10_SHIFT_READ =>
                next_state <= OP10_SHIFT_WRITE;
            
            when OP10_SHIFT_WRITE =>
                if current_addr >= target_addr then
                    next_state <= OP10_SHIFT_READ;
                else
                    next_state <= OP10_INSERT;
                    
                end if;         
                    
            when OP10_INSERT =>
                next_state <= OP10_UPDATE_SIZE;
                
            when OP10_UPDATE_SIZE =>
                next_state <= DONE;        


                    
            when DONE =>
                o_done <= '1';
                -- Protocollo Handshake: il modulo resta in DONE finché i_start è 1.
                -- Questo garantisce che il Test Bench abbia recepito il risultato.
                if i_start = '0' then
                    next_state <= IDLE;
                end if;

            when others =>
                next_state <= RESET; -- Recupero da stati illegali
        end case;
    end process;

    -- 4. PROCESSO: LOGICA DEL DATAPATH (COMBINATORIO)
    -- Utilità: È il "braccio operativo". Qui vengono fatti i calcoli (ALU), 
    -- generati gli indirizzi di memoria e preparati i dati da scrivere.
    datapath_logic: process(current_state, i_mem_data, num_tasks, current_addr, target_addr, extracted_id, data_buffer, concatenation)
    begin
        -- Valori di default: mantengono il valore attuale dei registri se lo stato non li cambia.
        -- Questo previene la generazione di Latch (circuiti sequenziali indesiderati).
        next_num_tasks <= num_tasks;
        next_current_addr <= current_addr;
        next_target_addr <= target_addr;
        next_extracted_id <= extracted_id;
        next_data_buffer <= data_buffer;
        
        o_mem_addr <= (others => '0');
        o_mem_data <= (others => '0');
        o_task_id <= extracted_id;

        case current_state is
            when INIT_MEM =>
                o_mem_addr <= (others => '0'); -- Scrive all'indirizzo 0
                o_mem_data <= (others => '0'); -- Valore 0 (lista vuota)

            when FETCH_SIZE =>
                o_mem_addr <= (others => '0'); -- Legge l'indirizzo 0

            when DECODE =>
                -- Riceve il dato letto dalla memoria (numero task) e lo salva nel registro
                next_num_tasks <= unsigned(i_mem_data);

--OP11
            when OP11_CLEAR =>
                o_mem_addr <= (others => '0');
                o_mem_data <= (others => '0');
                next_num_tasks <= (others => '0'); -- Azzera anche il registro     

--OP01
            when OP01_FORCE_ZERO =>
            --tip: per non scrivere ogni volta 000000 uso sintassi others => '0' 
            --è come dire al compilatore "riempi con tanti zeri quanti sono i bit disponibili"
                next_extracted_id <= (others => '0'); --quindi qui ad esempio forzo i 6 bit disponibili a 0

            when OP01_READ_FIRST =>
                o_mem_addr <= "0000000000000001";

            when OP01_SAVE =>
                next_extracted_id <= i_mem_data (7 downto 2); --id rimosso
                next_current_addr <= to_unsigned(2, 16);    -- Parto a leggere dal SECONDO

            when OP01_SHIFT_READ =>
                o_mem_addr <= std_logic_vector(current_addr);   --fortemente tipizzato quindi faccio cast per assegnamento
                
            when OP01_SHIFT_WRITE =>
                o_mem_addr <= std_logic_vector(current_addr - 1);
                o_mem_data <= i_mem_data;
                next_current_addr <= current_addr + 1;

            when OP01_UPDATE =>
                o_mem_data <= std_logic_vector(num_tasks - 1);
                o_mem_addr <= (others => '0');
                next_num_tasks <= num_tasks - 1;

--OP00
            when OP00_CHECK_EMPTY | OP01_CHECK_EMPTY | OP10_CHECK_EMPTY =>
            next_extracted_id <= (others => '0'); --per svuotare i vecchi id
            
                if num_tasks /= 00000000 then
                    next_current_addr <= to_unsigned(1, 16);
                end if;
            
            when OP00_READ =>
                o_mem_addr <= std_logic_vector(current_addr);
                
            when OP00_MODIFY =>
                o_mem_addr <= std_logic_vector(current_addr);
            -- 1. Calcolo della nuova priorità (Saturazione a 3, ovvero "11")
        -- Prendo i bit 1 e 0 di i_mem_data (la priorità attuale)
                if i_mem_data(1 downto 0) = "11" then
        -- Se è già al massimo, resta 3
                    o_mem_data <= i_mem_data(7 downto 2) & "11";
                else
        -- Altrimenti aggiungo 1 (usando unsigned per il calcolo)
                    o_mem_data <= i_mem_data(7 downto 2) & std_logic_vector(unsigned(i_mem_data(1 downto 0)) + 1);
                end if;
                
                next_extracted_id <= i_mem_data(7 downto 2);
                next_current_addr <= current_addr + 1;            

--OP10            
            when OP10_FIND_EVAL =>
                if i_mem_data(1 downto 0) <= i_task_priority and current_addr <= resize(num_tasks,16) then
                    next_current_addr <= current_addr + 1;
                else
                    next_target_addr <= current_addr;
                end if;
            
            when OP10_CHECK_SHIFT =>
                if target_addr <= resize(num_tasks,16) then
                    next_current_addr <= num_tasks;
                end if;
                
            when OP10_SHIFT_READ =>
                o_mem_addr <= std_logic_vector(current_addr);
                o_mem_we <= '0';
                o_mem_en <= '1';
            
            when OP10_SHIFT_WRITE =>
                o_mem_addr <= std_logic_vector(current_addr + 1);
                o_mem_data <= i_mem_data;
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                if current_addr >= target_addr then
                    next_current_addr <= current_addr - 1;
                end if;
                
            when OP10_INSERT =>
                o_mem_addr <= std_logic_vector(target_addr);
                o_mem_en <= '1';
                o_mem_we <= '1';
                o_mem_data <= concatenation;
            
            when OP10_UPDATE_SIZE =>
                o_mem_addr <= (others => '0');
                o_mem_data <= std_logic_vector(num_tasks + 1);
                o_mem_we   <= '1';
                o_mem_en   <= '1'; 
                
                next_num_tasks <= num_tasks + 1; 



            when others =>
                -- In tutti gli altri stati (es. DONE o IDLE), il datapath non deve agire.
                null; 
        end case;
    end process;

end Behavioral;
