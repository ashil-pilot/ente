#!/usr/bin/env node

import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, realpath, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const appDirectory = resolve(scriptDirectory, "..", "..");
const realOutputDirectory = join(appDirectory, "assets", "memories_collage");
const sourcePath = resolve(
  process.env.COLLAGE_SOURCE ?? join(scriptDirectory, "Memory Collage.dc.html"),
);
const supportPath = join(dirname(sourcePath), "support.js");
const vendorDirectory = join(scriptDirectory, "vendor");
const outputDirectory = resolve(
  process.env.COLLAGE_OUTPUT ?? realOutputDirectory,
);
const isRealOutput = outputDirectory === realOutputDirectory;

const expectedSourceHashes = {
  "Memory Collage.dc.html":
    "54a02ed673afbc920f37bde50fb9d391c0cdeab144d44c1283c93710b4b1623f",
  "support.js":
    "8fe7df74405f3c55f49b7249c74ea1397e65d07dea2b1bd3b4a489bec2e28cbe",
};
const fontSpecs = [
  {
    file: "Lora-SemiBold.ttf",
    hash: "a9f5bbcebb6b53d53b6d7d571b2076f3db4931026693397200f69801b6701a81",
  },
  {
    file: "Lora-Italic.ttf",
    hash: "22d8d8854b53807aa664ca34f2031a9ed57a1d0dea296b8b96cdd3aad937a2b3",
  },
  {
    file: "Inter-Medium.ttf",
    hash: "6df88fcb83ac96582350f801355c6eff55f15710093e9627fb431caa40521151",
  },
  {
    file: "Lora-OFL.txt",
    hash: "6d6bc7bbb828514925dabcaf89e4771398d12c60dd1cb2bbb90eea129535d0f4",
  },
];

const retainedAssetIds = [
  "paper-washi",
  "paper-cream-fiber",
  "paper-blush-stripe",
  "paper-sage-stripe",
  "paper-terracotta-mottle",
  "paper-torn",
  "polaroid-frame",
  "film-strip-four",
  "tape-mustard",
  "tape-blush",
  "tape-sage",
  "stamp-postmark",
  "star",
  "fern",
  "coffee-ring",
  "sun-streak",
  "vignette",
  "grain-overlay",
];
const maximalRasterAssetIds = ["banner-wide"];
const designRasterAssetIds = [
  "film-strip-four-horizontal",
  "film-strip-three-horizontal",
  "print-frame-hero",
];
const generatedColors = new Map([
  ["editorial-sand", "#e8dfcc"],
  ["editorial-sage", "#dde0d6"],
]);
const generatedColorAssetIds = [...generatedColors.keys()];
const newAssetIds = [
  ...maximalRasterAssetIds,
  ...designRasterAssetIds,
  ...generatedColorAssetIds,
];
const requiredAssetIds = [
  ...retainedAssetIds.slice(0, 8),
  ...maximalRasterAssetIds,
  ...retainedAssetIds.slice(8),
  ...designRasterAssetIds,
  ...generatedColorAssetIds,
];
const retainedAssetIdSet = new Set(retainedAssetIds);
const generatedColorAssetIdSet = new Set(generatedColorAssetIds);
const expectedRetainedInventoryDigest =
  "b71bdd5fba23b3be64a5c3523b4e58d68ec29133f93f6419b978795f392acfc7";
const expectedMaximalInventoryDigest =
  "cf69c941c126da1c0333f3ac663951372c9745d14316068f35486a5c2d6af052";
const expectedCalmInventoryDigest =
  "34f5c6196244bad68a7bc147ab41e0b83655ad0b66c1714958c3b902f9959170";

const dimensions = new Map([
  ["paper-washi", [1080, 1920]],
  ["paper-cream-fiber", [1080, 1920]],
  ["paper-blush-stripe", [1080, 1920]],
  ["paper-sage-stripe", [1080, 1920]],
  ["paper-terracotta-mottle", [1080, 1920]],
  ["paper-torn", [1098, 1734]],
  ["polaroid-frame", [462, 534]],
  ["film-strip-four", [390, 1800]],
  ["banner-wide", [900, 150]],
  ["tape-mustard", [336, 72]],
  ["tape-blush", [228, 66]],
  ["tape-sage", [210, 63]],
  ["stamp-postmark", [240, 270]],
  ["star", [282, 282]],
  ["fern", [228, 408]],
  ["coffee-ring", [192, 192]],
  ["sun-streak", [1080, 1920]],
  ["vignette", [1080, 1920]],
  ["grain-overlay", [1080, 1920]],
  ["film-strip-four-horizontal", [972, 252]],
  ["film-strip-three-horizontal", [972, 348]],
  ["print-frame-hero", [876, 594]],
  ["editorial-sand", [1080, 1920]],
  ["editorial-sage", [1080, 1920]],
]);
const expectedPhotoWindows = new Map([
  ["polaroid-frame", [{ x: 27, y: 27, width: 414, height: 420 }]],
  ["film-strip-four", [
    { x: 57, y: 69, width: 276, height: 318 },
    { x: 57, y: 453, width: 276, height: 318 },
    { x: 57, y: 837, width: 276, height: 318 },
    { x: 57, y: 1221, width: 276, height: 318 },
  ]],
  ["film-strip-four-horizontal", [
    { x: 30, y: 39, width: 210, height: 174 },
    { x: 264, y: 39, width: 210, height: 174 },
    { x: 498, y: 39, width: 210, height: 174 },
    { x: 732, y: 39, width: 210, height: 174 },
  ]],
  ["film-strip-three-horizontal", [
    { x: 30, y: 39, width: 288, height: 270 },
    { x: 342, y: 39, width: 288, height: 270 },
    { x: 654, y: 39, width: 288, height: 270 },
  ]],
  ["print-frame-hero", [
    { x: 24, y: 24, width: 834, height: 546 },
  ]],
]);
const expectedTemplateIds = [
  "scrapbook-maximal",
  "calm-classic",
  "calm-film-trio",
  "calm-accent-print",
  "minimal-classic",
  "minimal-rows",
  "minimal-grid",
];
// 2a/B2 projection: JSON.stringify({ assets: its new raster asset record,
// template: scrapbook-maximal }).
const expectedMaximalDesignContractDigest =
  "679ad2a2f9d4f46c2b0ac245e193f680f18722fe8db7fb1bcbe542c8b30481dc";
