const std = @import("std");

const Renderer = @import("renderer.zig").Renderer;
const Point = @import("primitives.zig").Point;
const Color = @import("primitives.zig").Color;
const InterruptController = @import("interrupt.zig").InterruptController;

pub const Color16 = packed struct(u16) {
    r: u5,
    g: u5,
    b: u5,
    semi_transparency: u1,
};

pub const TextureCoord = packed struct(u16) {
    u: u8,
    v: u8,

    pub fn fromWord(word: u32) TextureCoord {
        return @bitCast(@as(u16, @truncate(word)));
    }
};

pub const TexturePage = packed struct(u16) {
    x_base_raw: u4,
    y_base_1: u1,
    semi_transparency: SemiTransparency,
    color_depth: TextureColors,
    _reserved1: u2 = 0,
    y_base_2: u1,
    _reserved2: u4 = 0,

    pub fn fromWord(word: u32) TexturePage {
        return @bitCast(@as(u16, @truncate(word >> 16)));
    }

    pub fn xBase(self: TexturePage) u16 {
        return @as(u16, self.x_base_raw) * 64;
    }

    pub fn yBase(self: TexturePage) u16 {
        const y1 = @as(u16, self.y_base_1);
        const y2 = @as(u16, self.y_base_2);
        return (y1 * 256) + (y2 * 512);
    }
};

pub const Clut = packed struct(u16) {
    x_base_raw: u6,
    y_base: u9,
    _unused: u1 = 0,

    pub fn fromWord(word: u32) Clut {
        return @bitCast(@as(u16, @truncate(word >> 16)));
    }

    pub fn xBase(self: Clut) u16 {
        return @as(u16, self.x_base_raw) * 16;
    }
};

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

pub const ImageDestination = packed struct(u32) {
    x: u16,
    y: u16,
};

pub const ImageDimensions = packed struct(u32) {
    width: u16,
    height: u16,
};

// GP0
pub const Gp0Mode = enum {
    command,
    cpu_to_vram,
    vram_to_cpu,
    // polyline
};

pub const PolygonOpcode = packed struct(u8) {
    raw_texture: bool,
    semi_transparent: bool,
    is_textured: bool,
    is_quad: bool,
    is_gouraud: bool,
    command_group: u3,
};

pub const RectangleOpcode = packed struct(u8) {
    semi_transparent: bool,
    is_textured: bool,
    raw_texture: bool,
    size: u2,
    command_group: u3,
};

