const std = @import("std");

const Size = 512 * 1024;

pub const Bios = struct {
    allocator: std.mem.Allocator,

    data: []u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const data = try allocator.alloc(u8, Size);

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
        if (data.len != Size) {
            return error.InvalidBiosSize;
        }

        @memcpy(self.data, data);
    }

    pub fn read(self: *Self, address: u32) u32 {
        return std.mem.readInt(u32, self.data[address..][0..4], .little);
    }
};
