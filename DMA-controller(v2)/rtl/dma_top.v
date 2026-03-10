module dma_top (
    input  wire        clk,
    input  wire        rst_n,

    // APB Slave Interface (Configuration)
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] paddr,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // Interrupt
    output reg         dma_irq,

    // AXI4 Master Interface
    // Read Address
    output wire [31:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    // Read Data
    input  wire [31:0] m_axi_rdata,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,
    // Write Address
    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    // Write Data
    output wire [31:0] m_axi_wdata,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    // Write Resp
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready
);

    // Internal Signals
    wire [31:0] cfg_src_addr, cfg_dst_addr, cfg_byte_len;
    wire        cfg_start, clear_irq;
    wire        status_busy, status_done;
    
    wire        fifo_full, fifo_empty;
    wire        fifo_wr_en, fifo_rd_en;
    wire [31:0] fifo_wdata, fifo_rdata;

    // 1. APB Slave Instantiation
    dma_apb_slave u_slave (
        .pclk(clk),
        .presetn(rst_n),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .cfg_src_addr(cfg_src_addr),
        .cfg_dst_addr(cfg_dst_addr),
        .cfg_byte_len(cfg_byte_len),
        .cfg_start(cfg_start),
        .status_done(status_done),
        .status_busy(status_busy),
        .clear_irq(clear_irq)
    );

    // 2. Latch-based FIFO Instantiation
    dma_fifo_latch #(
        .DEPTH(16)
    ) u_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(fifo_wr_en),
        .wdata(fifo_wdata),
        .rd_en(fifo_rd_en),
        .rdata(fifo_rdata),
        .full(fifo_full),
        .empty(fifo_empty)
    );

    // 3. AXI4 Master (Decoupled) Instantiation
    dma_axi_master u_master (
        .aclk(clk),
        .aresetn(rst_n),
        .cfg_src_addr(cfg_src_addr),
        .cfg_dst_addr(cfg_dst_addr),
        .cfg_byte_len(cfg_byte_len),
        .cfg_start(cfg_start),
        .status_busy(status_busy),
        .status_done(status_done),
        .fifo_full(fifo_full),
        .fifo_empty(fifo_empty),
        .fifo_wr_en(fifo_wr_en),
        .fifo_wdata(fifo_wdata),
        .fifo_rd_en(fifo_rd_en),
        .fifo_rdata(fifo_rdata),
        // AXI Mappings
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

    // Interrupt Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dma_irq <= 0;
        else if (status_done) dma_irq <= 1;
        else if (clear_irq) dma_irq <= 0;
    end

endmodule