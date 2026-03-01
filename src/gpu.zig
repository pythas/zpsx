const std = @import("std");

pub const SemiTransparency = enum(u2) {
    b_half_plus_f_half = 0,
    b_plus_f = 1,
    b_minus_f = 2,
    b_plus_f_quarter = 3,
};

pub const TextureColors = enum(u2) {
    _4bit = 0,
    _8bit = 1,
    _15bit = 2,
    reserved = 3,
};

pub const VerticalResolution = enum(u1) {
    _240 = 0,
    _480 = 1,
};

pub const VideoMode = enum(u1) {
    ntsc = 0,
    pal = 1,
};

pub const ColorDepth = enum(u1) {
    _15bit = 0,
    _24bit = 1,
};

pub const DmaDirection = enum(u2) {
    off = 0,
    fifo = 1,
    cpu_to_gp0 = 2,
    vram_to_cpu = 3,
};

// GP0
pub const PolygonOpcode = packed struct(u8) {
    raw_texture: bool,
    semi_transparent: bool,
    is_textured: bool,
    is_quad: bool,
    is_gouraud: bool,
    command_group: u3,
};

const GP0_LENGTHS = init_lengths: {
    var lengths = [_]usize{1} ** 256;

    for (0x20..0x40) |opcode| {
        const op: PolygonOpcode = @bitCast(@as(u8, @intCast(opcode)));

        const vertices: usize = if (op.is_quad) 4 else 3;
        var len: usize = 1 + vertices;

        if (op.is_gouraud) len += vertices - 1;
        if (op.is_textured) len += vertices;

        lengths[opcode] = len;
    }

    break :init_lengths lengths;
};

pub const DrawModeCommand = packed struct(u32) {
    texture_page_x_base: u4,
    texture_page_y_base_1: u1,
    semi_transparency: SemiTransparency,
    texture_page_colors: TextureColors,
    dither_enabled: bool,
    drawing_to_display_area: bool,
    texture_page_y_base_2: u1,
    texture_rect_x_flip: bool,
    texture_rect_y_flip: bool,
    _unused: u10 = 0,
    opcode: u8,
};

pub const TextureWindowCommand = packed struct(u32) {
    mask_x: u5,
    mask_y: u5,
    offset_x: u5,
    offset_y: u5,
    _unused: u4 = 0,
    opcode: u8,
};

pub const DrawingAreaTopLeftCommand = packed struct(u32) {
    drawing_area_left: u10,
    drawing_area_top: u10,
    _unused: u4 = 0,
    opcode: u8,
};

pub const DrawingAreaBottomRightCommand = packed struct(u32) {
    drawing_area_right: u10,
    drawing_area_bottom: u10,
    _unused: u4 = 0,
    opcode: u8,
};

pub const DrawingOffsetCommand = packed struct(u32) {
    x: i11,
    y: i11,
    _unused: u2 = 0,
    opcode: u8,
};

pub const MaskBitSettingCommand = packed struct(u32) {
    set_mask_bit: bool,
    draw_pixels_not_masked: bool,
    _unused: u22 = 0,
    opcode: u8,
};

// GP1
pub const DmaDirectionCommand = packed struct(u32) {
    dma_direction: DmaDirection,
    _unused: u22 = 0,
    opcode: u8,
};

pub const DisplayVramStartCommand = packed struct(u32) {
    display_vram_x_start: u10,
    display_vram_y_start: u9,
    _unused: u5 = 0,
    opcode: u8,
};

pub const DisplayHorizontalRangeCommand = packed struct(u32) {
    display_horiz_start: u12,
    display_horiz_end: u12,
    opcode: u8,
};

pub const DisplayVerticalRangeCommand = packed struct(u32) {
    display_line_start: u10,
    display_line_end: u10,
    _unused: u4 = 0,
    opcode: u8,
};

pub const DisplayModeCommand = packed struct(u32) {
    horizontal_resolution_1: u2,
    vertical_resolution: VerticalResolution,
    video_mode: VideoMode,
    display_area_color_depth: ColorDepth,
    vertical_interlace: bool,
    horizontal_resolution_2: u1,
    flip_screen_horizontally: bool,
    _unused: u16 = 0,
    opcode: u8,
};

