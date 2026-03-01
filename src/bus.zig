const std = @import("std");
const Ram = @import("ram.zig").Ram;
const Dma = @import("dma.zig").Dma;
const Gpu = @import("gpu.zig").Gpu;
const Bios = @import("bios.zig").Bios;

const Range = struct {
    start: u32,
    end: u32,
};

pub const memory_map = struct {
    pub const ram = Range{ .start = 0x0000_0000, .end = 0x0020_0000 - 1 };
    pub const exp1 = Range{ .start = 0x1f00_0000, .end = 0x1f80_0000 - 1 };
    pub const scratchpad = Range{ .start = 0x1f80_0000, .end = 0x1f80_0400 - 1 };

    pub const hardware_io = Range{ .start = 0x1f80_1000, .end = 0x1f80_2000 - 1 };
    pub const mem_control = Range{ .start = 0x1f80_1000, .end = 0x1f80_1024 - 1 };
    pub const ram_size = Range{ .start = 0x1f80_1060, .end = 0x1f80_1064 - 1 };
    pub const irq_control = Range{ .start = 0x1f80_1070, .end = 0x1f80_1078 - 1 };
    pub const dma = Range{ .start = 0x1f80_1080, .end = 0x1f80_1100 - 1 };
    pub const timers = Range{ .start = 0x1f80_1100, .end = 0x1f80_1130 - 1 };
    pub const gpu = Range{ .start = 0x1f80_1810, .end = 0x1f80_1818 - 1 };
    pub const spu = Range{ .start = 0x1f80_1c00, .end = 0x1f80_1e80 - 1 };

    pub const exp2 = Range{ .start = 0x1f80_2000, .end = 0x1f80_4000 - 1 };
    pub const exp3 = Range{ .start = 0x1fa0_0000, .end = 0x1fc0_0000 - 1 };
    pub const bios = Range{ .start = 0x1fc0_0000, .end = 0x1fc8_0000 - 1 };
    pub const cache_control = Range{ .start = 0xfffe_0000, .end = 0xfffe_0200 - 1 };
};

