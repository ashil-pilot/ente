# Memories collage asset export

This directory preserves the approved Claude Design 2a, 2b, and 3b/4a/5b
collage templates and exports their isolated artwork as resolution-aware
Flutter PNG assets. The generated files live in
`../../assets/memories_collage/`; rotation, layer and mat shadows, titles, mats,
rules, and photo placement remain compositor-owned.

Empty photo windows use the material colors authored into the source contract:
warm emulsion browns for instant prints and film, and a pale warm aperture for
the minimal mats. These fills remain visible only until each photo fades in.

Every template is seven-photo-only:

- `scrapbook-maximal` (2a/B2) uses four vertical film windows, three polaroids,
  the wider title ribbon approved for long-title fitting, and the approved
  upward foreground rebalance with a subtle rightward polaroid shift.
- `scrapbook-calm` (2b/C1) uses one hero print, three staggered polaroids, and
  three near-square horizontal film windows. Every photo's short side is at
  least 270 canvas pixels.
- `minimal-editorial` (3b/4a/5b/D1) draws a hero and two three-up rows on
  subtly lifted warm mats, keeps every photo's short side at least 270 canvas
  pixels, keeps the title treatment to hairline rules only, defaults to the
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
COLLAGE_ASSET_IDS=banner-wide,film-strip-three-horizontal,print-frame-hero \
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
The two approved C1 frame assets are pinned independently at inventory digest
`d08156d88c492d89bf9a9e4e3eeed74d83b564cce355c7bab8d4b254e51abcde`.
Run it twice and compare sorted file SHA-256 inventories before accepting a
source or toolchain change. The 72 PNG variants combined with the D1 manifest
form a 73-file inventory with digest
`2d1f2bfb6b7482dd44ef21e26721a910264cb67f1d87215a8354380bac983dc5`.
The normalized staging manifest is byte-identical to the runtime manifest,
SHA-256 `4de2abc94e842dff1c4b6350092aaad48b63c21ac807655e74260c563b8bd475`.

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

The 24 assets produce 72 variants totaling 9,595,495 bytes (9.15 MiB):

- 18 retained legacy assets / 54 variants: 8,905,497 bytes (8.49 MiB)
- one Design-authored wide 2a banner / 3 variants: 242,956 bytes (0.23 MiB)
- two Design-authored C1 frame assets and three deterministic editorial solid
  assets / 15 variants: 447,042 bytes (0.43 MiB)

The obsolete `film-strip.png`, retired four-window
`film-strip-four-horizontal.png`, retired `banner.png`, and retired notebook
and `editorial-paper` backgrounds are intentionally absent at every resolution.

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
  `6b27e83c89b66bf95187774bb242ac7b78f56d5c3868f4185eb411c4bbb433ca`.
  It preserves the 2a vertical film-window geometry at y
  69/453/837/1221 while integrating B2's 42px upward foreground rebalance,
  24px rightward polaroid shift, approved 900x150 title ribbon, and exact
  fresh export recipe. It also
  integrates C1's hero, three-polaroid row and three-window film while sharing
  Maximal's non-terracotta papers, and integrates the production 3b/4a
  editorial layout with the approved 5b paper-ground material treatment.
- The source contract digests are 2a/B2
  `ec31b48701b048d324d17b05a589f88287328386f9c60cb2fe5cac086b4319bb`,
  2b/6a/C1 `121d10ca64825d4790c4830f22088cc068569a5f74b1806729d8a6965ae22d62`,
  and 3b/4a/5b/6a/D1
  `fec40d41802d26aa6fd06f012be72bc758caaf9c1cb97695ce26899ef7602a94`.
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
  windows remain x=57, y=69/453/837/1221, 276x318. C1's horizontal film
  windows are x=30/342/654, y=39, 288x270. The hero print window is x=24,
  y=24, 834x546.
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
  charcoal. D1 places the hero mat at `(78,351,924,699)` and its photo at
  `(93,366,894,669)`; the two three-up rows use 300x330 mats at x=78/390/702,
  y=1095/1470, with 270x300 photo rectangles.
- Apply each layer's recorded blend mode, opacity, z-order, rotation, and
  `dropShadow` values at runtime. The PNGs remain shadow- and rotation-free.
- Maximal B2 places `banner-wide` at `(90,138)` at `900x150`, `tapeA` at y=78,
  and the stamp at `(786,72)`, and typesets the title in the explicit
  `(144,156,618,114)` rect at z=20 and -2.5 degrees. The foreground composition
  is 42px higher than 2a, while p1/p2/p3 are also 24px farther right. The
  background, sun streak, vignette, and grain remain pinned at `(0,0)`. This
  asymmetric title rect
  clears both ribbon notches and the stamp; do not replace it with uniform
  padding derived from `safetyMarginPx`.
- Calm C1 keeps the hero at `(102,264,876,594)`, places three 312x361
  polaroids at `(48,900)`, `(384,930)`, and `(720,912)`, places the 972x348
  `film-strip-three-horizontal` at `(54,1434)`, and raises the stamp to
  `(840,1254)`. Its seven slots are hero, three polaroids, then the film's three
  windows; the tapes, fern, title, and material overlays retain their approved
  2b geometry.
- Titles are app-rendered and never baked into assets. Use the manifest's title
  placement and typography: Lora SemiBold for maximal; upright Lora SemiBold
  at 96/60 for calm; and upright Inter Medium at 102/66 for minimal. Preserve
  localized memory titles and the per-template generated month-label casing
  exactly.
