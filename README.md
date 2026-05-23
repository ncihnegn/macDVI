# macDVI

An AppKit DVI viewer for macOS.

The viewer opens `.dvi` files in a native macOS window. It renders DVI files directly with a built-in parser and AppKit renderer that handles pages, positioning, text, rules, zooming, TeX font metrics, page-size specials, and common color specials. If the native parser cannot read a file, the app can still fall back to `dvipdfmx` and PDFKit when a TeX converter is installed.

## Build and Run

Run directly from SwiftPM:

```sh
swift run macDVI
swift run macDVI path/to/file.dvi
```

Build a `.app` bundle:

```sh
./Scripts/build_app.sh
open build/macDVI.app
```

## Notes

- The native renderer reads `.tfm` files next to the document and through `kpsewhich` when available, using real TFM width, height, depth, and italic-correction metrics.
- The optional converter fallback requires `dvipdfmx` on the path or in `/Library/TeX/texbin`.
- The native renderer is intended for inspection and simple DVI documents; virtual fonts, PK/GF bitmap fonts, and complete Computer Modern glyph mapping are not fully implemented.
