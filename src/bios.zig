const std = @import("std");

const size = 512 * 1024;

pub const Bios = struct {
    allocator: std.mem.Allocator,

    data: []u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const data = try allocator.alloc(u8, size);

        @memset(data, 0);

        return .{
            .allocator = allocator,
            .data = data,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
    }

    pub fn load(self: *Self, data: []const u8) !void {
        if (data.len != size) {
            return error.InvalidBiosSize;
        }

        @memcpy(self.data, data);
    }

    pub fn read32(self: *Self, address: u32) u32 {
        return std.mem.readInt(u32, self.data[address..][0..4], .little);
    }

    pub fn read16(self: *Self, address: u32) u16 {
        return std.mem.readInt(u16, self.data[address..][0..2], .little);
    }

    pub fn read8(self: *Self, address: u32) u8 {
        return self.data[address];
    }
};
