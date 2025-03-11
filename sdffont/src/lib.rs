use std::collections::hash_map::Entry;
use ttf_parser::gpos::{PairAdjustment, PositioningSubtable};

#[unsafe(no_mangle)]
pub extern "C" fn font_create(
    bytes: RawSlice,
    settings: SdfFontSettings,
    err: *mut RawString,
) -> *mut SdfFont {
    match SdfFont::new(bytes.typed::<u8>(), settings) {
        Ok(font) => {
            return Box::leak(Box::new(font)) as *mut SdfFont;
        }
        Err(err_str) => {
            RawString::set(err, err_str);
            return std::ptr::null_mut();
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn font_free(font: *mut SdfFont) {
    if !font.is_null() {
        let font_box = unsafe { Box::from_raw(font) };
        drop(font_box);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn font_has_atlas_image_changed(font: *mut SdfFont) -> bool {
    unsafe {
        font.as_ref()
            .map(|f| f.has_atlas_image_changed)
            .unwrap_or(false)
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn font_get_atlas_image(font: *mut SdfFont) -> AtlasImage {
    let font = unsafe { font.as_mut() };
    if let Some(font) = font {
        font.has_atlas_image_changed = false; // set to false, such that people can call font_has_atlas_image_changed repeatedly and when true, call this font_get_atlas_image one time. 
        let (width, height) = (font.settings.atlas_width, font.settings.atlas_height);
        return AtlasImage {
            width,
            height,
            bytes: RawSlice {
                ptr: font.atlas_image.as_ptr() as *const (),
                len: (width * height) as isize,
            },
        };
    } else {
        return AtlasImage {
            width: 0,
            height: 0,
            bytes: RawSlice {
                ptr: std::ptr::null(),
                len: 0,
            },
        };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn font_get_or_add_glyph(font: *mut SdfFont, ch: u32) -> GlyphInfo {
    let ch = unsafe { char::from_u32_unchecked(ch) };
    if let Some(font) = unsafe { font.as_mut() } {
        font.get_or_add_glyph(ch)
    } else {
        UNKNOWN_GLYPH
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn font_get_horizontal_kerning(
    font: *mut SdfFont,
    left_ch: u32,
    right_ch: u32,
) -> f32 {
    let left_ch = unsafe { char::from_u32_unchecked(left_ch) };
    let right_ch = unsafe { char::from_u32_unchecked(right_ch) };
    if let Some(font) = unsafe { font.as_mut() } {
        font.get_horizontal_kerning(left_ch, right_ch)
    } else {
        0.0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn font_get_line_metrics(font: *mut SdfFont) -> LineMetrics {
    if let Some(font) = unsafe { font.as_mut() } {
        font.line_metrics
    } else {
        LineMetrics {
            ascent: 0.0,
            descent: 0.0,
            line_gap: 0.0,
        }
    }
}

#[repr(C)]
pub struct AtlasImage {
    width: u32,
    height: u32,
    bytes: RawSlice,
}

#[repr(C)]
pub struct RawString {
    ptr: *const u8,
    len: isize,
}

impl RawString {
    // fn from_str(str: &'static str) -> Self {
    //     return RawString {
    //         ptr: str.as_ptr(),
    //         len: str.len() as isize,
    //     };
    // }

    fn set(ptr: *mut RawString, value: &'static str) {
        unsafe {
            if let Some(ptr) = ptr.as_mut() {
                ptr.len = value.len() as isize;
                ptr.ptr = value.as_ptr();
            }
        }
    }
}

#[repr(C)]
pub struct RawSlice {
    ptr: *const (),
    len: isize,
}
impl RawSlice {
    fn typed<T>(&self) -> &[T] {
        let align = std::mem::align_of::<T>();
        if self.ptr as usize % align != 0 {
            panic!("Unaligned pointer to type {}", std::any::type_name::<T>())
        }
        assert!(self.len >= 0);
        unsafe { std::slice::from_raw_parts(self.ptr as *const T, self.len as usize) }
    }
}

#[derive(Debug, Clone, Copy)]
#[repr(C)]
pub struct SdfFontSettings {
    /// fontsize the sdf is rasterized at. 32 or 64 is recommended.
    font_size: u32,
    /// padding to each of the 4 dimensions for each glyph. A value of font_size / 8 is recommended.
    pad_size: u32,
    // if sdf_radius is 0, no sdf is computed at all and the original rasterized greyimage is put into the atlas
    sdf_radius: f32,
    /// should be a power of 2
    atlas_width: u32,
    /// should be a power of 2
    atlas_height: u32,
    // if true, the font will rasterize the majority of ascii characters already upon creation
    initialize_with_default_glyphs: bool,
}

pub struct SdfFont {
    settings: SdfFontSettings,
    _font_bytes: Vec<u8>,
    font_face: ttf_parser::Face<'static>,
    font: fontdue::Font,
    line_metrics: LineMetrics,

    atlas: etagere::AtlasAllocator,
    atlas_image: Vec<u8>,

    glyphs: ahash::AHashMap<char, SdfGlyph>,
    horizontal_kerning: ahash::AHashMap<(char, char), f32>,
    reusable_buffers: Option<sdfer::esdt::ReusableBuffers>,
    has_atlas_image_changed: bool, // reset to false if the Odin code accesses the image (to update a texture)
}

impl SdfFont {
    fn new(bytes: &[u8], settings: SdfFontSettings) -> Result<Self, &'static str> {
        let font_bytes = bytes.to_vec();
        let font_face = ttf_parser::Face::parse(static_bytes(&font_bytes), 0)
            .map_err(|_| "Font Parsing Error")?;
        let fontdue_settings = fontdue::FontSettings {
            collection_index: 0,
            scale: settings.font_size as f32,
            load_substitutions: false,
        };
        let font = fontdue::Font::from_bytes(&font_bytes[..], fontdue_settings)?;
        let Some(h_line_metrics) = font.horizontal_line_metrics(settings.font_size as f32) else {
            return Err("font does not have horizontal line metrics");
        };
        let line_metrics = LineMetrics {
            ascent: h_line_metrics.ascent,
            descent: h_line_metrics.descent,
            line_gap: h_line_metrics.line_gap,
        };

        let atlas = etagere::AtlasAllocator::new(etagere::size2(
            settings.atlas_width as i32,
            settings.atlas_height as i32,
        ));
        let atlas_image: Vec<u8> = vec![0; (settings.atlas_width * settings.atlas_height) as usize];
        // font.horizontal_kern_indexed(left, right, px)
        let mut font = SdfFont {
            _font_bytes: font_bytes, // just to ensure that they live as long as the face.
            font_face,
            line_metrics,
            settings,
            font,
            atlas,
            atlas_image,
            glyphs: Default::default(),
            horizontal_kerning: Default::default(),
            reusable_buffers: Default::default(),
            has_atlas_image_changed: false,
        };
        if settings.initialize_with_default_glyphs {
            font.initialize_with_default_glyphs();
        }
        Ok(font)
    }
    fn initialize_with_default_glyphs(&mut self) {
        const DEFAULT_CHARS: &str = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.@#$%^&,!:;/?|(){}[]!+-_=* \n\t'\"><~`\\";
        for ch in DEFAULT_CHARS.chars() {
            _ = self.get_or_add_glyph(ch);
        }
    }

    // this tries to add the glyph into the
    fn get_or_add_glyph(&mut self, ch: char) -> GlyphInfo {
        let info: GlyphInfo;
        match self.glyphs.entry(ch) {
            Entry::Occupied(occupied) => return occupied.get().info,
            Entry::Vacant(vacant_entry) => {
                let is_white_space = ch.is_whitespace();
                if !self.font.has_glyph(ch) {
                    // if glyph not in font, mark this in the hashmap and return NotContained.
                    info = GlyphInfo {
                        kind: if is_white_space {
                            GlyphKind::Whitespace
                        } else {
                            GlyphKind::NotContained
                        },
                        ..UNKNOWN_GLYPH
                    };
                    vacant_entry.insert(SdfGlyph {
                        info,
                        _alloc_id: None,
                    });
                    return info;
                }
                // add the glyph:
                let (f_metrics, rasterized_buf) =
                    self.font.rasterize(ch, self.settings.font_size as f32);
                if is_white_space {
                    let info = GlyphInfo {
                        kind: GlyphKind::Whitespace,
                        advance: f_metrics.advance_width,
                        ..Default::default()
                    };
                    vacant_entry.insert(SdfGlyph {
                        info,
                        _alloc_id: None,
                    });
                    return info;
                }
                let pad = self.settings.pad_size;

                // add the padding here, because sdf requires larger quads than usual, important for e.g. text shadow

                let alloc_id: etagere::AllocId;
                let (pos_x, pos_y, size_x, size_y): (usize, usize, usize, usize);
                if self.settings.sdf_radius == 0.0 {
                    // just copy grey img into atlas, but allocate padding in atlas as well
                    size_x = f_metrics.width as usize + 2 * pad as usize;
                    size_y = f_metrics.height as usize + 2 * pad as usize;
                    let allocation = self
                        .atlas
                        .allocate(etagere::size2(size_x as i32, size_y as i32))
                        .expect("font atlas is too small");
                    alloc_id = allocation.id;
                    pos_x = allocation.rectangle.min.x as usize;
                    pos_y = allocation.rectangle.min.y as usize;
                    copy_gray_into_atlas(
                        &mut self.atlas_image,
                        self.settings.atlas_width as usize,
                        &rasterized_buf,
                        f_metrics.width,
                        f_metrics.height,
                        pos_x + pad as usize,
                        pos_y + pad as usize,
                    );
                } else {
                    // generate sdf and put it into the atlas
                    let mut gray_for_sdfer = sdfer::Image2d::<sdfer::Unorm8>::from_storage(
                        f_metrics.width,
                        f_metrics.height,
                        rasterized_buf
                            .into_iter()
                            .map(|e| sdfer::Unorm8::from_bits(e))
                            .collect::<Vec<sdfer::Unorm8>>(),
                    );
                    let (esdfer_sdf_img, reuse) = sdfer::esdt::glyph_to_sdf(
                        &mut gray_for_sdfer,
                        sdfer::esdt::Params {
                            pad: self.settings.pad_size as usize,
                            radius: self.settings.sdf_radius,
                            cutoff: 0.5,
                            solidify: true,
                            preprocess: true,
                        },
                        self.reusable_buffers.take(),
                    );
                    self.reusable_buffers = Some(reuse);
                    (size_x, size_y) = (esdfer_sdf_img.width(), esdfer_sdf_img.height());
                    let allocation = self
                        .atlas
                        .allocate(etagere::size2(size_x as i32, size_y as i32))
                        .expect("font atlas is too small");
                    alloc_id = allocation.id;
                    pos_x = allocation.rectangle.min.x as usize;
                    pos_y = allocation.rectangle.min.y as usize;
                    copy_sdf_into_atlas(
                        &mut self.atlas_image,
                        self.settings.atlas_width as usize,
                        &esdfer_sdf_img,
                        pos_x,
                        pos_y,
                    );
                }

                // adding the padding should not have any influence on the layout algorithm, only on the size of the quads rendered
                let atlas_w = self.settings.atlas_width as f32;
                let atlas_h = self.settings.atlas_height as f32;
                info = GlyphInfo {
                    kind: GlyphKind::Default,
                    xmin: f_metrics.bounds.xmin - pad as f32,
                    ymin: f_metrics.bounds.ymin - pad as f32,
                    width: f_metrics.bounds.width + (2 * pad) as f32,
                    height: f_metrics.bounds.height + (2 * pad) as f32,
                    advance: f_metrics.advance_width,
                    uv_min_x: pos_x as f32 / atlas_w,
                    uv_min_y: pos_y as f32 / atlas_h,
                    uv_max_x: (pos_x + size_x) as f32 / atlas_w,
                    uv_max_y: (pos_y + size_y) as f32 / atlas_h,
                };
                self.has_atlas_image_changed = true;
                vacant_entry.insert(SdfGlyph {
                    info,
                    _alloc_id: Some(alloc_id),
                });
            }
        }

        // calculate the kerning between this glyph and all others and insert it into the hashmap:
        for &other_ch in self.glyphs.keys() {
            let ch_to_other_kern = get_kerning(
                &self.font,
                &self.font_face,
                ch,
                other_ch,
                self.settings.font_size,
            );
            if let Some(kern) = ch_to_other_kern {
                self.horizontal_kerning.insert((ch, other_ch), kern);
            }
            if other_ch != ch {
                let other_to_ch_kern = get_kerning(
                    &self.font,
                    &self.font_face,
                    other_ch,
                    ch,
                    self.settings.font_size,
                );
                if let Some(kern) = other_to_ch_kern {
                    self.horizontal_kerning.insert((other_ch, ch), kern);
                }
            }
        }
        return info;
    }

    fn get_horizontal_kerning(&self, a: char, b: char) -> f32 {
        self.horizontal_kerning.get(&(a, b)).copied().unwrap_or(0.0)
    }
}

fn copy_sdf_into_atlas(
    atlas: &mut [u8],
    atlas_w: usize,
    sdf: &sdfer::Image2d<sdfer::Unorm8>,
    alloc_x: usize,
    alloc_y: usize,
) {
    let (sdf_w, sdf_h) = (sdf.width(), sdf.height());
    for y in 0..sdf_h {
        for x in 0..sdf_w {
            atlas[atlas_w * (y + alloc_y) + (x + alloc_x)] = sdf[(x, y)].to_bits();
        }
    }
}

fn copy_gray_into_atlas(
    atlas: &mut [u8],
    atlas_w: usize,
    gray: &[u8],
    gray_w: usize,
    gray_h: usize,
    alloc_x: usize,
    alloc_y: usize,
) {
    for y in 0..gray_h {
        let line = &gray[y * gray_w..y * gray_w + gray_w];
        let atlas_line = &mut atlas
            [(alloc_y + y) * atlas_w + alloc_x..(alloc_y + y) * atlas_w + alloc_x + gray_w];
        unsafe {
            std::ptr::copy_nonoverlapping(line.as_ptr(), atlas_line.as_mut_ptr(), gray_w);
        }
    }
}

pub fn static_bytes<'a>(bytes: &'a [u8]) -> &'static [u8] {
    unsafe { std::mem::transmute(bytes) }
}

struct SdfGlyph {
    info: GlyphInfo,
    _alloc_id: Option<etagere::AllocId>, // saved here for adding remove glyph functionality later.
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct GlyphInfo {
    kind: GlyphKind,
    pub xmin: f32,
    pub ymin: f32,
    pub width: f32,
    pub height: f32,
    pub advance: f32,
    pub uv_min_x: f32,
    pub uv_min_y: f32,
    pub uv_max_x: f32,
    pub uv_max_y: f32,
}
const UNKNOWN_GLYPH: GlyphInfo = GlyphInfo {
    kind: GlyphKind::NotContained,
    xmin: 0.0,
    ymin: 0.0,
    width: 0.0,
    height: 0.0,
    advance: 0.0,
    uv_min_x: 0.0,
    uv_min_y: 0.0,
    uv_max_x: 0.0,
    uv_max_y: 0.0,
};

#[repr(u8)]
#[derive(Debug, Clone, Copy, Default)]
pub enum GlyphKind {
    #[default]
    NotContained = 0,
    Whitespace = 1,
    Default = 2,
}

/// Metrics associated with line positioning.
#[derive(Copy, Clone, PartialEq, Debug)]
#[repr(C)]
pub struct LineMetrics {
    pub ascent: f32,
    pub descent: f32,
    pub line_gap: f32,
}

/// `a_ch` is the left character, `b_ch` is the right character. e.g. AV
fn get_kerning(
    font: &fontdue::Font,
    font_face: &ttf_parser::Face<'static>,
    a_ch: char,
    b_ch: char,
    font_size: u32,
) -> Option<f32> {
    let scale_factor = font.scale_factor(font_size as f32);
    if let Some(kern) = get_horizontal_kern_from_gpos_table(font_face, a_ch, b_ch, scale_factor) {
        return Some(kern);
    }
    return font.horizontal_kern(a_ch, b_ch, font_size as f32);
}

fn get_horizontal_kern_from_gpos_table(
    font_face: &ttf_parser::Face<'static>,
    a_ch: char,
    b_ch: char,
    scale_factor: f32,
) -> Option<f32> {
    let a_g_idx = font_face.glyph_index(a_ch)?;
    let b_g_idx = font_face.glyph_index(b_ch)?;
    let gpos = font_face.tables().gpos.as_ref()?;

    let x_advance_to_kerning = |x_advance: i16| -> Option<f32> {
        if x_advance == 0 {
            return None;
        } else {
            Some(x_advance as f32 * scale_factor)
        }
    };

    for lookup in gpos.lookups {
        for subtable in lookup.subtables.into_iter::<PositioningSubtable>() {
            match subtable {
                PositioningSubtable::Pair(PairAdjustment::Format1 { coverage, sets }) => {
                    if let Some(a_cov_idx) = coverage.get(a_g_idx) {
                        if let Some(pair_set) = sets.get(a_cov_idx) {
                            if let Some((rec_a, _rec_b)) = pair_set.get(b_g_idx) {
                                return x_advance_to_kerning(rec_a.x_advance);
                            }
                        }
                    }
                }
                PositioningSubtable::Pair(PairAdjustment::Format2 {
                    coverage,
                    classes,
                    matrix,
                }) => {
                    if coverage.get(a_g_idx).is_none() {
                        continue;
                    }
                    let classa = classes.0.get(a_g_idx);
                    let classb = classes.1.get(b_g_idx);
                    if let Some((rec_a, _rec_b)) = matrix.get((classa, classb)) {
                        return x_advance_to_kerning(rec_a.x_advance);
                    }
                }
                _ => {}
            }
        }
    }
    return None;
}
