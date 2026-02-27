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

    fn init(allocator: std.mem.Allocator, breakpoints: []const u32) !*Self {
        const self = try allocator.create(AppState);

        self.* = .{
            .allocator = allocator,
            .emulator = try Emulator.init(allocator, breakpoints),
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

    const allocator = gpa.allocator();

    var args = std.process.argsWithAllocator(allocator) catch |err| {
        std.debug.panic("Failed to init args: {}", .{err});
    };
    defer args.deinit();

    _ = args.next();

    var breakpoints: std.ArrayList(u32) = .empty;
    defer breakpoints.deinit(allocator);

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-b") or std.mem.eql(u8, arg, "--breakpoint")) {
            if (args.next()) |val| {
                const bp = std.fmt.parseInt(u32, val, 0) catch |err| {
                    std.debug.print("Failed to parse breakpoint '{s}': {}\n", .{ val, err });
                    continue;
                };
                breakpoints.append(allocator, bp) catch |err| {
                    std.debug.panic("Failed to append breakpoint: {}", .{err});
                };
            }
        }
    }

    state = AppState.init(gpa.allocator(), breakpoints.items) catch |err| {
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
