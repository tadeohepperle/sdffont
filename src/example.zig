const std = @import("std");

const sdffont = @import("sdffont");
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const font_path = "odin_example/MarkoOne-Regular.default.ttf";
    std.debug.print("Reading font file at: {s}\n", .{font_path});

    const bytes = try std.fs.cwd().readFileAlloc(allocator, font_path, 10 * 1024 * 1024);
    defer allocator.free(bytes);

    const font = sdffont.font_create(bytes.ptr, bytes.len, sdffont.SDF_FONT_SETTINGS_DEFAULT, null);
    if (font == null) {
        std.debug.print("font_create failed\n", .{});
        return;
    }

    const metrics = sdffont.font_get_line_metrics(font);
    std.debug.print("ascent={}, descent={}\n", .{ metrics.ascent, metrics.descent });

    sdffont.font_free(font);
}
