--------------------------------------------------------------------------------
-- Project:       vga-scanner
-- File:          uart_tx.vhd
--
-- Creation date: 2022-03-19
--
-- Author:        FPiorski
-- License:       CERN-OHL-W-2.0
--------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY uart_tx IS
    GENERIC
    (
        g_sys_clk_hz    : positive := 50_000_000;
        g_uart_baud     : positive :=    115_200;
        g_cnt_nibbles   : positive :=          8
    );
    PORT
    (
        --System
        i_clk        : IN    std_logic;
        i_rst_n      : IN    std_logic;

        --UART serial output
        o_uart_tx    :   OUT std_logic;

        --Parallel data input
        i_data       : IN    std_logic_vector;
        i_data_valid : IN    std_logic
    );
END uart_tx;

ARCHITECTURE RTL OF uart_tx IS

    TYPE     T_state IS (IDLE, START, DATA, STOP, INC_CHAR_CNT, WAIT_FOR_VALID_DEASSERT);
    SIGNAL   r_state_cur          : T_state                               := IDLE;
    SIGNAL   w_state_next         : T_state;

    CONSTANT C_clk_cnt_mod        : integer                               := g_sys_clk_hz / g_uart_baud;
    SIGNAL   r_clk_cnt            : integer RANGE 0 TO C_clk_cnt_mod-1    :=  0;
    SIGNAL   r_uart_clk_edge      : std_logic                             := '0';

    CONSTANT C_bit_cnt_mod        : integer                               :=  8;
    SIGNAL   r_bit_cnt            : integer RANGE 0 TO C_bit_cnt_mod-1    :=  0;

    CONSTANT C_char_cnt_mod       : integer                               :=  g_cnt_nibbles+2;
    SIGNAL   r_char_cnt           : integer RANGE 0 TO C_char_cnt_mod-1   :=  0;

    SIGNAL   r_data_in            : std_logic_vector(i_data'RANGE)        := (OTHERS => '0');
    SIGNAL   r_data_out           : std_logic                             := '0';

    FUNCTION slvbit(i_data : std_logic_vector; ix_where : integer) RETURN std_logic IS
    BEGIN
        IF (i_data'ASCENDING) THEN
            RETURN i_data(i_data'HIGH - ix_where);
        ELSE
            RETURN i_data(ix_where);
        END IF;
    END FUNCTION;

    FUNCTION hextoascii(i_data : std_logic_vector) RETURN std_logic_vector IS
    BEGIN
        CASE i_data IS
            WHEN X"0" =>
                RETURN std_logic_vector(to_unsigned(character'POS('0'), 8));
            WHEN X"1" =>
                RETURN std_logic_vector(to_unsigned(character'POS('1'), 8));
            WHEN X"2" =>
                RETURN std_logic_vector(to_unsigned(character'POS('2'), 8));
            WHEN X"3" =>
                RETURN std_logic_vector(to_unsigned(character'POS('3'), 8));
            WHEN X"4" =>
                RETURN std_logic_vector(to_unsigned(character'POS('4'), 8));
            WHEN X"5" =>
                RETURN std_logic_vector(to_unsigned(character'POS('5'), 8));
            WHEN X"6" =>
                RETURN std_logic_vector(to_unsigned(character'POS('6'), 8));
            WHEN X"7" =>
                RETURN std_logic_vector(to_unsigned(character'POS('7'), 8));
            WHEN X"8" =>
                RETURN std_logic_vector(to_unsigned(character'POS('8'), 8));
            WHEN X"9" =>
                RETURN std_logic_vector(to_unsigned(character'POS('9'), 8));
            WHEN X"A" =>
                RETURN std_logic_vector(to_unsigned(character'POS('A'), 8));
            WHEN X"B" =>
                RETURN std_logic_vector(to_unsigned(character'POS('B'), 8));
            WHEN X"C" =>
                RETURN std_logic_vector(to_unsigned(character'POS('C'), 8));
            WHEN X"D" =>
                RETURN std_logic_vector(to_unsigned(character'POS('D'), 8));
            WHEN X"E" =>
                RETURN std_logic_vector(to_unsigned(character'POS('E'), 8));
            WHEN X"F" =>
                RETURN std_logic_vector(to_unsigned(character'POS('F'), 8));

            WHEN OTHERS =>
                RETURN X"3F";
        END CASE;
    END FUNCTION;

BEGIN

    o_uart_tx <= r_data_out;

    P_update_state : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_state_cur <= IDLE;
            ELSE
                r_state_cur <= w_state_next;
            END IF;
        END IF;
    END PROCESS;

    P_decide_next_state : PROCESS(r_state_cur, i_data_valid, r_uart_clk_edge, r_bit_cnt, r_char_cnt)
    BEGIN

        w_state_next <= r_state_cur;

        CASE r_state_cur IS
            WHEN IDLE =>
                IF (i_data_valid = '1') THEN
                    w_state_next <= START;
                END IF;

            WHEN START =>
                IF (r_uart_clk_edge = '1') THEN
                    w_state_next <= DATA;
                END IF;

            WHEN DATA =>
                IF (r_uart_clk_edge = '1' AND r_bit_cnt = C_bit_cnt_mod-1) THEN
                    w_state_next <= STOP;
                END IF;

            WHEN STOP =>
                IF (r_uart_clk_edge = '1') THEN
                    w_state_next <= INC_CHAR_CNT;
                END IF;

            WHEN INC_CHAR_CNT =>
                IF (r_char_cnt >= C_char_cnt_mod-1) THEN
                    w_state_next <= WAIT_FOR_VALID_DEASSERT;
                ELSE
                    w_state_next <= START;
                END IF;

            WHEN WAIT_FOR_VALID_DEASSERT =>
                IF (i_data_valid = '0') THEN
                    w_state_next <= IDLE;
                END IF;

        END CASE;

    END PROCESS;

    P_latch_data : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_data_in <= (OTHERS => '0');
            ELSE
                IF (r_state_cur = IDLE AND i_data_valid = '1') THEN
                    r_data_in <= i_data;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    P_output_data : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_data_out <= '1';
            ELSE
                IF (r_uart_clk_edge = '1') THEN
                    CASE r_state_cur IS
                        WHEN IDLE =>
                            r_data_out <= '1';
                        WHEN START =>
                            r_data_out <= '0';
                        WHEN DATA =>
                            IF    (r_char_cnt < C_char_cnt_mod-2) THEN
                                r_data_out <= slvbit(hextoascii(r_data_in((C_char_cnt_mod-r_char_cnt-2)*4-1 downto (C_char_cnt_mod-r_char_cnt-3)*4)), r_bit_cnt);
                            ELSIF (r_char_cnt = C_char_cnt_mod-2) THEN
                                r_data_out <= slvbit(X"0D", r_bit_cnt);
                            ELSE
                                r_data_out <= slvbit(X"0A", r_bit_cnt);
                            END IF;
                        WHEN STOP =>
                            r_data_out <= '1';
                        WHEN OTHERS =>
                            NULL;
                        END CASE;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    P_bit_cnt : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_bit_cnt <= 0;
            ELSE
                IF (r_uart_clk_edge = '1') THEN
                    IF (r_state_cur = DATA) THEN
                        IF (r_bit_cnt < C_bit_cnt_mod-1) THEN
                            r_bit_cnt <= r_bit_cnt + 1;
                        END IF;
                    ELSE
                        r_bit_cnt <= 0;
                    END IF;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    P_char_cnt : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_char_cnt <= 0;
            ELSE
                IF (r_state_cur = INC_CHAR_CNT) THEN
                    IF (r_char_cnt < C_char_cnt_mod-1) THEN
                        r_char_cnt <= r_char_cnt + 1;
                    END IF;
                ELSIF (r_state_cur = IDLE) THEN
                    r_char_cnt <= 0;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    P_uart_clk : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_clk_cnt       <=  0;
                r_uart_clk_edge <= '0';
            ELSE
                IF (r_clk_cnt < C_clk_cnt_mod-1) THEN
                    r_clk_cnt       <= r_clk_cnt + 1;
                    r_uart_clk_edge <= '0';
                ELSE
                    r_clk_cnt       <=  0;
                    r_uart_clk_edge <= '1';
                END IF;
            END IF;
        END IF;
    END PROCESS;


END ARCHITECTURE;
