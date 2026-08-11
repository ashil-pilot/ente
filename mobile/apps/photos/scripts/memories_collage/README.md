# Memories collage asset export

This directory preserves the approved Claude Design 2a, 2b, and 3b/4a/5b
collage templates and exports their isolated artwork as resolution-aware
Flutter PNG assets. The generated files live in
`../../assets/memories_collage/`; rotation, layer and mat shadows, titles, mats,
rules, and photo placement remain compositor-owned.

Every template is seven-photo-only:

- `scrapbook-maximal` (2a) uses four vertical film windows, three polaroids,
  and the wider title ribbon approved for long-title fitting.
- `scrapbook-calm` (2b) uses one hero print, two polaroids, and four horizontal
  film windows.
- `minimal-editorial` (3b/4a/5b) draws seven inset photos on subtly lifted warm
  mats, keeps the title treatment to hairline rules only, defaults to the
  cream-fiber paper, and reuses the grain overlay only on flat backgrounds.

`scrapbook-calm` is the authoritative default. The template order remains
Scrapbook, Calm, then Minimal.

Memories with fewer than seven eligible photos do not get a collage end card.
There is no six-photo layout or fallback in the source contract.

## Regenerate

The script needs Node.js, Playwright, Sharp, and a local Chrome/Chromium binary:

```sh
node mobile/apps/photos/scripts/memories_collage/export_assets.mjs
```

When the output is the real asset directory, the safe default exports only the
new wide 2a banner and the five 2b/3b assets. The exporter refuses to overwrite
the 18 retained legacy assets or write `manifest.json` there. Select a subset
with a comma-separated list when needed:

```sh
COLLAGE_ASSET_IDS=banner-wide,film-strip-four-horizontal,print-frame-hero \
node mobile/apps/photos/scripts/memories_collage/export_assets.mjs
```

Use a staging directory for a complete 24-asset verification render and a
normalized runtime manifest:

```sh
collage_stage_dir=$(mktemp -d)
COLLAGE_OUTPUT="$collage_stage_dir" COLLAGE_WRITE_MANIFEST=1 \
node mobile/apps/photos/scripts/memories_collage/export_assets.mjs
```

The complete staging render must reproduce the retained legacy inventory digest
`b71bdd5fba23b3be64a5c3523b4e58d68ec29133f93f6419b978795f392acfc7`.
The approved `banner-wide` variants are pinned independently at inventory
digest `cf69c941c126da1c0333f3ac663951372c9745d14316068f35486a5c2d6af052`.
The two approved 2b frame assets are pinned independently at inventory digest
`9a2c7a78411cb8fd469c85fc688fcac82d31a1d245eb6313ed30e93cec04f49d`.
Run it twice and compare sorted file SHA-256 inventories before accepting a
source or toolchain change. The 72 PNG variants combined with the 5b manifest
form a 73-file inventory with digest
`75d2b66343b0488f1df3ae470adf7288b93dd7fd58dc4bb4d1258cea6880a096`.
The normalized staging manifest is byte-identical to the runtime manifest,
SHA-256 `c473198bd51c56108be696566affb94d03ae16aec2677a8f904fe8c4507dbb8e`.

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
geometry, seven contiguous slots in every template, matted-photo insets and
shadows, conditional-layer background subsets, per-background rule colors,
asset/layer references, canvas bounds, alpha and clear-window cores, generated
solid colors, stale PNGs, pinned source/font hashes, and retained byte identity.
The 2a template, 2b raster/template projection, and 3b/4a/5b color/template
projection are digest-pinned separately so drift in one direction cannot hide
drift in another.

Large paper and grain textures use a visually loss-minimized 256-color PNG
palette. The faint sun-streak and vignette use a lossless-quality palette so
their alpha ramps survive export. Set `COLLAGE_TRUECOLOR=1` only to inspect
unoptimized true-color output; do not ship it without an explicit app-size
decision.

The 24 assets produce 72 variants totaling 9,579,064 bytes (9.14 MiB):

- 18 retained legacy assets / 54 variants: 8,905,497 bytes (8.49 MiB)
- one Design-authored wide 2a banner / 3 variants: 242,956 bytes (0.23 MiB)
- two Design-authored 2b frame assets and three deterministic editorial solid
  assets / 15 variants: 430,611 bytes (0.41 MiB)

The obsolete three-frame `film-strip.png`, retired `banner.png`, and retired
notebook and `editorial-paper` backgrounds are intentionally absent at every
resolution.

