`timescale 1ns / 1ps

interface axi4lite_apb_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int NUM_SLAVES = 4
) (
    input logic aclk,
    input logic aresetn
);

    // -------------------------------------------------------------------------
    // 1. AXI4-Lite Slave Interface Signals (Connected to Bridge Slave Port)
    // -------------------------------------------------------------------------
    // Write Address Channel
    logic [ADDR_WIDTH-1:0]     s_axi_awaddr;
    logic [2:0]                s_axi_awprot;
    logic                      s_axi_awvalid;
    logic                      s_axi_awready;

    // Write Data Channel
    logic [DATA_WIDTH-1:0]     s_axi_wdata;
    logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb;
    logic                      s_axi_wvalid;
    logic                      s_axi_wready;

    // Write Response Channel
    logic [1:0]                s_axi_bresp;
    logic                      s_axi_bvalid;
    logic                      s_axi_bready;

    // Read Address Channel
    logic [ADDR_WIDTH-1:0]     s_axi_araddr;
    logic [2:0]                s_axi_arprot;
    logic                      s_axi_arvalid;
    logic                      s_axi_arready;

    // Read Data Channel
    logic [DATA_WIDTH-1:0]     s_axi_rdata;
    logic [1:0]                s_axi_rresp;
    logic                      s_axi_rvalid;
    logic                      s_axi_rready;

    // -------------------------------------------------------------------------
    // 2. Multi-Slave APB3 Master Interface Signals (1-to-4 Decoder)
    // -------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0]     m_apb_paddr;
    logic [NUM_SLAVES-1:0]     m_apb_psel;
    logic                      m_apb_penable;
    logic                      m_apb_pwrite;
    logic [DATA_WIDTH-1:0]     m_apb_pwdata;
    logic [DATA_WIDTH-1:0]     m_apb_prdata;
    logic                      m_apb_pready;
    logic                      m_apb_pslverr;

    // -------------------------------------------------------------------------
    // 3. Clocking Blocks (Zero-Race Driver & Monitor Synchronization)
    // -------------------------------------------------------------------------
    clocking drv_cb @(posedge aclk);
        default input #1step output #1ns;
        // AXI4-Lite Master Driver outputs
        output s_axi_awaddr, s_axi_awprot, s_axi_awvalid;
        input  s_axi_awready;

        output s_axi_wdata, s_axi_wstrb, s_axi_wvalid;
        input  s_axi_wready;

        input  s_axi_bresp, s_axi_bvalid;
        output s_axi_bready;

        output s_axi_araddr, s_axi_arprot, s_axi_arvalid;
        input  s_axi_arready;

        input  s_axi_rdata, s_axi_rresp, s_axi_rvalid;
        output s_axi_rready;

        // APB3 Slave Responder outputs (for fault/wait-state injection)
        input  m_apb_paddr, m_apb_psel, m_apb_penable, m_apb_pwrite, m_apb_pwdata;
        output m_apb_prdata, m_apb_pready, m_apb_pslverr;
    endclocking

    clocking mon_cb @(posedge aclk);
        default input #1step;
        input s_axi_awaddr, s_axi_awprot, s_axi_awvalid, s_axi_awready;
        input s_axi_wdata, s_axi_wstrb, s_axi_wvalid, s_axi_wready;
        input s_axi_bresp, s_axi_bvalid, s_axi_bready;
        input s_axi_araddr, s_axi_arprot, s_axi_arvalid, s_axi_arready;
        input s_axi_rdata, s_axi_rresp, s_axi_rvalid, s_axi_rready;
        input m_apb_paddr, m_apb_psel, m_apb_penable, m_apb_pwrite, m_apb_pwdata;
        input m_apb_prdata, m_apb_pready, m_apb_pslverr;
    endclocking

    // -------------------------------------------------------------------------
    // 4. Modports
    // -------------------------------------------------------------------------
    modport DRV (clocking drv_cb, input aclk, aresetn);
    modport MON (clocking mon_cb, input aclk, aresetn);

    // -------------------------------------------------------------------------
    // 5. Concurrent SystemVerilog Assertions (Protocol & Low-Power Checks)
    // -------------------------------------------------------------------------

    // A1: One-Hot or Zero Peripheral Selection ($onehot0 prevents bus contention)
    property p_apb_psel_onehot0;
        @(posedge aclk) disable iff (!aresetn)
        $onehot0(m_apb_psel);
    endproperty
    assert_apb_psel_onehot0: assert property (p_apb_psel_onehot0)
        else $error("[SVA FAIL] m_apb_psel is not one-hot: %b", m_apb_psel);

    // A2: APB3 SETUP -> ACCESS Phase Transition
    // PENABLE must assert 1 cycle after PSEL goes high from idle
    property p_apb_setup_to_access;
        @(posedge aclk) disable iff (!aresetn)
        (|m_apb_psel && !m_apb_penable) |=> (|m_apb_psel && m_apb_penable);
    endproperty
    assert_apb_setup_to_access: assert property (p_apb_setup_to_access)
        else $error("[SVA FAIL] APB3 illegal SETUP to ACCESS transition");

    // A3: APB3 Signal Stability During Wait States (ACCESS phase while !PREADY)
    property p_apb_wait_state_stability;
        @(posedge aclk) disable iff (!aresetn)
        (|m_apb_psel && m_apb_penable && !m_apb_pready) |=>
            ($stable(m_apb_psel) && $stable(m_apb_paddr) &&
             $stable(m_apb_pwrite) && (!m_apb_pwrite || $stable(m_apb_pwdata)));
    endproperty
    assert_apb_wait_state_stability: assert property (p_apb_wait_state_stability)
        else $error("[SVA FAIL] APB3 control/addr/wdata changed during wait state");

    // A4: Low-Power Idle-Bus Operand Isolation Check
    // When no APB slave is selected (m_apb_psel == 0), PADDR and PWDATA must clamp to 0
    property p_apb_idle_operand_isolation;
        @(posedge aclk) disable iff (!aresetn)
        (m_apb_psel == '0) |-> (m_apb_paddr == '0 && m_apb_pwdata == '0 && !m_apb_penable);
    endproperty
    assert_apb_idle_operand_isolation: assert property (p_apb_idle_operand_isolation)
        else $error("[SVA FAIL] Operand isolation violated during APB idle state");

    // A5: AXI4-Lite AWVALID/AWADDR Stability Until AWREADY Handshake
    property p_axi_aw_handshake_stability;
        @(posedge aclk) disable iff (!aresetn)
        (s_axi_awvalid && !s_axi_awready) |=> (s_axi_awvalid && $stable(s_axi_awaddr));
    endproperty
    assert_axi_aw_handshake_stability: assert property (p_axi_aw_handshake_stability)
        else $error("[SVA FAIL] AXI4-Lite AWVALID/AWADDR unstable before AWREADY");

    // A6: AXI4-Lite WVALID/WDATA/WSTRB Stability Until WREADY Handshake
    property p_axi_w_handshake_stability;
        @(posedge aclk) disable iff (!aresetn)
        (s_axi_wvalid && !s_axi_wready) |=> (s_axi_wvalid && $stable(s_axi_wdata) && $stable(s_axi_wstrb));
    endproperty
    assert_axi_w_handshake_stability: assert property (p_axi_w_handshake_stability)
        else $error("[SVA FAIL] AXI4-Lite WVALID/WDATA unstable before WREADY");

    // A7: AXI4-Lite ARVALID/ARADDR Stability Until ARREADY Handshake
    property p_axi_ar_handshake_stability;
        @(posedge aclk) disable iff (!aresetn)
        (s_axi_arvalid && !s_axi_arready) |=> (s_axi_arvalid && $stable(s_axi_araddr));
    endproperty
    assert_axi_ar_handshake_stability: assert property (p_axi_ar_handshake_stability)
        else $error("[SVA FAIL] AXI4-Lite ARVALID/ARADDR unstable before ARREADY");

endinterface