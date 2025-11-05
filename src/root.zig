const std = @import("std");

pub const SdfFontSettings = extern struct {
    font_size: u32,
    pad_size: u32,
    sdf_radius: f32,
    atlas_size: [2]u32,
    initialize_with_default_glyphs: bool,
};

pub const SDF_FONT_SETTINGS_DEFAULT = SdfFontSettings{
    .font_size = 64,
    .pad_size = 16,
    .sdf_radius = 16.0,
    .atlas_size = .{ 1024, 1024 },
    .initialize_with_default_glyphs = true,
};

pub const LineMetrics = extern struct {
    ascent: f32,
    descent: f32,
    line_gap: f32,
};

pub const GlyphKind = enum(u8) {
    NotContained = 0,
    Whitespace = 1,
    Default = 2,
};

pub const GlyphInfo = extern struct {
    kind: GlyphKind,
    xmin: f32,
    ymin: f32,
    width: f32,
    height: f32,
    advance: f32,
    uv_min: [2]f32,
    uv_max: [2]f32,
};

const AtlasImageRaw = extern struct {
    size: [2]u32,
    bytes: RawSlice,
};

/// Grayscale image of sdf font
pub const AtlasImage = struct {
    size: [2]u32,
    bytes: []const u8,
};

// Use "sdffont" as the library name (links to libsdffont.so or sdffont.dll)
const RawSlice = extern struct {
    ptr: [*]const u8,
    len: isize,

    fn fromSlice(slice: []const u8) @This() {
        return .{
            .ptr = slice.ptr,
            .len = @intCast(slice.len),
        };
    }

    fn asSlice(self: @This()) []const u8 {
        var err_string: []const u8 = undefined;
        err_string.ptr = self.ptr;
        err_string.len = @intCast(self.len);
        return err_string;
    }
};
const RawString = RawSlice;

pub const SdfFont = opaque {
    const Self = @This();
    pub fn create(bytes: []const u8, settings: SdfFontSettings) !*Self {
        var err: RawString = undefined;
        const self = font_create(RawSlice.fromSlice(bytes), settings, &err) orelse {
            std.log.err("could not load SdfFont: {s}", .{err.asSlice()});
            return error.CouldNotCreateFont;
        };
        return self;
    }
    pub fn free(self: *Self) void {
        font_free(self);
    }
    // Returns true if the atlas has changed (new glyphs added) since the last call to `getAtlasImage`.
    // So calling getAtlasImage resets this to false. Can be used every frame to check if texture writes
    // to the atlas texture need to be done. Currently only writing the entire texture is supported.
    // In the future we should provide finer dirty regions that need to be uploaded to the gpu.
    pub inline fn hasAtlasImageChanged(self: *Self) bool {
        return font_has_atlas_image_changed(self);
    }
    pub inline fn getAtlasImage(self: *Self) AtlasImage {
        const atlas_image_raw = font_get_atlas_image(self);
        return AtlasImage{
            .size = atlas_image_raw.size,
            .bytes = atlas_image_raw.bytes.asSlice(),
        };
    }
    pub inline fn getOrAddGlyph(self: *Self, codepoint: u32) GlyphInfo {
        return font_get_or_add_glyph(self, codepoint);
    }
    pub inline fn getHorizontalKerning(self: *Self, left_codepoint: u32, right_codepoint: u32) f32 {
        return font_get_horizontal_kerning(self, left_codepoint, right_codepoint);
    }
    pub inline fn getLineMetrics(self: *Self) LineMetrics {
        return font_get_line_metrics(self);
    }
};

extern "sdffont" fn font_create(
    bytes: RawSlice,
    settings: SdfFontSettings,
    err: *RawString,
) callconv(.c) ?*SdfFont;
extern "sdffont" fn font_free(font: *SdfFont) callconv(.c) void;
extern "sdffont" fn font_has_atlas_image_changed(font: *SdfFont) callconv(.c) bool;
extern "sdffont" fn font_get_atlas_image(font: *SdfFont) callconv(.c) AtlasImageRaw;
extern "sdffont" fn font_get_or_add_glyph(font: *SdfFont, ch: u32) callconv(.c) GlyphInfo;
extern "sdffont" fn font_get_horizontal_kerning(font: *SdfFont, left: u32, right: u32) callconv(.c) f32;
extern "sdffont" fn font_get_line_metrics(font: *SdfFont) callconv(.c) LineMetrics;
