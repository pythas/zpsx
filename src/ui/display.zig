const std = @import("std");

const ig = @import("cimgui_docking");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simgui = sokol.imgui;

const Emulator = @import("../emulator.zig").Emulator;
const WindowConfig = @import("state.zig").WindowConfig;

pub const DisplayWindow = struct {
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
        for (gpu.vram, 0..) |pixel, i| {
            const r5 = pixel & 0x1f;
            const g5 = (pixel >> 5) & 0x1f;
            const b5 = (pixel >> 10) & 0x1f;

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

        if (ig.igBegin("Display", &config.visible, 0)) {
            const display_x: f32 = @floatFromInt(gpu.display_vram_x_start);
            const display_y: f32 = @floatFromInt(gpu.display_vram_y_start);

            const display_w: f32 = @floatFromInt(gpu.gpustat.horizontalResolution());
            const display_h: f32 = @floatFromInt(gpu.gpustat.verticalResolution());

            const vram_w: f32 = 1024.0;
            const vram_h: f32 = 512.0;

            const uv0 = ig.ImVec2{
                .x = display_x / vram_w,
                .y = display_y / vram_h,
            };
            const uv1 = ig.ImVec2{
                .x = (display_x + display_w) / vram_w,
                .y = (display_y + display_h) / vram_h,
            };

            const w_size = ig.igGetContentRegionAvail();
            const aspect: f32 = 4.0 / 3.0;

            var draw_w = w_size.x;
            var draw_h = w_size.x / aspect;

            if (draw_h > w_size.y) {
                draw_h = w_size.y;
                draw_w = w_size.y * aspect;
            }

            ig.igSetCursorPosX((w_size.x - draw_w) * 0.5 + ig.igGetCursorPosX());
            ig.igSetCursorPosY((w_size.y - draw_h) * 0.5 + ig.igGetCursorPosY());

            // pub extern fn igImageEx(tex_ref: ImTextureRef, image_size: ImVec2, uv0: ImVec2, uv1: ImVec2) void;

            ig.igImageEx(
                .{
                    ._TexID = simgui.imtextureidWithSampler(
                        self.view,
                        self.sampler,
                    ),
                },
                .{ .x = draw_w, .y = draw_h },
                uv0,
                uv1,
            );
        }
        ig.igEnd();
    }
};
