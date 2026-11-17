// ============================================================================
// File        : tb_basic_axi4lite_apb_bridge.sv
// Author      : Vijay Kumar
// Description : Self-Checking Testbench for Baseline Single-Slave AXI4-Lite
//               to APB3 Bridge (basic_axi4lite_apb_bridge.sv)
// ============================================================================

`timescale 1ns / 1ps

module tb_basic_axi4lite_apb_bridge;

    localparam int ADDR_W = 32;
    localparam int DATA_W = 32;

    logic                aclk;
    logic                aresetn;

    // AXI4-Lite Write Address Channel
    logic [ADDR_W-1:0]   s_axi_awaddr;
    logic                s_axi_awvalid;
    logic                s_axi_awready;

    // AXI4-Lite Write Data Channel
    logic [DATA_W-1:0]   s_axi_wdata;
    logic [DATA_W/8-1:0] s_axi_wstrb;
    logic                s_axi_wvalid;
    logic                s_axi_wready;

    // AXI4-Lite Write Response Channel
    logic [1:0]          s_axi_bresp;
    logic                s_axi_bvalid;
    logic                s_axi_bready;

    // AXI4-Lite Read Address Channel
    logic [ADDR_W-1:0]   s_axi_araddr;
    logic                s_axi_arvalid;
    logic                s_axi_arready;

    // AXI4-Lite Read Data Channel
    logic [DATA_W-1:0]   s_axi_rdata;
    logic [1:0]          s_axi_rresp;
    logic                s_axi_rvalid;
    logic                s_axi_rready;

    // APB3 Master Interface (Single Slave)
    logic [ADDR_W-1:0]   m_apb_paddr;
    logic                m_apb_psel;
    logic                m_apb_penable;
    logic                m_apb_pwrite;
    logic [DATA_W-1:0]   m_apb_pwdata;
    logic [DATA_W-1:0]   m_apb_prdata;
    logic                m_apb_pready;
    logic                m_apb_pslverr;

    // 200 MHz Clock Generator (5.000 ns period)
    initial aclk = 1'b0;
    always #2.5 aclk = ~aclk;

    // DUT Instantiation
    basic_axi4lite_apb_bridge #(
        .ADDR_W (ADDR_W),
        .DATA_W (DATA_W)
    ) dut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .m_apb_paddr   (m_apb_paddr),
        .m_apb_psel    (m_apb_psel),
        .m_apb_penable (m_apb_penable),
        .m_apb_pwrite  (m_apb_pwrite),
        .m_apb_pwdata  (m_apb_pwdata),
        .m_apb_prdata  (m_apb_prdata),
        .m_apb_pready  (m_apb_pready),
        .m_apb_pslverr (m_apb_pslverr)
    );

    // ========================================================================
    // SINGLE-SLAVE APB3 PERIPHERAL MEMORY MODEL
    // ========================================================================
    logic [DATA_W-1:0] apb_mem [0:15];
    int                inject_wait_cycles = 0;
    bit                inject_pslverr     = 0;
    int                wait_cnt           = 0;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            m_apb_pready  <= 1'b0;
            m_apb_pslverr <= 1'b0;
            m_apb_prdata  <= '0;
            wait_cnt      <= 0;
            for (int i = 0; i < 16; i++)
                apb_mem[i] <= 32'h0000_0000;
        end else begin
            int reg_idx;
            m_apb_pready  <= 1'b0;
            m_apb_pslverr <= 1'b0;

            if (m_apb_psel && m_apb_penable) begin
                if (wait_cnt < inject_wait_cycles) begin
                    m_apb_pready <= 1'b0;
                    wait_cnt     <= wait_cnt + 1;
                end else begin
                    m_apb_pready  <= 1'b1;
                    m_apb_pslverr <= inject_pslverr;
                    wait_cnt      <= 0;

                    reg_idx = m_apb_paddr[5:2];
                    if (m_apb_pwrite) begin
                        apb_mem[reg_idx] <= m_apb_pwdata;
                    end else begin
                        m_apb_prdata <= apb_mem[reg_idx];
                    end
                end
            end else begin
                wait_cnt <= 0;
            end
        end
    end

    // ========================================================================
    // AXI4-LITE MASTER TASKS & SCOREBOARD
    // ========================================================================
    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic axi_write(
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] data,
        input logic [1:0]        exp_resp
    );
        @(posedge aclk);
        s_axi_awaddr  <= addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= 4'hF;
        s_axi_wvalid  <= 1'b1;
        s_axi_bready  <= 1'b1;

        wait (s_axi_awready && s_axi_wready);
        @(posedge aclk);
        s_axi_awvalid <= 1'b0;
        s_axi_wvalid  <= 1'b0;

        wait (s_axi_bvalid);
        @(posedge aclk);
        if (s_axi_bresp === exp_resp) begin
            pass_cnt++;
        end else begin
            $error("[BASELINE FAIL] Write Addr=%0h ExpResp=%b ActResp=%b", addr, exp_resp, s_axi_bresp);
            fail_cnt++;
        end
        s_axi_bready <= 1'b0;
    endtask

    task automatic axi_read(
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] exp_data,
        input logic [1:0]        exp_resp,
        input bit                check_data = 1'b1
    );
        @(posedge aclk);
        s_axi_araddr  <= addr;
        s_axi_arvalid <= 1'b1;
        s_axi_rready  <= 1'b1;

        wait (s_axi_arready);
        @(posedge aclk);
        s_axi_arvalid <= 1'b0;

        wait (s_axi_rvalid);
        @(posedge aclk);
        if (s_axi_rresp !== exp_resp) begin
            $error("[BASELINE FAIL] Read Addr=%0h ExpResp=%b ActResp=%b", addr, exp_resp, s_axi_rresp);
            fail_cnt++;
        end else if (check_data && (s_axi_rdata !== exp_data)) begin
            $error("[BASELINE FAIL] Read Addr=%0h ExpData=%0h ActData=%0h", addr, exp_data, s_axi_rdata);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
        s_axi_rready <= 1'b0;
    endtask

    // ========================================================================
    // MAIN TEST SEQUENCE
    // ========================================================================
    initial begin
        aresetn       = 1'b0;
        s_axi_awaddr  = '0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = '0;
        s_axi_wstrb   = '0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_araddr  = '0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;

        repeat (5) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);

        // 1. Zero-Wait-State Write & Read Sweep (16 Registers)
        inject_wait_cycles = 0;
        inject_pslverr     = 0;
        for (int i = 0; i < 16; i++) begin
            logic [31:0] addr = 32'h4000_0000 + (i << 2);
            logic [31:0] val  = 32'hA5A5_0000 + i;
            axi_write(addr, val, 2'b00);
            axi_read(addr, val, 2'b00, 1'b1);
        end

        // 2. APB Wait-State Stall Test (3 Wait-States per Transfer)
        inject_wait_cycles = 3;
        axi_write(32'h4000_0010, 32'h1234_5678, 2'b00);
        axi_read(32'h4000_0010, 32'h1234_5678, 2'b00, 1'b1);
        inject_wait_cycles = 0;

        // 3. Slave Error (PSLVERR -> AXI SLVERR 2'b10) Propagation Test
        inject_pslverr = 1;
        axi_write(32'h4000_0020, 32'hDEAD_BEEF, 2'b10);
        axi_read(32'h4000_0020, 32'h0, 2'b10, 1'b0);
        inject_pslverr = 0;

        repeat (5) @(posedge aclk);

        $display("\n=======================================================");
        $display(" BASELINE BRIDGE SUMMARY : PASS = %0d | FAIL = %0d", pass_cnt, fail_cnt);
        $display("=======================================================\n");

        if (fail_cnt == 0)
            $display("BASELINE VERIFICATION PASSED!");
        else
            $fatal(1, "BASELINE VERIFICATION FAILED!");

        $finish;
    end

endmodule