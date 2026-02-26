const std = @import("std");
const utils = @import("utils.zig");

const ig = @import("cimgui_docking");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;

const Emulator = @import("emulator.zig").Emulator;
const Cpu = @import("cpu.zig").Cpu;
const Bus = @import("bus.zig").Bus;

const RegisterWindow = @import("ui/register.zig").RegisterWindow;
const DisassemblyWindow = @import("ui/disassembly.zig").DisassemblyWindow;
const UiState = @import("ui/state.zig").UiState;

const AppState = struct {
    allocator: std.mem.Allocator,

    emulator: *Emulator,

    ui: UiState,
    register_window: RegisterWindow,
    disassembly_window: DisassemblyWindow,

    pass_action: sg.PassAction,

    const Self = @This();

    fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(AppState);

        self.* = .{
            .allocator = allocator,
            .emulator = try Emulator.init(allocator),
            .ui = UiState.init(),
            .pass_action = .{},
            .register_window = RegisterWindow.init(),
            .disassembly_window = DisassemblyWindow.init(),
        };

        return self;
    }

    fn reset(self: *AppState) !void {
        _ = self;
        // self.bus.reset();
        // self.cpu.reset();
    }
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var state: *AppState = undefined;

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    simgui.setup(.{
        .logger = .{ .func = slog.func },
    });

    state = AppState.init(gpa.allocator()) catch |err| {
        std.debug.panic("Failed to init emulator: {}", .{err});
    };

    state.pass_action = .{};
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.2, .g = 0.2, .b = 0.25, .a = 1.0 },
    };
}

export fn frame() void {
    const width = sapp.widthf();
    const height = sapp.heightf();

    state.emulator.runFrame();

    simgui.newFrame(.{
        .width = @intFromFloat(width),
        .height = @intFromFloat(height),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    if (ig.igBeginMainMenuBar()) {
        if (ig.igBeginMenu("View")) {
            _ = ig.igMenuItemBoolPtr("Registers", "", &state.ui.registers.visible, true);
            _ = ig.igMenuItemBoolPtr("Disassembly", "", &state.ui.disassembly.visible, true);
            ig.igEndMenu();
        }
        ig.igEndMainMenuBar();
    }

    state.register_window.draw(&state.ui.registers, state.emulator);
    state.disassembly_window.draw(&state.ui.disassembly, state.emulator);

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn event(ev: [*c]const sapp.Event) void {
    _ = simgui.handleEvent(ev.*);
}

export fn cleanup() void {
    const allocator = state.allocator;
    state.emulator.deinit(allocator);
    allocator.destroy(state);

    simgui.shutdown();
    sg.shutdown();

    _ = gpa.deinit();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .window_title = "zpsx",
        .width = 1000,
        .height = 600,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}

test "CPU: delay slot lw overwritten by addiu" {
    const allocator = std.testing.allocator;

    var bus = try Bus.init(allocator);
    defer bus.deinit();

    var cpu = Cpu.init(&bus);
    defer cpu.deinit();

    const bios_data = try utils.readBinaryFile(allocator, "tests/delay_overwrite.bin");
    try bus.loadBios(bios_data);
    allocator.free(bios_data);

    var timeout: usize = 100;
    while (cpu.registers[30] != 0xdead0000 and timeout > 0) {
        cpu.step();
        timeout -= 1;
    }

    try std.testing.expect(timeout > 0);

    try std.testing.expectEqual(@as(u32, 0x99990000), cpu.registers[4]);
    try std.testing.expectEqual(@as(u32, 42), cpu.registers[1]);
}

test "CPU: load delay slot read visibility" {
    const allocator = std.testing.allocator;

    var bus = try Bus.init(std.testing.allocator);
    defer bus.deinit();

    var cpu = Cpu.init(&bus);
    defer cpu.deinit();

    const bios_data = try utils.readBinaryFile(allocator, "tests/delay_read.bin");
    try bus.loadBios(bios_data);
    allocator.free(bios_data);

    var timeout: usize = 100;
    while (cpu.registers[30] != 0xdead0000 and timeout > 0) {
        cpu.step();
        timeout -= 1;
    }

    try std.testing.expect(timeout > 0);

    try std.testing.expectEqual(@as(u32, 0xABCD0000), bus.read32(0));

    // first move should read old value of $1
    try std.testing.expectEqual(@as(u32, 0), cpu.registers[2]);

    // second move should read new value of $1
    try std.testing.expectEqual(@as(u32, 0xABCD0000), cpu.registers[3]);
}

test "Emulator: stepOver and stepOut" {
    const allocator = std.testing.allocator;

    var emulator = try Emulator.init(allocator);
    defer emulator.deinit(allocator);

    const bios_data = try utils.readBinaryFile(allocator, "tests/step_test.bin");
    try emulator.bus.loadBios(bios_data);
    allocator.free(bios_data);

    // Initial PC: 0xbfc0_0000
    // Reset PC to the start of the ROM to avoid any pre-stepping logic in init
    emulator.cpu.pc = 0xbfc0_0000;
    emulator.cpu.next_pc = 0xbfc0_0004;
    emulator.is_paused = true;

    // 0xbfc0_0000: addiu $1, $0, 1
    emulator.step();
    try std.testing.expectEqual(@as(u32, 0xbfc0_0004), emulator.cpu.pc);
    try std.testing.expectEqual(@as(u32, 1), emulator.cpu.registers[1]);

    // 0xbfc0_0004: jal func (func is at 0xbfc0_0018)
    // StepOver should execute jal and func, then stop at 0xbfc0_000c
    emulator.stepOver();

    // Run until it stops at temp_breakpoint
    while (!emulator.is_paused) {
        emulator.runFrame();
    }

    try std.testing.expectEqual(@as(u32, 0xbfc0_000c), emulator.cpu.pc);
    // After step over, func should have executed:
    // func sets $4 to 4, then delay slot sets $5 to 5
    try std.testing.expectEqual(@as(u32, 4), emulator.cpu.registers[4]);
    try std.testing.expectEqual(@as(u32, 5), emulator.cpu.registers[5]);

    // Now test StepOut
    // PC is currently at 0xbfc0_000c (addiu $2, $0, 2)
    // Let's go back and step INTO the call
    emulator.cpu.pc = 0xbfc0_0004; // jal func
    emulator.cpu.next_pc = 0xbfc0_0008;

    // Step once to execute JAL (it sets next_pc to target and $31 to return addr)
    emulator.step();
    try std.testing.expectEqual(@as(u32, 0xbfc0_0008), emulator.cpu.pc);
    try std.testing.expectEqual(@as(u32, 0xbfc0_000c), emulator.cpu.registers[31]);

    // Step again to execute delay slot (next_pc becomes target + 4)
    emulator.step();
    try std.testing.expectEqual(@as(u32, 0xbfc0_0018), emulator.cpu.pc);

    // We are inside func now. Let's execute one instruction in func.
    emulator.step(); // addiu $4, $0, 4
    try std.testing.expectEqual(@as(u32, 4), emulator.cpu.registers[4]);

    // PC is now at 0xbfc0_001c (jr $ra)
    // StepOut should set breakpoint to $ra (0xbfc0_000c)
    emulator.stepOut();

    while (!emulator.is_paused) {
        emulator.runFrame();
    }

    try std.testing.expectEqual(@as(u32, 0xbfc0_000c), emulator.cpu.pc);
}
