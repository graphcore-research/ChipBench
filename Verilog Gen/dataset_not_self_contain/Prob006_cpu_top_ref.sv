
module RefModule (
    output reg readM,                       // read from memory
    output reg [`WORD_SIZE-1:0] address,    // current address for data
    inout [`WORD_SIZE-1:0] data,            // data being input or output
    input inputReady,                       // indicates that data is ready from the input port
    input reset_n,                          // active-low RESET signal
    input clk,                              // clock signal

    // for debuging/testing purpose
    output reg [`WORD_SIZE-1:0] num_inst,   // number of instruction during execution
    output [`WORD_SIZE-1:0] output_port // this will be used for a "WWD" instruction
);

    // General CPU declarations
    reg reading_instruction;                    // Whether the current data access is for instruction or memory
    reg [`WORD_SIZE-1:0] PC, nextPC;            // Update PC to nextPC at every posedge clk
    reg [`WORD_SIZE-1:0] instruction, dataReg;  // Because data is only available for a short time, we need to save it.
    
    // Control signals from control module
    wire RegDst, Jump, Branch, MemRead, MemtoReg, MemWrite, ALUSrc, RegWrite, OpenPort;
    wire [3:0] ALUOp;
    
    // RF related declarations
    wire [`WORD_SIZE-1:0] ReadData1, ReadData2;
    
    // ALU related declarations
    wire bcond;
    wire [`WORD_SIZE-1:0] ALUResult;
    
    // Actual modul declarations
    Control control(.opcode(instruction[15:12]),
                    .func(instruction[5:0]),
                    .RegDst(RegDst),
                    .Jump(Jump),
                    .Branch(Branch),
                    .MemRead(MemRead),
                    .MemtoReg(MemtoReg),
                    .ALUOp(ALUOp),
                    .MemWrite(MemWrite),
                    .ALUSrc(ALUSrc),
                    .RegWrite(RegWrite),
                    .OpenPort(OpenPort));
                    
    RF rf(.write(RegWrite),
          .clk(clk),
          .reset_n(reset_n),
          .addr1(instruction[11:10]),
          .addr2(instruction[9:8]),
          .addr3(RegDst ? instruction[7:6] : instruction[9:8]), // Write address either rt or rd
          .data1(ReadData1),
          .data2(ReadData2),
          .data3(MemtoReg ? dataReg : ALUResult));
          
    ALU alu(.A(ReadData1),
            .B(ALUSrc ? {{8{instruction[7]}}, instruction[7:0]} : ReadData2),   // Either sign-extended immediate or second register read from RF.
            .OP(ALUOp),
            .C(ALUResult),
            .bcond(bcond));
    
    always @(*) begin
        if (Jump) nextPC = {PC[15:12], instruction[11:0]};  // Jumping to target (12 bit), concatenated with the upper 4 bits of PC.
        else if (Branch & bcond) nextPC = PC + {{8{instruction[7]}}, instruction[7:0]}; // Branching to PC + sign-extend(immediate)
        else nextPC = PC + 1;   // Next instruction
    end
    
    // Only open when OpenPort is asserted by the control module
    assign output_port = OpenPort ? ReadData1 : `WORD_SIZE'bz;
  
    always @(posedge clk, negedge reset_n) begin
        if (!reset_n) begin     // Asynchronous active low reset
            PC <= 0;
            nextPC <= 0;
            num_inst <= 1;
        end else begin
            PC <= nextPC;
            num_inst <= num_inst + 1;
        end
    end
    
    // When PC updates, assert readM for instruction fetch
    always @(PC) begin
        address = PC;
        readM = 1;
        reading_instruction = 1;
    end
    
    // When inputReady changes from 0 to 1
    always @(posedge inputReady) begin
        if (reading_instruction) begin  // instruction fetch mode
            instruction <= data;
            readM <= 0;
            reading_instruction <= 0;   // deassert since instruction fetch is done
        end else begin                  // data fetch mode
            dataReg <= data;
            readM <= 0;
        end
    end

endmodule


`define FUNC_ADD 6'd0
`define FUNC_SUB 6'd1
`define FUNC_AND 6'd2
`define FUNC_ORR 6'd3
`define FUNC_NOT 6'd4
`define FUNC_TCP 6'd5
`define FUNC_SHL 6'd6
`define FUNC_SHR 6'd7
`define FUNC_RWD 6'd27
`define FUNC_WWD 6'd28
`define FUNC_JPR 6'd25
`define FUNC_JRL 6'd26
`define FUNC_HLT 6'd29
`define FUNC_ENI 6'd30
`define FUNC_DSI 6'd31

`define OPCODE_ADI 4'd4
`define OPCODE_ORI 4'd5
`define OPCODE_LHI 4'd6
`define OPCODE_LWD 4'd7
`define OPCODE_SWD 4'd8
`define OPCODE_BNE 4'd0
`define OPCODE_BEQ 4'd1
`define OPCODE_BGZ 4'd2
`define OPCODE_BLZ 4'd3
`define OPCODE_JMP 4'd9
`define OPCODE_JAL 4'd10
`define OPCODE_R   4'd15

