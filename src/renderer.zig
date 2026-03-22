const std = @import("std");

const sokol = @import("sokol");
const sg = sokol.gfx;

const Gpu = @import("gpu.zig").Gpu;
const Point = @import("primitives.zig").Point;
const Color = @import("primitives.zig").Color;
const TextureCoord = @import("gpu.zig").TextureCoord;
const TexturePage = @import("gpu.zig").TexturePage;
const Clut = @import("gpu.zig").Clut;

const TextureParams = struct {
    t1: TextureCoord,
    t2: TextureCoord,
    t3: TextureCoord,
    tpage: TexturePage,
    clut: Clut,
    raw_texture: bool,
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    fn rasterizeTriangle(
        _: *Self,
        gpu: *Gpu,
        pts: [3]Point,
        cols: [3]Color,
        texture_params: ?TextureParams,
    ) void {
        var points = pts;
        var colors = cols;
        var tex = texture_params;

        var area: i64 = edgeFunction(points[0], points[1], points[2]);

        if (area < 0) {
            std.mem.swap(Point, &points[1], &points[2]);
            std.mem.swap(Color, &colors[1], &colors[2]);
            if (tex) |*t| {
                std.mem.swap(TextureCoord, &t.t2, &t.t3);
            }
            area = -area;
        }

        if (area == 0) return;

        var bbx = Bbx.fromPoints(&points);
        bbx.min_x = @max(bbx.min_x, @as(i16, @intCast(gpu.drawing_area_left)));
        bbx.max_x = @min(bbx.max_x, @as(i16, @intCast(gpu.drawing_area_right)));
        bbx.min_y = @max(bbx.min_y, @as(i16, @intCast(gpu.drawing_area_top)));
        bbx.max_y = @min(bbx.max_y, @as(i16, @intCast(gpu.drawing_area_bottom)));

        if (bbx.min_x > bbx.max_x or bbx.min_y > bbx.max_y) return;

        var y: i32 = bbx.min_y;
        while (y <= bbx.max_y) : (y += 1) {
            var x: i32 = bbx.min_x;
            while (x <= bbx.max_x) : (x += 1) {
                const p = Point{ .x = @intCast(x), .y = @intCast(y) };

                // calc weights
                const w0 = edgeFunction(points[1], points[2], p);
                const w1 = edgeFunction(points[2], points[0], p);
                const w2 = edgeFunction(points[0], points[1], p);

                if (w0 >= 0 and w1 >= 0 and w2 >= 0) {
                    const w0_fixed = @divTrunc(@as(i64, w0) << 12, area);
                    const w1_fixed = @divTrunc(@as(i64, w1) << 12, area);
                    const w2_fixed = @divTrunc(@as(i64, w2) << 12, area);

                    // base vertex color
                    var r = interpolate(w0_fixed, w1_fixed, w2_fixed, colors[0].r, colors[1].r, colors[2].r);
                    var g = interpolate(w0_fixed, w1_fixed, w2_fixed, colors[0].g, colors[1].g, colors[2].g);
                    var b = interpolate(w0_fixed, w1_fixed, w2_fixed, colors[0].b, colors[1].b, colors[2].b);

                    // texture mapping
                    if (tex) |t| {
                        const u = interpolate(w0_fixed, w1_fixed, w2_fixed, t.t1.u, t.t2.u, t.t3.u);
                        const v = interpolate(w0_fixed, w1_fixed, w2_fixed, t.t1.v, t.t2.v, t.t3.v);

                        var texel16: u16 = 0;

                        switch (t.tpage.color_depth) {
                            ._15bit => {
                                const vram_x: usize = @as(usize, t.tpage.xBase()) + u;
                                const vram_y: usize = @as(usize, t.tpage.yBase()) + v;

                                if (vram_x < 1024 and vram_y < 512) {
                                    texel16 = gpu.vram[vram_y * 1024 + vram_x];
                                }
                            },
                            ._8bit => {
                                const vram_x: usize = @as(usize, t.tpage.xBase()) + (u / 2);
                                const vram_y: usize = @as(usize, t.tpage.yBase()) + v;

                                if (vram_x < 1024 and vram_y < 512) {
                                    const word = gpu.vram[vram_y * 1024 + vram_x];
                                    const index: u8 = if (u % 2 == 0) @truncate(word & 0xff) else @truncate(word >> 8);

                                    if (index != 0) {
                                        const clut_y = @as(usize, t.clut.y_base);
                                        const clut_x = @as(usize, t.clut.xBase());
                                        const clut_idx = clut_y * 1024 + clut_x + index;

                                        if (clut_idx < 1024 * 512) {
                                            texel16 = gpu.vram[clut_idx];
                                        }
                                    }
                                }
                            },
                            ._4bit => {
                                const vram_x: usize = @as(usize, t.tpage.xBase()) + (u / 4);
                                const vram_y: usize = @as(usize, t.tpage.yBase()) + v;

                                if (vram_x < 1024 and vram_y < 512) {
                                    const word = gpu.vram[vram_y * 1024 + vram_x];

                                    const shift = @as(u4, @truncate(u % 4)) * 4;
                                    const index: u4 = @truncate((word >> shift) & 0xf);

                                    if (index != 0) {
                                        const clut_y = @as(usize, t.clut.y_base);
                                        const clut_x = @as(usize, t.clut.xBase());
                                        const clut_idx = clut_y * 1024 + clut_x + index;

                                        if (clut_idx < 1024 * 512) {
                                            texel16 = gpu.vram[clut_idx];
                                        }
                                    }
                                }
                            },
                            .reserved => {},
                        }

                        // transparency
                        if (texel16 == 0) continue;

                        // convert to 8-bit
                        const tr = @as(u16, texel16 & 0x1f) << 3;
                        const tg = @as(u16, (texel16 >> 5) & 0x1f) << 3;
                        const tb = @as(u16, (texel16 >> 10) & 0x1f) << 3;

                        if (t.raw_texture) {
                            // bypass blending
                            r = @intCast(tr);
                            g = @intCast(tg);
                            b = @intCast(tb);
                        } else {
                            // blend
                            r = @as(u8, @intCast(@min(255, (@as(u16, tr) * r) / 128)));
                            g = @as(u8, @intCast(@min(255, (@as(u16, tg) * g) / 128)));
                            b = @as(u8, @intCast(@min(255, (@as(u16, tb) * b) / 128)));
                        }
                    }

                    gpu.putPixel(@as(i16, @intCast(x)), @as(i16, @intCast(y)), r, g, b);
                }
            }
        }
    }

    pub fn pushShadedTriangle(
        self: *Self,
        gpu: *Gpu,
        p1: Point,
        c1: Color,
        p2: Point,
        c2: Color,
        p3: Point,
        c3: Color,
    ) void {
        self.rasterizeTriangle(gpu, .{ p1, p2, p3 }, .{ c1, c2, c3 }, null);
    }

    pub fn pushTexturedTriangle(
        self: *Self,
        gpu: *Gpu,
        p1: Point,
        c1: Color,
        t1: TextureCoord,
        p2: Point,
        c2: Color,
        t2: TextureCoord,
        p3: Point,
        c3: Color,
        t3: TextureCoord,
        tpage: TexturePage,
        clut: Clut,
        raw_texture: bool,
    ) void {
        const tex_params = TextureParams{
            .t1 = t1,
            .t2 = t2,
            .t3 = t3,
            .tpage = tpage,
            .clut = clut,
            .raw_texture = raw_texture,
        };
        self.rasterizeTriangle(gpu, .{ p1, p2, p3 }, .{ c1, c2, c3 }, tex_params);
    }
};