## Source provenance

Source hashes are pinned so an upstream design change cannot silently alter
shipped artwork. Review intentional changes and update both invariants and
hashes in the exporter. `ALLOW_COLLAGE_SOURCE_DRIFT=1` is only for a reviewed
local probe; structural and contract checks still run.

- The approved downloaded Claude Design handoff
  `/Users/ashilmacmini/Downloads/Memory Collage.dc.html` has SHA-256
  `47ec9f40479c74a50660b69463264e0488e78e4b941324390e71bf18c1e79118`.
- The approved downloaded Claude Design 3b handoff
  `/Users/ashilmacmini/Downloads/Memory Collage 3b.dc.html` has SHA-256
  `cdd9c2855bd8fe035d84a1eb0217cdbc6d9ddb162e46cc46227772c3636536b6`.
- The canonical integrated `Memory Collage.dc.html` has SHA-256
  `7712f0e13d1759ef6e70f5c23f773b49c57c1fb0958639c67c00fe1a0415d806`.
  It preserves every 2a photo coordinate, including vertical film-window y
  values 69/453/837/1221, while integrating the approved 900x150 title ribbon,
  its exact fresh export recipe, and the repositioned tape/stamp. It also
  preserves the approved 2b layout while sharing Maximal's non-terracotta
  papers, and integrates the production 3b/4a editorial layout with the
  approved 5b paper-ground material treatment.
- The source contract digests are 2a
  `9a9246ff8988d8741f86c0ea2f71df22dba594b762d3939abce2a20cc4cc94da`,
  2b/6a `c5ef278d78d7ef74904028c775aa15b37ed0217e3f512a0b1fc893fdd4ac8ac2`,
  and 3b/4a/5b/6a
  `ebdadd0b3afa05ba8491a57477df6b75754b848044a4164f67412f5b464c43d6`.
- `support.js` is the matching generated Design document runtime, SHA-256
  `8fe7df74405f3c55f49b7249c74ea1397e65d07dea2b1bd3b4a489bec2e28cbe`.
- `fonts/Lora-SemiBold.ttf` has SHA-256
  `a9f5bbcebb6b53d53b6d7d571b2076f3db4931026693397200f69801b6701a81`.
- `fonts/Lora-Italic.ttf` has SHA-256
  `22d8d8854b53807aa664ca34f2031a9ed57a1d0dea296b8b96cdd3aad937a2b3`.
- `fonts/Inter-Medium.ttf` has SHA-256
  `6df88fcb83ac96582350f801355c6eff55f15710093e9627fb431caa40521151`.
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
  calm uses Maximal's washi, cream-fiber, blush-stripe, and sage-stripe papers
  with cream fiber as its default; minimal defaults to the retained cream-fiber
  paper and also offers exact generated sand `#e8dfcc`, sage `#dde0d6`, and
  charcoal `#2b2723` PNGs.
- Minimal renders each photo inside its declared `mat` rectangle with a 15px
  inset to the nested photo `rect`, a 3px `rgba(90,75,55,0.20)` inside border,
  and the recorded `0/3/9 rgba(90,70,45,0.12)` mat shadow. Render mats/photos
  at z=4, both hairlines at z=10, and the title at z=20. Render the reused
  `grain-overlay` at z=38 with overlay blend mode and opacity 0.12 only for
  editorial sand, sage, and charcoal; omit it on cream fiber. The hairlines use
  `#cfc5ae` on cream fiber, `#d8cfbc` on sand and sage, and the dark fallback on
  charcoal.
- Apply each layer's recorded blend mode, opacity, z-order, rotation, and
  `dropShadow` values at runtime. The PNGs remain shadow- and rotation-free.
- Maximal places `banner-wide` at `(90,180)` at `900x150`, moves `tapeA` to
  y=120 and the stamp to `(786,114)`, and typesets the title in the explicit
  `(144,198,618,114)` rect at z=20 and -2.5 degrees. This asymmetric title rect
  clears both ribbon notches and the stamp; do not replace it with uniform
  padding derived from `safetyMarginPx`.
- Titles are app-rendered and never baked into assets. Use the manifest's title
  placement and typography: Lora SemiBold for maximal; upright Lora SemiBold
  at 96/60 for calm; and upright Inter Medium at 102/66 for minimal. Preserve
  localized memory titles and the per-template generated month-label casing
  exactly.
