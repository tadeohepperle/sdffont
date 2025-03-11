package sdffont

import "core:fmt"
import "core:os"
import "vendor:stb/image"

when ODIN_OS == .Linux do foreign import __lib "./sdffont/target/release/libsdffont.so"
when ODIN_OS == .Windows do foreign import __lib "./sdffont/target/release/sdffont.dll"
foreign __lib {
	font_create :: proc(bytes: []u8, settings: SdfFontSettings = SDF_FONT_SETTINGS_DEFAULT, error: ^string = nil) -> SdfFont ---
	font_free :: proc(font: SdfFont) ---
	font_has_atlas_image_changed :: proc(font: SdfFont) -> bool ---
	font_get_atlas_image :: proc(font: SdfFont) -> AtlasImage ---
	font_get_or_add_glyph :: proc(font: SdfFont, ch: rune) -> GlyphInfo ---
	font_get_horizontal_kerning :: proc(font: SdfFont, left: rune, right: rune) -> f32 ---
	font_get_line_metrics :: proc(font: SdfFont) -> LineMetrics ---
}

AtlasImage :: struct {
	size:  [2]u32,
	bytes: []u8, // single channel grey image with 1 byte per pixel
}

SdfFont :: ^struct {} // opaque ptr, in Rust this is Box<SdfFont>

SdfFontSettings :: struct {
	/// fontsize the sdf is rasterized at. 32 or 64 is recommended.
	font_size:                      u32,
	/// padding to each of the 4 dimensions for each glyph. A value of font_size / 8 is recommended.
	pad_size:                       u32,
	/// should be <= pad_size, if sdf_radius is 0, no sdf is computed at all and the original rasterized greyimage is put into the atlas
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

	image.write_bmp("font_after.bmp", i32(img.size.x), i32(img.size.y), 1, raw_data(img.bytes))
	fmt.println(font_get_horizontal_kerning(font, 'V', 'i'))

	fmt.println("\n\n")
	fmt.println("'T':", font_get_or_add_glyph(font, 'T'))
	fmt.println("'p':", font_get_or_add_glyph(font, 'p'))
	fmt.println(font_get_line_metrics(font))
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
	xmin:    f32,
	ymin:    f32,
	width:   f32,
	height:  f32,
	advance: f32,
	uv_min:  [2]f32,
	uv_max:  [2]f32,
}
GlyphKind :: enum u8 {
	NotContained = 0,
	Whitespace   = 1,
	Default      = 2,
}