const GP0_LENGTHS = init_lengths: {
    var lengths = [_]usize{1} ** 256;

    // polygons
    for (0x20..0x40) |opcode| {
        const op: PolygonOpcode = @bitCast(@as(u8, @intCast(opcode)));

        const vertices: usize = if (op.is_quad) 4 else 3;
        var len: usize = 1 + vertices;

        if (op.is_gouraud) len += vertices - 1;
        if (op.is_textured) len += vertices;

        lengths[opcode] = len;
    }

    // rectangles
    for (0x60..0x80) |opcode| {
        const op: RectangleOpcode = @bitCast(@as(u8, @intCast(opcode)));

        var len: usize = 2;

        if (op.size == 0) len += 1;
        if (op.is_textured) len += 1;

        lengths[opcode] = len;
    }

    // vram transfers
    lengths[0x80] = 4;
    lengths[0xA0] = 3;
    lengths[0xC0] = 3;

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

pub const DisplayEnableCommand = packed struct(u32) {
    display_disabled: bool,
    _unused: u23 = 0,
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

    pub fn texturePageX(self: Self) u32 {
        return @as(u32, self.texture_page_x_base) * 64;
    }

    pub fn texturePageY(self: Self) u32 {
        const y1: u32 = self.texture_page_y_base_1;
        const y2: u32 = self.texture_page_y_base_2;

        return (y1 * 256) + (y2 * 512);
    }
};

pub const Gpu = struct {
    allocator: std.mem.Allocator,

    renderer: Renderer,

    vram: []u16,

    gpuread: u32,
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

    gp0_mode: Gp0Mode,
    gp0_words_remaining: u32,

    gp0_buffer: [16]u32,
    gp0_buffer_len: usize,
    gp0_expected_len: usize,

    transfer_dest_x: u16,
    transfer_dest_y: u16,
    transfer_current_x: u16,
    transfer_current_y: u16,
    transfer_width: u16,
    transfer_height: u16,

    scanline: u16,
    scanline_cycles: u16,

    in_vblank: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const vram = try allocator.alloc(u16, 1024 * 512);
        @memset(vram, 0);

        return .{
            .allocator = allocator,

            .renderer = try Renderer.init(allocator),

            .vram = vram,

            .gpuread = 0,
            .gpustat = @bitCast(@as(u32, 0x1c802000)),

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

            .gp0_mode = .command,
            .gp0_words_remaining = 0,

            .gp0_buffer = [_]u32{0} ** 16,
            .gp0_buffer_len = 0,
            .gp0_expected_len = 0,

            .transfer_dest_x = 0,
            .transfer_dest_y = 0,
            .transfer_current_x = 0,
            .transfer_current_y = 0,
            .transfer_width = 0,
            .transfer_height = 0,

            .scanline = 0,
            .scanline_cycles = 0,

            .in_vblank = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.renderer.deinit();
    }

    pub fn step(self: *Self, cycles: u16, intc: *InterruptController) void {
        self.scanline_cycles += cycles;

        if (self.scanline_cycles >= 2145) {
            self.scanline_cycles -= 2145;
            self.scanline += 1;

            if (self.scanline == 240 and !self.in_vblank) {
                self.in_vblank = true;
                intc.trigger(.vblank);
            }

            if (self.scanline >= 263) {
                self.scanline = 0;
                self.in_vblank = false;
                self.gpustat.drawing_odd_lines ^= 1;
            }
        }
    }

    pub fn read32(self: *Self, offset: u32) u32 {
        return switch (offset) {
            0x00 => self.gp0Read(),
            0x04 => @bitCast(self.gpustat),
            else => {
                std.debug.print("gpu: Unhandled read32 from offset: {x}\n", .{offset});
                return 0;
            },
        };
    }

    pub fn write32(self: *Self, address: u32, value: u32) void {
        switch (address) {
            0x00 => self.gp0Write(value),
            0x04 => self.gp1Write(value),
            else => std.debug.panic("gpu: Unhandled write32 to offset: {x}\n", .{address}),
        }
    }

    pub fn putPixel(self: *Gpu, x: i16, y: i16, r: u8, g: u8, b: u8) void {
        if (x < 0 or y < 0) return;
        if (x >= 1024 or y >= 512) return;
        if (x < self.drawing_area_left or x > self.drawing_area_right or
            y < self.drawing_area_top or y > self.drawing_area_bottom) return;

        const index = @as(usize, @intCast(y)) * 1024 + @as(usize, @intCast(x));

        const r5 = @as(u16, r >> 3);
        const g5 = @as(u16, g >> 3);
        const b5 = @as(u16, b >> 3);

        const color: u16 = (1 << 15) | (b5 << 10) | (g5 << 5) | r5;

        self.vram[index] = color;
    }

    fn writeWordToVram(self: *Self, word: u32) void {
        const pixel1: u16 = @truncate(word & 0xffff);
        const pixel2: u16 = @truncate(word >> 16);

        self.writePixelToVram(pixel1);
        self.writePixelToVram(pixel2);
    }

    fn writePixelToVram(self: *Self, pixel: u16) void {
        const x = self.transfer_current_x & 1023;
        const y = self.transfer_current_y & 511;

        const index = (@as(usize, y) * 1024) + @as(usize, x);
        self.vram[index] = pixel;

        self.transfer_current_x += 1;

        if (self.transfer_current_x >= self.transfer_dest_x + self.transfer_width) {
            self.transfer_current_x = self.transfer_dest_x;
            self.transfer_current_y += 1;
        }
    }

    // GP0
    pub fn gp0Write(self: *Self, value: u32) void {
        switch (self.gp0_mode) {
            .command => {
                if (self.gp0_buffer_len == 0) {
                    const opcode: u8 = @truncate(value >> 24);
                    self.gp0_expected_len = GP0_LENGTHS[opcode];
                }

                self.gp0_buffer[self.gp0_buffer_len] = value;
                self.gp0_buffer_len += 1;

                if (self.gp0_buffer_len == self.gp0_expected_len) {
                    self.gp0ExecuteCommand();
                    self.gp0_buffer_len = 0;
                }
            },
            .cpu_to_vram => {
                self.writeWordToVram(value);
                self.gp0_words_remaining -= 1;

                if (self.gp0_words_remaining == 0) {
                    self.gp0_mode = .command;
                }
            },
            else => unreachable,
        }
    }

    pub fn gp0Read(self: *Self) u32 {
        if (self.gp0_mode == .vram_to_cpu) {
            const data: u32 = 0;

            self.gp0_words_remaining -= 1;

            if (self.gp0_words_remaining == 0) {
                self.gp0_mode = .command;
                self.gpustat.ready_send_vram_to_cpu = false;
            }

            return data;
        }

        return self.gpuread;
    }

    fn gp0ExecuteCommand(self: *Self) void {
        const header = self.gp0_buffer[0];
        const opcode: u8 = @truncate(header >> 24);

        // TODO: check ranges, eg. 0x20...0x3f, and use generic methods like gp0DrawPolygon
        switch (opcode) {
            0x00 => {},
            0x01 => self.gp0ResetCommandBuffer(),
            0x02 => self.gp0FillRectangle(
                self.gp0_buffer[0],
                self.gp0_buffer[1],
                self.gp0_buffer[2],
            ),
            0x20, 0x21, 0x22, 0x23 => self.gp0FlatTriangle(
                self.gp0_buffer[1],
                self.gp0_buffer[2],
                self.gp0_buffer[3],
            ),
            0x24, 0x25, 0x26, 0x27 => self.gp0TexturedTriangle(
                self.gp0_buffer[0],
                self.gp0_buffer[1],
                self.gp0_buffer[2],
                self.gp0_buffer[3],
                self.gp0_buffer[4],
                self.gp0_buffer[5],
                self.gp0_buffer[6],
            ),
            0x28, 0x29, 0x2a, 0x2b => self.gp0FlatQuad(
                self.gp0_buffer[1],
                self.gp0_buffer[2],
                self.gp0_buffer[3],
                self.gp0_buffer[4],
            ),
            0x2c, 0x2d, 0x2e, 0x2f => self.gp0TexturedQuad(
                self.gp0_buffer[0],
                self.gp0_buffer[1],
                self.gp0_buffer[2],
                self.gp0_buffer[3],
                self.gp0_buffer[4],
                self.gp0_buffer[5],
                self.gp0_buffer[6],
                self.gp0_buffer[7],
                self.gp0_buffer[8],
            ),
            0x30, 0x31, 0x32, 0x33 => self.gp0ShadedTriangle(
                self.gp0_buffer[0],
                self.gp0_buffer[1],
                self.gp0_buffer[2],
                self.gp0_buffer[3],
                self.gp0_buffer[4],
                self.gp0_buffer[5],
            ),
            0x34, 0x35, 0x36, 0x37 => self.gp0ShadedTexturedTriangle(
                self.gp0_buffer[0],
                self.gp0_buffer[1],
                self.gp0_buffer[2],
                self.gp0_buffer[3],
                self.gp0_buffer[4],
                self.gp0_buffer[5],
                self.gp0_buffer[6],
                self.gp0_buffer[7],
                self.gp0_buffer[8],
            ),
            0x38, 0x39, 0x3a, 0x3b => self.gp0ShadedQuad(
                self.gp0_buffer[0],
                self.gp0_buffer[1],
                self.gp0_buffer[2],
                self.gp0_buffer[3],
                self.gp0_buffer[4],
                self.gp0_buffer[5],
                self.gp0_buffer[6],
                self.gp0_buffer[7],
            ),
            0x3c, 0x3d, 0x3e, 0x3f => self.gp0ShadedTexturedQuad(
                self.gp0_buffer[0],
                self.gp0_buffer[1],
                self.gp0_buffer[2],
                self.gp0_buffer[3],
                self.gp0_buffer[4],
                self.gp0_buffer[5],
                self.gp0_buffer[6],
                self.gp0_buffer[7],
                self.gp0_buffer[8],
                self.gp0_buffer[9],
                self.gp0_buffer[10],
                self.gp0_buffer[11],
            ),
            0x68 => self.gp0Dot(
                self.gp0_buffer[0],
                self.gp0_buffer[1],
            ),
            0xa0 => self.gp0LoadImage(self.gp0_buffer[1], self.gp0_buffer[2]),
            0xc0 => self.gp0StoreImage(self.gp0_buffer[1], self.gp0_buffer[2]),
            0xe1 => self.gp0DrawMode(header),
            0xe2 => self.gp0TextureWindow(header),
            0xe3 => self.gp0DrawingAreaTopLeft(header),
            0xe4 => self.gp0DrawingAreaBottomRight(header),
            0xe5 => self.gp0DrawingOffset(header),
            0xe6 => self.gp0MaskBitSetting(header),
            else => std.debug.panic("Unhandled GP0 execute opcode: {x}\n", .{opcode}),
        }
    }

    fn gp0ResetCommandBuffer(self: *Self) void {
        _ = self;
        // TODO: "resets the command buffer and CLUT cache."
    }

    fn gp0FillRectangle(self: *Self, c: u32, xy: u32, wh: u32) void {
        const color = Color.fromWord(c);
        const top_left = Point.fromWord(xy);
        const size = Point.fromWord(wh);

        _ = color;
        _ = top_left;
        _ = size;
        _ = self;

        // TODO: THIS.
    }

    fn gp0FlatQuad(
        self: *Self,
        v1: u32,
        v2: u32,
        v3: u32,
        v4: u32,
    ) void {
        const color = Color.fromWord(self.gp0_buffer[0]);

        const dx = self.drawing_x_offset;
        const dy = self.drawing_y_offset;

        const p1 = Point.fromWord(v1).offset(dx, dy);
        const p2 = Point.fromWord(v2).offset(dx, dy);
        const p3 = Point.fromWord(v3).offset(dx, dy);
        const p4 = Point.fromWord(v4).offset(dx, dy);

        self.renderer.pushShadedTriangle(self, p1, color, p2, color, p3, color);
        self.renderer.pushShadedTriangle(self, p2, color, p3, color, p4, color);
    }

    fn gp0TexturedQuad(
        self: *Self,
        c1: u32,
        v1: u32,
        uv1: u32,
        v2: u32,
        uv2: u32,
        v3: u32,
        uv3: u32,
        v4: u32,
        uv4: u32,
    ) void {
        const dx = self.drawing_x_offset;
        const dy = self.drawing_y_offset;

        const p1 = Point.fromWord(v1).offset(dx, dy);
        const p2 = Point.fromWord(v2).offset(dx, dy);
        const p3 = Point.fromWord(v3).offset(dx, dy);
        const p4 = Point.fromWord(v4).offset(dx, dy);

        const color = Color.fromWord(c1);

        const t1 = TextureCoord.fromWord(uv1);
        const clut = Clut.fromWord(uv1);

        const t2 = TextureCoord.fromWord(uv2);
        const tpage = TexturePage.fromWord(uv2);

        const t3 = TextureCoord.fromWord(uv3);
        const t4 = TextureCoord.fromWord(uv4);

        self.renderer.pushTexturedTriangle(self, p1, color, t1, p2, color, t2, p3, color, t3, tpage, clut);
        self.renderer.pushTexturedTriangle(self, p2, color, t2, p3, color, t3, p4, color, t4, tpage, clut);
    }

    fn gp0ShadedQuad(
        self: *Self,
        c1: u32,
        v1: u32,
        c2: u32,
        v2: u32,
        c3: u32,
        v3: u32,
        c4: u32,
        v4: u32,
    ) void {
        const dx = self.drawing_x_offset;
        const dy = self.drawing_y_offset;

        const p1 = Point.fromWord(v1).offset(dx, dy);
        const p2 = Point.fromWord(v2).offset(dx, dy);
        const p3 = Point.fromWord(v3).offset(dx, dy);
        const p4 = Point.fromWord(v4).offset(dx, dy);

        const color1 = Color.fromWord(c1);
        const color2 = Color.fromWord(c2);
        const color3 = Color.fromWord(c3);
        const color4 = Color.fromWord(c4);

        self.renderer.pushShadedTriangle(self, p1, color1, p2, color2, p3, color3);
        self.renderer.pushShadedTriangle(self, p2, color2, p3, color3, p4, color4);
    }

    fn gp0ShadedTriangle(
        self: *Self,
        c1: u32,
        v1: u32,
        c2: u32,
        v2: u32,
        c3: u32,
        v3: u32,
    ) void {
        const dx = self.drawing_x_offset;
        const dy = self.drawing_y_offset;

        const p1 = Point.fromWord(v1).offset(dx, dy);
        const p2 = Point.fromWord(v2).offset(dx, dy);
        const p3 = Point.fromWord(v3).offset(dx, dy);

        const color1 = Color.fromWord(c1);
        const color2 = Color.fromWord(c2);
        const color3 = Color.fromWord(c3);

        self.renderer.pushShadedTriangle(self, p1, color1, p2, color2, p3, color3);
    }

    fn gp0Dot(self: *Self, c: u32, xy: u32) void {
        const dx = self.drawing_x_offset;
        const dy = self.drawing_y_offset;

        const color = Color.fromWord(c);
        const point = Point.fromWord(xy).offset(dx, dy);

        self.putPixel(
            @as(i16, @intCast(point.x)),
            @as(i16, @intCast(point.y)),
            color.r,
            color.g,
            color.b,
        );
    }

    fn gp0FlatTriangle(
        self: *Self,
        v1: u32,
        v2: u32,
        v3: u32,
    ) void {
        const color = Color.fromWord(self.gp0_buffer[0]);

        const dx = self.drawing_x_offset;
        const dy = self.drawing_y_offset;

        const p1 = Point.fromWord(v1).offset(dx, dy);
        const p2 = Point.fromWord(v2).offset(dx, dy);
        const p3 = Point.fromWord(v3).offset(dx, dy);

        self.renderer.pushShadedTriangle(self, p1, color, p2, color, p3, color);
    }

    fn gp0TexturedTriangle(
        self: *Self,
        c1: u32,
        v1: u32,
        uv1: u32,
        v2: u32,
        uv2: u32,
        v3: u32,
        uv3: u32,
    ) void {
        const dx = self.drawing_x_offset;
        const dy = self.drawing_y_offset;

        const p1 = Point.fromWord(v1).offset(dx, dy);
        const p2 = Point.fromWord(v2).offset(dx, dy);
        const p3 = Point.fromWord(v3).offset(dx, dy);

        const color = Color.fromWord(c1);

        const t1 = TextureCoord.fromWord(uv1);
        const clut = Clut.fromWord(uv1);

        const t2 = TextureCoord.fromWord(uv2);
        const tpage = TexturePage.fromWord(uv2);

        const t3 = TextureCoord.fromWord(uv3);

        self.renderer.pushTexturedTriangle(self, p1, color, t1, p2, color, t2, p3, color, t3, tpage, clut);
    }

    fn gp0ShadedTexturedTriangle(
        self: *Self,
        c1: u32,
        v1: u32,
        uv1: u32,
        c2: u32,
        v2: u32,
        uv2: u32,
        c3: u32,
        v3: u32,
        uv3: u32,
    ) void {
        const dx = self.drawing_x_offset;
        const dy = self.drawing_y_offset;

        const p1 = Point.fromWord(v1).offset(dx, dy);
        const p2 = Point.fromWord(v2).offset(dx, dy);
        const p3 = Point.fromWord(v3).offset(dx, dy);

        const color1 = Color.fromWord(c1);
        const color2 = Color.fromWord(c2);
        const color3 = Color.fromWord(c3);

        const t1 = TextureCoord.fromWord(uv1);
        const clut = Clut.fromWord(uv1);

        const t2 = TextureCoord.fromWord(uv2);
        const tpage = TexturePage.fromWord(uv2);

        const t3 = TextureCoord.fromWord(uv3);

        self.renderer.pushTexturedTriangle(self, p1, color1, t1, p2, color2, t2, p3, color3, t3, tpage, clut);
    }

    fn gp0ShadedTexturedQuad(
        self: *Self,
        c1: u32,
        v1: u32,
        uv1: u32,
        c2: u32,
        v2: u32,
        uv2: u32,
        c3: u32,
        v3: u32,
        uv3: u32,
        c4: u32,
        v4: u32,
        uv4: u32,
    ) void {
        const dx = self.drawing_x_offset;
        const dy = self.drawing_y_offset;

        const p1 = Point.fromWord(v1).offset(dx, dy);
        const p2 = Point.fromWord(v2).offset(dx, dy);
        const p3 = Point.fromWord(v3).offset(dx, dy);
        const p4 = Point.fromWord(v4).offset(dx, dy);

        const color1 = Color.fromWord(c1);
        const color2 = Color.fromWord(c2);
        const color3 = Color.fromWord(c3);
        const color4 = Color.fromWord(c4);

        const t1 = TextureCoord.fromWord(uv1);
        const clut = Clut.fromWord(uv1);

        const t2 = TextureCoord.fromWord(uv2);
        const tpage = TexturePage.fromWord(uv2);

        const t3 = TextureCoord.fromWord(uv3);
        const t4 = TextureCoord.fromWord(uv4);

        self.renderer.pushTexturedTriangle(self, p1, color1, t1, p2, color2, t2, p3, color3, t3, tpage, clut);
        self.renderer.pushTexturedTriangle(self, p2, color2, t2, p3, color3, t3, p4, color4, t4, tpage, clut);
    }

    fn gp0LoadImage(self: *Self, word1: u32, word2: u32) void {
        const destination: ImageDestination = @bitCast(word1);
        const dimensions: ImageDimensions = @bitCast(word2);

        const width: u32 = dimensions.width;
        const height: u32 = dimensions.height;
        const image_size = ((width + 1) / 2) * height;

        self.gp0_mode = .cpu_to_vram;
        self.gp0_words_remaining = image_size;

        self.transfer_dest_x = destination.x;
        self.transfer_dest_y = destination.y;
        self.transfer_current_x = destination.x;
        self.transfer_current_y = destination.y;

        self.transfer_width = if (dimensions.width == 0) 1024 else dimensions.width;
        self.transfer_height = if (dimensions.height == 0) 512 else dimensions.height;
    }

    fn gp0StoreImage(self: *Self, word1: u32, word2: u32) void {
        const dest: ImageDestination = @bitCast(word1);
        const dims: ImageDimensions = @bitCast(word2);

        _ = dest;

        const width: u32 = dims.width;
        const height: u32 = dims.height;
        const image_size = ((width + 1) / 2) * height;

        self.gp0_mode = .vram_to_cpu;
        self.gp0_words_remaining = image_size;

        self.gpustat.ready_send_vram_to_cpu = true;
    }

    fn gp0DrawMode(self: *Self, value: u32) void {
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

    pub fn gp0TextureWindow(self: *Self, value: u32) void {
        const cmd: TextureWindowCommand = @bitCast(value);

        self.texture_window_x_mask = cmd.mask_x;
        self.texture_window_y_mask = cmd.mask_y;
        self.texture_window_x_offset = cmd.offset_x;
        self.texture_window_y_offset = cmd.offset_y;
    }

    fn gp0DrawingAreaTopLeft(self: *Self, value: u32) void {
        const cmd: DrawingAreaTopLeftCommand = @bitCast(value);

        self.drawing_area_left = cmd.drawing_area_left;
        self.drawing_area_top = cmd.drawing_area_top;
    }

    fn gp0DrawingAreaBottomRight(self: *Self, value: u32) void {
        const cmd: DrawingAreaBottomRightCommand = @bitCast(value);

        self.drawing_area_right = cmd.drawing_area_right;
        self.drawing_area_bottom = cmd.drawing_area_bottom;
    }

    fn gp0DrawingOffset(self: *Self, value: u32) void {
        const cmd: DrawingOffsetCommand = @bitCast(value);

        self.drawing_x_offset = cmd.x;
        self.drawing_y_offset = cmd.y;
    }

    fn gp0MaskBitSetting(self: *Self, value: u32) void {
        const cmd: MaskBitSettingCommand = @bitCast(value);

        self.gpustat.set_mask_bit = cmd.set_mask_bit;
        self.gpustat.draw_pixels_not_masked = cmd.draw_pixels_not_masked;
    }

    // GP1
    fn gp1Write(self: *Self, value: u32) void {
        const opcode: u8 = @truncate(value >> 24);

        switch (opcode) {
            0x00 => self.gp1Reset(),
            0x01 => self.gp1ResetCommandBuffer(),
            0x02 => self.gp1AcknowledgeIrq(),
            0x03 => self.gp1DisplayEnable(value),
            0x04 => self.gp1DmaDirection(value),
            0x05 => self.gp1DisplayVramStart(value),
            0x06 => self.gp1DisplayHorizontalRange(value),
            0x07 => self.gp1DisplayVerticalRange(value),
            0x08 => self.gp1DisplayMode(value),
            0x10 => self.gp1Read(value),
            else => std.debug.panic("gpu: Unhandled GP1 opcode: {x}\n", .{opcode}),
        }
    }

    fn gp1Reset(self: *Self) void {
        self.* = Self.init(self.allocator) catch @panic("Failed to reset GPU");

        // TODO: clear FIFO
        // TODO: invalidate GPU cache
    }

    fn gp1ResetCommandBuffer(self: *Self) void {
        self.gp0_mode = .command;
        self.gp0_words_remaining = 0;
        // TODO: clear FIFO
    }

    fn gp1AcknowledgeIrq(self: *Self) void {
        _ = self;
    }

    fn gp1DisplayEnable(self: *Self, value: u32) void {
        const cmd: DisplayEnableCommand = @bitCast(value);

        self.gpustat.display_disabled = cmd.display_disabled;
    }

    fn gp1DmaDirection(self: *Self, value: u32) void {
        const cmd: DmaDirectionCommand = @bitCast(value);

        self.gpustat.dma_direction = cmd.dma_direction;
    }

    fn gp1DisplayVramStart(self: *Self, value: u32) void {
        const cmd: DisplayVramStartCommand = @bitCast(value);

        self.display_vram_x_start = cmd.display_vram_x_start;
        self.display_vram_y_start = cmd.display_vram_y_start;
    }

    fn gp1DisplayHorizontalRange(self: *Self, value: u32) void {
        const cmd: DisplayHorizontalRangeCommand = @bitCast(value);

        self.display_horiz_start = cmd.display_horiz_start;
        self.display_horiz_end = cmd.display_horiz_end;
    }

    fn gp1DisplayVerticalRange(self: *Self, value: u32) void {
        const cmd: DisplayVerticalRangeCommand = @bitCast(value);

        self.display_line_start = cmd.display_line_start;
        self.display_line_end = cmd.display_line_end;
    }

    fn gp1DisplayMode(self: *Self, value: u32) void {
        const cmd: DisplayModeCommand = @bitCast(value);

        self.gpustat.horizontal_resolution_1 = cmd.horizontal_resolution_1;
        self.gpustat.vertical_resolution = cmd.vertical_resolution;
        self.gpustat.video_mode = cmd.video_mode;
        self.gpustat.display_area_color_depth = cmd.display_area_color_depth;
        self.gpustat.vertical_interlace = cmd.vertical_interlace;
        self.gpustat.horizontal_resolution_2 = cmd.horizontal_resolution_2;
        self.gpustat.flip_screen_horizontally = cmd.flip_screen_horizontally;
    }

    fn gp1Read(self: *Self, value: u32) void {
        const index = value & 0x00ff_ffff;

        self.gpuread = switch (index) {
            7 => 2,
            else => unreachable,
        };
    }
};
