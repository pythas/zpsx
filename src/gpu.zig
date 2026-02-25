const std = @import("std");

pub const Gpu = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
    }

    pub fn read32(self: *Self, address: u32) u32 {
        _ = self;

        return switch (address) {
            0x04 => 0x1000_0000,
            else => {
                std.debug.print("bus: Unhandled read32 from GPU\n", .{});
                return 0;
            },
        };
    }

    // pub fn write32(self: *Self, address: u32, value: u32) void {}
};
