const std = @import("std");

const ig = @import("cimgui_docking");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simgui = sokol.imgui;

const Emulator = @import("../emulator.zig").Emulator;
const WindowConfig = @import("state.zig").WindowConfig;

pub const VramWindow = struct {
    allocator: std.mem.Allocator,

    image: sg.Image,
    view: sg.View,
    sampler: sg.Sampler,

    texture_data: []u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const image = sg.makeImage(.{
            .width = 1024,
            .height = 512,
            .pixel_format = .RGBA8,
            .usage = .{ .stream_update = true },
            .label = "vram_render_target",
        });

        const view = sg.makeView(.{ .texture = .{ .image = image } });
        const sampler = sg.makeSampler(.{
            .min_filter = .NEAREST,
            .mag_filter = .NEAREST,
        });

        const texture_data = try allocator.alloc(u32, 1024 * 512);
        @memset(texture_data, 0xff000000);

        return .{
            .allocator = allocator,
            .image = image,
            .view = view,
            .sampler = sampler,
            .texture_data = texture_data,
        };
    }

    pub fn deinit(self: *Self) void {
        sg.destroyImage(self.image);
        sg.destroyView(self.view);
        sg.destroySampler(self.sampler);
    }

    pub fn draw(self: *Self, config: *WindowConfig, emulator: *Emulator) void {
        if (!config.visible) {
            return;
        }

        const gpu = &emulator.bus.gpu;

        // TODO: replace this with a u16 shader
        for (gpu.vram, 0..) |ps1_pixel, i| {
            const r5 = ps1_pixel & 0x1F;
            const g5 = (ps1_pixel >> 5) & 0x1F;
            const b5 = (ps1_pixel >> 10) & 0x1F;

            const r8 = @as(u32, r5) << 3;
            const g8 = @as(u32, g5) << 3;
            const b8 = @as(u32, b5) << 3;
            const a8 = @as(u32, 255);

            self.texture_data[i] = (a8 << 24) | (b8 << 16) | (g8 << 8) | r8;
        }

        var data_desc = sg.ImageData{};
        data_desc.mip_levels[0] = sg.asRange(self.texture_data);
        sg.updateImage(self.image, data_desc);

        ig.igSetNextWindowPos(config.pos, ig.ImGuiCond_FirstUseEver);
        ig.igSetNextWindowSize(config.size, ig.ImGuiCond_FirstUseEver);

        if (ig.igBegin("Vram", &config.visible, 0)) {
            const w_size = ig.igGetContentRegionAvail();
            const aspect: f32 = 1024.0 / 512.0;
            var draw_w = w_size.x;
            var draw_h = w_size.x / aspect;

            if (draw_h > w_size.y) {
                draw_h = w_size.y;
                draw_w = w_size.y * aspect;
            }

            ig.igSetCursorPosX((w_size.x - draw_w) * 0.5 + ig.igGetCursorPosX());
            ig.igSetCursorPosY((w_size.y - draw_h) * 0.5 + ig.igGetCursorPosY());

            ig.igImage(
                .{
                    ._TexID = simgui.imtextureidWithSampler(
                        self.view,
                        self.sampler,
                    ),
                },
                .{ .x = draw_w, .y = draw_h },
            );
        }
        ig.igEnd();
    }
};
