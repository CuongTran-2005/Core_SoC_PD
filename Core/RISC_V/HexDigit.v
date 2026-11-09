module HexDigit (
    input  [3:0] hex_digit,
    output reg [6:0] segments
);

    always @(*) begin
        case (hex_digit)
            4'h0: segments = 7'b1000000; // Hiển thị 0
            4'h1: segments = 7'b1111001; // Hiển thị 1
            4'h2: segments = 7'b0100100; // Hiển thị 2
            4'h3: segments = 7'b0110000; // Hiển thị 3
            4'h4: segments = 7'b0011001; // Hiển thị 4
            4'h5: segments = 7'b0010010; // Hiển thị 5
            4'h6: segments = 7'b0000010; // Hiển thị 6
            4'h7: segments = 7'b1111000; // Hiển thị 7
            4'h8: segments = 7'b0000000; // Hiển thị 8
            4'h9: segments = 7'b0010000; // Hiển thị 9
            4'hA: segments = 7'b0001000; // Hiển thị A
            4'hB: segments = 7'b0000011; // Hiển thị b
            4'hC: segments = 7'b1000110; // Hiển thị C
            4'hD: segments = 7'b0100001; // Hiển thị d
            4'hE: segments = 7'b0000110; // Hiển thị E
            4'hF: segments = 7'b0001110; // Hiển thị F
            default: segments = 7'b1111111; // Tắt hết
        endcase
    end

endmodule