pub const Bus = struct {
    allocator: std.mem.Allocator,

    ram: Ram,
    dma: Dma,
    gpu: Gpu,
    bios: Bios,

    const Self = @This();
    const region_masks = [_]u32{
        0xffff_ffff, 0xffff_ffff, 0xffff_ffff, 0xffff_ffff, // KUSEG: 2048MB
        0x7fff_ffff, // KSEG0: 512MB
        0x1fff_ffff, // KSEG1: 512MB
        0xffff_ffff, 0xffff_ffff, // KSEG2: 1024MB
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        const ram = try Ram.init(allocator);
        const dma = Dma.init();
        const gpu = Gpu.init();
        const bios = try Bios.init(allocator);

        return .{
            .allocator = allocator,
            .ram = ram,
            .dma = dma,
            .gpu = gpu,
            .bios = bios,
        };
    }

    pub fn deinit(self: *Self) void {
        self.ram.deinit();
        self.bios.deinit();
    }

    pub fn loadBios(self: *Self, data: []const u8) !void {
        try self.bios.load(data);
    }

    fn physicalAddress(virtual_address: u32) u32 {
        const index = virtual_address >> 29;

        return virtual_address & region_masks[index];
    }

    pub fn read32(self: *Self, virtual_address: u32) u32 {
        const address = physicalAddress(virtual_address);

        // std.debug.print(
        //     "read32: V:0x{x:0>8} P:0x{x:0>8}\n",
        //     .{ virtual_address, address },
        // );

        return switch (address) {
            memory_map.ram.start...memory_map.ram.end => self.ram.read32(address),
            memory_map.irq_control.start...memory_map.irq_control.end => 0x00,
            memory_map.dma.start...memory_map.dma.end => self.dma.read32(address - memory_map.dma.start),
            memory_map.timers.start...memory_map.timers.end => {
                std.debug.print("bus: Unhandled read16 from IRQ_CONTROL\n", .{});
                return 0;
            },
            memory_map.gpu.start...memory_map.gpu.end => return self.gpu.read32(address - memory_map.gpu.start),
            memory_map.bios.start...memory_map.bios.end => self.bios.read32(address - memory_map.bios.start),
            else => std.debug.panic("bus: Unsupported read32: {x}", .{address}),
        };
    }

    pub fn write32(self: *Self, virtual_address: u32, value: u32) void {
        // TODO: panic at unaligned store

        const address = physicalAddress(virtual_address);

        // std.debug.print(
        //     "write32: V:0x{x:0>8} P:0x{x:0>8} VAL:0x{x:0>8}\n",
        //     .{ virtual_address, address, value },
        // );

        switch (address) {
            memory_map.ram.start...memory_map.ram.end => self.ram.write32(address, value),
            memory_map.irq_control.start...memory_map.irq_control.end => std.debug.print("bus: Unhandled write32 to IRQ_CONTROL\n", .{}),
            memory_map.dma.start...memory_map.dma.end => self.dma.write32(address - memory_map.dma.start, value),
            memory_map.timers.start...memory_map.timers.end => std.debug.print("bus: Unhandled write32 to TIMERS\n", .{}),
            memory_map.gpu.start...memory_map.gpu.end => self.gpu.write32(address - memory_map.gpu.start, value),
            memory_map.mem_control.start...memory_map.mem_control.end => std.debug.print("bus: Unhandled write32 to MEMCONTROL\n", .{}),
            memory_map.ram_size.start...memory_map.ram_size.end => std.debug.print("bus: Unhandled write32 to RAM_SIZE\n", .{}),
            memory_map.cache_control.start...memory_map.cache_control.end => std.debug.print("bus: Unhandled write32 to CACHE_CONTROL\n", .{}),
            else => std.debug.panic("bus: Unsupported write32: {x}", .{address}),
        }
    }

    pub fn read16(self: *Self, virtual_address: u32) u16 {
        const address = physicalAddress(virtual_address);

        // std.debug.print(
        //     "read16: V:0x{x:0>8} P:0x{x:0>8}\n",
        //     .{ virtual_address, address },
        // );

        return switch (address) {
            memory_map.ram.start...memory_map.ram.end => self.ram.read16(address),
            memory_map.irq_control.start...memory_map.irq_control.end => {
                std.debug.print("bus: Unhandled read16 from IRQ_CONTROL\n", .{});
                return 0;
            },
            memory_map.spu.start...memory_map.spu.end => {
                std.debug.print("bus: Unhandled read16 from SPU\n", .{});
                return 0;
            },
            else => std.debug.panic("bus: Unsupported read16: {x}", .{address}),
        };
    }

    pub fn write16(self: *Self, virtual_address: u32, value: u16) void {
        // TODO: panic at unaligned store

        const address = physicalAddress(virtual_address);

        // std.debug.print(
        //     "write16: V:0x{x:0>8} P:0x{x:0>8} VAL:0x{x:0>8}\n",
        //     .{ virtual_address, address, value },
        // );

        switch (address) {
            memory_map.ram.start...memory_map.ram.end => self.ram.write16(address, value),
            memory_map.irq_control.start...memory_map.irq_control.end => std.debug.print("bus: Unhandled write16 to IRQ_CONTROL\n", .{}),
            memory_map.timers.start...memory_map.timers.end => std.debug.print("bus: Unhandled write16 to TIMERS\n", .{}),
            memory_map.spu.start...memory_map.spu.end => std.debug.print("bus: Unhandled write16 to SPU\n", .{}),
            else => std.debug.panic("bus: Unsupported write16: {x}", .{address}),
        }
    }

    pub fn read8(self: *Self, virtual_address: u32) u8 {
        const address = physicalAddress(virtual_address);

        // std.debug.print(
        //     "read8: V:0x{x:0>8} P:0x{x:0>8}\n",
        //     .{ virtual_address, address },
        // );

        return switch (address) {
            memory_map.ram.start...memory_map.ram.end => self.ram.read8(address),
            memory_map.exp1.start...memory_map.exp1.end => 0xff,
            memory_map.bios.start...memory_map.bios.end => self.bios.read8(address - memory_map.bios.start),
            else => std.debug.panic("bus: Unsupported read8: {x}", .{address}),
        };
    }

    pub fn write8(self: *Self, virtual_address: u32, value: u8) void {
        // TODO: panic at unaligned store

        const address = physicalAddress(virtual_address);

        // std.debug.print(
        //     "write8: V:0x{x:0>8} P:0x{x:0>8} VAL:0x{x:0>8}\n",
        //     .{ virtual_address, address, value },
        // );

        switch (address) {
            memory_map.ram.start...memory_map.ram.end => self.ram.write8(address, value),
            memory_map.exp2.start...memory_map.exp2.end => std.debug.print("bus: Unhandled write8 to EXPANSION_2\n", .{}),
            else => std.debug.panic("bus: Unsupported write8: {x}", .{address}),
        }
    }

    pub fn processPendingDma(self: *Self) void {
        for (0..7) |i| {
            const channel_bit = @as(u7, 1) << @intCast(i);

            if ((self.dma.pending_channels & channel_bit) != 0) {
                self.dma.pending_channels &= ~channel_bit;

                self.doDma(i);
            }
        }
    }

    fn doDma(self: *Self, channel_index: usize) void {
        const channel = &self.dma.channels[channel_index];

        switch (channel.chcr.sync_mode) {
            .manual, .request => self.doDmaBlock(channel_index),
            .linked_list => self.doDmaLinkedList(channel_index),
            else => unreachable,
        }
    }

    fn doDmaBlock(self: *Self, channel_index: usize) void {
        const channel = &self.dma.channels[channel_index];
        const port: @import("dma.zig").Port = @enumFromInt(channel_index);

        var address = channel.madr;

        var remaining = channel.transferSize() orelse std.debug.panic("Could not calculate block transfer size", .{});

        while (remaining > 0) {
            const current_address = address & 0x001f_fffc;

            switch (channel.chcr.transfer_direction) {
                .to_ram => {
                    const data: u32 = switch (port) {
                        .otc => if (remaining == 1)
                            0x00ff_ffff
                        else
                            (address -% 4) & 0x001f_ffff,
                        else => std.debug.panic("Unhandled DMA block ToRam for channel {}", .{channel_index}),
                    };

                    self.write32(current_address, data);
                },
                .from_ram => {
                    const data = self.read32(current_address);

                    switch (port) {
                        .gpu => self.gpu.write32(0, data),
                        else => std.debug.panic("Unhandled DMA block FromRam for channel {}", .{channel_index}),
                    }
                },
            }

            switch (channel.chcr.madr_increment) {
                .increment => address +%= 4,
                .decrement => address -%= 4,
            }

            remaining -= 1;
        }

        channel.setInactive();
    }

    fn doDmaLinkedList(self: *Self, channel_index: usize) void {
        const channel = &self.dma.channels[channel_index];
        const port: @import("dma.zig").Port = @enumFromInt(channel_index);

        var address = channel.madr & 0x001f_fffc;

        if (channel.chcr.transfer_direction == .to_ram) {
            unreachable;
        }

        if (port != .gpu) {
            unreachable;
        }

        while (true) {
            const header = self.read32(address);

            var remaining = header >> 24;

            while (remaining > 0) {
                address = (address +% 4) & 0x001f_fffc;

                const command = self.read32(address);

                self.gpu.write32(0x00, command);

                remaining -= 1;
            }

            if (header & 0x0080_0000 != 0) {
                break;
            }

            address = header & 0x001f_fffc;
        }

        channel.setInactive();
    }
};