// Each later direction is pinned separately so a change in one cannot be
// hidden by simultaneously changing the other projection.
// C0/C1/C2 projection: JSON.stringify({ assets: the Calm raster asset
// records, templates: the three approved Calm variants }).
const expectedCalmDesignContractDigest =
  "12627ad08a7328c3978fe9aefd744224e4f2ed94980841cde7ba7dcf08aa0cfc";
// D0/D1/D2 projection: JSON.stringify({ assets: the two retained generated
// color records, templates: the three approved Minimal variants }).
const expectedMinimalDesignContractDigest =
  "7675498d53189ddbb64083cf8008071744f0d0c4c69b3a3d02df9abfdd6a6266";

const paletteTextureIds = new Set([
  "paper-washi",
  "paper-cream-fiber",
  "paper-blush-stripe",
  "paper-sage-stripe",
  "paper-terracotta-mottle",
  "paper-torn",
  "grain-overlay",
]);
const losslessOverlayPaletteIds = new Set(["sun-streak", "vignette"]);
const translucentOverlayIds = new Set([
  "coffee-ring",
  "sun-streak",
  "vignette",
  "grain-overlay",
]);
const offlineRuntimeScripts = [
  {
    url: "https://unpkg.com/react@18.3.1/umd/react.production.min.js",
    file: "react-18.3.1.production.min.js",
    sha384:
      "DGyLxAyjq0f9SPpVevD6IgztCFlnMF6oW/XQGmfe+IsZ8TqEiDrcHkMLKI6fiB/Z",
  },
  {
    url: "https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js",
    file: "react-dom-18.3.1.production.min.js",
    sha384:
      "gTGxhz21lVGYNMcdJOyq01Edg0jhn/c22nsx0kyqP0TxaV5WVdsSH1fSDUf5YJj1",
  },
];

function fail(message) {
  throw new Error(message);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function validateShadow(shadow, path) {
  if (
    !shadow ||
    shadow.kind !== "dropShadow" ||
    !Number.isFinite(shadow.dx) ||
    !Number.isFinite(shadow.dy) ||
    !Number.isFinite(shadow.blur) ||
    shadow.blur < 0 ||
    typeof shadow.color !== "string" ||
    shadow.color.length === 0
  ) {
    fail(`${path} is not a valid drop shadow.`);
  }
}

async function verifySource(path, expectedHash, { allowDrift = false } = {}) {
  const bytes = await readFile(path);
  const actualHash = sha256(bytes);
  if (
    actualHash !== expectedHash &&
    (!allowDrift || process.env.ALLOW_COLLAGE_SOURCE_DRIFT !== "1")
  ) {
    fail(
      `Unexpected source hash for ${path}: ${actualHash}. ` +
        "Review the source and update the pinned hash." +
        (allowDrift
          ? " Set ALLOW_COLLAGE_SOURCE_DRIFT=1 for an intentional local experiment."
          : ""),
    );
  }
  return { bytes, actualHash };
}

async function loadOfflineRuntime() {
  const scripts = new Map();
  for (const spec of offlineRuntimeScripts) {
    const body = await readFile(join(vendorDirectory, spec.file));
    const actual = createHash("sha384").update(body).digest("base64");
    if (actual !== spec.sha384) {
      fail(`Vendored runtime hash mismatch for ${spec.file}: ${actual}.`);
    }
    scripts.set(spec.url, { ...spec, body });
  }
  return scripts;
}

function loadDependency(packageName, overridePath) {
  const nodeRuntimeModules = resolve(
    dirname(process.execPath),
    "..",
    "node_modules",
    packageName,
  );
  const codexRuntimeModules = join(
    homedir(),
    ".cache",
    "codex-runtimes",
    "codex-primary-runtime",
    "dependencies",
    "node",
    "node_modules",
    packageName,
  );
  const candidates = [overridePath, packageName, nodeRuntimeModules, codexRuntimeModules]
    .filter(Boolean);
  let lastError;
  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch (error) {
      lastError = error;
    }
  }
  fail(
    `Could not load ${packageName}. Install it locally or set ` +
      `${packageName.toUpperCase()}_MODULE to its package directory. ` +
      `Last error: ${lastError?.message}`,
  );
}

function findChrome() {
  const candidates = [
    process.env.CHROME_BINARY,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
  ].filter(Boolean);
  const chrome = candidates.find(existsSync);
  if (!chrome) {
    fail("Chrome or Chromium was not found. Set CHROME_BINARY to its executable.");
  }
  return chrome;
}

