pub const Interrupt = enum(u32) {
    vblank = 0,
    gpu = 1,
    cdrom = 2,
    dma = 3,
    timer0 = 4,
    timer1 = 5,
    timer2 = 6,
    controller = 7,
    sio = 8,
    spu = 9,
    lightpen = 10,
};

pub const InterruptController = struct {
    status: u32,
    mask: u32,

    const Self = @This();

    pub fn init() Self {
        return .{
            .status = 0,
            .mask = 0,
        };
    }

    pub fn is_active(self: *Self) bool {
        return (self.status & self.mask) != 0;
    }

    pub fn trigger(self: *Self, irq: Interrupt) void {
        self.status |= (@as(u32, 1) << @intFromEnum(irq));
    }

    pub fn read32(self: *Self, address: u32) u32 {
        return switch (address) {
            0x00 => self.status,
            0x04 => self.mask,
            else => unreachable,
        };
    }

    pub fn write32(self: *Self, address: u32, value: u32) void {
        switch (address) {
            0x00 => self.status &= value, // inverted acknowledge
            0x04 => self.mask = value,
            else => unreachable,
        }
    }
};
