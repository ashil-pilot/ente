# Memories collage asset export

This directory preserves the approved Claude Design 2a, 2b, and 2c collage
templates and exports their isolated artwork as resolution-aware Flutter PNG
assets. The generated files live in `../../assets/memories_collage/`; rotation,
layer shadows, titles, rules, and photo placement remain compositor-owned.

Every template is seven-photo-only:

- `scrapbook-maximal` (2a) uses four vertical film windows and three polaroids.
- `scrapbook-calm` (2b) uses one hero print, two polaroids, and four horizontal
  film windows.
- `minimal-editorial` (2c) draws seven direct photo rectangles without frames.

Memories with fewer than seven eligible photos do not get a collage end card.
There is no six-photo layout or fallback in the source contract.

## Regenerate

The script needs Node.js, Playwright, Sharp, and a local Chrome/Chromium binary:

```sh
node mobile/apps/photos/scripts/memories_collage/export_assets.mjs
```

When the output is the real asset directory, the safe default exports only the
eight new 2b/2c assets. The exporter refuses to overwrite the 19 retained 2a
assets or write `manifest.json` there. Select a subset with a comma-separated
list when needed:

```sh
COLLAGE_ASSET_IDS=film-strip-four-horizontal,print-frame-hero \
node mobile/apps/photos/scripts/memories_collage/export_assets.mjs
```

Use a staging directory for a complete 27-asset verification render and a
normalized runtime manifest:

```sh
collage_stage_dir=$(mktemp -d)
COLLAGE_OUTPUT="$collage_stage_dir" COLLAGE_WRITE_MANIFEST=1 \
node mobile/apps/photos/scripts/memories_collage/export_assets.mjs
```

The complete staging render must reproduce the retained 2a inventory digest
`422d287821ede0238ccc03c9692115e7d8c592797f86237970d03edca037cc08`.
Run it twice and compare sorted file SHA-256 inventories before accepting a
source or toolchain change. The 2026-08-07 verification produced identical
82-file staging trees (81 PNG variants plus the manifest), inventory digest
`ea3e979aa86e7dba2810d12b7f625797315d879b6d2da0b94bfe6c4cf9b5fa94`.
The normalized staging manifest was byte-identical to the runtime manifest,
SHA-256 `e579f7e0021f0e7a6d3adfa5e5f9790576f48772e8dc8a228be81864e7151722`.

When packages are not installed in the active Node environment, point at
existing package directories explicitly:

```sh
PLAYWRIGHT_MODULE=/path/to/node_modules/playwright \
SHARP_MODULE=/path/to/node_modules/sharp \
CHROME_BINARY=/path/to/Chrome \
node mobile/apps/photos/scripts/memories_collage/export_assets.mjs
```

Capture is offline. The two pinned React UMD files needed by Design's runtime
are served from `vendor/`, and every other HTTP(S) request is blocked. Their
SHA-384 values are checked before Chrome starts; their MIT license is in
`vendor/REACT_LICENSE`.

The exporter verifies the exact asset order and dimensions, frame window
geometry, seven contiguous slots in every template, asset/layer references,
canvas bounds, alpha and clear-window cores, generated solid colors, stale
PNGs, pinned source/font hashes, and retained byte identity. The full 2a JSON
template is digest-pinned. The 2b/2c digest projection is explicitly defined in
the exporter as their eight source asset records plus both source templates.

Large paper and grain textures use a visually loss-minimized 256-color PNG
palette. The faint sun-streak and vignette use a lossless-quality palette so
their alpha ramps survive export. Set `COLLAGE_TRUECOLOR=1` only to inspect
unoptimized true-color output; do not ship it without an explicit app-size
decision.

The 27 assets produce 81 variants totaling 11,379,482 bytes (10.85 MiB):

- 19 retained 2a assets / 57 variants: 9,049,751 bytes (8.63 MiB)
- four Design-authored 2b raster assets and four deterministic editorial solid
  assets / 24 variants: 2,329,731 bytes (2.22 MiB)

The obsolete three-frame `film-strip.png` is intentionally absent at every
resolution.

## Source provenance

Source hashes are pinned so an upstream design change cannot silently alter
shipped artwork. Review intentional changes and update both invariants and
hashes in the exporter. `ALLOW_COLLAGE_SOURCE_DRIFT=1` is only for a reviewed
local probe; structural and contract checks still run.

- The approved downloaded Claude Design handoff
  `/Users/ashilmacmini/Downloads/Memory Collage.dc.html` has SHA-256
  `47ec9f40479c74a50660b69463264e0488e78e4b941324390e71bf18c1e79118`.
- The canonical integrated `Memory Collage.dc.html` has SHA-256
  `80934d55081fc9983f2187d0721fb21b9d1bb8478614aaec4f4abc42305a2d4c`.
  It retains the approved 2a geometry, including vertical film-window y values
  69/453/837/1221, and gives that export root a complete authored seven-segment
  mask rather than relying on exporter DOM mutation.
- `support.js` is the matching generated Design document runtime, SHA-256
  `8fe7df74405f3c55f49b7249c74ea1397e65d07dea2b1bd3b4a489bec2e28cbe`.
- `fonts/Lora-SemiBold.ttf` has SHA-256
  `a9f5bbcebb6b53d53b6d7d571b2076f3db4931026693397200f69801b6701a81`.
- `fonts/Lora-Italic.ttf` has SHA-256
  `22d8d8854b53807aa664ca34f2031a9ed57a1d0dea296b8b96cdd3aad937a2b3`.
- Both Lora faces are distributed under the SIL Open Font License 1.1 in
  `fonts/Lora-OFL.txt`, SHA-256
  `6d6bc7bbb828514925dabcaf89e4771398d12c60dd1cb2bbb90eea129535d0f4`.

## Compositor contract

- Layout coordinates in `manifest.json` are authored against 1080x1920. For a
  1080x1920 export, explicitly load the `3.0x` PNG variants; do not rely on
  `AssetImage` device-pixel-ratio selection.
- All frame assets are drawn above cover-fitted photos. The vertical film
  windows remain x=57, y=69/453/837/1221, 276x318. The horizontal film windows
  are x=30/264/498/732, y=39, 210x174. The hero print window is x=24, y=24,
  834x546.
- `polaroid-frame` and `print-frame-hero` intentionally retain soft inset seams
  over the edge of their declared photo rectangles. Place photos behind the
  full manifest rect; the exporter verifies that the inset core is alpha-zero.
- Background swapping is template-local. Maximal uses its five paper assets;
  calm uses the notebook/paper set; minimal uses exact generated bone
  `#f4f0e8`, sand `#e8dfcc`, sage `#dde0d6`, and charcoal `#2b2723` PNGs.
- Apply each layer's recorded blend mode, opacity, z-order, rotation, and
  `dropShadow` values at runtime. The PNGs remain shadow- and rotation-free.
- Titles are app-rendered and never baked into assets. Use the manifest's title
  placement and typography: Lora SemiBold for maximal, and Lora Italic for calm
  and minimal. Preserve localized memory titles and the per-template generated
  month-label casing exactly.