// GPUSTAT
pub const GpuStatusRegister = packed struct(u32) {
    texture_page_x_base: u4,
    texture_page_y_base_1: u1,
    semi_transparency: SemiTransparency,
    texture_page_colors: TextureColors,
    dither_enabled: bool,
    drawing_to_display_area: bool,
    set_mask_bit: bool,
    draw_pixels_not_masked: bool,
    interlace_field: u1,
    flip_screen_horizontally: bool,
    texture_page_y_base_2: u1,
    horizontal_resolution_2: u1,
    horizontal_resolution_1: u2,
    vertical_resolution: VerticalResolution,
    video_mode: VideoMode,
    display_area_color_depth: ColorDepth,
    vertical_interlace: bool,
    display_disabled: bool,
    interrupt_request: bool,
    dma_data_request: u1,
    ready_receive_cmd_word: bool,
    ready_send_vram_to_cpu: bool,
    ready_receive_dma_block: bool,
    dma_direction: DmaDirection,
    drawing_odd_lines: u1,

    const Self = @This();

    pub fn horizontalResolution(self: Self) u32 {
        if (self.horizontal_resolution_2 == 1) {
            return 368;
        }

        return switch (self.horizontal_resolution_1) {
            0 => 256,
            1 => 320,
            2 => 512,
            3 => 640,
        };
    }

    pub fn verticalResolution(self: GpuStatusRegister) u32 {
        return switch (self.vertical_resolution) {
            ._240 => 240,
            ._480 => 480,
        };
    }
};

