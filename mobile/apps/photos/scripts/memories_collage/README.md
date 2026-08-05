# Memories collage asset export

This directory preserves the approved Claude Design template 2a and exports its
isolated artwork as resolution-aware Flutter PNG assets. The generated files
live in `../../assets/memories_collage/`; do not add shadows or rotation to the
source assets because the compositor owns those effects.

## Regenerate

The script needs Node.js, Playwright, Sharp, and a local Chrome/Chromium binary:

```sh
node mobile/apps/photos/scripts/memories_collage/export_assets.mjs
```

When those packages are not installed in the active Node environment, point at
existing package directories explicitly:

```sh
PLAYWRIGHT_MODULE=/path/to/node_modules/playwright \
SHARP_MODULE=/path/to/node_modules/sharp \
CHROME_BINARY=/path/to/Chrome \
node mobile/apps/photos/scripts/memories_collage/export_assets.mjs
```

The exporter reads the embedded JSON manifest, captures every
`data-export-asset` root, writes 1x/2x/3x variants, and verifies dimensions,
alpha/window bounds, the exact asset and layer references, stale output, the
1080x1920 canvas, all runtime shadow definitions, and the six-slot template
contract. Capture is offline: the
two pinned React UMD files needed by Design's runtime are served from `vendor/`,
and every other HTTP(S) request is blocked. Their SHA-384 values are checked
before Chrome starts; their MIT license is in `vendor/REACT_LICENSE`.

Large paper and grain textures use a visually loss-minimized 256-color PNG
palette. The faint sun-streak and vignette use a lossless-quality palette so
their alpha ramps survive export. The 57 PNGs total 9,214,606 bytes (8.79 MiB).
Set
`COLLAGE_TRUECOLOR=1` only to inspect unoptimized true-color output; do not ship
the larger variant set without making an explicit app-size decision.

Source hashes are pinned so an upstream design change cannot silently alter the
shipped artwork. Review intentional changes and update the hashes in the
exporter; `ALLOW_COLLAGE_SOURCE_DRIFT=1` is only for local probes.

Source provenance:

- `Memory Collage.dc.html` is the approved 2a design/export source with trailing
  whitespace normalized, SHA-256
  `b068c928077adece9e859bc86f2e3ea1b7be89d7ff240bd75146ea918c6134af`.
- `support.js` is the matching generated Design document runtime, SHA-256
  `8fe7df74405f3c55f49b7249c74ea1397e65d07dea2b1bd3b4a489bec2e28cbe`.
- `fonts/Lora-SemiBold.ttf` is the unmodified static 600-weight face from Lora
  upstream commit `2d53b449b60e185b39f671b44fded83e0910ad30`, SHA-256
  `a9f5bbcebb6b53d53b6d7d571b2076f3db4931026693397200f69801b6701a81`.
  It is distributed under the SIL Open Font License 1.1 in
  `fonts/Lora-OFL.txt`, SHA-256
  `1d9a970809ac804b582a6ce7f0ebc4e7fefcbfd7ff6299cad35ee656a21be716`.

## Compositor contract

- Layout coordinates in `manifest.json` are authored against 1080x1920.
- For a 1080x1920 export, explicitly load the `3.0x` PNG variants; do not rely
  on `AssetImage` device-pixel-ratio selection.
- Exactly six photos fill the three film-strip windows and three reused
  polaroid windows.
- The polaroid keeps the approved soft inset seam over the edge of its declared
  photo rect (up to 36 px at 3x); the exporter verifies the entire inset core is
  alpha-zero and caps the seam's coverage and opacity so it cannot silently
  grow. Place the photo behind the full manifest rect.
- The five `paper-*` backgrounds are the launch background-swap set.
- `coffee-ring`, `sun-streak`, and `vignette` restore the approved 2a decor.
  Apply the blend mode, opacity, position, and z-order recorded in the manifest.
- Twelve layers carry exact runtime `dropShadow` arrays. Render each shadow
  from the rotated layer silhouette beneath the unrotated, shadow-free PNG.
- Apply `grain-overlay` with overlay blend mode at opacity 0.55.
- The title is rendered by the app; it is intentionally absent from `banner`.
  Use the app-local `Lora` family at weight 600 with the exact canvas-pixel
  typography recorded in `template2a.titleStyle`, centered in both axes over
  the banner. Preserve the supplied, localized memory title exactly. Uppercase
  only a generated month label that is supplied separately; never uppercase
  the full memory title heuristically.
  Lora covers Latin, Cyrillic, and Vietnamese. Let Flutter use its platform
  glyph fallback for other scripts; a consistent cross-platform non-Latin serif
  would require bundling an additional font family.