function readManifest(source) {
  const match = source.match(
    /<script id="asset-manifest" type="application\/json">([\s\S]*?)<\/script>/,
  );
  if (!match) fail("The source does not contain #asset-manifest.");
  const manifest = JSON.parse(match[1]);

  if (
    manifest.version !== 2 ||
    manifest.canvas?.width !== 1080 ||
    manifest.canvas?.height !== 1920 ||
    manifest.photoCount !== 7 ||
    manifest.defaultTemplateId !== "calm-film-trio"
  ) {
    fail("The source must preserve the v2 1080x1920 seven-photo contract.");
  }
  if (!/seven-photo-only/i.test(manifest.photoPolicy ?? "")) {
    fail("The source photo policy must explicitly remain seven-photo-only.");
  }
  if (!Array.isArray(manifest.assets)) fail("The source has no asset array.");
  const assetIds = manifest.assets.map((asset) => asset.id);
  if (JSON.stringify(assetIds) !== JSON.stringify(requiredAssetIds)) {
    fail(`Asset IDs/order changed; expected ${requiredAssetIds.join(", ")}.`);
  }

  const assetsById = new Map(manifest.assets.map((asset) => [asset.id, asset]));
  for (const asset of manifest.assets) {
    const expected = dimensions.get(asset.id);
    if (
      asset.width !== expected[0] ||
      asset.height !== expected[1] ||
      asset.width % 3 !== 0 ||
      asset.height % 3 !== 0
    ) {
      fail(
        `${asset.id} must be ${expected[0]}x${expected[1]} and divisible by three.`,
      );
    }
    for (const window of asset.photoWindows ?? []) {
      if (
        !Number.isInteger(window.x) ||
        !Number.isInteger(window.y) ||
        !Number.isInteger(window.width) ||
        !Number.isInteger(window.height) ||
        window.x < 0 ||
        window.y < 0 ||
        window.width <= 0 ||
        window.height <= 0 ||
        window.x + window.width > asset.width ||
        window.y + window.height > asset.height
      ) {
        fail(`${asset.id} contains an invalid photo window.`);
      }
    }
    if ((asset.photoWindows?.length ?? 0) > 0 && !asset.emptyWindowColor) {
      fail(`${asset.id} must declare an emptyWindowColor.`);
    }
  }
  for (const [assetId, windows] of expectedPhotoWindows) {
    if (JSON.stringify(assetsById.get(assetId).photoWindows) !== JSON.stringify(windows)) {
      fail(`${assetId} photo windows differ from the approved geometry.`);
    }
  }
  for (const [assetId, color] of generatedColors) {
    const asset = assetsById.get(assetId);
    if (
      asset.source !== "generatedColor" ||
      asset.color?.toLowerCase() !== color ||
      asset.opaque !== true ||
      asset.role !== "background"
    ) {
      fail(`${assetId} must remain the generated opaque ${color} background.`);
    }
  }

  if (
    !manifest.templates ||
    JSON.stringify(Object.keys(manifest.templates)) !== JSON.stringify(expectedTemplateIds)
  ) {
    fail(`Templates must be ordered ${expectedTemplateIds.join(", ")}.`);
  }
  for (const templateId of expectedTemplateIds) {
    const template = manifest.templates[templateId];
    if (!Array.isArray(template.backgrounds) || template.backgrounds.length === 0) {
      fail(`${templateId} must declare asset-backed backgrounds.`);
    }
    const minimumPhotoShortSide = template.minimumPhotoShortSide ?? 270;
    if (!Number.isFinite(minimumPhotoShortSide) || minimumPhotoShortSide <= 0) {
      fail(`${templateId} has an invalid minimumPhotoShortSide.`);
    }
    const backgroundIds = template.backgrounds.map((background) => background.id);
    const backgroundIdSet = new Set(backgroundIds);
    if (!backgroundIds.includes(template.defaultBackgroundId)) {
      fail(`${templateId} default background is not in its background palette.`);
    }
    for (const background of template.backgrounds) {
      if (background.kind !== "asset" || !assetsById.has(background.id)) {
        fail(`${templateId} has an invalid background ${background.id}.`);
      }
    }

    if (!Array.isArray(template.layers)) fail(`${templateId} must declare layers.`);
    const layerIds = template.layers.map((layer) => layer.layerId);
    if (new Set(layerIds).size !== layerIds.length) {
      fail(`${templateId} contains duplicate layer IDs.`);
    }
    const layersById = new Map(template.layers.map((layer) => [layer.layerId, layer]));
    for (const layer of template.layers) {
      if (!assetsById.has(layer.asset)) {
        fail(`${templateId}.${layer.layerId} references unknown asset ${layer.asset}.`);
      }
      for (const [index, shadow] of (layer.shadows ?? []).entries()) {
        validateShadow(shadow, `${templateId}.${layer.layerId}.shadows[${index}]`);
      }
      if (layer.backgroundAssetIds !== undefined) {
        if (
          !Array.isArray(layer.backgroundAssetIds) ||
          layer.backgroundAssetIds.length === 0 ||
          new Set(layer.backgroundAssetIds).size !== layer.backgroundAssetIds.length ||
          layer.backgroundAssetIds.some((id) => !backgroundIdSet.has(id))
        ) {
          fail(
            `${templateId}.${layer.layerId}.backgroundAssetIds must be a ` +
              "non-empty unique subset of the template backgrounds.",
          );
        }
      }
    }
    for (const [index, rule] of (template.rules ?? []).entries()) {
      if (rule.colorsByBackground !== undefined) {
        if (
          rule.colorsByBackground === null ||
          typeof rule.colorsByBackground !== "object" ||
          Array.isArray(rule.colorsByBackground)
        ) {
          fail(
            `${templateId}.rules[${index}].colorsByBackground must be an ` +
              "object.",
          );
        }
        const entries = Object.entries(rule.colorsByBackground);
        if (
          entries.length === 0 ||
          entries.some(
            ([id, color]) =>
              !backgroundIdSet.has(id) ||
              typeof color !== "string" ||
              color.length === 0,
          )
        ) {
          fail(
            `${templateId}.rules[${index}].colorsByBackground must map ` +
              "template background IDs to non-empty colors.",
          );
        }
      }
    }
    for (const [index, shadow] of (template.matStyle?.shadows ?? []).entries()) {
      validateShadow(shadow, `${templateId}.matStyle.shadows[${index}]`);
    }

    if (
      !Array.isArray(template.photoSlots) ||
      template.photoSlots.length !== 7 ||
      template.photoSlots.some((slot, index) => slot.slot !== index)
    ) {
      fail(`${templateId} must contain seven contiguous photo slots.`);
    }
    const targets = new Set();
    for (const slot of template.photoSlots) {
      if (slot.kind === "canvasRect") {
        const rect = slot.rect;
        if (
          !rect ||
          rect.x < 0 ||
          rect.y < 0 ||
          rect.width <= 0 ||
          rect.height <= 0 ||
          rect.x + rect.width > manifest.canvas.width ||
          rect.y + rect.height > manifest.canvas.height
        ) {
          fail(`${templateId} slot ${slot.slot} has an invalid canvas rect.`);
        }
        if (
          rect.width < minimumPhotoShortSide ||
          rect.height < minimumPhotoShortSide
        ) {
          fail(`${templateId} slot ${slot.slot} is below its photo size floor.`);
        }
        continue;
      }
      if (slot.kind === "mattedRect") {
        for (const [name, rect] of [["mat", slot.mat], ["rect", slot.rect]]) {
          if (
            !rect ||
            rect.x < 0 ||
            rect.y < 0 ||
            rect.width <= 0 ||
            rect.height <= 0 ||
            rect.x + rect.width > manifest.canvas.width ||
            rect.y + rect.height > manifest.canvas.height
          ) {
            fail(`${templateId} slot ${slot.slot} has an invalid ${name} rect.`);
          }
        }
        const inset = template.matStyle?.photoInset;
        if (
          !Number.isFinite(inset) ||
          inset <= 0 ||
          slot.rect.x !== slot.mat.x + inset ||
          slot.rect.y !== slot.mat.y + inset ||
          slot.rect.width !== slot.mat.width - inset * 2 ||
          slot.rect.height !== slot.mat.height - inset * 2
        ) {
          fail(`${templateId} slot ${slot.slot} does not honor its mat inset.`);
        }
        if (
          slot.rect.width < minimumPhotoShortSide ||
          slot.rect.height < minimumPhotoShortSide
        ) {
          fail(`${templateId} slot ${slot.slot} is below its photo size floor.`);
        }
        continue;
      }
      if (slot.kind !== undefined && slot.kind !== "assetWindow") {
        fail(`${templateId} slot ${slot.slot} has unknown kind ${slot.kind}.`);
      }
      const layer = layersById.get(slot.layerId);
      const asset = layer && assetsById.get(layer.asset);
      if (!asset?.photoWindows?.[slot.windowIndex]) {
        fail(`${templateId} slot ${slot.slot} references a missing asset window.`);
      }
      const window = asset.photoWindows[slot.windowIndex];
      const effectiveWidth = window.width / asset.width * layer.width;
      const effectiveHeight = window.height / asset.height * layer.height;
      if (
        effectiveWidth < minimumPhotoShortSide ||
        effectiveHeight < minimumPhotoShortSide
      ) {
        fail(`${templateId} slot ${slot.slot} is below its photo size floor.`);
      }
      const target = `${slot.layerId}:${slot.windowIndex}`;
      if (targets.has(target)) fail(`${templateId} repeats photo target ${target}.`);
      targets.add(target);
    }
  }

  const maximalProjection = {
    assets: maximalRasterAssetIds.map((id) => assetsById.get(id)),
    template: manifest.templates["scrapbook-maximal"],
  };
  const maximalDigest = sha256(JSON.stringify(maximalProjection));
  if (maximalDigest !== expectedMaximalDesignContractDigest) {
    fail(`The approved 2a source contract changed: ${maximalDigest}.`);
  }
  const calmProjection = {
    assets: designRasterAssetIds.map((id) => assetsById.get(id)),
    templates: [
      manifest.templates["calm-classic"],
      manifest.templates["calm-film-trio"],
      manifest.templates["calm-accent-print"],
    ],
  };
  const calmDigest = sha256(JSON.stringify(calmProjection));
  if (calmDigest !== expectedCalmDesignContractDigest) {
    fail(`The approved 2b source contract changed: ${calmDigest}.`);
  }
  const minimalProjection = {
    assets: generatedColorAssetIds.map((id) => assetsById.get(id)),
    templates: [
      manifest.templates["minimal-classic"],
      manifest.templates["minimal-rows"],
      manifest.templates["minimal-grid"],
    ],
  };
  const minimalDigest = sha256(JSON.stringify(minimalProjection));
  if (minimalDigest !== expectedMinimalDesignContractDigest) {
    fail(`The approved 3b source contract changed: ${minimalDigest}.`);
  }
  return manifest;
}

