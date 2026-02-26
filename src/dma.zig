const std = @import("std");
const bus = @import("bus.zig");

const DmaChannel = struct {
    madr: u32,
    bcr: u32,
    chcr: DmaChannelControlRegister,

    const Self = @This();

    pub fn init() Self {
        return .{
            .madr = 0,
            .bcr = 0,
            .chcr = @bitCast(@as(u32, 0)),
        };
    }
};

pub const DmaChannelControlRegister = packed struct(u32) {
    transfer_direction: u1,
    madr_increment: u1,
    _unused_0: u6 = 0,
    chopping_enable: bool,
    sync_mode: u2,
    _unused_1: u5 = 0,
    chopping_dma_window_size: u3,
    _unused_2: u1 = 0,
    chopping_cpu_window_size: u3,
    _unused_3: u1 = 0,
    start_transfer: bool,
    _unused_4: u3 = 0,
    force_transfer_start: bool,
    pause_transfer: bool,
    bus_snooping: bool,
    _unused_5: u1 = 0,
};

const DmaControlRegister = packed struct(u32) {
    dma0_mdecin_priority: u3,
    dma0_mdecin_enable: bool,
    dma1_mdecout_priority: u3,
    dma1_mdecout_enable: bool,
    dma2_gpu_priority: u3,
    dma2_gpu_enable: bool,
    dma3_cdrom_priority: u3,
    dma3_cdrom_enable: bool,
    dma4_spu_priority: u3,
    dma4_spu_enable: bool,
    dma5_pio_priority: u3,
    dma5_pio_enable: bool,
    dma6_otc_priority: u3,
    dma6_otc_enable: bool,
    cpu_memory_access_priority: u3,
    cpu_memory_access_enable: bool,
};

const DmaInterruptRegister = packed struct(u32) {
    channel_interrupt_mode: u7,
    _unused: u8 = 0,
    force_irq: bool,
    channel_interrupt_mask: u7,
    master_interrupt_enable: bool,
    channel_interrupt_flags: u7,
    master_interrupt_flag: bool,

    const Self = @This();

    fn write(self: *Self, value: u32) void {
        const val_struct: DmaInterruptRegister = @bitCast(value);

        self.channel_interrupt_mode = val_struct.channel_interrupt_mode;
        self.force_irq = val_struct.force_irq;
        self.channel_interrupt_mask = val_struct.channel_interrupt_mask;
        self.master_interrupt_enable = val_struct.master_interrupt_enable;

        //  w1c logic
        self.channel_interrupt_flags &= ~val_struct.channel_interrupt_flags;

        self.updateMasterFlag();
    }

    fn updateMasterFlag(self: *Self) void {
        const old_flag = self.master_interrupt_flag;

        const has_channel_interrupt = self.channel_interrupt_flags != 0;
        const is_interrupt_triggered = self.master_interrupt_enable and has_channel_interrupt;

        const new_flag = self.force_irq or is_interrupt_triggered;
        self.master_interrupt_flag = new_flag;

        // edge trigger
        if (new_flag and !old_flag) {
            // TODO: bus.trigger_irq(3);
        }
    }
};

pub const Dma = struct {
    channels: [7]DmaChannel,
    dpcr: DmaControlRegister,
    dicr: DmaInterruptRegister,

    const Self = @This();

    pub fn init() Self {
        return .{
            .channels = [_]DmaChannel{DmaChannel.init()} ** 7,
            .dpcr = @bitCast(@as(u32, 0x07654321)),
            .dicr = @bitCast(@as(u32, 0)),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn read32(self: *Self, address: u32) u32 {
        return switch (address) {
            0x70 => @bitCast(self.dpcr),
            0x74 => @bitCast(self.dicr),
            else => {
                std.debug.print("bus: Unhandled read32 from DMA: {x}\n", .{address});
                return 0;
            },
        };
    }

    pub fn write32(self: *Self, address: u32, value: u32) void {
        switch (address) {
            0x70 => self.dpcr = @bitCast(value),
            0x74 => self.dicr.write(value),
            else => std.debug.print("bus: Unhandled write32 to DMA: {x} - {x}\n", .{ address + bus.memory_map.dma.start, value }),
        }
    }
};
