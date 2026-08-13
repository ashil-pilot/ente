# Memories collage asset export

This directory preserves the approved Claude Design Scrapbook, C0/C1/C2 Calm,
and D0/D1/D2 Minimal collage templates and exports their isolated artwork as
resolution-aware Flutter PNG assets. The generated files live in
`../../assets/memories_collage/`; rotation, layer and mat shadows, titles, mats,
rules, and photo placement remain compositor-owned.

Empty photo windows use the material colors authored into the source contract:
warm emulsion browns for instant prints and film, and a pale warm aperture for
the minimal mats. These fills remain visible only until each photo fades in.

Every template is seven-photo-only:

- `scrapbook-maximal` (2a/B2) uses four vertical film windows, three polaroids,
  the wider title ribbon approved for long-title fitting, and the approved
  upward foreground rebalance with a subtle rightward polaroid shift.
- `calm-classic` (C0) uses one hero print, two large polaroids, and four compact
  horizontal film windows.
- `calm-film-trio` (C1) uses one hero print, three staggered polaroids, and
  three near-square horizontal film windows.
- `calm-accent-print` (C2) uses the C0 hero and large-polaroid composition,
  three near-square film windows, and a taped accent print in the upper-right.
- `minimal-classic` (D0) draws one hero, two medium photos, and four compact
  photos on subtly lifted warm mats.
- `minimal-rows` (D1) draws one hero and two three-up rows on those mats.
- `minimal-grid` (D2) draws two wide photos, a three-up center row, and two
  wide photos on those mats.

All Minimal styles keep the title treatment to full-width hairline rules,
default to the cream-fiber paper, and reuse the grain overlay only on flat
backgrounds. Every style offers the same seven backgrounds, and the selected
background remains unchanged while cycling styles. `calm-film-trio` remains
the authoritative default so the app's existing default visual does not
change. Template order is Scrapbook, C0, C1, C2, D0, D1, then D2.

Memories with fewer than seven eligible photos do not get a collage end card.
There is no six-photo layout or fallback in the source contract.

## Regenerate

The script needs Node.js, Playwright, Sharp, and a local Chrome/Chromium binary:

```sh
node mobile/apps/photos/scripts/memories_collage/export_assets.mjs
```

When the output is the real asset directory, the safe default exports only the
new wide 2a banner and the five Calm/Minimal assets. The exporter refuses to overwrite
the 18 retained legacy assets or write `manifest.json` there. Select a subset
with a comma-separated list when needed:

