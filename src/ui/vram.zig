const ig = @import("cimgui_docking");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simgui = sokol.imgui;

const Emulator = @import("../emulator.zig").Emulator;
const WindowConfig = @import("state.zig").WindowConfig;

pub const VramWindow = struct {
    image: sg.Image,
    view: sg.View,
    sampler: sg.Sampler,

    texture_buffer: [1024 * 512]u32,

    const Self = @This();

    pub fn init() Self {
        const image = sg.makeImage(.{
            .width = 1024,
            .height = 512,
            .pixel_format = .RGBA8,
            .usage = .{ .stream_update = true },
            .label = "vram",
        });
        const view = sg.makeView(.{ .texture = .{ .image = image } });
        const sampler = sg.makeSampler(.{
            .min_filter = .NEAREST,
            .mag_filter = .NEAREST,
        });

        return .{
            .image = image,
            .view = view,
            .sampler = sampler,
            .texture_buffer = [_]u32{0xff000000} ** (1024 * 512),
        };
    }

    pub fn deinit(self: *Self) void {
        sg.destroySampler(self.sampler);
        sg.destroyView(self.view);
        sg.destroyImage(self.image);
    }

    pub fn draw(self: *Self, config: *WindowConfig, emulator: *Emulator) void {
        if (!config.visible) {
            return;
        }

        const gpu = &emulator.bus.gpu;
        _ = gpu;

        var data_desc = sg.ImageData{};
        data_desc.mip_levels[0] = sg.asRange(&self.texture_buffer);
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
