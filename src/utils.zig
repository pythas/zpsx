const std = @import("std");

pub inline fn signExtend16(value: u16) u32 {
    return @bitCast(@as(i32, @as(i16, @bitCast(value))));
}

pub fn readBinaryFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var dir = std.fs.cwd();
    const file = try dir.openFile(path, .{ .mode = .read_only });
    defer file.close();
    return try file.readToEndAlloc(allocator, 1024 * 1024);
}