pub const Gpu = struct {
    gpustat: GpuStatusRegister,

    texture_rect_x_flip: bool,
    texture_rect_y_flip: bool,

    texture_window_x_mask: u8,
    texture_window_y_mask: u8,
    texture_window_x_offset: u8,
    texture_window_y_offset: u8,

    drawing_area_left: u16,
    drawing_area_top: u16,
    drawing_area_right: u16,
    drawing_area_bottom: u16,

    drawing_x_offset: i16,
    drawing_y_offset: i16,

    display_vram_x_start: u16,
    display_vram_y_start: u16,

    display_horiz_start: u16,
    display_horiz_end: u16,
    display_line_start: u16,
    display_line_end: u16,

    gp0_buffer: [16]u32,
    gp0_buffer_len: usize,
    gp0_expected_len: usize,

    const Self = @This();

    pub fn init() Self {
        return .{
            .gpustat = @bitCast(@as(u32, 0x14802000)),

            .texture_rect_x_flip = false,
            .texture_rect_y_flip = false,

            .texture_window_x_mask = 0,
            .texture_window_y_mask = 0,
            .texture_window_x_offset = 0,
            .texture_window_y_offset = 0,

            .drawing_area_left = 0,
            .drawing_area_top = 0,
            .drawing_area_right = 0,
            .drawing_area_bottom = 0,

            .drawing_x_offset = 0,
            .drawing_y_offset = 0,

            .display_vram_x_start = 0,
            .display_vram_y_start = 0,

            .display_horiz_start = 0x200,
            .display_horiz_end = 0xc00,
            .display_line_start = 0x10,
            .display_line_end = 0x100,

            .gp0_buffer = [_]u32{0} ** 16,
            .gp0_buffer_len = 0,
            .gp0_expected_len = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn read32(self: *Self, address: u32) u32 {
        return switch (address) {
            0x04 => @bitCast(self.gpustat),
            else => {
                std.debug.print("bus: Unhandled read32 from GPU\n", .{});
                return 0;
            },
        };
    }

    pub fn write32(self: *Self, address: u32, value: u32) void {
        switch (address) {
            0x00 => self.gp0_write(value),
            0x04 => {
                const opcode: u8 = @truncate(value >> 24);

                switch (opcode) {
                    0x00 => self.gp1_reset(),
                    0x04 => self.gp1_dma_direction(value),
                    0x05 => self.gp1_display_vram_start(value),
                    0x06 => self.gp1_display_horizontal_range(value),
                    0x07 => self.gp1_display_vertical_range(value),
                    0x08 => self.gp1_display_mode(value),
                    else => std.debug.panic("Unhandled GP1 opcode: {x}\n", .{opcode}),
                }
            },
            else => std.debug.panic("gpu: write {x} to {x}\n", .{ value, address }),
        }
    }

    // GP0
    pub fn gp0_write(self: *Self, value: u32) void {
        if (self.gp0_buffer_len == 0) {
            const opcode: u8 = @truncate(value >> 24);
            self.gp0_expected_len = GP0_LENGTHS[opcode];
        }

        self.gp0_buffer[self.gp0_buffer_len] = value;
        self.gp0_buffer_len += 1;

        if (self.gp0_buffer_len == self.gp0_expected_len) {
            self.gp0_execute_command();
            self.gp0_buffer_len = 0;
        }
    }

    fn gp0_execute_command(self: *Self) void {
        const header = self.gp0_buffer[0];
        const opcode: u8 = @truncate(header >> 24);

        switch (opcode) {
            0x00 => {},
            0xe1 => self.gp0_draw_mode(header),
            0xe2 => self.gp0_texture_window(header),
            0xe3 => self.gp0_drawing_area_top_left(header),
            0xe4 => self.gp0_drawing_area_bottom_right(header),
            0xe5 => self.gp0_drawing_offset(header),
            0xe6 => self.gp0_mask_bit_setting(header),

            0x28 => {
                const v1 = self.gp0_buffer[1];
                const v2 = self.gp0_buffer[2];
                const v3 = self.gp0_buffer[3];
                const v4 = self.gp0_buffer[4];
                std.debug.print("gpu: draw flat quad. V1:{x} V2:{x} V3:{x} V4:{x}\n", .{ v1, v2, v3, v4 });
            },
            else => std.debug.panic("Unhandled GP0 execute opcode: {x}\n", .{opcode}),
        }
    }

    fn gp0_draw_mode(self: *Self, value: u32) void {
        const cmd: DrawModeCommand = @bitCast(value);

        self.gpustat.texture_page_x_base = cmd.texture_page_x_base;
        self.gpustat.texture_page_y_base_1 = cmd.texture_page_y_base_1;
        self.gpustat.semi_transparency = cmd.semi_transparency;
        self.gpustat.texture_page_colors = cmd.texture_page_colors;
        self.gpustat.dither_enabled = cmd.dither_enabled;
        self.gpustat.drawing_to_display_area = cmd.drawing_to_display_area;
        self.gpustat.texture_page_y_base_2 = cmd.texture_page_y_base_2;

        self.texture_rect_x_flip = cmd.texture_rect_x_flip;
        self.texture_rect_y_flip = cmd.texture_rect_y_flip;
    }

    pub fn gp0_texture_window(self: *Self, value: u32) void {
        const cmd: TextureWindowCommand = @bitCast(value);

        self.texture_window_x_mask = cmd.mask_x;
        self.texture_window_y_mask = cmd.mask_y;
        self.texture_window_x_offset = cmd.offset_x;
        self.texture_window_y_offset = cmd.offset_y;
    }

    fn gp0_drawing_area_top_left(self: *Self, value: u32) void {
        const cmd: DrawingAreaTopLeftCommand = @bitCast(value);

        self.drawing_area_left = cmd.drawing_area_left;
        self.drawing_area_top = cmd.drawing_area_top;
    }

    fn gp0_drawing_area_bottom_right(self: *Self, value: u32) void {
        const cmd: DrawingAreaBottomRightCommand = @bitCast(value);

        self.drawing_area_right = cmd.drawing_area_right;
        self.drawing_area_bottom = cmd.drawing_area_bottom;
    }

    fn gp0_drawing_offset(self: *Self, value: u32) void {
        const cmd: DrawingOffsetCommand = @bitCast(value);

        self.drawing_x_offset = cmd.x;
        self.drawing_y_offset = cmd.y;
    }

    fn gp0_mask_bit_setting(self: *Self, value: u32) void {
        const cmd: MaskBitSettingCommand = @bitCast(value);

        self.gpustat.set_mask_bit = cmd.set_mask_bit;
        self.gpustat.draw_pixels_not_masked = cmd.draw_pixels_not_masked;
    }

    // GP1
    fn gp1_reset(self: *Self) void {
        self.* = Self.init();

        // TODO: clear FIFO
        // TODO: invalidate GPU cache
    }

    fn gp1_dma_direction(self: *Self, value: u32) void {
        const cmd: DmaDirectionCommand = @bitCast(value);

        self.gpustat.dma_direction = cmd.dma_direction;
    }

    fn gp1_display_vram_start(self: *Self, value: u32) void {
        const cmd: DisplayVramStartCommand = @bitCast(value);

        self.display_vram_x_start = cmd.display_vram_x_start;
        self.display_vram_y_start = cmd.display_vram_y_start;
    }

    fn gp1_display_horizontal_range(self: *Self, value: u32) void {
        const cmd: DisplayHorizontalRangeCommand = @bitCast(value);

        self.display_horiz_start = cmd.display_horiz_start;
        self.display_horiz_end = cmd.display_horiz_end;
    }

    fn gp1_display_vertical_range(self: *Self, value: u32) void {
        const cmd: DisplayVerticalRangeCommand = @bitCast(value);

        self.display_line_start = cmd.display_line_start;
        self.display_line_end = cmd.display_line_end;
    }

    fn gp1_display_mode(self: *Self, value: u32) void {
        const cmd: DisplayModeCommand = @bitCast(value);

        self.gpustat.horizontal_resolution_1 = cmd.horizontal_resolution_1;
        self.gpustat.vertical_resolution = cmd.vertical_resolution;
        self.gpustat.video_mode = cmd.video_mode;
        self.gpustat.display_area_color_depth = cmd.display_area_color_depth;
        self.gpustat.vertical_interlace = cmd.vertical_interlace;
        self.gpustat.horizontal_resolution_2 = cmd.horizontal_resolution_2;
        self.gpustat.flip_screen_horizontally = cmd.flip_screen_horizontally;
    }
};