function cleanAsset(asset) {
  return {
    id: asset.id,
    width: asset.width,
    height: asset.height,
    ...(asset.emptyWindowColor
      ? { emptyWindowColor: asset.emptyWindowColor }
      : {}),
    ...(asset.photoWindows ? { photoWindows: asset.photoWindows } : {}),
  };
}

function cleanLayers(layers) {
  return layers.map(({ backgroundSwappable, ...layer }) => layer);
}

function assetWindowSlots(slots) {
  return slots.map((slot) => ({
    slot: slot.slot,
    kind: "assetWindow",
    layerId: slot.layerId,
    windowIndex: slot.windowIndex,
  }));
}

function runtimeTitleStyle(source, { z }) {
  const placement = {
    kind: "rect",
    ...source.box,
    z,
    rotation: source.rotation,
  };
  const fontFamily = source.fontFamily
    .split(",")[0]
    .trim()
    .replace(/^['"]|['"]$/g, "");
  const fontKey = `${fontFamily}|${source.fontWeight}|${source.fontStyle}`;
  const approvedFontAssets = new Map([
    ["Lora|600|normal", "fonts/Lora-SemiBold.ttf"],
    ["Lora|500|italic", "fonts/Lora-Italic.ttf"],
    ["Lora|600|italic", "fonts/Lora-Italic.ttf"],
    ["Inter|500|normal", "fonts/Inter-Medium.ttf"],
  ]);
  const expectedFontAsset = approvedFontAssets.get(fontKey);
  if (!expectedFontAsset) {
    fail(`Unsupported title font contract: ${fontKey}`);
  }
  const fontAsset = source.fontAsset ?? expectedFontAsset;
  if (fontAsset !== expectedFontAsset) {
    fail(
      `Title font asset ${fontAsset} does not match ${fontKey}; expected ` +
        expectedFontAsset,
    );
  }
  return {
    placement,
    fontFamily,
    fontWeight: source.fontWeight,
    fontStyle: source.fontStyle,
    fontSize: source.fontSize,
    minFontSize: source.minFontSize ?? 27,
    lineHeight: source.lineHeight ?? 1,
    maxLines: source.maxLines ?? 1,
    letterSpacing: source.letterSpacing,
    color: source.color,
    textAlign: source.textAlign ?? source.align,
    verticalAlign: (source.verticalAlign ?? source.vAlign) === "middle"
      ? "center"
      : source.verticalAlign ?? source.vAlign,
    shadow: source.shadow ?? {
      dx: 0,
      dy: 0,
      blur: 0,
      color: "rgba(0,0,0,0)",
    },
  };
}

function normalizeRuntimeManifest(source) {
  const maximal = source.templates["scrapbook-maximal"];
  const background = (template) => ({
    layerId: "bg",
    defaultAssetId: template.defaultBackgroundId,
    assetIds: template.backgrounds.map((entry) => entry.id),
  });
  const normalizeCalm = (id) => {
    const template = source.templates[id];
    return {
      id,
      ...(template.minimumPhotoShortSide === undefined
        ? {}
        : { minimumPhotoShortSide: template.minimumPhotoShortSide }),
      background: background(template),
      layers: cleanLayers(template.layers),
      photoSlots: assetWindowSlots(template.photoSlots),
      titleStyle: runtimeTitleStyle(template.titleStyle, { z: 20 }),
    };
  };
  const normalizeMinimal = (id) => {
    const template = source.templates[id];
    return {
      id,
      ...(template.minimumPhotoShortSide === undefined
        ? {}
        : { minimumPhotoShortSide: template.minimumPhotoShortSide }),
      background: background(template),
      layers: [
        {
          layerId: "bg",
          asset: template.defaultBackgroundId,
          x: 0,
          y: 0,
          width: source.canvas.width,
          height: source.canvas.height,
          z: 0,
          rotation: 0,
        },
        ...cleanLayers(template.layers),
      ],
      matStyle: {
        fill: template.matStyle.fill,
        photoFill: template.matStyle.photoFill,
        border: template.matStyle.border,
        shadows: template.matStyle.shadows,
        photoInset: template.matStyle.photoInset,
      },
      rules: [...template.accents, ...template.rules].map((rule) => ({
        x: rule.x,
        y: rule.y,
        width: rule.width,
        height: rule.height,
        z: 10,
        color: rule.color,
        ...(rule.colorsByBackground
          ? { colorsByBackground: rule.colorsByBackground }
          : {}),
      })),
      photoSlots: template.photoSlots.map((slot) => ({
        slot: slot.slot,
        kind: "mattedRect",
        mat: slot.mat,
        rect: slot.rect,
        z: 4,
        rotation: slot.rotation,
      })),
      titleStyle: runtimeTitleStyle(template.titleStyle, { z: 20 }),
    };
  };

  return {
    version: source.version,
    canvas: source.canvas,
    assets: source.assets.map(cleanAsset),
    defaultTemplateId: source.defaultTemplateId,
    templates: [
      {
        id: "scrapbook-maximal",
        background: background(maximal),
        layers: cleanLayers(maximal.layers),
        photoSlots: assetWindowSlots(maximal.photoSlots),
        titleStyle: runtimeTitleStyle(maximal.titleStyle, { z: 20 }),
      },
      normalizeCalm("calm-classic"),
      normalizeCalm("calm-film-trio"),
      normalizeCalm("calm-accent-print"),
      normalizeMinimal("minimal-classic"),
      normalizeMinimal("minimal-rows"),
      normalizeMinimal("minimal-grid"),
    ],
  };
}

function assertOnlyKeys(value, allowed, path) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${path} must be an object.`);
  }
  const unexpected = Object.keys(value).filter((key) => !allowed.has(key));
  if (unexpected.length > 0) {
    fail(`${path} contains authoring-only fields: ${unexpected.join(", ")}.`);
  }
}

function assertRuntimeManifestShape(manifest) {
  const keys = (...values) => new Set(values);
  assertOnlyKeys(
    manifest,
    keys("version", "canvas", "assets", "defaultTemplateId", "templates"),
    "runtime manifest",
  );
  assertOnlyKeys(manifest.canvas, keys("width", "height"), "runtime canvas");

  for (const asset of manifest.assets) {
    assertOnlyKeys(
      asset,
      keys(
        "id",
        "width",
        "height",
        "emptyWindowColor",
        "photoWindows",
      ),
      `runtime asset ${asset.id}`,
    );
    for (const [index, window] of (asset.photoWindows ?? []).entries()) {
      assertOnlyKeys(
        window,
        keys("x", "y", "width", "height"),
        `runtime asset ${asset.id} window ${index}`,
      );
    }
  }

  for (const template of manifest.templates) {
    const templatePath = `runtime template ${template.id}`;
    assertOnlyKeys(
      template,
      keys(
        "id",
        "minimumPhotoShortSide",
        "background",
        "layers",
        "photoSlots",
        "rules",
        "matStyle",
        "titleStyle",
      ),
      templatePath,
    );
    assertOnlyKeys(
      template.background,
      keys("layerId", "defaultAssetId", "assetIds"),
      `${templatePath} background`,
    );
    for (const layer of template.layers) {
      assertOnlyKeys(
        layer,
        keys(
          "layerId",
          "asset",
          "x",
          "y",
          "width",
          "height",
          "z",
          "rotation",
          "shadows",
          "backgroundAssetIds",
          "blendMode",
          "opacity",
        ),
        `${templatePath} layer ${layer.layerId}`,
      );
    }
    for (const slot of template.photoSlots) {
      const allowed = slot.kind === "assetWindow"
        ? keys("slot", "kind", "layerId", "windowIndex")
        : slot.kind === "mattedRect"
          ? keys("slot", "kind", "mat", "rect", "z", "rotation")
          : null;
      if (!allowed) fail(`${templatePath} has unsupported slot kind ${slot.kind}.`);
      assertOnlyKeys(slot, allowed, `${templatePath} slot ${slot.slot}`);
      if (slot.kind === "mattedRect") {
        assertOnlyKeys(
          slot.mat,
          keys("x", "y", "width", "height"),
          `${templatePath} slot ${slot.slot} mat`,
        );
        assertOnlyKeys(
          slot.rect,
          keys("x", "y", "width", "height"),
          `${templatePath} slot ${slot.slot} rect`,
        );
      }
    }
    for (const [index, rule] of (template.rules ?? []).entries()) {
      assertOnlyKeys(
        rule,
        keys(
          "x",
          "y",
          "width",
          "height",
          "z",
          "color",
          "colorsByBackground",
        ),
        `${templatePath} rule ${index}`,
      );
    }
    if (template.matStyle) {
      assertOnlyKeys(
        template.matStyle,
        keys("fill", "photoFill", "border", "photoInset", "shadows"),
        `${templatePath} matStyle`,
      );
      assertOnlyKeys(
        template.matStyle.border,
        keys("width", "color"),
        `${templatePath} matStyle border`,
      );
    }
    assertOnlyKeys(
      template.titleStyle,
      keys(
        "placement",
        "fontFamily",
        "fontWeight",
        "fontStyle",
        "fontSize",
        "minFontSize",
        "lineHeight",
        "maxLines",
        "letterSpacing",
        "color",
        "textAlign",
        "verticalAlign",
        "shadow",
      ),
      `${templatePath} titleStyle`,
    );
    assertOnlyKeys(
      template.titleStyle.placement,
      keys("kind", "x", "y", "width", "height", "z", "rotation"),
      `${templatePath} title placement`,
    );
    if (template.titleStyle.placement.kind !== "rect") {
      fail(`${templatePath} must use the frozen rect title placement.`);
    }
  }
}

function dimensionsAtScale(asset, numerator) {
  return {
    width: (asset.width / 3) * numerator,
    height: (asset.height / 3) * numerator,
  };
}

function parseSelectedAssets() {
  const raw = process.env.COLLAGE_ASSET_IDS;
  const ids = raw
    ? raw.split(",").map((id) => id.trim()).filter(Boolean)
    : isRealOutput
      ? newAssetIds
      : requiredAssetIds;
  if (ids.length === 0) fail("COLLAGE_ASSET_IDS selected no assets.");
  if (new Set(ids).size !== ids.length) fail("COLLAGE_ASSET_IDS has duplicates.");
  for (const id of ids) {
    if (!requiredAssetIds.includes(id)) fail(`Unknown selected asset ${id}.`);
  }
  if (isRealOutput && ids.some((id) => retainedAssetIdSet.has(id))) {
    fail(
      "Refusing to overwrite retained approved assets in the real output tree. " +
        "Use a staging COLLAGE_OUTPUT for a full verification export.",
    );
  }
  return ids;
}

async function inventoryDigest(root, assetIds) {
  let lines = "";
  for (const variant of ["", "2.0x", "3.0x"]) {
    for (const id of assetIds) {
      const relativePath = join(variant, `${id}.png`);
      const bytes = await readFile(join(root, relativePath));
      lines += `${relativePath}:${sha256(bytes)}\n`;
    }
  }
  return sha256(lines);
}

async function assertRealRetainedInventory() {
  const digest = await inventoryDigest(realOutputDirectory, retainedAssetIds);
  if (digest !== expectedRetainedInventoryDigest) {
    fail(
      `Retained real asset inventory changed: ${digest}; expected ` +
        `${expectedRetainedInventoryDigest}.`,
    );
  }
  return digest;
}

async function assertRealMaximalInventory() {
  const digest = await inventoryDigest(
    realOutputDirectory,
    maximalRasterAssetIds,
  );
  if (digest !== expectedMaximalInventoryDigest) {
    fail(
      `Approved wide 2a banner inventory changed: ${digest}; expected ` +
        `${expectedMaximalInventoryDigest}.`,
    );
  }
  return digest;
}

async function assertRealCalmInventory() {
  const digest = await inventoryDigest(realOutputDirectory, designRasterAssetIds);
  if (digest !== expectedCalmInventoryDigest) {
    fail(
      `Approved 2b real asset inventory changed: ${digest}; expected ` +
        `${expectedCalmInventoryDigest}.`,
    );
  }
  return digest;
}

async function outputAliasesRealTree() {
  const [resolvedOutput, resolvedRealOutput] = await Promise.all([
    realpath(outputDirectory),
    realpath(realOutputDirectory),
  ]);
  return resolvedOutput === resolvedRealOutput;
}

async function validateNoStalePngs(manifest) {
  const expected = new Set(manifest.assets.map((asset) => `${asset.id}.png`));
  for (const variant of ["", "2.0x", "3.0x"]) {
    const directory = join(outputDirectory, variant);
    const names = await readdir(directory);
    const stale = names.filter((name) => name.endsWith(".png") && !expected.has(name));
    if (stale.length > 0) {
      fail(`Remove stale generated PNGs from ${directory}: ${stale.join(", ")}`);
    }
  }
}

async function alphaRange(sharp, path) {
  const { data, info } = await sharp(path)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  let minimum = 255;
  let maximum = 0;
  for (let index = 3; index < data.length; index += info.channels) {
    minimum = Math.min(minimum, data[index]);
    maximum = Math.max(maximum, data[index]);
  }
  return { minimum, maximum, data, info };
}

function rgbFromHex(color) {
  const value = Number.parseInt(color.slice(1), 16);
  return {
    r: (value >> 16) & 0xff,
    g: (value >> 8) & 0xff,
    b: value & 0xff,
  };
}

async function validatePng(sharp, path, asset, numerator) {
  const expected = dimensionsAtScale(asset, numerator);
  const metadata = await sharp(path).metadata();
  if (metadata.width !== expected.width || metadata.height !== expected.height) {
    fail(
      `${path} is ${metadata.width}x${metadata.height}; expected ` +
        `${expected.width}x${expected.height}.`,
    );
  }
  const alpha = await alphaRange(sharp, path);
  if (asset.opaque === true) {
    if (alpha.minimum !== 255 || alpha.maximum !== 255) {
      fail(`${path} is marked opaque but contains transparency.`);
    }
  } else if (translucentOverlayIds.has(asset.id)) {
    const mustReachTransparent = asset.id !== "grain-overlay";
    if (
      (mustReachTransparent && alpha.minimum > 1) ||
      alpha.maximum >= 255 ||
      alpha.maximum === 0
    ) {
      fail(`${path} must contain transparent pixels and translucent visible art.`);
    }
  } else if (alpha.minimum >= 255 || alpha.maximum === 0) {
    fail(`${path} must contain visible art and transparency.`);
  }

  if (generatedColorAssetIdSet.has(asset.id)) {
    const expectedRgb = rgbFromHex(generatedColors.get(asset.id));
    for (let index = 0; index < alpha.data.length; index += alpha.info.channels) {
      if (
        alpha.data[index] !== expectedRgb.r ||
        alpha.data[index + 1] !== expectedRgb.g ||
        alpha.data[index + 2] !== expectedRgb.b ||
        alpha.data[index + 3] !== 255
      ) {
        fail(`${path} contains pixels outside its exact generated solid color.`);
      }
    }
  }

  const windowAlpha = [];
  for (const window of asset.photoWindows ?? []) {
    const scale = numerator / 3;
    const sourceInset = asset.id === "polaroid-frame"
      ? 36
      : asset.id === "print-frame-hero"
        ? 57
        : asset.id === "film-strip-three-horizontal"
          ? 9
          : 9;
    const inset = Math.max(1, Math.ceil(sourceInset * scale));
    const left = Math.floor(window.x * scale);
    const top = Math.floor(window.y * scale);
    const right = Math.ceil((window.x + window.width) * scale);
    const bottom = Math.ceil((window.y + window.height) * scale);
    let nonzero = 0;
    let maximum = 0;
    for (let y = top; y < bottom; y += 1) {
      for (let x = left; x < right; x += 1) {
        const index = (y * alpha.info.width + x) * alpha.info.channels + 3;
        const value = alpha.data[index];
        if (value > 0) nonzero += 1;
        maximum = Math.max(maximum, value);
        if (
          x >= left + inset &&
          x < right - inset &&
          y >= top + inset &&
          y < bottom - inset &&
          value !== 0
        ) {
          fail(`${path} has alpha inside a photo window's clear core.`);
        }
      }
    }
    const nonzeroFraction = nonzero / ((right - left) * (bottom - top));
    const fractionLimit = asset.id === "polaroid-frame"
      ? 0.31
      : asset.id === "print-frame-hero"
        ? 0.29
        : asset.id === "film-strip-three-horizontal"
          ? 0.13
          : 0.12;
    if (nonzeroFraction > fractionLimit) {
      fail(
        `${path} window alpha fraction ${nonzeroFraction} exceeds ${fractionLimit}.`,
      );
    }
    if (
      asset.id === "polaroid-frame" &&
      maximum > 105
    ) {
      fail(`${path} frame seam is darker than the approved art.`);
    }
    windowAlpha.push({ nonzeroFraction, maximum, clearInset: inset });
  }

  return {
    width: metadata.width,
    height: metadata.height,
    alpha: [alpha.minimum, alpha.maximum],
    windowAlpha,
    sha256: sha256(await readFile(path)),
  };
}

