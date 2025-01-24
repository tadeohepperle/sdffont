package fontduesdf

import "core:fmt"
import "core:os"
import "vendor:stb/image"

foreign import __lib "./fontduesdf/target/release/libfontduesdf.a"
foreign __lib {
	add :: proc(a: f32, b: f32) -> f32 ---
	font_create :: proc(bytes: []u8, settings: SdfFontSettings = SDF_FONT_SETTINGS_DEFAULT, error: ^string = nil) -> ^SdfFont ---
	font_free :: proc(font: ^SdfFont) ---
	font_has_atlas_image_changed :: proc(font: ^SdfFont) -> bool ---
	font_get_atlas_image :: proc(font: ^SdfFont) -> AtlasImage ---
	font_get_or_add_glyph :: proc(font: ^SdfFont, ch: rune) -> GlyphInfo ---
	font_get_horizontal_kerning :: proc(font: ^SdfFont, left: rune, right: rune) -> f32 ---
	font_get_line_metrics :: proc(font: ^SdfFont) -> LineMetrics ---
}

AtlasImage :: struct {
	size:  [2]u32,
	bytes: []u8, // single channel grey image with 1 byte per pixel
}

SdfFont :: struct {}
SdfFontSettings :: struct {
	/// fontsize the sdf is rasterized at. 32 or 64 is recommended.
	font_size:                      u32,
	/// padding to each of the 4 dimensions for each glyph. A value of font_size / 8 is recommended.
	pad_size:                       u32,
	/// should be <= pad_size
	sdf_radius:                     f32,
	/// should be a power of 2
	atlas_size:                     [2]u32,
	// if true, the font will rasterize the majority of ascii characters already upon creation
	initialize_with_default_glyphs: bool,
}
SDF_FONT_SETTINGS_DEFAULT :: SdfFontSettings {
	font_size                      = 64,
	pad_size                       = 16,
	sdf_radius                     = 16,
	atlas_size                     = {1024, 1024},
	initialize_with_default_glyphs = true,
}

main :: proc() {

	bytes, success := os.read_entire_file("./LuxuriousRoman-Regular.ttf")
	assert(success)
	errstr: string
	font := font_create(bytes, SDF_FONT_SETTINGS_DEFAULT, &errstr)
	fmt.println(errstr)
	fmt.println(rawptr(font))

	img := font_get_atlas_image(font)
	image.write_bmp("font_before.bmp", i32(img.size.x), i32(img.size.y), 1, raw_data(img.bytes))
	fmt.println(font_get_or_add_glyph(font, 'Å'))
	fmt.println(font_get_or_add_glyph(font, '§'))
	fmt.println(font_get_line_metrics(font))
	image.write_bmp("font_after.bmp", i32(img.size.x), i32(img.size.y), 1, raw_data(img.bytes))
	fmt.println(font_get_horizontal_kerning(font, 'V', 'i'))

	// os.read_entire_file()
	// fmt.println("hello", add(3, 4))
}

LineMetrics :: struct {
	ascent:   f32,
	descent:  f32,
	line_gap: f32,
}
GlyphInfo :: struct {
	kind:    GlyphKind,
	metrics: GlyphMetrics,
	uv:      Aabb,
}
GlyphKind :: enum u8 {
	NotContained = 0,
	Whitespace   = 1,
	Default      = 2,
}
GlyphMetrics :: struct {
	xmin:    f32,
	ymin:    f32,
	width:   f32,
	height:  f32,
	advance: f32,
}
Aabb :: struct {
	min: [2]f32,
	max: [2]f32,
}
