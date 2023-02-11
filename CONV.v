// 553010000 ps

`timescale 1ns/10ps

module  CONV(
	input		        clk,     // posedge
	input		        reset,   // active high asynchronous
	output	reg	        busy,	 // 1->do CONV, 
	input		        ready,	 // 
			
	output	reg [11:0]	iaddr,   // image address, 0~4095
	input	    [19:0]	idata,	 // 4+16 bit, input image
	
	output	reg 	    cwr,     // 1->wirte
	output	reg [11:0] 	caddr_wr,// write CONV result to address
	output	reg [19:0] 	cdata_wr,// write CONV result
	
	output	reg         crd,     // 1->read image
	output	reg [11:0] 	caddr_rd,//
	input	    [19:0] 	cdata_rd,
	
	output	reg [2:0] 	csel
	);

// state
parameter IDLE     = 3'd0,  // idle state, wait to do CONV
          INPUT_F  = 3'd1,  // input feature map state, take 9 clk to CONV
          WRITE_L0 = 3'd2,  // write CONV result to L0_MEM
          READ_L0  = 3'd3,  // read data from L0_MEM, take 4 clk to MaxPooling
          WRITE_L1 = 3'd4;  // write MaxPooling result to L1_MEM

// kernal map
parameter Kernal1 = 20'h0A89E,
          Kernal2 = 20'h092D5,
          Kernal3 = 20'h06D43,
          Kernal4 = 20'h01004,
          Kernal5 = 20'hF8F71,
          Kernal6 = 20'hF6E54,
          Kernal7 = 20'hFA6D7,
          Kernal8 = 20'hFC834,
          Kernal9 = 20'hFAC19,
          BIAS    = 20'h01310;

reg        [2:0]   current_state, next_state;  // FSM state
reg        [5:0]   index_MSB, index_LSB;       // index for kernal
reg        [3:0]   counter;                    // counter for FSM
reg signed [19:0]  input_data;                 // to store input data of image
reg signed [19:0]  kernal_temp;                // to store kernal weight at that moment
reg signed [39:0]  accumulate;                 // to store input_data * kernal_temp
reg signed [19:0]  maximum;                    // to store maximum value for maxpooling

// ===================================================== //
//                         FSM                           //
// ===================================================== //
always @(posedge clk or posedge reset) begin
	if (reset) current_state <= IDLE;
	else current_state <= next_state;
end

always @(*) begin
	case (current_state)
		IDLE:     next_state = (ready)? INPUT_F : IDLE;
		INPUT_F:  next_state = (counter == 4'd12)? WRITE_L0 : INPUT_F;
		WRITE_L0: next_state = ({index_MSB, index_LSB} == 12'd4096)? READ_L0 : INPUT_F;
		READ_L0:  next_state = (counter == 4'd5)? WRITE_L1 : READ_L0;
		WRITE_L1: next_state = ({index_MSB, index_LSB} == 12'd0)? IDLE : READ_L0;
		default:  next_state = IDLE;
	endcase
end

// ===================================================== //
//                       counter                         //
// ===================================================== //
always @(posedge clk or posedge reset) begin
	if (reset) counter <= 4'd0;
	else if (next_state == INPUT_F || next_state == READ_L0) counter <= counter + 4'd1;
	else counter <= 4'd0;
end

// ===================================================== //
//                        index                          //
// ===================================================== //
// index_MSB
always @(posedge clk or posedge reset) begin
	if (reset) index_MSB <= 6'd0;
	else if (next_state == WRITE_L0) begin
		if (index_LSB == 6'd63) index_MSB <= index_MSB + 6'd1;
		else index_MSB <= index_MSB;
	end
	else if (next_state == WRITE_L1) begin
		if (index_LSB == 6'd62) index_MSB <= index_MSB + 6'd2;
		else index_MSB <= index_MSB;
	end
	else if (next_state == READ_L0 && current_state == WRITE_L0) begin
		index_MSB <= 6'd0; // CONV done
	end
	else if (next_state == IDLE)begin
		index_MSB <= 6'd0; // Maxpooling done
	end
	else index_MSB <= index_MSB;
end
// index_LSB
always @(posedge clk or posedge reset) begin
	if (reset) begin
		index_LSB <= 6'd0;
	end
	else if (next_state == WRITE_L0) begin
		index_LSB <= index_LSB + 6'd1;
	end
	else if (next_state == WRITE_L1) begin
		index_LSB <= index_LSB + 6'd2;
	end
	else if (next_state == READ_L0 && current_state == WRITE_L0) begin
		index_LSB <= 6'd0; // CONV done
	end
	else if (next_state == IDLE)begin
		index_LSB <= 6'd0; // Maxpooling done
	end
	else begin
		index_LSB <= index_LSB;
	end
		
end


// ===================================================== //
//                         busy                          //
// ===================================================== //
always @(posedge clk or posedge reset) begin
	if (reset) busy <= 1'b0;
	else if (ready) busy <= 1'b1;
	else if(next_state == IDLE) busy <= 1'b0;
	else busy <= busy;
end

// ===================================================== //
//                  csel, cwr, crd                       //
// ===================================================== //
// csel
always @(*) begin
	if (current_state == WRITE_L0 || current_state == READ_L0) csel = 3'b001; // MEM_L0
	else if (current_state == WRITE_L1) csel = 3'b011; // MEM_L1
	else csel = 3'b000; // No select
end

// cwr
always @(posedge clk or posedge reset) begin
	if (reset) cwr <= 1'b0;
	else if (next_state == WRITE_L0 || next_state == WRITE_L1) cwr <= 1'b1;
	else cwr <= 1'b0;
end

// crd
always @(posedge clk or posedge reset) begin
	if (reset) crd <= 1'b0;
	else if (next_state == READ_L0) crd <= 1'b1;
	else crd <= 1'b0;
end

// ===================================================== //
//                  iaddr, idata                         //
// ===================================================== //
// iaddr
always @(posedge clk or posedge reset) begin
	if (reset) iaddr <= 12'd0;
	else if (next_state == INPUT_F) begin
		case (counter)
			4'd0: iaddr <= {index_MSB - 6'd1, index_LSB - 6'd1};
			4'd1: iaddr <= {index_MSB - 6'd1, index_LSB};
			4'd2: iaddr <= {index_MSB - 6'd1, index_LSB + 6'd1};
			4'd3: iaddr <= {index_MSB, index_LSB - 6'd1};
			4'd4: iaddr <= {index_MSB, index_LSB};
			4'd5: iaddr <= {index_MSB, index_LSB + 6'd1};
			4'd6: iaddr <= {index_MSB + 6'd1, index_LSB - 6'd1};
			4'd7: iaddr <= {index_MSB + 6'd1, index_LSB};
			4'd8: iaddr <= {index_MSB + 6'd1, index_LSB + 6'd1};
			4'd9: iaddr <= iaddr;
			default: iaddr <= 12'd0;
		endcase
	end
	else iaddr <= iaddr;
end

// idata (input)
always @(posedge clk or posedge reset) begin
	if (reset) input_data <= 20'd0;
	else if (current_state == INPUT_F) begin
		case (counter)
			4'd1: begin
				if (index_MSB == 6'd0 || index_LSB == 6'd0) input_data <= 20'd0;
				else input_data <= idata;
			end
			4'd2: begin
				if (index_MSB == 6'd0) input_data <= 20'd0;
				else input_data <= idata;
			end
			4'd3: begin
				if (index_MSB == 6'd0 || index_LSB == 6'd63) input_data <= 20'd0;
				else input_data <= idata;
			end
			4'd4: begin
				if (index_LSB == 6'd0) input_data <= 20'd0;
				else input_data <= idata;
			end
			4'd5: begin
				input_data <= idata;
			end
			4'd6: begin
				if (index_LSB == 6'd63) input_data <= 20'd0;
				else input_data <= idata;
			end
			4'd7: begin
				if (index_MSB == 6'd63 || index_LSB == 6'd0) input_data <= 20'd0;
				else input_data <= idata;
			end
			4'd8: begin
				if (index_MSB == 6'd63) input_data <= 20'd0;
				else input_data <= idata;
			end
			4'd9: begin
				if (index_MSB == 6'd63 || index_LSB == 6'd63) input_data <= 20'd0;
				else input_data <= idata;
			end
			default input_data <= input_data;
		endcase
	end
	else input_data <= 20'd0;
end

// ===================================================== //
//                    CONV circuit                       //
// ===================================================== //
always @(*) begin
	if (current_state == INPUT_F) begin
		case (counter)
			4'd2:  kernal_temp <= Kernal1;
			4'd3:  kernal_temp <= Kernal2;
			4'd4:  kernal_temp <= Kernal3;
			4'd5:  kernal_temp <= Kernal4;
			4'd6:  kernal_temp <= Kernal5;
			4'd7:  kernal_temp <= Kernal6;
			4'd8:  kernal_temp <= Kernal7;
			4'd9:  kernal_temp <= Kernal8;
			4'd10: kernal_temp <= Kernal9;
			default: kernal_temp <= Kernal1;
		endcase
	end
	else kernal_temp <= kernal_temp;
end

wire signed [39:0] product; // to store kernal_temp * input_data
assign product = kernal_temp * input_data;

always @(posedge clk or posedge reset) begin
	if (reset) accumulate <= 40'd0;
	else if (next_state == INPUT_F) begin
			case (counter)
				4'd0: accumulate <= 40'd0;
				4'd2: accumulate <= accumulate + product;
				4'd3: accumulate <= accumulate + product;
				4'd4: accumulate <= accumulate + product;
				4'd5: accumulate <= accumulate + product;
				4'd6: accumulate <= accumulate + product;
				4'd7: accumulate <= accumulate + product;
				4'd8: accumulate <= accumulate + product;
				4'd9: accumulate <= accumulate + product;
				4'd10: accumulate <= accumulate + product + {4'd0, BIAS, 16'h8000}; // add bias for last kernal, "8000" mean rounding
				default: accumulate <= accumulate;
			endcase
	end
end

// ===================================================== //
//                  Maxpooling circuit                   //
// ===================================================== //
always @(posedge clk or posedge reset) begin
	if (reset) maximum <= 20'd0;
	else if (current_state == READ_L0) begin
		if (cdata_rd > maximum) maximum <= cdata_rd;
		else maximum <= maximum;
	end
	else maximum <= 20'd0;
end


// ===================================================== //
//                 cdata_wr, caddr_wr                    //
// ===================================================== //
// cdata_wr
always @(posedge clk or posedge reset) begin
	if (reset) cdata_wr <= 20'd0;
	// CONV
	else if (next_state == WRITE_L0) begin
		if (accumulate[39]) cdata_wr <= 20'd0;  // ReLU
		else cdata_wr <= accumulate[35:16];
	end
	// Maxpooling
	else if (next_state == WRITE_L1) begin
		cdata_wr <= maximum;
	end
	else cdata_wr <= cdata_wr;
end

// caddr_wr
always @(posedge clk or posedge reset) begin
		if (reset) caddr_wr <= 12'd0;
		// CONV
		else if (next_state == WRITE_L0) begin
			caddr_wr <= {index_MSB, index_LSB};
		end
		// Maxpooling
		else if (next_state == WRITE_L1) begin
			caddr_wr <= {2'd0, index_MSB[5:1], index_LSB[5:1]};
		end
		else caddr_wr <= caddr_wr;
end



// ===================================================== //
//                     caddr_rd                          //
// ===================================================== //
always @(posedge clk or posedge reset) begin
	if (reset) caddr_rd <= 12'd0;
	else if (next_state == READ_L0) begin
		case (counter)
			4'd0: caddr_rd <= {index_MSB, index_LSB};
			4'd1: caddr_rd <= {index_MSB, index_LSB + 6'd1};
			4'd2: caddr_rd <= {index_MSB + 6'd1, index_LSB};
			4'd3: caddr_rd <= {index_MSB + 6'd1, index_LSB + 6'd1};
			default: caddr_rd <= caddr_rd;
		endcase
	end
	else caddr_rd <= caddr_rd;
end

endmodule




