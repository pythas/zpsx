const ig = @import("cimgui_docking");
const std = @import("std");

const Emulator = @import("../emulator.zig").Emulator;
const WindowConfig = @import("state.zig").WindowConfig;
const disassemble = @import("disassembler.zig").disassemble;

pub const DisassemblyWindow = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn draw(_: *Self, config: *WindowConfig, emulator: *Emulator) void {
        if (!config.visible) {
            return;
        }

        const bus = &emulator.bus;
        const cpu = &emulator.cpu;

        ig.igSetNextWindowPos(config.pos, ig.ImGuiCond_FirstUseEver);
        ig.igSetNextWindowSize(config.size, ig.ImGuiCond_FirstUseEver);

        if (ig.igBegin("Disassembly", &config.visible, 0)) {
            if (ig.igButton("Break")) {
                emulator.is_paused = true;
            }

            ig.igSameLine();
            if (ig.igButton("Run")) {
                emulator.is_paused = false;
            }

            ig.igSameLine();
            if (ig.igButton("Step into")) {
                emulator.step();
            }

            const start_pc = if (cpu.pc >= 40) cpu.pc - 40 else 0;
            var buf: [128]u8 = undefined;

            for (0..40) |i| {
                const addr = start_pc +% @as(u32, @intCast(i * 4));
                const instr = bus.read32(addr);
                const dis = disassemble(@bitCast(instr), addr, &buf) catch "error";

                const is_pc = (addr == cpu.pc);
                const is_bp = emulator.breakpoints.contains(addr);

                if (is_pc and is_bp) {
                    ig.igTextColored(.{ .x = 1.0, .y = 0.3, .z = 0.3, .w = 1.0 }, "-> * %08X: %08X  %s", addr, instr, dis.ptr);
                } else if (is_pc) {
                    ig.igTextColored(.{ .x = 1.0, .y = 1.0, .z = 0.0, .w = 1.0 }, "->   %08X: %08X  %s", addr, instr, dis.ptr);
                } else if (is_bp) {
                    ig.igTextColored(.{ .x = 1.0, .y = 0.5, .z = 0.5, .w = 1.0 }, "   * %08X: %08X  %s", addr, instr, dis.ptr);
                } else {
                    ig.igText("     %08X: %08X  %s", addr, instr, dis.ptr);
                }
            }
        }
        ig.igEnd();
    }
};