function pngOptions(asset) {
  const common = { compressionLevel: 9, adaptiveFiltering: true };
  if (
    losslessOverlayPaletteIds.has(asset.id) &&
    process.env.COLLAGE_TRUECOLOR !== "1"
  ) {
    return {
      ...common,
      palette: true,
      quality: 100,
      colours: 256,
      dither: 0,
      effort: 10,
    };
  }
  if (
    paletteTextureIds.has(asset.id) &&
    process.env.COLLAGE_TRUECOLOR !== "1"
  ) {
    return {
      ...common,
      palette: true,
      quality: 90,
      colours: 256,
      dither: 0,
      effort: 10,
    };
  }
  return common;
}

async function renderAsset(page, asset) {
  const url = new URL(pathToFileURL(sourcePath));
  url.searchParams.set("exportAsset", asset.id);
  await page.goto(url.href, { waitUntil: "load" });
  await page.waitForFunction(
    (assetId) => document.querySelector(`[data-export-asset="${assetId}"]`),
    asset.id,
  );
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all(
      [...document.images].map((image) => image.decode().catch(() => undefined)),
    );
    await new Promise((resolveFrame) =>
      requestAnimationFrame(() => requestAnimationFrame(resolveFrame)),
    );
  });
  if (asset.id === "banner-wide") {
    const loaded = await page.evaluate(async () => {
      const faces = await document.fonts.load("600 45px Lora", "DECEMBER");
      return faces.some((face) => face.status === "loaded");
    });
    if (!loaded) fail("The approved Lora title font did not load.");
  }

  const locator = page.locator(`[data-export-asset="${asset.id}"]`);
  if (await locator.count() !== 1) {
    fail(`${asset.id} must render exactly one isolated export root.`);
  }
  const box = await locator.boundingBox();
  if (
    !box ||
    Math.abs(box.x) > 0.01 ||
    Math.abs(box.y) > 0.01 ||
    Math.abs(box.width - asset.width) > 0.01 ||
    Math.abs(box.height - asset.height) > 0.01
  ) {
    fail(`${asset.id} rendered with unexpected bounds: ${JSON.stringify(box)}.`);
  }
  return locator.screenshot({
    type: "png",
    omitBackground: true,
    animations: "disabled",
    scale: "css",
  });
}

