-------------------------------------------------------------------------------
--
-- Final Project for the Digital Circuit Design Course (Reti Logiche 085877)
-- Prof. G. Palermo
--
-- Developed by: Truong Kien Tuong (10582491/887907)
--
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Package for the custom-defined data types
-------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;

package custom_types is
    type wz_array is array(7 downto 0) of std_logic_vector(7 downto 0);
    type wz_valid_array is array(7 downto 0) of std_logic;
end custom_types;

package body custom_types is
end custom_types;


-------------------------------------------------------------------------------
-- An Address Offset Unit (AOU for short) is a combinatorial module which
-- tries to calculate an encoded address.
-------------------------------------------------------------------------------

LIBRARY IEEE;
LIBRARY work;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE work.custom_types.ALL;

entity aou is
    generic (
        WZ_NUMBER : integer
    );
    port (
        i_wzaddress     : in std_logic_vector(7 downto 0);    -- the wz address
        i_address       : in std_logic_vector(7 downto 0);    -- the input address
        o_address       : out std_logic_vector(7 downto 0)    -- the codified address
    );
end aou;

architecture behavioural of aou is
    constant MASK           : std_logic_vector(7 downto 0) := x"FC"; -- 11111100
    constant LSB_SET        : std_logic_vector(3 downto 0) := b"0001";
begin
    ENCODE_ADDRESS: process(i_address, i_wzaddress)
        variable contained      : std_logic := '0';
        variable offset         : std_logic_vector(7 downto 0);
        variable encoded_addr   : std_logic_vector(3 downto 0);
    begin
        -- Compute offset between address and the wz address
        offset := std_logic_vector(unsigned(i_address) - unsigned(i_wzaddress));

        -- Check if the resulting offset is within 4 cells from the wz address
        if(((offset AND MASK) = "00000000") AND (i_address >= i_wzaddress)) then
            contained := '1';
        else
            contained := '0';
        end if;

        encoded_addr := (others => '0');
        if(contained = '1') then
            -- Convert from binary to one-hot encoding
            encoded_addr(to_integer(unsigned(offset))) := '1';
        end if;

        -- Set address
           o_address <= contained & std_logic_vector(to_unsigned(WZ_NUMBER, 3)) & encoded_addr;
    end process;
end behavioural;


-------------------------------------------------------------------------------
-- The AOU Controller is a combinatorial circuit which contains the AOU
-- instances and outputs the correct result to be written to the output RAM
-------------------------------------------------------------------------------

LIBRARY IEEE;
LIBRARY work;
USE IEEE.std_logic_1164.ALL;
USE work.custom_types.ALL;

entity aou_controller is
    port(
        i_wz_array          : in wz_array;
        i_wz_valid          : in wz_valid_array;
        i_address           : in std_logic_vector(7 downto 0);
        o_result_found      : out std_logic;
        o_result            : out std_logic_vector(7 downto 0)
    );
end aou_controller;

architecture behavioural of aou_controller is
    component aou is
        port (
            i_wzaddress     : in std_logic_vector(7 downto 0);    -- the wz address
            i_address       : in std_logic_vector(7 downto 0);    -- the input address
            o_address       : out std_logic_vector(7 downto 0)    -- the codified address
        );
    end component;
    signal aou_outputs : wz_array;
begin
    -- Generate systolic array of 8 AOUs
    AOU_GENERATE: for i in 7 downto 0 generate
    begin
        AOU_Gen: entity work.aou
        generic map (
            WZ_NUMBER   => i
        )
        port map(
            i_wzaddress => i_wz_array(i),
            i_address   => i_address,
            o_address   => aou_outputs(i)
        );
    end generate;

    FIND_RESULT: process(aou_outputs, i_address, i_wz_valid)
        variable output         : std_logic_vector(7 downto 0) := (others => '0');
        variable found_valid    : boolean := false;
    begin
        for i in 7 downto 0 loop
            if(aou_outputs(i)(7) = '1'and i_wz_valid(i) = '1') then
                -- If the output of the i-th AOU has MSB set and that AOU has a valid WZ address then set the result
                output := aou_outputs(i);
                found_valid := true;
            end if;
        end loop;

        if(found_valid) then
            o_result <= output;
            o_result_found <= '1';
        else
            o_result <= i_address;
            o_result_found <= '0';
        end if;

        found_valid := false;
        output := "00000000";
    end process;
end behavioural;


-------------------------------------------------------------------------------
-- The top-level module that is to be synthetized
-------------------------------------------------------------------------------

LIBRARY IEEE;
LIBRARY work;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE work.custom_types.ALL;

entity project_reti_logiche is
    port (
        i_clk       : in std_logic;
        i_start     : in std_logic;
        i_rst       : in std_logic;
        i_data      : in std_logic_vector(7 downto 0);
        o_address   : out std_logic_vector(15 downto 0);
        o_done      : out std_logic;
        o_en        : out std_logic;
        o_we        : out std_logic;
        o_data      : out std_logic_vector(7 downto 0)
    );
end project_reti_logiche;

