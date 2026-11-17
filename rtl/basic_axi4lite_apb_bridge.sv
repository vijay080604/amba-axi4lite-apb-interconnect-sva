// ============================================================================
// File        : basic_axi4lite_apb_bridge.sv
// Author      : Vijay Kumar
// Description : Baseline Single-Slave AXI4-Lite to APB3 Bridge
//               (Used as PPA & SAIF Power Benchmark Reference)
// ============================================================================

`timescale 1ns / 1ps

module basic_axi4lite_apb_bridge #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32
) (         
    input  logic                aclk,
    input  logic                aresetn,

    // AXI4-Lite Write Address Channel
    input  logic [ADDR_W-1:0]   s_axi_awaddr,
    input  logic                s_axi_awvalid,
    output logic                s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  logic [DATA_W-1:0]   s_axi_wdata,
    input  logic [DATA_W/8-1:0] s_axi_wstrb,
    input  logic                s_axi_wvalid,
    output logic                s_axi_wready,

    // AXI4-Lite Write Response Channel
    output logic [1:0]          s_axi_bresp,
    output logic                s_axi_bvalid,
    input  logic                s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  logic [ADDR_W-1:0]   s_axi_araddr,
    input  logic                s_axi_arvalid,
    output logic                s_axi_arready,

    // AXI4-Lite Read Data Channel
    output logic [DATA_W-1:0]   s_axi_rdata,
    output logic [1:0]          s_axi_rresp,
    output logic                s_axi_rvalid,
    input  logic                s_axi_rready,

    // APB3 Master Interface (Single Slave)
    output logic [ADDR_W-1:0]   m_apb_paddr,
    output logic                m_apb_psel,
    output logic                m_apb_penable,
    output logic                m_apb_pwrite,
    output logic [DATA_W-1:0]   m_apb_pwdata,
    input  logic [DATA_W-1:0]   m_apb_prdata,
    input  logic                m_apb_pready,
    input  logic                m_apb_pslverr
);

    typedef enum logic [1:0] {
        ST_IDLE   = 2'b00,
        ST_SETUP  = 2'b01,
        ST_ACCESS = 2'b10,
        ST_RESP   = 2'b11
    } state_t;

    state_t state;
    logic   is_write;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state         <= ST_IDLE;
            is_write      <= 1'b0;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= '0;
            s_axi_rresp   <= 2'b00;
            m_apb_paddr   <= '0;
            m_apb_psel    <= 1'b0;
            m_apb_penable <= 1'b0;
            m_apb_pwrite  <= 1'b0;
            m_apb_pwdata  <= '0;
        end else begin
            // Clear single-cycle ready pulses
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_arready <= 1'b0;

            case (state)
                ST_IDLE: begin
                    m_apb_psel    <= 1'b0;
                    m_apb_penable <= 1'b0;
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 1'b1;
                        s_axi_wready  <= 1'b1;
                        m_apb_paddr   <= s_axi_awaddr;
                        m_apb_pwdata  <= s_axi_wdata;
                        m_apb_pwrite  <= 1'b1;
                        m_apb_psel    <= 1'b1;
                        is_write      <= 1'b1;
                        state         <= ST_SETUP;
                    end else if (s_axi_arvalid) begin
                        s_axi_arready <= 1'b1;
                        m_apb_paddr   <= s_axi_araddr;
                        m_apb_pwrite  <= 1'b0;
                        m_apb_psel    <= 1'b1;
                        is_write      <= 1'b0;
                        state         <= ST_SETUP;
                    end
                end

                ST_SETUP: begin
                    m_apb_penable <= 1'b1;
                    state         <= ST_ACCESS;
                end

                ST_ACCESS: begin
                    if (m_apb_pready) begin
                        m_apb_psel    <= 1'b0;
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