`timescale 1ns / 1ps

module tb_dma_top;

    //Parameters
    parameter CLK_PERIOD = 10; // 100 MHz

    // --- Signals ---
    reg clk;
    reg rst_n;

    // APB Interface (CPU -> DMA)
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] paddr;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;

    // Interrupt
    wire        dma_irq;

    // AXI4 Interface (DMA -> System Memory)
    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid;
    reg         m_axi_arready;

    reg  [31:0] m_axi_rdata;
    reg         m_axi_rlast;
    reg         m_axi_rvalid;
    wire        m_axi_rready;

    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    reg         m_axi_awready;

    wire [31:0] m_axi_wdata;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    reg         m_axi_wready;

    reg         m_axi_bvalid;
    wire        m_axi_bready;

    // --- Instantiate DMA TOP ---
    dma_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        
        // APB
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        
        // IRQ
        .dma_irq(dma_irq),
        
        // AXI Read
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
        
        // AXI Write
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

    // --- Clock Generation ---
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Simulation Memory (Byte Addressable) ---
    reg [7:0] main_memory [0:4095]; // 4KB Mock RAM

    // Initialize Memory with patterns
    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            main_memory[i] = i[7:0]; // Data = Address LSB
        end
    end

    // --- AXI4 Slave Logic (Mock Memory Controller) ---
    
    // 1. Write Channel Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready <= 0;
            m_axi_wready  <= 0;
            m_axi_bvalid  <= 0;
        end else begin
            // Address Handshake
            m_axi_awready <= 1; // Always ready for address
            
            // Data Handshake
            m_axi_wready <= 1;  // Always ready for data

            // Actual Write to Memory
            if (m_axi_wvalid && m_axi_wready) begin
                // Lưu ý: Đây là mô phỏng đơn giản, giả sử địa chỉ đã được căn chỉnh (aligned)
                // và burst luôn là INCR.
                // Trong thực tế cần logic latch AWADDR và tự tăng địa chỉ.
                // Ở đây ta "cheat" bằng cách dùng biến static hoặc giả định DMA master xử lý đúng sequence.
            end
            
            // Write Response
            if (m_axi_wlast && m_axi_wvalid && m_axi_wready) begin
                m_axi_bvalid <= 1;
            end else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 0;
            end
        end
    end

    // Handling Write Data into Array (Separate block for cleaner logic)
    reg [31:0] curr_wr_addr;
    always @(posedge clk) begin
        if (m_axi_awvalid && m_axi_awready) begin
            curr_wr_addr <= m_axi_awaddr;
        end else if (m_axi_wvalid && m_axi_wready) begin
            // Little Endian Write
            main_memory[curr_wr_addr]   <= m_axi_wdata[7:0];
            main_memory[curr_wr_addr+1] <= m_axi_wdata[15:8];
            main_memory[curr_wr_addr+2] <= m_axi_wdata[23:16];
            main_memory[curr_wr_addr+3] <= m_axi_wdata[31:24];
            curr_wr_addr <= curr_wr_addr + 4;
        end
    end

    // 2. Read Channel Logic
    reg [31:0] r_addr_latch;
    reg [7:0]  r_len_latch;
    reg [7:0]  r_beat_cnt;
    reg        r_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 0;
            m_axi_rvalid  <= 0;
            m_axi_rlast   <= 0;
            r_active      <= 0;
        end else begin
            m_axi_arready <= 1; // Always ready

            if (m_axi_arvalid && m_axi_arready) begin
                r_addr_latch <= m_axi_araddr;
                r_len_latch  <= m_axi_arlen;
                r_beat_cnt   <= 0;
                r_active     <= 1;
            end

            if (r_active) begin
                m_axi_rvalid <= 1;
                // Fetch data from memory (Little Endian)
                m_axi_rdata <= {
                    main_memory[r_addr_latch+3],
                    main_memory[r_addr_latch+2],
                    main_memory[r_addr_latch+1],
                    main_memory[r_addr_latch]
                };

                if (m_axi_rready && m_axi_rvalid) begin
                    r_addr_latch <= r_addr_latch + 4;
                    r_beat_cnt   <= r_beat_cnt + 1;
                    
                    if (r_beat_cnt == r_len_latch) begin
                        m_axi_rlast  <= 1;
                        r_active     <= 0; // End burst
                    end else begin
                        m_axi_rlast <= 0;
                    end
                end
            end else begin
                m_axi_rvalid <= 0;
                m_axi_rlast  <= 0;
            end
        end
    end


    // --- APB Master Task (Simulate CPU) ---
    task apb_write_cfg;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            psel    <= 1;
            pwrite  <= 1;
            paddr   <= addr;
            pwdata  <= data;
            penable <= 0;
            @(posedge clk);
            penable <= 1;
            wait (pready);
            @(posedge clk);
            psel    <= 0;
            penable <= 0;
            pwrite  <= 0;
        end
    endtask

    // --- Main Test Sequence ---
    localparam SRC_ADDR = 32'h0000_0100; // 256
    localparam DST_ADDR = 32'h0000_0200; // 512
    localparam BYTES    = 128;           // Copy 128 bytes

    initial begin
        // 0. Initialize
        $dumpfile("dma_wave.vcd");
        $dumpvars(0, tb_dma_top);
        
        rst_n = 0;
        psel = 0; penable = 0; pwrite = 0;
        #100;
        rst_n = 1;
        #20;

        $display("--- [TEST] Starting DMA Simulation ---");

        // 1. Configure DMA via APB
        $display("--- [TEST] Configuring DMA Registers ---");
        // Set Source Address
        apb_write_cfg(32'h04, SRC_ADDR); 
        // Set Dest Address
        apb_write_cfg(32'h08, DST_ADDR);
        // Set Byte Count
        apb_write_cfg(32'h0C, BYTES);
        
        // 2. Start DMA
        $display("--- [TEST] Enabling DMA ---");
        // Write Control Reg: Enable bit 0 = 1 (Start)
        apb_write_cfg(32'h00, 32'h0000_0001);

        // 3. Wait for Interrupt (Done)
        $display("--- [TEST] Waiting for DMA Completion ---");
        wait(dma_irq == 1);
        $display("--- [TEST] DMA IRQ Received! ---");

        // 4. Verify Data Integrity
        #100; // Wait a bit for bus to settle
        check_memory(SRC_ADDR, DST_ADDR, BYTES);

        // 5. Clear Interrupt
        apb_write_cfg(32'h00, 32'h0000_0002); // Bit 1 = Clear IRQ
        #20;
        if (dma_irq == 0) $display("--- [TEST] IRQ Cleared Successfully ---");
        else $error("--- [FAIL] IRQ did not clear ---");

        $finish;
    end

    // --- Verification Task ---
    task check_memory;
        input [31:0] src;
        input [31:0] dst;
        input [31:0] len;
        integer k;
        reg [7:0] s_dat, d_dat;
        integer err_cnt;
        begin
            err_cnt = 0;
            for (k = 0; k < len; k = k + 1) begin
                s_dat = main_memory[src + k];
                d_dat = main_memory[dst + k];
                if (s_dat !== d_dat) begin
                    $error("[FAIL] Mismatch at offset %d. Src: %h, Dst: %h", k, s_dat, d_dat);
                    err_cnt = err_cnt + 1;
                end
            end
            
            if (err_cnt == 0) 
                $display("--- [PASS] Data Verification Successful! Transferred %d bytes. ---", len);
            else 
                $display("--- [FAIL] Found %d mismatches. ---", err_cnt);
        end
    endtask

endmodule