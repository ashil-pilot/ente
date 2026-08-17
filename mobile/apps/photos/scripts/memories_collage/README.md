# Frozen memory-collage plates

The seven memory-collage layouts are frozen. Flutter no longer rebuilds them
from individual frame, tape, mat, shadow, and decoration records. Each layout
is a full-canvas 1080x1920 transparent PNG plate:

- `layout-scrapbook-maximal`
- `layout-calm-classic`
- `layout-calm-film-trio` (the product default)
- `layout-calm-accent-print`
- `layout-minimal-classic`
- `layout-minimal-rows`
- `layout-minimal-grid`

The runtime draws the selected background, natural empty-photo backing, seven
cover-cropped photos, the selected plate, dynamic title, and a narrowly scoped
finish preset. Photos bleed two canvas pixels under their openings to avoid
anti-alias seams.

The approved empty materials are:

- Polaroid and hero print: `#E7E1D4`
- Vertical film: `#7B4A32`
- Horizontal film: `#7A5B41`
- Minimal apertures: `#E7E1D4`

The plate openings themselves remain transparent. The backing is drawn below
each photo, so users see the natural empty material while a photo fades in and
never see the selected background through an empty frame.

## Runtime assets

Flutter packages `manifest.json` and the `3.0x` directory. That directory has
exactly 17 PNGs:

- Seven independently selectable 1080x1920 backgrounds
- Seven 1080x1920 transparent layout plates
- `sun-streak`, `vignette`, and `grain-overlay`

The three finish textures remain live because their soft-light, multiply, and
overlay results depend on the selected background and user photos. Their
fixed behavior is represented by `scrapbook`, `calm`, and `minimal` finish
presets rather than general-purpose manifest layers.

The 17 runtime PNGs total 7,913,419 bytes (7.55 MiB):

- Backgrounds: 3,592,366 bytes
- Finish textures: 774,356 bytes
- Layout plates: 3,546,697 bytes

The previous 14 decorative/runtime ingredient IDs are no longer in the
Flutter asset tree. Their approved 3x copies live in `source_assets/` solely
for deterministic plate rebuilding and are not bundled by Flutter. Obsolete
base and 2x ingredient copies were removed.

## Verify checked-in output

Run from `mobile/apps/photos`:

```sh
node scripts/memories_collage/export_assets.mjs
```

The verifier checks:

- The pinned Claude Design source and support hashes
- The pinned authoring-ingredient inventory
- The exact v3 runtime-manifest projection
- The seven backgrounds and seven contiguous slots per template
- Plate IDs, title contracts, finish presets, and backing colors
- The exact 17-file runtime PNG inventory
- 1080x1920 dimensions, alpha contracts, and plate-window transparency
- Encoded and decoded-RGBA hashes for every plate
- Absence of obsolete ingredients from the base and 2x runtime asset folders

Point `SHARP_MODULE` at an installed Sharp package if it is not available in
the active Node environment.

## Rebuild into staging

Never write generated files directly into the Flutter asset directory. Rebuild
all seven plates and the normalized manifest into a temporary directory:

```sh
collage_stage_dir=$(mktemp -d)
COLLAGE_REBUILD_PLATES=1 COLLAGE_OUTPUT="$collage_stage_dir" \
node scripts/memories_collage/export_assets.mjs
```

This is the clean-checkout rebuild path: it reads the pinned 3x ingredients
from `source_assets/` and does not depend on any removed Flutter runtime PNG.

The rebuild runs `export_plates_test.dart` with Flutter/Skia at a 3x pixel
ratio. It walks fixed layers in z/source order. Before adding a photo-bearing
layer, it erases accumulated lower-z artwork inside that layer's transformed
photo windows. This preserves the Scrapbook p2/p3 overlap and Calm Accent
hero/accent overlap while retaining one plate per template.

Each PNG is then re-encoded losslessly. The exporter rejects it unless decoded
RGBA is byte-identical before and after optimization. The staged outputs are
also checked against the approved hashes in `plate_provenance.json`.

When Node cannot locate the local dependencies, provide their package paths:

```sh
PLAYWRIGHT_MODULE=/path/to/playwright \
SHARP_MODULE=/path/to/sharp \
CHROME_BINARY=/path/to/Chrome \
COLLAGE_REBUILD_PLATES=1 COLLAGE_OUTPUT="$collage_stage_dir" \
node scripts/memories_collage/export_assets.mjs
```

`COLLAGE_REFRESH_INGREDIENTS=1` asks the HTML source to rasterize fresh
authoring ingredients in a temporary directory before rebuilding plates. Use
it only for an intentional, reviewed source/toolchain change: Chrome raster
output can drift between versions, so refreshed ingredients and any resulting
plate hashes require visual review and an explicit provenance update.

## Source and provenance

`Memory Collage.dc.html` is retained as the original Claude Design authoring
contract and asset recipe. Its visible artifact has three screens; it is not
described as a complete canonical visual presentation of all seven layouts.
Its embedded v2 data remains authoring-only and is projected into the small v3
runtime manifest by the exporter.

The final seven-layout visual review lives in the Claude Design project page
`Plate Review.dc.html`. `plate_provenance.json` records the review reference,
source hashes, Flutter/engine versions, pinned authoring inputs, natural
backing colors, and encoded/decoded hashes for every approved plate.

`support.js` and the vendored React files preserve the offline Claude Design
runtime used only when refreshing authoring ingredients. The Lora and Inter
font files and their licenses remain under the app's `fonts/` directory; title
text stays dynamic and is not baked into the plates.
