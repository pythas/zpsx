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
    status: u16,
    mask: u16,

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
        self.status |= (@as(u16, 1) << @intCast(@intFromEnum(irq)));
    }

    pub fn read16(self: *Self, offset: u32) u16 {
        return switch (offset) {
            0x00 => self.status,
            0x04 => self.mask,
            else => unreachable,
        };
    }

    pub fn write16(self: *Self, offset: u32, value: u16) void {
        switch (offset) {
            0x00 => self.status &= value, // inverted acknowledge
            0x04 => self.mask = value,
            else => unreachable,
        }
    }
};
