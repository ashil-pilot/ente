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
    "80934d55081fc9983f2187d0721fb21b9d1bb8478614aaec4f4abc42305a2d4c",
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
  "banner",
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
const designRasterAssetIds = [
  "film-strip-four-horizontal",
  "print-frame-hero",
  "paper-notebook-blush",
  "paper-notebook-sage",
];
const generatedColors = new Map([
  ["editorial-bone", "#f4f0e8"],
  ["editorial-sand", "#e8dfcc"],
  ["editorial-sage", "#dde0d6"],
  ["editorial-charcoal", "#2b2723"],
]);
const generatedColorAssetIds = [...generatedColors.keys()];
const newAssetIds = [...designRasterAssetIds, ...generatedColorAssetIds];
const requiredAssetIds = [...retainedAssetIds, ...newAssetIds];
const retainedAssetIdSet = new Set(retainedAssetIds);
const generatedColorAssetIdSet = new Set(generatedColorAssetIds);
const expectedRetainedInventoryDigest =
  "422d287821ede0238ccc03c9692115e7d8c592797f86237970d03edca037cc08";

const dimensions = new Map([
  ["paper-washi", [1080, 1920]],
  ["paper-cream-fiber", [1080, 1920]],
  ["paper-blush-stripe", [1080, 1920]],
  ["paper-sage-stripe", [1080, 1920]],
  ["paper-terracotta-mottle", [1080, 1920]],
  ["paper-torn", [1098, 1734]],
  ["polaroid-frame", [462, 534]],
  ["film-strip-four", [390, 1800]],
  ["banner", [546, 150]],
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
  ["print-frame-hero", [876, 594]],
  ["paper-notebook-blush", [1080, 1920]],
  ["paper-notebook-sage", [1080, 1920]],
  ["editorial-bone", [1080, 1920]],
  ["editorial-sand", [1080, 1920]],
  ["editorial-sage", [1080, 1920]],
  ["editorial-charcoal", [1080, 1920]],
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
  ["print-frame-hero", [
    { x: 24, y: 24, width: 834, height: 546 },
  ]],
]);
const expectedTemplateIds = [
  "scrapbook-maximal",
  "scrapbook-calm",
  "minimal-editorial",
];
// JSON.stringify(template) pins every approved 2a coordinate and shadow.
const expectedMaximalTemplateDigest =
  "6817de9b4f5cf2c017264aa575d9c2e35f763eab7177bb59af7c7da4fab590d9";
// Projection: JSON.stringify({ assets: the final eight source asset records,
// templates: { scrapbook-calm, minimal-editorial } }).
const expectedNewDesignContractDigest =
  "bc3af973973d9eab10d605e5c5c8776ea514dd67ae37b12610e6b2449995076f";

const paletteTextureIds = new Set([
  "paper-washi",
  "paper-cream-fiber",
  "paper-blush-stripe",
  "paper-sage-stripe",
  "paper-terracotta-mottle",
  "paper-torn",
  "paper-notebook-blush",
  "paper-notebook-sage",
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
    manifest.defaultTemplateId !== "scrapbook-maximal"
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
    const backgroundIds = template.backgrounds.map((background) => background.id);
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
        continue;
      }
      const layer = layersById.get(slot.layerId);
      const asset = layer && assetsById.get(layer.asset);
      if (!asset?.photoWindows?.[slot.windowIndex]) {
        fail(`${templateId} slot ${slot.slot} references a missing asset window.`);
      }
      const target = `${slot.layerId}:${slot.windowIndex}`;
      if (targets.has(target)) fail(`${templateId} repeats photo target ${target}.`);
      targets.add(target);
    }
  }

  const maximalDigest = sha256(JSON.stringify(manifest.templates["scrapbook-maximal"]));
  if (maximalDigest !== expectedMaximalTemplateDigest) {
    fail(`The approved 2a template contract changed: ${maximalDigest}.`);
  }
  const newDesignProjection = {
    assets: manifest.assets.slice(retainedAssetIds.length),
    templates: {
      "scrapbook-calm": manifest.templates["scrapbook-calm"],
      "minimal-editorial": manifest.templates["minimal-editorial"],
    },
  };
  const newDesignDigest = sha256(JSON.stringify(newDesignProjection));
  if (newDesignDigest !== expectedNewDesignContractDigest) {
    fail(`The approved 2b/2c source contract changed: ${newDesignDigest}.`);
  }
  return manifest;
}