const Bbx = struct {
    min_x: i16,
    max_x: i16,
    min_y: i16,
    max_y: i16,

    pub fn fromPoints(points: []const Point) Bbx {
        var bbx = Bbx{
            .min_x = std.math.maxInt(i16),
            .max_x = std.math.minInt(i16),
            .min_y = std.math.maxInt(i16),
            .max_y = std.math.minInt(i16),
        };

        for (points) |point| {
            bbx.min_x = @min(bbx.min_x, point.x);
            bbx.max_x = @max(bbx.max_x, point.x);
            bbx.min_y = @min(bbx.min_y, point.y);
            bbx.max_y = @max(bbx.max_y, point.y);
        }

        return bbx;
    }
};

inline fn edgeFunction(a: Point, b: Point, c: Point) i32 {
    const ax: i64 = a.x;
    const ay: i64 = a.y;
    const bx: i64 = b.x;
    const by: i64 = b.y;
    const cx: i64 = c.x;
    const cy: i64 = c.y;

    const result = (cx - ax) * (by - ay) - (cy - ay) * (bx - ax);
    return @as(i32, @intCast(std.math.clamp(result, std.math.minInt(i32), std.math.maxInt(i32))));
}

inline fn interpolate(w0: i64, w1: i64, w2: i64, val0: u8, val1: u8, val2: u8) u8 {
    const result = (w0 * @as(i64, val0) + w1 * @as(i64, val1) + w2 * @as(i64, val2)) >> 12;

    return @as(u8, @intCast(@max(0, @min(255, result))));
}