architecture behavioural of project_reti_logiche is
    constant ADDR_RAM_POS : integer := 8;
    type fsm_state is (
        IDLING,              -- Idling, waiting for START signal
        SET_READ_WZ,         -- Setting address and enables for WZs
        WAIT_READ_WZ,        -- Waiting for RAM to load WZ address
        FETCH_DATA_WZ,       -- Save WZ address from RAM
        SET_READ_ADDR,       -- Setting address and enables for address to be encoded
        WAIT_READ_ADDR,      -- Waiting for RAM to load address to be encoded
        FETCH_DATA_ADDR,     -- Save address to be encoded from RAM
        WAIT_RESULT,         -- Waiting result from AOU Controller
        SET_WRITE,           -- Setting address and enables to write result in RAM
        END_WRITE            -- Waits for the write and waits for the start signal
    );

    signal curr_wz, next_wz                     : integer range 0 to 7 := 0;                            -- The WZ that is currently being loaded
    signal address, address_next                : std_logic_vector(7 downto 0) := (others => '0');      -- The saved address to be encoded
    signal curr_state, next_state               : fsm_state := IDLING;                                  -- The state of the FSM
    signal wz_addresses, wz_addresses_next      : wz_array := (others => (others => '0'));              -- The addresses of the WZs
    signal wz_valid, wz_valid_next              : wz_valid_array := (others => '0');                    -- The validity status of each WZs in memory
    signal result_found                         : std_logic := '0';                                     -- Whether the AOU Controller has found a valid result
    signal address_loaded, address_loaded_next  : std_logic := '0';                                     -- Whether the address has been loaded from RAM
    signal calculated_result                    : std_logic_vector(7 downto 0);                         -- The result outputted by the AOU Controller

    signal o_address_next                       : std_logic_vector(15 downto 0) := (others => '0');
    signal o_en_next                            : std_logic := '0';
    signal o_we_next                            : std_logic := '0';
    signal o_done_next                          : std_logic := '0';
    signal o_data_next                          : std_logic_vector(7 downto 0) := (others => '0');

    component aou_controller is
        port(
            i_wz_array      : wz_array;
            i_wz_valid      : wz_valid_array;
            i_address       : in std_logic_vector(7 downto 0);
            o_result_found  : out std_logic;
            o_result        : out std_logic_vector(7 downto 0)
        );
    end component;
begin
    CONTROLLER: aou_controller
    port map(
        i_wz_array         => wz_addresses,
        i_wz_valid         => wz_valid,
        i_address          => address,
        o_result_found     => result_found,
        o_result           => calculated_result
    );

    STATE_OUTPUT: process(i_clk, i_rst)
    -- The sequential process which asserts outputs and saves the values for the state
    begin
        if (i_rst = '1') then
            -- Asynchronously reset the machine
            curr_wz <= 0;
            address <= (others => '0');
            curr_state <= IDLING;
            wz_addresses <= (others => (others => '0'));
            wz_valid <= (others => '0');
            address_loaded <= '0';
        elsif rising_edge(i_clk) then
            -- Assign values to current state
            curr_wz <= next_wz;
            address <= address_next;
            curr_state <= next_state;
            wz_addresses <= wz_addresses_next;
            wz_valid <= wz_valid_next;
            address_loaded <= address_loaded_next;
            -- Assert outputs
            o_address <= o_address_next;
            o_en <= o_en_next;
            o_we <= o_we_next;
            o_data <= o_data_next;
            o_done <= o_done_next;
        end if;
    end process;

    DELTA_LAMBDA: process(i_data, i_start, curr_wz, curr_state, address, wz_addresses, wz_valid, result_found, calculated_result, address_loaded)
    -- The combinatorial process which computes the next state and the next output from the current state and the current input
    begin
        -- Signal assignments to avoid inferred latches
        o_address_next      <= (others => '0');
        o_en_next           <= '0';
        o_we_next           <= '0';
        o_done_next         <= '0';
        o_data_next         <= (others => '0');
        wz_addresses_next   <= wz_addresses;
        wz_valid_next       <= wz_valid;
        next_wz             <= curr_wz;
        address_next        <= address;
        next_state          <= curr_state;
        address_loaded_next <= address_loaded;

        case curr_state is
            when IDLING =>
                if(i_start = '1') then
                    o_done_next <= '0';
                    next_state <= SET_READ_ADDR;
                end if;

            when SET_READ_ADDR =>
                o_en_next <= '1';
                o_we_next <= '0';
                o_address_next <= std_logic_vector(to_unsigned(ADDR_RAM_POS, 16));
                next_state <= WAIT_READ_ADDR;

            when WAIT_READ_ADDR =>
                next_state <= FETCH_DATA_ADDR;

            when FETCH_DATA_ADDR =>
                address_next <= i_data;
                next_state <= SET_READ_WZ;
                address_loaded_next <= '1';

            when SET_READ_WZ =>
                if (result_found = '1' AND address_loaded = '1') then
                    -- If the result has been found while still loading WZs, go write the result
                    next_state <= SET_WRITE;
                else
                    -- Otherwise keep on loading the WZs
                    o_en_next <= '1';
                    o_we_next <= '0';
                    o_address_next <= std_logic_vector(to_unsigned(curr_wz, 16));
                    next_state <= WAIT_READ_WZ;
                end if;

            when WAIT_READ_WZ =>
                next_state <= FETCH_DATA_WZ;

            when FETCH_DATA_WZ =>
                wz_addresses_next(curr_wz) <= i_data;
                wz_valid_next(curr_wz) <= '1';
                if(curr_wz = ADDR_RAM_POS-1) then
                    -- All WZ have been loaded
                    next_wz <= 0;
                    next_state <= WAIT_RESULT;
                else
                    -- Load next WZ
                    next_wz <= curr_wz + 1;
                    next_state <= SET_READ_WZ;
                end if;

            when WAIT_RESULT =>
                next_state <= SET_WRITE;

            when SET_WRITE =>
                o_en_next <= '1';
                o_we_next <= '1';
                o_address_next <= std_logic_vector(to_unsigned(9, 16));
                o_data_next <= calculated_result;
                o_done_next <= '1';
                next_state <= END_WRITE;
                address_loaded_next <= '0';
                address_next <= (others => '0');

            when END_WRITE =>
                if(i_start = '0') then
                    o_done_next <= '0';
                    next_state <= IDLING;
                end if;
        end case;
    end process;
end behavioural;