async function writeVariants(sharp, asset, captured) {
  const paths = {
    "1x": join(outputDirectory, `${asset.id}.png`),
    "2x": join(outputDirectory, "2.0x", `${asset.id}.png`),
    "3x": join(outputDirectory, "3.0x", `${asset.id}.png`),
  };
  for (const [label, numerator] of [["1x", 1], ["2x", 2], ["3x", 3]]) {
    const target = paths[label];
    const size = dimensionsAtScale(asset, numerator);
    if (generatedColorAssetIdSet.has(asset.id)) {
      await sharp({
        create: {
          width: size.width,
          height: size.height,
          channels: 4,
          background: { ...rgbFromHex(generatedColors.get(asset.id)), alpha: 1 },
        },
      }).png(pngOptions(asset)).toFile(target);
    } else {
      let pipeline = sharp(captured).ensureAlpha();
      if (numerator !== 3) {
        pipeline = pipeline.resize(size.width, size.height, { kernel: "lanczos3" });
      }
      await pipeline.png(pngOptions(asset)).toFile(target);
    }
  }
  return {
    id: asset.id,
    "1x": await validatePng(sharp, paths["1x"], asset, 1),
    "2x": await validatePng(sharp, paths["2x"], asset, 2),
    "3x": await validatePng(sharp, paths["3x"], asset, 3),
  };
}

