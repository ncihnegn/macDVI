# macDVI

An AppKit DVI viewer for macOS.

The viewer opens `.dvi` files in a native macOS window. It renders DVI files directly with a built-in parser and AppKit renderer that handles pages, positioning, text, rules, zooming, TeX font metrics, Type 1 outline fonts, full Computer Modern glyph mapping (OT1, OT1tt, OML, OMS, OMX, MSAM, MSBM, and T1 / Cork encodings), page-size specials, and common color specials. If the native parser cannot read a file, the app can still fall back to `dvipdfmx` and PDFKit when a TeX converter is installed.

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

## Deploy

The build script produces a self-contained `build/macDVI.app` bundle. Deployment is a matter of getting that bundle onto a target Mac.

### Local install

Copy the app into `/Applications` (system-wide) or `~/Applications` (current user):

```sh
./Scripts/build_app.sh
cp -R build/macDVI.app /Applications/
```

### Code signing and notarization

For distribution outside your own machine, sign and notarize the bundle so Gatekeeper accepts it:

```sh
codesign --force --deep --options runtime \
    --sign "Developer ID Application: YOUR NAME (TEAMID)" \
    build/macDVI.app

ditto -c -k --keepParent build/macDVI.app build/macDVI.zip

xcrun notarytool submit build/macDVI.zip \
    --keychain-profile "AC_PASSWORD" --wait

xcrun stapler staple build/macDVI.app
```

`AC_PASSWORD` is a `notarytool` keychain profile created once with `xcrun notarytool store-credentials`. Replace the signing identity with one from your Apple Developer account.

### Distribute as a DMG

Package the signed app for download:

```sh
hdiutil create -volname macDVI -srcfolder build/macDVI.app \
    -ov -format UDZO build/macDVI.dmg
codesign --sign "Developer ID Application: YOUR NAME (TEAMID)" build/macDVI.dmg
xcrun notarytool submit build/macDVI.dmg \
    --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple build/macDVI.dmg
```

Upload `build/macDVI.dmg` to your release host (GitHub Releases, S3, a static site, etc.). For ad-hoc sharing, the unsigned `build/macDVI.app` also runs locally if the user clears the quarantine attribute with `xattr -dr com.apple.quarantine /Applications/macDVI.app`.

## Notes

- The native renderer reads `.tfm` files next to the document and through `kpsewhich` when available, using real TFM width, height, depth, and italic-correction metrics.
- Type 1 `.pfb` and `.pfa` fonts are resolved next to the document, through TeX map files, and through `kpsewhich`; unsupported or missing outlines fall back to AppKit fonts.
- Computer Modern character codes are mapped to Unicode and PostScript glyph names per font encoding (OT1, OT1tt, OML, OMS, OMX, MSAM, MSBM, T1) so outline glyphs resolve correctly across text, math, and AMS fonts.
- The optional converter fallback requires `dvipdfmx` on the path or in `/Library/TeX/texbin`.
- The native renderer is intended for inspection and simple DVI documents; virtual fonts and PK/GF bitmap fonts are not fully implemented.