```sh
COLLAGE_ASSET_IDS=banner-wide,film-strip-four-horizontal,film-strip-three-horizontal,print-frame-hero \
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
The three approved Calm frame assets are pinned independently at inventory
digest `34f5c6196244bad68a7bc147ab41e0b83655ad0b66c1714958c3b902f9959170`.
Run it twice and compare sorted file SHA-256 inventories before accepting a
source or toolchain change. The 72 PNG variants combined with the seven-style
manifest form a 73-file inventory.
The normalized staging manifest is byte-identical to the runtime manifest,
SHA-256 `ab64d0ee418b2082070c60ab65ecde9335d323def8b1d3893c530b271a7bc3b7`.

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
The 2a template, complete C-family raster/template projection, and complete
D-family color/template projection are digest-pinned separately so drift in
one direction cannot hide drift in another.

Large paper and grain textures use a visually loss-minimized 256-color PNG
palette. The faint sun-streak and vignette use a lossless-quality palette so
their alpha ramps survive export. Set `COLLAGE_TRUECOLOR=1` only to inspect
unoptimized true-color output; do not ship it without an explicit app-size
decision.

The 24 assets produce 72 variants totaling 9,815,736 bytes (9.36 MiB):

- 18 retained legacy assets / 54 variants: 8,905,497 bytes (8.49 MiB)
- one Design-authored wide 2a banner / 3 variants: 242,956 bytes (0.23 MiB)
- three Design-authored Calm frame assets / 9 variants: 629,503 bytes
  (0.60 MiB)
- two deterministic editorial solid assets / 6 variants: 37,780 bytes
  (0.04 MiB)

The obsolete `film-strip.png`, retired `banner.png`, and retired notebook and
`editorial-paper` backgrounds are intentionally absent at every resolution.

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
  `54a02ed673afbc920f37bde50fb9d391c0cdeab144d44c1283c93710b4b1623f`.
  It preserves the 2a vertical film-window geometry at y
  69/453/837/1221 while integrating B2's 42px upward foreground rebalance,
  24px rightward polaroid shift, approved 900x150 title ribbon, and exact
  fresh export recipe. It also
  integrates the approved C0/C1/C2 Calm and D0/D1/D2 Minimal contracts while
  sharing all seven backgrounds across every style and preserving the Minimal
  paper-ground material treatment.
- The source contract digests are 2a/B2
  `679ad2a2f9d4f46c2b0ac245e193f680f18722fe8db7fb1bcbe542c8b30481dc`,
  C0/C1/C2 `12627ad08a7328c3978fe9aefd744224e4f2ed94980841cde7ba7dcf08aa0cfc`,
  and D0/D1/D2
  `7675498d53189ddbb64083cf8008071744f0d0c4c69b3a3d02df9abfdd6a6266`.
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
  windows remain x=57, y=69/453/837/1221, 276x318. C0's horizontal film
  windows are x=30/264/498/732, y=39, 210x174. C1/C2's horizontal film
  windows are x=30/342/654, y=39, 288x270. The hero print window is x=24,
  y=24, 834x546.
- `polaroid-frame` and `print-frame-hero` intentionally retain soft inset seams
  over the edge of their declared photo rectangles. Place photos behind the
  full manifest rect; the exporter verifies that the inset core is alpha-zero.
- Every template exposes the same ordered palette: washi, cream-fiber,
  blush-stripe, sage-stripe, terracotta-mottle, generated sand `#e8dfcc`, and
  generated sage `#dde0d6`. Scrapbook defaults to washi; Calm and Minimal
  default to cream-fiber. The app preserves the selected background by asset ID
  when the style changes.
- Minimal renders each photo inside its declared `mat` rectangle with a 15px
  inset to the nested photo `rect`, a 3px `rgba(90,75,55,0.20)` inside border,
  and the recorded `0/3/9 rgba(90,70,45,0.12)` mat shadow. Render mats/photos
  at z=4, both hairlines at z=10, and the title at z=20. Render the reused
  `grain-overlay` at z=38 with overlay blend mode and opacity 0.12 only for
  editorial sand and sage; omit it on cream fiber. The hairlines use
  `#cfc5ae` on cream fiber and `#d8cfbc` on sand and sage. D1 places the hero
  mat at `(78,351,924,699)` and its photo at
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
- C0 keeps the hero at `(102,264,876,594)`, uses 462x534 polaroids at
  `(78,900)` and `(546,918)`, places `film-strip-four-horizontal` at
  `(54,1566,972,252)`, and declares an approved 174px photo short-side floor.
- C2 keeps C0's hero and two large polaroids, places the three-window film at
  `(54,1506,972,348)`, and adds the taped 312x361 accent print at `(726,204)`.
- Minimal D0 declares an approved 183px photo short-side floor for its compact
  four-up row. All other templates retain the standard 270px minimum.
- Minimal D2 uses 450x474 mats at x=78/552 and y=357/1299, with the three
  300x330 center mats at x=78/390/702 and y=900.
- Titles are app-rendered and never baked into assets. Use the manifest's title
  placement and typography: Lora SemiBold for maximal; upright Lora SemiBold
  at 96/60 for calm; and upright Inter Medium at 102/66 for minimal. Preserve
  localized memory titles and the per-template generated month-label casing
  exactly.
