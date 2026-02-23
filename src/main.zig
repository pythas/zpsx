const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Bus = @import("bus.zig").Bus;

fn readBinaryFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var dir = std.fs.cwd();
    const file = try dir.openFile(path, .{ .mode = .read_only });
    defer file.close();
    return try file.readToEndAlloc(allocator, 1024 * 1024);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var bus = try Bus.init(allocator);
    defer bus.deinit();
    var cpu = Cpu.init(&bus);
    defer cpu.deinit();

    const bios_data = try readBinaryFile(allocator, "roms/SCPH1001.BIN");
    try bus.loadBios(bios_data);
    allocator.free(bios_data);

    while (true) {
        cpu.step();
    }
}

test "CPU: delay slot lw overwritten by addiu" {
    const allocator = std.testing.allocator;

    var bus = try Bus.init(allocator);
    defer bus.deinit();

    var cpu = Cpu.init(&bus);
    defer cpu.deinit();

    const bios_data = try readBinaryFile(allocator, "tests/delay_overwrite.bin");
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

    const bios_data = try readBinaryFile(allocator, "tests/delay_read.bin");
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
