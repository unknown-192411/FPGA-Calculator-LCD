`timescale 1ns / 1ps

// Main Top Level Module
module calculator(
    input clk,               // 12MHz Clock
    input [3:0] kp_row,      // Keypad Rows (Inputs with Pullups)
    output [3:0] kp_col,     // Keypad Columns (Outputs)
    output uart_tx_pin,      // UART TX to ESP32 (Baud 9600)
    output led_ind           // Indicator LED for Keypress
);

    // --------------------------------------------------------
    // 1. Matrix Keypad Scanner
    // --------------------------------------------------------
    wire [3:0] key_val;
    wire key_pressed;
    wire key_active;
    
    // Light up the onboard LED whenever a key is held down
    assign led_ind = key_active; 
    
    keypad_scanner scanner(
        .clk(clk),
        .row(kp_row),
        .col(kp_col),
        .key_val(key_val),
        .key_pressed(key_pressed),
        .key_active(key_active)
    );

    // --------------------------------------------------------
    // 2. Calculator Logic (Typing & Operations)
    // --------------------------------------------------------
    reg [7:0] accumulator = 0; // Holds the number currently being typed
    reg [7:0] regA = 0;
    reg [7:0] regB = 0;
    reg [1:0] state = 0;       // 0: Entering A, 1: Entering B, 2: Result Shown
    reg [1:0] op = 0;          // 0: None, 1: Add, 2: Sub
    reg tx_req = 0;            // Trigger UART transmission

    // Wire to check if multiplying by 10 will exceed 8-bit limit (255)
    wire [15:0] next_acc = (accumulator * 10) + key_val;

    always @(posedge clk) begin
        tx_req <= 0; // Default: don't transmit
        
        if (key_pressed) begin
            tx_req <= 1; // Send display update to ESP32 on ANY key press
            
            if (key_val <= 9) begin 
                // --- Number Keys (0-9) ---
                if (state == 2) begin
                    // If result was showing, start a brand new calculation
                    accumulator <= key_val;
                    state <= 0;
                    op <= 0;
                end else begin
                    // Append digit if it doesn't overflow 255
                    if (next_acc <= 255) accumulator <= next_acc[7:0];
                end
                
            end else if (key_val == 10) begin 
                // --- 'A' Key: ADD ---
                regA <= (state == 2) ? regA : accumulator; // Allow chaining
                accumulator <= 0;
                op <= 1;
                state <= 1;
                
            end else if (key_val == 11) begin 
                // --- 'B' Key: SUBTRACT ---
                regA <= (state == 2) ? regA : accumulator;
                accumulator <= 0;
                op <= 2;
                state <= 1;
                
            end else if (key_val == 13) begin 
                // --- 'D' Key: EQUALS ---
                regB <= accumulator;
                state <= 2;
                
            end else if (key_val == 12) begin 
                // --- 'C' Key: CLEAR ---
                accumulator <= 0;
                regA <= 0;
                regB <= 0;
                op <= 0;
                state <= 0;
            end
        end
    end

    // Async Math Logic
    wire [8:0] sum = regA + regB;
    wire [8:0] diff = (regA >= regB) ? (regA - regB) : (regB - regA);
    wire is_neg = (op == 2) && (regA < regB);
    wire [8:0] calc_res = (op == 1) ? sum : (op == 2) ? diff : 0;

    // --------------------------------------------------------
    // 3. UART Transmitter (Dynamic ESP32 Data Formatting)
    // --------------------------------------------------------
    // Send live accumulator data so the LCD updates as you type
    wire [7:0] send_A   = (state == 0) ? accumulator : regA;
    wire [7:0] send_B   = (state == 1) ? accumulator : regB;
    wire [8:0] send_res = (state == 2) ? calc_res : 0;
    wire       send_neg = (state == 2) ? is_neg : 0;

    wire [7:0] packet [0:7];
    assign packet[0] = 8'hAA; // Start byte
    assign packet[1] = send_A;
    assign packet[2] = send_B;
    assign packet[3] = {6'b0, op};
    assign packet[4] = {7'b0, send_res[8]}; // High byte
    assign packet[5] = send_res[7:0];       // Low byte
    assign packet[6] = {7'b0, send_neg};
    assign packet[7] = 8'h55; // End byte

    reg [2:0] tx_sm = 0;
    reg [2:0] byte_idx = 0;
    reg tx_start = 0;
    reg [7:0] tx_data_reg = 0;
    wire tx_busy;

    always @(posedge clk) begin
        case(tx_sm)
            0: begin
                if (tx_req) begin
                    tx_sm <= 1;
                    byte_idx <= 0;
                end
            end
            1: begin
                if (!tx_busy) begin
                    tx_data_reg <= packet[byte_idx];
                    tx_start <= 1;
                    tx_sm <= 2;
                end
            end
            2: begin
                tx_start <= 0;
                tx_sm <= 3;
            end
            3: begin
                if (!tx_busy) begin
                    if (byte_idx == 7) tx_sm <= 0;
                    else begin
                        byte_idx <= byte_idx + 1;
                        tx_sm <= 1;
                    end
                end
            end
        endcase
    end

    uart_tx my_uart(.clk(clk), .tx_start(tx_start), .tx_data(tx_data_reg), .tx_pin(uart_tx_pin), .tx_busy(tx_busy));

endmodule

// ========================================================
// Helper Module: Matrix Keypad Scanner
// ========================================================
module keypad_scanner(
    input clk,
    input [3:0] row,
    output reg [3:0] col = 4'b1110,
    output reg [3:0] key_val = 0,
    output reg key_pressed = 0,
    output reg key_active = 0
);
    reg [15:0] timer = 0;
    reg [1:0] scan_idx = 0;

    always @(posedge clk) begin
        timer <= timer + 1;
        key_pressed <= 0; // Pulse high for only 1 clock cycle

        // ~5.4ms timer for debouncing and scanning pace (12MHz clock)
        if (timer == 0) begin
            if (row != 4'b1111) begin
                // A key is physically pressed
                if (!key_active) begin
                    key_active <= 1;
                    key_pressed <= 1; 
                    // Decode matrix intersection
                    case(col)
                        4'b1110: key_val <= (~row[0])? 1 : (~row[1])? 4 : (~row[2])? 7 : 14; // Col 1
                        4'b1101: key_val <= (~row[0])? 2 : (~row[1])? 5 : (~row[2])? 8 : 0;  // Col 2
                        4'b1011: key_val <= (~row[0])? 3 : (~row[1])? 6 : (~row[2])? 9 : 15; // Col 3
                        4'b0111: key_val <= (~row[0])? 10: (~row[1])? 11: (~row[2])? 12: 13; // Col 4
                        default: key_val <= 0;
                    endcase
                end
            end else begin
                if (key_active) begin
                    // Wait for key release before scanning again
                    key_active <= 0;
                end else begin
                    // Move to the next column
                    scan_idx <= scan_idx + 1;
                    case(scan_idx + 1)
                        2'd0: col <= 4'b1110;
                        2'd1: col <= 4'b1101;
                        2'd2: col <= 4'b1011;
                        2'd3: col <= 4'b0111;
                    endcase
                end
            end
        end
    end
endmodule

// ========================================================
// Helper Module: UART TX
// ========================================================
module uart_tx #(parameter CLKS_PER_BIT = 1250) (
    input clk, input tx_start, input [7:0] tx_data, output reg tx_pin = 1, output reg tx_busy = 0
);
    reg [2:0] state = 0; reg [10:0] clk_count = 0; reg [2:0] bit_idx = 0; reg [7:0] data_reg = 0;
    always @(posedge clk) begin
        case (state)
            0: begin tx_pin<=1; tx_busy<=0; if(tx_start) begin data_reg<=tx_data; tx_busy<=1; clk_count<=0; state<=1; end end
            1: begin tx_pin<=0; if(clk_count<CLKS_PER_BIT-1) clk_count<=clk_count+1; else begin clk_count<=0; bit_idx<=0; state<=2; end end
            2: begin tx_pin<=data_reg[bit_idx]; if(clk_count<CLKS_PER_BIT-1) clk_count<=clk_count+1; else begin clk_count<=0; if(bit_idx<7) bit_idx<=bit_idx+1; else state<=3; end end
            3: begin tx_pin<=1; if(clk_count<CLKS_PER_BIT-1) clk_count<=clk_count+1; else begin clk_count<=0; state<=0; end end
            default: state <= 0;
        endcase
    end
endmodule