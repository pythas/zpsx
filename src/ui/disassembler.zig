const std = @import("std");
const Instruction = @import("../cpu.zig").Instruction;

pub fn disassemble(instruction: Instruction, pc: u32, buf: []u8) ![]u8 {
    const opcode = instruction.r.opcode;
    const funct = instruction.r.funct;
    const rs = instruction.r.rs;
    const rt = instruction.r.rt;
    const rd = instruction.r.rd;
    const sa = instruction.r.sa;
    const imm = instruction.i.imm;
    const target = instruction.j.address;

    const register_names = [_][]const u8{
        "zero", "at", "v0", "v1", "a0", "a1", "a2", "a3",
        "t0",   "t1", "t2", "t3", "t4", "t5", "t6", "t7",
        "s0",   "s1", "s2", "s3", "s4", "s5", "s6", "s7",
        "t8",   "t9", "k0", "k1", "gp", "sp", "fp", "ra",
    };

    return switch (opcode) {
        0b000000 => switch (funct) {
            0b000000 => if (rt == 0 and rd == 0 and sa == 0)
                try std.fmt.bufPrint(buf, "nop", .{})
            else
                try std.fmt.bufPrint(buf, "sll {s}, {s}, {d}", .{ register_names[rd], register_names[rt], sa }),
            0b100101 => try std.fmt.bufPrint(buf, "or {s}, {s}, {s}", .{ register_names[rd], register_names[rs], register_names[rt] }),
            0b100001 => try std.fmt.bufPrint(buf, "addu {s}, {s}, {s}", .{ register_names[rd], register_names[rs], register_names[rt] }),
            0b101011 => try std.fmt.bufPrint(buf, "sltu {s}, {s}, {s}", .{ register_names[rd], register_names[rs], register_names[rt] }),
            0b001000 => try std.fmt.bufPrint(buf, "jr {s}", .{register_names[rs]}),
            0b100100 => try std.fmt.bufPrint(buf, "and {s}, {s}, {s}", .{ register_names[rd], register_names[rs], register_names[rt] }),
            0b100000 => try std.fmt.bufPrint(buf, "add {s}, {s}, {s}", .{ register_names[rd], register_names[rs], register_names[rt] }),
            0b001001 => try std.fmt.bufPrint(buf, "jalr {s}, {s}", .{ register_names[rd], register_names[rs] }),
            0b100011 => try std.fmt.bufPrint(buf, "subu {s}, {s}, {s}", .{ register_names[rd], register_names[rs], register_names[rt] }),
            0b000011 => try std.fmt.bufPrint(buf, "sra {s}, {s}, {d}", .{ register_names[rd], register_names[rt], sa }),
            0b011010 => try std.fmt.bufPrint(buf, "div {s}, {s}", .{ register_names[rs], register_names[rt] }),
            0b010010 => try std.fmt.bufPrint(buf, "mflo {s}", .{register_names[rd]}),
            0b000010 => try std.fmt.bufPrint(buf, "srl {s}, {s}, {d}", .{ register_names[rd], register_names[rt], sa }),
            0b011011 => try std.fmt.bufPrint(buf, "divu {s}, {s}", .{ register_names[rs], register_names[rt] }),
            0b010000 => try std.fmt.bufPrint(buf, "mfhi {s}", .{register_names[rd]}),
            0b101010 => try std.fmt.bufPrint(buf, "slt {s}, {s}, {s}", .{ register_names[rd], register_names[rs], register_names[rt] }),
            0b001100 => try std.fmt.bufPrint(buf, "syscall", .{}),
            0b010011 => try std.fmt.bufPrint(buf, "mtlo {s}", .{register_names[rs]}),
            0b010001 => try std.fmt.bufPrint(buf, "mthi {s}", .{register_names[rs]}),
            0b000100 => try std.fmt.bufPrint(buf, "sllv {s}, {s}, {s}", .{ register_names[rd], register_names[rt], register_names[rs] }),
            0b100111 => try std.fmt.bufPrint(buf, "nor {s}, {s}, {s}", .{ register_names[rd], register_names[rs], register_names[rt] }),
            0b000111 => try std.fmt.bufPrint(buf, "srav {s}, {s}, {s}", .{ register_names[rd], register_names[rt], register_names[rs] }),
            0b000110 => try std.fmt.bufPrint(buf, "srlv {s}, {s}, {s}", .{ register_names[rd], register_names[rt], register_names[rs] }),
            0b011001 => try std.fmt.bufPrint(buf, "multu {s}, {s}", .{ register_names[rs], register_names[rt] }),
            0b100110 => try std.fmt.bufPrint(buf, "xor {s}, {s}, {s}", .{ register_names[rd], register_names[rs], register_names[rt] }),
            0b001101 => try std.fmt.bufPrint(buf, "break", .{}),
            0b011000 => try std.fmt.bufPrint(buf, "mult {s}, {s}", .{ register_names[rs], register_names[rt] }),
            0b100010 => try std.fmt.bufPrint(buf, "sub {s}, {s}, {s}", .{ register_names[rd], register_names[rs], register_names[rt] }),
            else => try std.fmt.bufPrint(buf, "unknown r-type (0x{x:0>2})", .{funct}),
        },
        0b010000 => switch (instruction.cop0_move.sub) {
            0b00100 => try std.fmt.bufPrint(buf, "mtc0 {s}, r{d}", .{ register_names[rt], rd }),
            0b00000 => try std.fmt.bufPrint(buf, "mfc0 {s}, r{d}", .{ register_names[rt], rd }),
            0b10000 => try std.fmt.bufPrint(buf, "rfe", .{}),
            else => try std.fmt.bufPrint(buf, "unknown cop0 (0x{x:0>2})", .{instruction.cop0_move.sub}),
        },
        0b001111 => try std.fmt.bufPrint(buf, "lui {s}, 0x{x:0>4}", .{ register_names[rt], imm }),
        0b001101 => try std.fmt.bufPrint(buf, "ori {s}, {s}, 0x{x:0>4}", .{ register_names[rt], register_names[rs], imm }),
        0b101011 => try std.fmt.bufPrint(buf, "sw {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b001001 => try std.fmt.bufPrint(buf, "addiu {s}, {s}, {d}", .{ register_names[rt], register_names[rs], @as(i16, @bitCast(imm)) }),
        0b000101 => try std.fmt.bufPrint(buf, "bne {s}, {s}, 0x{x:0>8}", .{ register_names[rs], register_names[rt], pc +% 4 +% (@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(imm))))) << 2) }),
        0b001000 => try std.fmt.bufPrint(buf, "addi {s}, {s}, {d}", .{ register_names[rt], register_names[rs], @as(i16, @bitCast(imm)) }),
        0b100011 => try std.fmt.bufPrint(buf, "lw {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b101001 => try std.fmt.bufPrint(buf, "sh {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b001100 => try std.fmt.bufPrint(buf, "andi {s}, {s}, 0x{x:0>4}", .{ register_names[rt], register_names[rs], imm }),
        0b101000 => try std.fmt.bufPrint(buf, "sb {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b100000 => try std.fmt.bufPrint(buf, "lb {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b000100 => try std.fmt.bufPrint(buf, "beq {s}, {s}, 0x{x:0>8}", .{ register_names[rs], register_names[rt], pc +% 4 +% (@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(imm))))) << 2) }),
        0b000111 => try std.fmt.bufPrint(buf, "bgtz {s}, 0x{x:0>8}", .{ register_names[rs], pc +% 4 +% (@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(imm))))) << 2) }),
        0b000110 => try std.fmt.bufPrint(buf, "blez {s}, 0x{x:0>8}", .{ register_names[rs], pc +% 4 +% (@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(imm))))) << 2) }),
        0b100100 => try std.fmt.bufPrint(buf, "lbu {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b000001 => switch (rt) {
            0b00000 => try std.fmt.bufPrint(buf, "bltz {s}, 0x{x:0>8}", .{ register_names[rs], pc +% 4 +% (@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(imm))))) << 2) }),
            0b00001 => try std.fmt.bufPrint(buf, "bgez {s}, 0x{x:0>8}", .{ register_names[rs], pc +% 4 +% (@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(imm))))) << 2) }),
            0b10000 => try std.fmt.bufPrint(buf, "bltzal {s}, 0x{x:0>8}", .{ register_names[rs], pc +% 4 +% (@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(imm))))) << 2) }),
            0b10001 => try std.fmt.bufPrint(buf, "bgezal {s}, 0x{x:0>8}", .{ register_names[rs], pc +% 4 +% (@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(imm))))) << 2) }),
            else => try std.fmt.bufPrint(buf, "unknown bcond (0x{x:0>2})", .{rt}),
        },
        0b001010 => try std.fmt.bufPrint(buf, "slti {s}, {s}, {d}", .{ register_names[rt], register_names[rs], @as(i16, @bitCast(imm)) }),
        0b001011 => try std.fmt.bufPrint(buf, "sltiu {s}, {s}, {d}", .{ register_names[rt], register_names[rs], @as(i16, @bitCast(imm)) }),
        0b100101 => try std.fmt.bufPrint(buf, "lhu {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b100001 => try std.fmt.bufPrint(buf, "lh {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b001110 => try std.fmt.bufPrint(buf, "xori {s}, {s}, 0x{x:0>4}", .{ register_names[rt], register_names[rs], imm }),
        0b100010 => try std.fmt.bufPrint(buf, "lwl {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b100110 => try std.fmt.bufPrint(buf, "lwr {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b101010 => try std.fmt.bufPrint(buf, "swl {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b101110 => try std.fmt.bufPrint(buf, "swr {s}, 0x{x:0>4}({s})", .{ register_names[rt], imm, register_names[rs] }),
        0b000010 => try std.fmt.bufPrint(buf, "j 0x{x:0>8}", .{((pc +% 4) & 0xf000_0000) | (target << 2)}),
        0b000011 => try std.fmt.bufPrint(buf, "jal 0x{x:0>8}", .{((pc +% 4) & 0xf000_0000) | (target << 2)}),
        else => try std.fmt.bufPrint(buf, "unknown opcode (0x{x:0>2})", .{opcode}),
    };
}
