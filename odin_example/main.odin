package example

import sdffont "../"
import "core:fmt"
import "core:os"
import "vendor:stb/image"

main :: proc() {
	bytes, success := os.read_entire_file("./MarkoOne-Regular.default.ttf")
	assert(success)
	errstr: string
	font := sdffont.font_create(bytes, sdffont.SDF_FONT_SETTINGS_DEFAULT, &errstr)
	fmt.println(errstr)
	fmt.println(rawptr(font))

	img := sdffont.font_get_atlas_image(font)
	image.write_bmp("font_before.bmp", i32(img.size.x), i32(img.size.y), 1, raw_data(img.bytes))
	fmt.println(sdffont.font_get_or_add_glyph(font, 'Å'))
	fmt.println(sdffont.font_get_or_add_glyph(font, '§'))

	image.write_bmp("font_after.bmp", i32(img.size.x), i32(img.size.y), 1, raw_data(img.bytes))
	fmt.println(sdffont.font_get_horizontal_kerning(font, 'V', 'i'))

	fmt.println("\n\n")
	fmt.println("'T':", sdffont.font_get_or_add_glyph(font, 'T'))
	fmt.println("'p':", sdffont.font_get_or_add_glyph(font, 'p'))
	fmt.println(sdffont.font_get_line_metrics(font))
}