module Control(
    input [3:0] opcode,
    input [5:0] func,
    output RegDst,
    output Jump,
    output Branch,
    output MemRead,
    output MemtoReg,
    output reg [3:0] ALUOp,
    output MemWrite,
    output ALUSrc,
    output RegWrite,
    output OpenPort
    );
    
    /* 
    Receives opcode and function code of an instruction, and generates control signals.
    RegDst  : Chooses RF write address (rt or rd)
    Jump    : Whether this instruction is a jump
    Branch  : Whether this instruction is a branch
    MemRead : Whether we should read data memory
    MemtoReg: Chooses what to write to RF (ALU result or data read from memory)
    ALUOp   : Controls ALU operation. Directly connected to the input OP of the ALU. (There is no ALU control module in this CPU)
    MemWrite: Whether we should write data to memory
    ALUSrc  : Chooses ALU second input (Second RF read data or sign-extended immediate)
    RegWrite: Whether we should write data to RF
    OpenPort: Wheter to open output_port of CPU
    */
    
    assign RegDst = (opcode==`OPCODE_R);
    assign Jump = (opcode==`OPCODE_JMP || opcode==`OPCODE_JAL);
    assign Branch = (opcode==`OPCODE_BEQ || opcode==`OPCODE_BNE || opcode==`OPCODE_BGZ || opcode==`OPCODE_BLZ);
    assign MemRead = (opcode==`OPCODE_LWD || opcode==`OPCODE_SWD);
    assign MemtoReg = (opcode==`OPCODE_LWD);
    assign MemWrite = (opcode==`OPCODE_SWD);
    assign ALUSrc = !(opcode==`OPCODE_R || opcode==`OPCODE_BEQ || opcode==`OPCODE_BNE);
    assign RegWrite = !(opcode==`OPCODE_SWD || opcode==`OPCODE_BEQ || opcode==`OPCODE_BNE || opcode==`OPCODE_BGZ || opcode==`OPCODE_BLZ || opcode==`OPCODE_JMP || func==`FUNC_WWD);
    assign OpenPort = (opcode==`OPCODE_R & func==`FUNC_WWD);
    
    always @(*) begin
        if (opcode==`OPCODE_R & func<8) ALUOp = func[3:0];
        else if (opcode==`OPCODE_ADI || opcode==`OPCODE_LWD || opcode==`OPCODE_SWD) ALUOp = 0;
        else if (opcode==`OPCODE_ORI) ALUOp = 3;
        else if (opcode==`OPCODE_LHI) ALUOp = 8;
        else if (opcode==`OPCODE_BNE) ALUOp = 9;
        else if (opcode==`OPCODE_BEQ) ALUOp = 10;
        else if (opcode==`OPCODE_BGZ) ALUOp = 11;
        else if (opcode==`OPCODE_BLZ) ALUOp = 12;
        else ALUOp = 15;
    end
    
endmodule

module RF(
    input write,
    input clk,
    input reset_n,
    input [1:0] addr1,
    input [1:0] addr2,
    input [1:0] addr3,
    output [15:0] data1,
    output [15:0] data2,
    input [15:0] data3
    );
    
    reg [63:0] register;
    /*
    register[63:48] == register[16*3+: 16] (addr is 2'b11)
    register[47:32] == register[16*2+: 16] (addr is 2'b10)
    register[31:16] == register[16*1+: 16] (addr is 2'b01)
    register[15: 0] == register[16*0+: 16] (addr is 2'b00)
    */
    
    always @(posedge clk, negedge reset_n) begin
        // Asynchronous active low reset -> This used to be Synchronous reset; modified to asynchronous for Project 4.
    	if (!reset_n) register <= 64'b0;
    	// Synchronous data write
    	else if (write) register[16*addr3+: 16] <= data3;
    end
    
    // Asynchronous data read
    assign data1 = register[16*addr1+: 16];
    assign data2 = register[16*addr2+: 16];
    
endmodule

module ALU(
    input signed [15:0] A,
    input signed [15:0] B,
    input [3:0] OP,
    output reg [15:0] C,
    output bcond
    );
    
    always @(*) begin
        case (OP)
            0:  C = A + B;          // ADD, ADI, LWD, SWD
            1:  C = A - B;          // SUB
            2:  C = A & B;          // AND
            3:  C = A | B;          // ORR, ORI
            4:  C = ~A;             // NOT
            5:  C = ~A + 1'b1;      // TCP
            6:  C = A << 1;         // SHL
            7:  C = A >>> 1;        // SHR
            8:  C = {B[7:0], 8'b0}; // LHI
            9:  C = A - B;          // BNE
            10: C = A - B;          // BEQ
            11: C = A;              // BGZ
            12: C = A;              // BLZ
            default: C = 16'bz;
        endcase
    end
    
    // Using assign, C and bcond change at the same time.
    // The timing would have been different if they were inside a single always block. 
    assign bcond = OP==9  ? (C!=0) :        // BNE
                   OP==10 ? (C==0) :        // BEQ
                   OP==11 ? (C>0)  :        // BGZ                
                   OP==12 ? (C<0)  : 0;     // BLZ
    
endmodule