async function main() {
  const selectedIds = parseSelectedAssets();
  await mkdir(outputDirectory, { recursive: true });
  const writesRealTree = await outputAliasesRealTree();
  if (writesRealTree && selectedIds.some((id) => retainedAssetIdSet.has(id))) {
    fail(
      "Refusing to overwrite retained approved assets through a path alias to " +
        "the real output tree.",
    );
  }
  const retainedBefore = await assertRealRetainedInventory();
  const maximalBefore = await assertRealMaximalInventory();
  const calmBefore = await assertRealCalmInventory();
  const source = await verifySource(
    sourcePath,
    expectedSourceHashes["Memory Collage.dc.html"],
    { allowDrift: true },
  );
  const support = await verifySource(
    supportPath,
    expectedSourceHashes["support.js"],
    { allowDrift: true },
  );
  for (const font of fontSpecs) {
    await verifySource(join(appDirectory, "fonts", font.file), font.hash);
  }
  const manifest = readManifest(source.bytes.toString("utf8"));
  const runtimeManifest = normalizeRuntimeManifest(manifest);
  assertRuntimeManifestShape(runtimeManifest);
  if (process.env.COLLAGE_WRITE_MANIFEST === "1") {
    if (writesRealTree) {
      fail(
        "Refusing to write the runtime manifest from the exporter into the real " +
          "asset tree; use a staging COLLAGE_OUTPUT.",
      );
    }
  }

  const sharp = loadDependency("sharp", process.env.SHARP_MODULE);
  await mkdir(join(outputDirectory, "2.0x"), { recursive: true });
  await mkdir(join(outputDirectory, "3.0x"), { recursive: true });
  if (process.env.COLLAGE_WRITE_MANIFEST === "1") {
    await writeFile(
      join(outputDirectory, "manifest.json"),
      `${JSON.stringify(runtimeManifest, null, 2)}\n`,
    );
  }

  const assetsById = new Map(manifest.assets.map((asset) => [asset.id, asset]));
  const browserAssetIds = selectedIds.filter(
    (id) => !generatedColorAssetIdSet.has(id),
  );
  const results = [];
  let browser;
  const pageErrors = [];
  try {
    let page;
    if (browserAssetIds.length > 0) {
      const offlineRuntime = await loadOfflineRuntime();
      const { chromium } = loadDependency(
        "playwright",
        process.env.PLAYWRIGHT_MODULE,
      );
      browser = await chromium.launch({
        headless: true,
        executablePath: findChrome(),
      });
      page = await browser.newPage({
        viewport: { width: 1200, height: 2000 },
        deviceScaleFactor: 1,
      });
      page.on("pageerror", (error) => pageErrors.push(error.message));
      await page.route("**/*", async (route) => {
        const requestUrl = route.request().url();
        const runtime = offlineRuntime.get(requestUrl);
        if (runtime) {
          await route.fulfill({
            status: 200,
            body: runtime.body,
            headers: {
              "content-type": "application/javascript; charset=utf-8",
              "access-control-allow-origin": "*",
            },
          });
        } else if (
          requestUrl.startsWith("http://") ||
          requestUrl.startsWith("https://")
        ) {
          await route.abort("blockedbyclient");
        } else {
          await route.continue();
        }
      });
    }

    for (const assetId of selectedIds) {
      const asset = assetsById.get(assetId);
      const captured = generatedColorAssetIdSet.has(assetId)
        ? undefined
        : await renderAsset(page, asset);
      results.push(await writeVariants(sharp, asset, captured));
      console.log(`exported ${asset.id}`);
    }
    if (pageErrors.length > 0) {
      fail(`The design source raised page errors: ${pageErrors.join(" | ")}`);
    }
  } finally {
    await browser?.close();
  }

  await validateNoStalePngs(manifest);
  const retainedAfter = await assertRealRetainedInventory();
  const maximalAfter = await assertRealMaximalInventory();
  const calmAfter = await assertRealCalmInventory();
  let stagedRetainedDigest;
  let stagedMaximalDigest;
  let stagedCalmDigest;
  if (
    !isRealOutput &&
    retainedAssetIds.every((id) => selectedIds.includes(id))
  ) {
    stagedRetainedDigest = await inventoryDigest(
      outputDirectory,
      retainedAssetIds,
    );
    if (stagedRetainedDigest !== expectedRetainedInventoryDigest) {
      fail(
        `Staged retained assets are not byte-identical: ${stagedRetainedDigest}.`,
      );
    }
    stagedMaximalDigest = await inventoryDigest(
      outputDirectory,
      maximalRasterAssetIds,
    );
    if (stagedMaximalDigest !== expectedMaximalInventoryDigest) {
      fail(
        `Staged wide 2a banner is not byte-identical: ${stagedMaximalDigest}.`,
      );
    }
    stagedCalmDigest = await inventoryDigest(
      outputDirectory,
      designRasterAssetIds,
    );
    if (stagedCalmDigest !== expectedCalmInventoryDigest) {
      fail(`Staged 2b assets are not byte-identical: ${stagedCalmDigest}.`);
    }
  }

  console.log(JSON.stringify({
    assets: results.length,
    variants: results.length * 3,
    selectedIds,
    outputDirectory,
    wroteManifest: process.env.COLLAGE_WRITE_MANIFEST === "1",
    sourceSha256: source.actualHash,
    supportSha256: support.actualHash,
    retainedRealSha256Before: retainedBefore,
    retainedRealSha256After: retainedAfter,
    maximalRealSha256Before: maximalBefore,
    maximalRealSha256After: maximalAfter,
    calmRealSha256Before: calmBefore,
    calmRealSha256After: calmAfter,
    ...(stagedRetainedDigest
      ? { stagedRetainedSha256: stagedRetainedDigest }
      : {}),
    ...(stagedMaximalDigest
      ? { stagedMaximalSha256: stagedMaximalDigest }
      : {}),
    ...(stagedCalmDigest
      ? { stagedCalmSha256: stagedCalmDigest }
      : {}),
    files: results,
  }, null, 2));
}

await main();
