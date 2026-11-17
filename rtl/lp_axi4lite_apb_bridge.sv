

// ============================================================================
// File        : lp_axi4lite_apb_bridge.sv
// Author      : Vijay Kumar
// Description : Low-Power Fault-Tolerant AXI4-Lite to APB3 Bridge
//
// Architectural Optimizations:
//   1. 4-Slave Address Decoder (PSEL[3:0] via ADDR[13:12]) + Out-of-Bounds Check
//   2. 16-Cycle APB Timeout Watchdog: Aborts hung PREADY==0 slaves and returns
//      AXI SLVERR (2'b10) with timeout_err telemetry pulse to prevent bus lockup.
//   3. Low-Power Operand Isolation: Clamps PADDR, PWDATA, and PWRITE to 0
//      whenever PSEL == 0, eliminating downstream peripheral bus switching.
// ============================================================================

`timescale 1ns / 1ps

module lp_axi4lite_apb_bridge #(
    parameter int ADDR_W        = 32,
    parameter int DATA_W        = 32,
    parameter int NUM_SLAVES    = 4,
    parameter int TIMEOUT_LIMIT = 16
) (
    input  logic                  aclk,
    input  logic                  aresetn,

    // AXI4-Lite Write Address Channel
    input  logic [ADDR_W-1:0]     s_axi_awaddr,
    input  logic                  s_axi_awvalid,
    output logic                  s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  logic [DATA_W-1:0]     s_axi_wdata,
    input  logic [DATA_W/8-1:0]   s_axi_wstrb,
    input  logic                  s_axi_wvalid,
    output logic                  s_axi_wready,

    // AXI4-Lite Write Response Channel
    output logic [1:0]            s_axi_bresp,
    output logic                  s_axi_bvalid,
    input  logic                  s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  logic [ADDR_W-1:0]     s_axi_araddr,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,

    // AXI4-Lite Read Data Channel
    output logic [DATA_W-1:0]     s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,

    // Multi-Slave APB3 Master Interface
    output logic [ADDR_W-1:0]     m_apb_paddr,
    output logic [NUM_SLAVES-1:0] m_apb_psel,
    output logic                  m_apb_penable,
    output logic                  m_apb_pwrite,
    output logic [DATA_W-1:0]     m_apb_pwdata,
    input  logic [DATA_W-1:0]     m_apb_prdata,
    input  logic                  m_apb_pready,
    input  logic                  m_apb_pslverr,

    // Fault Telemetry Output
    output logic                  timeout_err
);

    typedef enum logic [1:0] {
        ST_IDLE   = 2'b00,
        ST_SETUP  = 2'b01,
        ST_ACCESS = 2'b10,
        ST_RESP   = 2'b11
    } state_t;

    state_t state;
    logic   is_write;
    logic [$clog2(TIMEOUT_LIMIT):0] timeout_cnt;

    // Internal gated registers before operand isolation clamping
    logic [ADDR_W-1:0] paddr_reg;
    logic [DATA_W-1:0] pwdata_reg;
    logic              pwrite_reg;

    // ------------------------------------------------------------------------
    // Optimization 1: Combinational 4-Slave Address Decoder (ADDR[13:12])
    // ------------------------------------------------------------------------
    function automatic logic [NUM_SLAVES-1:0] decode_psel(input logic [ADDR_W-1:0] addr);
        logic [NUM_SLAVES-1:0] sel;
        sel = '0;
        if (addr[31:16] == 16'h4000) begin // Valid APB peripheral window: 0x4000_0000 - 0x4000_3FFF
            case (addr[13:12])
                2'd0: sel = 4'b0001;
                2'd1: sel = 4'b0010;
                2'd2: sel = 4'b0100;
                2'd3: sel = 4'b1000;
            endcase
        end
        return sel;
    endfunction

    // ------------------------------------------------------------------------
    // Optimization 2: Low-Power Operand Isolation Output Clamping
    // Zero-clamps APB address/data/write buses whenever no slave is selected
    // ------------------------------------------------------------------------
    wire bus_active = |m_apb_psel;
    assign m_apb_paddr  = bus_active ? paddr_reg  : '0;
    assign m_apb_pwdata = (bus_active && pwrite_reg) ? pwdata_reg : '0;
    assign m_apb_pwrite = bus_active ? pwrite_reg : 1'b0;

    // ------------------------------------------------------------------------
    // Main APB Bridge FSM + Watchdog Counter
    // ------------------------------------------------------------------------
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state         <= ST_IDLE;
            is_write      <= 1'b0;
            timeout_cnt   <= '0;
            timeout_err   <= 1'b0;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= '0;
            s_axi_rresp   <= 2'b00;
            m_apb_psel    <= '0;
            m_apb_penable <= 1'b0;
            paddr_reg     <= '0;
            pwdata_reg    <= '0;
            pwrite_reg    <= 1'b0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_arready <= 1'b0;
            timeout_err   <= 1'b0;

            case (state)
                ST_IDLE: begin
                    m_apb_psel    <= '0;
                    m_apb_penable <= 1'b0;
                    timeout_cnt   <= '0;

                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 1'b1;
                        s_axi_wready  <= 1'b1;
                        is_write      <= 1'b1;

                        if (decode_psel(s_axi_awaddr) == '0) begin
                            // Immediate SLVERR for unmapped address (zero APB power)
                            s_axi_bvalid <= 1'b1;
                            s_axi_bresp  <= 2'b10; // SLVERR
                            state        <= ST_RESP;
                        end else begin
                            paddr_reg  <= s_axi_awaddr;
                            pwdata_reg <= s_axi_wdata;
                            pwrite_reg <= 1'b1;
                            m_apb_psel <= decode_psel(s_axi_awaddr);
                            state      <= ST_SETUP;
                        end
                    end else if (s_axi_arvalid) begin
                        s_axi_arready <= 1'b1;
                        is_write      <= 1'b0;

                        if (decode_psel(s_axi_araddr) == '0) begin
                            // Immediate SLVERR for unmapped address
                            s_axi_rvalid <= 1'b1;
                            s_axi_rdata  <= '0;
                            s_axi_rresp  <= 2'b10; // SLVERR
                            state        <= ST_RESP;
                        end else begin
                            paddr_reg  <= s_axi_araddr;
                            pwrite_reg <= 1'b0;
                            m_apb_psel <= decode_psel(s_axi_araddr);
                            state      <= ST_SETUP;
                        end
                    end
                end

                ST_SETUP: begin
                    m_apb_penable <= 1'b1;
                    timeout_cnt   <= '0;
                    state         <= ST_ACCESS;
                end

                ST_ACCESS: begin
                    if (m_apb_pready) begin
                        // Normal slave completion
                        m_apb_psel    <= '0;
                        m_apb_penable <= 1'b0;
                        if (is_write) begin
                            s_axi_bvalid <= 1'b1;
                            s_axi_bresp  <= m_apb_pslverr ? 2'b10 : 2'b00;
                        end else begin
                            s_axi_rvalid <= 1'b1;
                            s_axi_rdata  <= m_apb_prdata;
                            s_axi_rresp  <= m_apb_pslverr ? 2'b10 : 2'b00;
                        end
                        state <= ST_RESP;
                    end else if (timeout_cnt == TIMEOUT_LIMIT - 1) begin
                        // Watchdog timeout abort: prevents SoC bus deadlock
                        m_apb_psel    <= '0;
                        m_apb_penable <= 1'b0;
                        timeout_err   <= 1'b1;
                        if (is_write) begin
                            s_axi_bvalid <= 1'b1;
                            s_axi_bresp  <= 2'b10; // SLVERR
                        end else begin
                            s_axi_rvalid <= 1'b1;
                            s_axi_rdata  <= '0;
                            s_axi_rresp  <= 2'b10; // SLVERR
                        end
                        state <= ST_RESP;
                    end else begin
                        timeout_cnt <= timeout_cnt + 1'b1;
                    end
                end

                ST_RESP: begin
                    if (is_write && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        state        <= ST_IDLE;
                    end else if (!is_write && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        state        <= ST_IDLE;
                    end
                end
            endcase
        end
    end
endmodule