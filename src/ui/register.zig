const ig = @import("cimgui_docking");

const Emulator = @import("../emulator.zig").Emulator;
const WindowConfig = @import("state.zig").WindowConfig;

pub const RegisterWindow = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn draw(_: *Self, config: *WindowConfig, emulator: *Emulator) void {
        if (!config.visible) {
            return;
        }

        const cpu = &emulator.cpu;

        ig.igSetNextWindowPos(config.pos, ig.ImGuiCond_FirstUseEver);
        ig.igSetNextWindowSize(config.size, ig.ImGuiCond_FirstUseEver);

        if (ig.igBegin("Registers", &config.visible, 0)) {
            ig.igText("PC: 0x%08X", cpu.pc);
            ig.igText("HI: 0x%08X", cpu.hi);
            ig.igText("LO: 0x%08X", cpu.lo);

            ig.igSeparator();

            const register_names = [_][]const u8{
                "r0", "at", "v0", "v1", "a0", "a1", "a2", "a3",
                "t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7",
                "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7",
                "t8", "t9", "k0", "k1", "gp", "sp", "fp", "ra",
            };

            for (0..32) |i| {
                ig.igText("%s: 0x%08X", register_names[i].ptr, cpu.registers[i]);
                if (i % 2 == 0) {
                    ig.igSameLine();
                }
            }

            ig.igSeparator();
            ig.igText("CP0 Registers");
            ig.igText("SR:    0x%08X", cpu.cp0_registers[12][0]);
            ig.igText("Cause: 0x%08X", cpu.cp0_registers[13][0]);
            ig.igText("EPC:   0x%08X", cpu.cp0_registers[14][0]);

            ig.igSeparator();
            ig.igText("All CP0 Registers (sel 0)");
            for (0..32) |i| {
                ig.igText("r%d: 0x%08X", @as(i32, @intCast(i)), cpu.cp0_registers[i][0]);
                if (i % 2 == 0) {
                    ig.igSameLine();
                }
            }
        }
        ig.igEnd();
    }
};
