This is an Odin package wrapping the Rust libraries fontdue, etagere and sdfer to provide fast sdf font atlas generation with a simple interface.

How to build for small binary size:

```sh
RUSTFLAGS="-Zlocation-detail=none -Zfmt-debug=none" cargo +nightly build --release
```

<img src="./font_after.bmp" />
