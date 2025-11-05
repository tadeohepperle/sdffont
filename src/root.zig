// ---------- Type definitions ----------

pub const SdfFont = ?*anyopaque;

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

pub const AtlasImage = extern struct {
    size: [2]u32,
    bytes: [*]u8,
};

// ---------- Foreign functions ----------
// Use "sdffont" as the library name (links to libsdffont.so or sdffont.dll)

pub extern "sdffont" fn font_create(
    bytes: [*]const u8,
    len: usize,
    settings: SdfFontSettings,
    err: ?*[*:0]const u8,
) callconv(.c) SdfFont;

pub extern "sdffont" fn font_free(font: SdfFont) callconv(.c) void;
pub extern "sdffont" fn font_has_atlas_image_changed(font: SdfFont) callconv(.c) bool;
pub extern "sdffont" fn font_get_atlas_image(font: SdfFont) callconv(.c) AtlasImage;
pub extern "sdffont" fn font_get_or_add_glyph(font: SdfFont, ch: u32) callconv(.c) GlyphInfo;
pub extern "sdffont" fn font_get_horizontal_kerning(font: SdfFont, left: u32, right: u32) callconv(.c) f32;
pub extern "sdffont" fn font_get_line_metrics(font: SdfFont) callconv(.c) LineMetrics;