function cleanAsset(asset) {
  if (generatedColorAssetIdSet.has(asset.id)) {
    return {
      id: asset.id,
      width: asset.width,
      height: asset.height,
      opaque: true,
      ...(asset.id === "editorial-charcoal" ? { dark: true } : {}),
      role: "background",
    };
  }
  const noteOverrides = {
    "film-strip-four-horizontal":
      "calm umber film stock with four live horizontal windows",
    "print-frame-hero": "even-border cream print frame with a baked alpha seam",
    "paper-notebook-blush": "cream fiber sheet with a blush notebook spine",
    "paper-notebook-sage": "cream fiber sheet with a sage notebook spine",
  };
  return noteOverrides[asset.id]
    ? { ...asset, note: noteOverrides[asset.id] }
    : { ...asset };
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

function runtimeTitleStyle(source, { z, layerId } = {}) {
  const placement = layerId
    ? { kind: "layer", layerId }
    : {
        kind: "rect",
        ...source.box,
        z,
        rotation: source.rotation,
      };
  return {
    placement,
    units: "1080x1920 canvas pixels",
    fontFamily: "Lora",
    fontAsset: source.fontStyle === "italic"
      ? "fonts/Lora-Italic.ttf"
      : "fonts/Lora-SemiBold.ttf",
    fontWeight: source.fontWeight,
    fontStyle: source.fontStyle,
    fontSize: source.fontSize,
    minFontSize: source.minFontSize ?? 27,
    lineHeight: source.lineHeight ?? 1,
    maxLines: source.maxLines ?? 1,
    letterSpacing: source.letterSpacing,
    color: source.color,
    ...(source.colorOnDark ? { colorOnDark: source.colorOnDark } : {}),
    textAlign: source.textAlign ?? source.align,
    verticalAlign: (source.verticalAlign ?? source.vAlign) === "middle"
      ? "center"
      : source.verticalAlign ?? source.vAlign,
    memoryTitleCasing: "preserve",
    generatedMonthLabelCasing:
      source.generatedMonthLabelCasing ?? "preserve",
    glyphFallback: "platform",
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
  const calm = source.templates["scrapbook-calm"];
  const minimal = source.templates["minimal-editorial"];
  const common = {
    rotationOrigin: source.rotationOrigin,
    overflow: source.overflow,
  };
  const background = (template) => ({
    layerId: "bg",
    defaultAssetId: template.defaultBackgroundId,
    assetIds: template.backgrounds.map((entry) => entry.id),
  });

  return {
    version: source.version,
    scale: source.scale,
    canvas: source.canvas,
    assets: source.assets.map(cleanAsset),
    defaultTemplateId: source.defaultTemplateId,
    templates: [
      {
        id: "scrapbook-maximal",
        ...common,
        background: background(maximal),
        shadowSchema: {
          kind: "dropShadow",
          units: "1080x1920 canvas pixels",
          fields: ["dx", "dy", "blur", "color"],
          application:
            "cast from the rotated layer silhouette and rendered under the art",
        },
        layers: cleanLayers(maximal.layers),
        photoSlots: assetWindowSlots(maximal.photoSlots),
        appRendered: maximal.appRendered,
        titleStyle: runtimeTitleStyle(maximal.titleStyle, {
          layerId: maximal.titleStyle.layerId,
        }),
      },
      {
        id: "scrapbook-calm",
        ...common,
        background: background(calm),
        layers: cleanLayers(calm.layers),
        photoSlots: assetWindowSlots(calm.photoSlots),
        appRendered: "title text is typeset directly by the app",
        titleStyle: runtimeTitleStyle(calm.titleStyle, { z: 20 }),
      },
      {
        id: "minimal-editorial",
        ...common,
        background: background(minimal),
        layers: [
          {
            layerId: "bg",
            asset: minimal.defaultBackgroundId,
            x: 0,
            y: 0,
            width: source.canvas.width,
            height: source.canvas.height,
            z: 0,
            rotation: 0,
          },
        ],
        rules: minimal.rules.map((rule) => ({
          x: rule.x,
          y: rule.y,
          width: rule.width,
          height: rule.height,
          z: 1,
          color: rule.color,
          colorOnDark: rule.colorOnDark,
        })),
        photoSlots: minimal.photoSlots.map((slot) => ({
          slot: slot.slot,
          kind: "rect",
          ...slot.rect,
          z: 4,
          rotation: slot.rotation,
        })),
        appRendered:
          "flat background, hairlines, title, and photo tiles are composed by the app",
        titleStyle: runtimeTitleStyle(minimal.titleStyle, { z: 2 }),
      },
    ],
  };
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
        : asset.id === "film-strip-four-horizontal"
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
        : asset.id === "film-strip-four-horizontal"
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
  if (asset.id === "banner") {
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
  let stagedRetainedDigest;
  if (
    !isRealOutput &&
    retainedAssetIds.every((id) => selectedIds.includes(id))
  ) {
    stagedRetainedDigest = await inventoryDigest(outputDirectory, retainedAssetIds);
    if (stagedRetainedDigest !== expectedRetainedInventoryDigest) {
      fail(
        `Staged retained assets are not byte-identical: ${stagedRetainedDigest}.`,
      );
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
    ...(stagedRetainedDigest
      ? { stagedRetainedSha256: stagedRetainedDigest }
      : {}),
    files: results,
  }, null, 2));
}

await main();
