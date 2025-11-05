const std = @import("std");

const sdffont = @import("sdffont");
const SdfFont = sdffont.SdfFont;
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const font_path = "odin_example/MarkoOne-Regular.default.ttf";
    std.debug.print("Reading font file at: {s}\n", .{font_path});

    const bytes = try std.fs.cwd().readFileAlloc(allocator, font_path, 10 * 1024 * 1024);
    defer allocator.free(bytes);

    const font = try SdfFont.create(bytes, sdffont.SDF_FONT_SETTINGS_DEFAULT);
    defer font.free();

    const metrics = font.getLineMetrics();
    std.debug.print("ascent={}, descent={}\n", .{ metrics.ascent, metrics.descent });

    std.debug.print("{}\n", .{font.hasAtlasImageChanged()});

    std.debug.print("glyph for 'A': {}\n", .{font.getOrAddGlyph('A')});
    std.debug.print("atlas_image_changed: {}\n", .{font.hasAtlasImageChanged()});
    const img = font.getAtlasImage();
    std.debug.print("atlas image size: {any}\n", .{img.size});

    std.debug.print("glyph for ' ': {}\n", .{font.getOrAddGlyph(' ')});
    std.debug.print("atlas_image_changed: {}\n", .{font.hasAtlasImageChanged()});
}
