#!/usr/bin/env node

import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const sourcePath = resolve(
  process.env.COLLAGE_SOURCE ?? join(scriptDirectory, "Memory Collage.dc.html"),
);
const supportPath = join(dirname(sourcePath), "support.js");
const vendorDirectory = join(scriptDirectory, "vendor");
const outputDirectory = resolve(
  process.env.COLLAGE_OUTPUT ??
    join(scriptDirectory, "..", "..", "assets", "memories_collage"),
);
const titleFontPath = join(scriptDirectory, "..", "..", "fonts", "Lora-SemiBold.ttf");
const titleFontLicensePath = join(scriptDirectory, "..", "..", "fonts", "Lora-OFL.txt");

const expectedSourceHashes = {
  "Memory Collage.dc.html":
    "115a6fe96caa01e0183d104aac8e2b98ffbdbc34833ef9601e9d6c172e0e6eb3",
  "support.js":
    "8fe7df74405f3c55f49b7249c74ea1397e65d07dea2b1bd3b4a489bec2e28cbe",
};
const expectedTitleFontHashes = {
  "Lora-SemiBold.ttf":
    "a9f5bbcebb6b53d53b6d7d571b2076f3db4931026693397200f69801b6701a81",
  "Lora-OFL.txt":
    "6d6bc7bbb828514925dabcaf89e4771398d12c60dd1cb2bbb90eea129535d0f4",
};
const expectedTitleStyle = {
  layerId: "banner",
  units: "1080x1920 canvas pixels",
  fontFamily: "Lora",
  fontAsset: "fonts/Lora-SemiBold.ttf",
  fontWeight: 600,
  fontStyle: "normal",
  fontSize: 45,
  letterSpacing: 12,
  color: "#f4e7cf",
  textAlign: "center",
  verticalAlign: "center",
  memoryTitleCasing: "preserve",
  generatedMonthLabelCasing: "uppercase",
  glyphFallback: "platform",
  shadow: {
    dx: 0,
    dy: 3,
    blur: 3,
    color: "rgba(90,40,15,0.5)",
  },
};
const requiredAssetIds = [
  "paper-washi",
  "paper-cream-fiber",
  "paper-blush-stripe",
  "paper-sage-stripe",
  "paper-terracotta-mottle",
  "paper-torn",
  "polaroid-frame",
  "film-strip",
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
const expectedLayers = [
  {
    layerId: "bg",
    asset: "paper-washi",
    x: 0,
    y: 0,
    width: 1080,
    height: 1920,
    z: 0,
    rotation: 0,
    backgroundSwappable: true,
  },
  {
    layerId: "torn",
    asset: "paper-torn",
    x: -12,
    y: 162,
    width: 1098,
    height: 1734,
    z: 2,
    rotation: 0.8,
  },
  {
    layerId: "ring",
    asset: "coffee-ring",
    x: 444,
    y: 1530,
    width: 192,
    height: 192,
    z: 3,
    rotation: 8,
  },
  {
    layerId: "fern",
    asset: "fern",
    x: 897,
    y: 114,
    width: 228,
    height: 408,
    z: 4,
    rotation: 196,
  },
  {
    layerId: "star",
    asset: "star",
    x: 336,
    y: 240,
    width: 282,
    height: 282,
    z: 9,
    rotation: 12,
  },
  {
    layerId: "strip",
    asset: "film-strip",
    x: 618,
    y: 312,
    width: 390,
    height: 1800,
    z: 10,
    rotation: 2,
  },
  {
    layerId: "p1",
    asset: "polaroid-frame",
    x: 18,
    y: 354,
    width: 462,
    height: 534,
    z: 12,
    rotation: -4.5,
  },
  {
    layerId: "p2",
    asset: "polaroid-frame",
    x: 72,
    y: 900,
    width: 462,
    height: 534,
    z: 13,
    rotation: 3,
  },
  {
    layerId: "p3",
    asset: "polaroid-frame",
    x: 24,
    y: 1404,
    width: 462,
    height: 534,
    z: 14,
    rotation: -2,
  },
  {
    layerId: "banner",
    asset: "banner",
    x: 264,
    y: 198,
    width: 546,
    height: 150,
    z: 16,
    rotation: -2.5,
  },
  {
    layerId: "tapeA",
    asset: "tape-mustard",
    x: 54,
    y: 162,
    width: 336,
    height: 72,
    z: 17,
    rotation: -4,
  },
  {
    layerId: "tapeB",
    asset: "tape-blush",
    x: 132,
    y: 318,
    width: 228,
    height: 66,
    z: 15,
    rotation: 2,
  },
  {
    layerId: "tapeC",
    asset: "tape-sage",
    x: 444,
    y: 864,
    width: 210,
    height: 63,
    z: 15,
    rotation: -36,
  },
  {
    layerId: "stamp",
    asset: "stamp-postmark",
    x: 678,
    y: 150,
    width: 240,
    height: 270,
    z: 17,
    rotation: 5,
  },
  {
    layerId: "sunStreak",
    asset: "sun-streak",
    x: 0,
    y: 0,
    width: 1080,
    height: 1920,
    z: 34,
    rotation: 0,
    blendMode: "soft-light",
    opacity: 1,
  },
  {
    layerId: "vignette",
    asset: "vignette",
    x: 0,
    y: 0,
    width: 1080,
    height: 1920,
    z: 36,
    rotation: 0,
    blendMode: "multiply",
    opacity: 1,
  },
  {
    layerId: "grain",
    asset: "grain-overlay",
    x: 0,
    y: 0,
    width: 1080,
    height: 1920,
    z: 38,
    rotation: 0,
    blendMode: "overlay",
    opacity: 0.55,
  },
];
const expectedPhotoLayouts = [
  {
    photoCount: 6,
    assetOverrides: { strip: "film-strip" },
    photoSlots: [
      { slot: 0, layerId: "strip", windowIndex: 0 },
      { slot: 1, layerId: "strip", windowIndex: 1 },
      { slot: 2, layerId: "strip", windowIndex: 2 },
      { slot: 3, layerId: "p1", windowIndex: 0 },
      { slot: 4, layerId: "p2", windowIndex: 0 },
      { slot: 5, layerId: "p3", windowIndex: 0 },
    ],
  },
  {
    photoCount: 7,
    assetOverrides: { strip: "film-strip-four" },
    photoSlots: [
      { slot: 0, layerId: "strip", windowIndex: 0 },
      { slot: 1, layerId: "strip", windowIndex: 1 },
      { slot: 2, layerId: "strip", windowIndex: 2 },
      { slot: 3, layerId: "p1", windowIndex: 0 },
      { slot: 4, layerId: "p2", windowIndex: 0 },
      { slot: 5, layerId: "p3", windowIndex: 0 },
      { slot: 6, layerId: "strip", windowIndex: 3 },
    ],
  },
];
const expectedShadows = new Map([
  ["torn", [
    { kind: "dropShadow", dx: 0, dy: 42, blur: 66, color: "rgba(80,50,22,0.3)" },
  ]],
  ["fern", [
    { kind: "dropShadow", dx: 3, dy: 6, blur: 9, color: "rgba(80,60,30,0.3)" },
  ]],
  ["star", [
    { kind: "dropShadow", dx: 3, dy: 9, blur: 15, color: "rgba(90,55,15,0.35)" },
  ]],
  ["strip", [
    { kind: "dropShadow", dx: 0, dy: 30, blur: 54, color: "rgba(70,32,12,0.38)" },
  ]],
  ["p1", [
    { kind: "dropShadow", dx: 0, dy: 9, blur: 18, color: "rgba(90,60,30,0.22)" },
    { kind: "dropShadow", dx: 0, dy: 36, blur: 72, color: "rgba(90,60,30,0.26)" },
  ]],
  ["p2", [
    { kind: "dropShadow", dx: 0, dy: 9, blur: 18, color: "rgba(90,60,30,0.22)" },
    { kind: "dropShadow", dx: 0, dy: 36, blur: 72, color: "rgba(90,60,30,0.26)" },
  ]],
  ["p3", [
    { kind: "dropShadow", dx: 0, dy: 9, blur: 18, color: "rgba(90,60,30,0.22)" },
    { kind: "dropShadow", dx: 0, dy: 36, blur: 72, color: "rgba(90,60,30,0.26)" },
  ]],
  ["banner", [
    { kind: "dropShadow", dx: 0, dy: 9, blur: 18, color: "rgba(80,40,15,0.35)" },
  ]],
  ["tapeA", [
    { kind: "dropShadow", dx: 0, dy: 6, blur: 12, color: "rgba(90,60,25,0.22)" },
  ]],
  ["tapeB", [
    { kind: "dropShadow", dx: 0, dy: 6, blur: 12, color: "rgba(110,60,45,0.22)" },
  ]],
  ["tapeC", [
    { kind: "dropShadow", dx: 0, dy: 6, blur: 12, color: "rgba(70,80,45,0.22)" },
  ]],
  ["stamp", [
    { kind: "dropShadow", dx: 0, dy: 6, blur: 12, color: "rgba(90,60,30,0.3)" },
  ]],
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
  if (actualHash !== expectedHash &&
      (!allowDrift || process.env.ALLOW_COLLAGE_SOURCE_DRIFT !== "1")) {
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

  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch (error) {
      if (candidate === candidates.at(-1)) {
        fail(
          `Could not load ${packageName}. Install it locally or set ` +
            `${packageName.toUpperCase()}_MODULE to its package directory. ` +
            `Last error: ${error.message}`,
        );
      }
    }
  }
}

function findChrome() {
  const candidates = [
    process.env.CHROME_BINARY,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
  ].filter(Boolean);
  const chrome = candidates.find(existsSync);
  if (!chrome) {
    fail(
      "Chrome or Chromium was not found. Set CHROME_BINARY to its executable.",
    );
  }
  return chrome;
}

function validateLayerContract(layers) {
  if (layers.length !== expectedLayers.length) {
    fail(`template2a must contain exactly ${expectedLayers.length} layers.`);
  }

  for (let index = 0; index < expectedLayers.length; index += 1) {
    const layer = layers[index];
    const expected = expectedLayers[index];
    for (const [field, value] of Object.entries(expected)) {
      if (layer[field] !== value) {
        fail(
          `template2a layer ${index} must have ${field}=${JSON.stringify(value)}; ` +
            `received ${JSON.stringify(layer[field])}.`,
        );
      }
    }

    const expectedLayerShadows = expectedShadows.get(layer.layerId);
    if (!expectedLayerShadows) {
      if (layer.shadows !== undefined &&
          (!Array.isArray(layer.shadows) || layer.shadows.length > 0)) {
        fail(`${layer.layerId} must not declare shadows.`);
      }
      continue;
    }
    if (!Array.isArray(layer.shadows)) {
      fail(`${layer.layerId} must declare its runtime shadow array.`);
    }

    const normalizedShadows = layer.shadows.map((shadow, shadowIndex) => {
      if (!shadow || typeof shadow !== "object" || Array.isArray(shadow)) {
        fail(`${layer.layerId} shadow ${shadowIndex} must be an object.`);
      }
      const fields = Object.keys(shadow).sort();
      const expectedFields = ["blur", "color", "dx", "dy", "kind"];
      if (JSON.stringify(fields) !== JSON.stringify(expectedFields)) {
        fail(
          `${layer.layerId} shadow ${shadowIndex} must contain exactly ` +
            `${expectedFields.join(", ")}.`,
        );
      }
      if (shadow.kind !== "dropShadow" ||
          !Number.isFinite(shadow.dx) ||
          !Number.isFinite(shadow.dy) ||
          !Number.isFinite(shadow.blur) ||
          shadow.blur < 0 ||
          typeof shadow.color !== "string") {
        fail(`${layer.layerId} shadow ${shadowIndex} has invalid values.`);
      }
      const color = shadow.color.replace(/\s+/g, "");
      if (!/^rgba\(\d{1,3},\d{1,3},\d{1,3},(?:0(?:\.\d+)?|1(?:\.0+)?)\)$/.test(color)) {
        fail(`${layer.layerId} shadow ${shadowIndex} must use an rgba color.`);
      }
      return { ...shadow, color };
    });
    if (JSON.stringify(normalizedShadows) !== JSON.stringify(expectedLayerShadows)) {
      fail(`${layer.layerId} shadows differ from the approved template.`);
    }
  }
}

function readManifest(source) {
  const match = source.match(
    /<script id="asset-manifest" type="application\/json">([\s\S]*?)<\/script>/,
  );
  if (!match) fail("The source does not contain #asset-manifest.");

  const manifest = JSON.parse(match[1]);
  if (!Array.isArray(manifest.assets)) {
    fail("The manifest does not contain an asset list.");
  }
  const assetIds = manifest.assets.map((asset) => asset.id);
  if (JSON.stringify(assetIds) !== JSON.stringify(requiredAssetIds)) {
    fail(
      "The manifest asset IDs or order changed. Expected: " +
        requiredAssetIds.join(", "),
    );
  }
  for (const asset of manifest.assets) {
    if (!Number.isInteger(asset.width) ||
        !Number.isInteger(asset.height) ||
        asset.width <= 0 ||
        asset.height <= 0) {
      fail(`${asset.id} has invalid dimensions.`);
    }
  }
  if (manifest.template2a?.canvas?.width !== 1080 ||
      manifest.template2a?.canvas?.height !== 1920) {
    fail("template2a must use a 1080x1920 canvas.");
  }

  const assetsById = new Map(manifest.assets.map((asset) => [asset.id, asset]));
  for (const [assetId, dimensions] of Object.entries({
    "coffee-ring": [192, 192],
    "sun-streak": [1080, 1920],
    vignette: [1080, 1920],
  })) {
    const asset = assetsById.get(assetId);
    if (asset.width !== dimensions[0] || asset.height !== dimensions[1]) {
      fail(`${assetId} must be ${dimensions[0]}x${dimensions[1]}.`);
    }
  }
  const shadowSchema = manifest.template2a?.shadowSchema;
  if (shadowSchema?.kind !== "dropShadow" ||
      !/canvas pixels/i.test(shadowSchema?.units ?? "") ||
      !/rotated layer silhouette/i.test(shadowSchema?.application ?? "")) {
    fail("template2a must document the runtime drop-shadow coordinate contract.");
  }
  const layers = manifest.template2a?.layers;
  if (!Array.isArray(layers) || layers.length === 0) {
    fail("template2a must contain layers.");
  }
  validateLayerContract(layers);
  const layerIds = layers.map((layer) => layer.layerId);
  if (new Set(layerIds).size !== layerIds.length) {
    fail("template2a contains duplicate layer IDs.");
  }
  for (const layer of layers) {
    if (!assetsById.has(layer.asset)) {
      fail(`${layer.layerId} references unknown asset ${layer.asset}.`);
    }
  }
  const layersById = new Map(layers.map((layer) => [layer.layerId, layer]));
  const photoLayouts = manifest.template2a?.photoLayouts;
  if (JSON.stringify(photoLayouts) !== JSON.stringify(expectedPhotoLayouts)) {
    fail("template2a must preserve the approved six/seven photo layouts.");
  }
  for (const layout of photoLayouts) {
    if (layout.photoSlots.length !== layout.photoCount) {
      fail(`The ${layout.photoCount}-photo layout has the wrong slot count.`);
    }
    const slotNumbers = layout.photoSlots.map((slot) => slot.slot).sort();
    if (slotNumbers.some((slot, index) => slot !== index)) {
      fail(`The ${layout.photoCount}-photo layout slots must be contiguous.`);
    }
    const targets = new Set();
    for (const slot of layout.photoSlots) {
      const target = `${slot.layerId}:${slot.windowIndex}`;
      if (targets.has(target)) {
        fail(`The ${layout.photoCount}-photo layout repeats ${target}.`);
      }
      targets.add(target);
      const layer = layersById.get(slot.layerId);
      const assetId = layout.assetOverrides?.[slot.layerId] ?? layer?.asset;
      const asset = assetId && assetsById.get(assetId);
      if (!asset?.photoWindows?.[slot.windowIndex]) {
        fail(
          `Photo slot ${slot.slot} in the ${layout.photoCount}-photo layout ` +
            "references a missing window.",
        );
      }
    }
    for (const [layerId, assetId] of Object.entries(layout.assetOverrides)) {
      if (!layersById.has(layerId) || !assetsById.has(assetId)) {
        fail(
          `The ${layout.photoCount}-photo layout has an invalid asset override ` +
            `${layerId}:${assetId}.`,
        );
      }
    }
  }

  const omittedDecor = JSON.stringify(
    manifest.template2a?.omittedDecor ?? "",
  ).toLowerCase().replaceAll("-", " ");
  for (const restoredAsset of ["coffee ring", "sun streak", "vignette"]) {
    if (omittedDecor.includes(restoredAsset)) {
      fail(`omittedDecor must not name restored asset ${restoredAsset}.`);
    }
  }
  const appRendered = JSON.stringify(
    manifest.template2a?.appRendered ?? "",
  );
  if (!/banner/i.test(appRendered) || !/(?:title|text)/i.test(appRendered)) {
    fail("template2a appRendered metadata must assign the banner title to the app.");
  }
  if (JSON.stringify(manifest.template2a?.titleStyle) !==
      JSON.stringify(expectedTitleStyle)) {
    fail("template2a titleStyle differs from the approved Lora title contract.");
  }
  return manifest;
}

function dimensionsAtScale(asset, numerator) {
  if (asset.width % 3 !== 0 || asset.height % 3 !== 0) {
    fail(`${asset.id} dimensions must be divisible by three.`);
  }
  return {
    width: (asset.width / 3) * numerator,
    height: (asset.height / 3) * numerator,
  };
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

async function validatePng(sharp, path, asset, numerator) {
  const expected = dimensionsAtScale(asset, numerator);
  const metadata = await sharp(path).metadata();
  if (metadata.width !== expected.width || metadata.height !== expected.height) {
    fail(
      `${path} is ${metadata.width}x${metadata.height}; expected ` +
        `${expected.width}x${expected.height}.`,
    );
  }
  if (!metadata.hasAlpha && asset.opaque !== true) {
    fail(`${path} does not contain an alpha channel.`);
  }

  const alpha = await alphaRange(sharp, path);
  if (asset.opaque === true) {
    if (alpha.minimum !== 255 || alpha.maximum !== 255) {
      fail(`${path} is marked opaque but contains transparent pixels.`);
    }
  } else if (translucentOverlayIds.has(asset.id)) {
    const mustReachTransparent = asset.id !== "grain-overlay";
    if ((mustReachTransparent && alpha.minimum > 1) ||
        alpha.maximum >= 255 || alpha.maximum === 0) {
      fail(`${path} must contain transparent pixels and visible translucent art.`);
    }
  } else if (alpha.minimum >= 255 || alpha.maximum === 0) {
    fail(`${path} must contain visible art and transparency.`);
  }

  const windowAlpha = [];
  for (const window of asset.photoWindows ?? []) {
    const scale = numerator / 3;
    const inset = asset.id === "polaroid-frame"
      ? Math.max(1, Math.ceil(36 * scale))
      : 3;
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
    const pixels = (right - left) * (bottom - top);
    const nonzeroFraction = nonzero / pixels;
    if (
      asset.id === "polaroid-frame" &&
      (nonzeroFraction > 0.31 || maximum > 105)
    ) {
      fail(`${path} polaroid seam is wider or darker than the approved art.`);
    }
    windowAlpha.push({ nonzeroFraction, maximum, clearInset: inset });
  }

  // The approved strip ends in plain rust leader. A prior source revision left
  // an opaque, near-black fourth frame here even though only three windows were
  // declared, so keep a targeted regression check on the leader's center.
  if (asset.id === "film-strip") {
    const x = Math.floor(alpha.info.width * 0.5);
    const y = Math.floor(alpha.info.height * 0.78);
    const index = (y * alpha.info.width + x) * alpha.info.channels;
    const red = alpha.data[index];
    const green = alpha.data[index + 1];
    const blue = alpha.data[index + 2];
    const pixelAlpha = alpha.data[index + 3];
    const luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    if (pixelAlpha < 200 || luminance < 55) {
      fail(`${path} still contains a dark fourth film frame.`);
    }
  }

  return {
    width: metadata.width,
    height: metadata.height,
    alpha: [alpha.minimum, alpha.maximum],
    windowAlpha,
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

async function renderAsset(page, asset) {
  const sourceAssetId = asset.id === "film-strip-four"
    ? "film-strip"
    : asset.id;
  const url = new URL(pathToFileURL(sourcePath));
  url.searchParams.set("exportAsset", sourceAssetId);
  await page.goto(url.href, { waitUntil: "load" });
  await page.waitForFunction(
    (assetId) => document.querySelector(`[data-export-asset="${assetId}"]`),
    sourceAssetId,
  );
  if (asset.id === "film-strip" || asset.id === "film-strip-four") {
    await page.evaluate(
      ({ sourceAssetId, outputAssetId, fourFrames }) => {
        const root = document.querySelector(
          `[data-export-asset="${sourceAssetId}"]`,
        );
        const surface = root?.firstElementChild?.firstElementChild;
        const filmRow = surface?.firstElementChild;
        const centerColumn = filmRow?.children?.[1];
        if (!root || !surface || !centerColumn) {
          throw new Error("Unable to locate the authored film-strip structure.");
        }

        const sizes = fourFrames
          ? [
              "100% 23px",
              "100% 22px",
              "100% 22px",
              "100% 22px",
              "100% 87px",
              "19px 100%",
              "19px 100%",
            ]
          : [
              "100% 87px",
              "100% 22px",
              "100% 22px",
              "100% 151px",
              "19px 100%",
              "19px 100%",
            ];
        const positions = fourFrames
          ? [
              "0 0",
              "0 129px",
              "0 257px",
              "0 385px",
              "0 513px",
              "0 0",
              "100% 0",
            ]
          : [
              "0 0",
              "0 193px",
              "0 321px",
              "0 449px",
              "0 0",
              "100% 0",
            ];
        const maskImages = sizes.map(() => "linear-gradient(#000,#000)");
        surface.style.maskImage = maskImages.join(",");
        surface.style.maskSize = sizes.join(",");
        surface.style.maskPosition = positions.join(",");
        surface.style.maskRepeat = "no-repeat";
        surface.style.webkitMaskImage = maskImages.join(",");
        surface.style.webkitMaskSize = sizes.join(",");
        surface.style.webkitMaskPosition = positions.join(",");
        surface.style.webkitMaskRepeat = "no-repeat";
        centerColumn.style.paddingTop = fourFrames ? "7px" : "71px";

        const frames = [...centerColumn.children].filter(
          (child) => child.style.width === "92px" &&
            child.style.height === "106px",
        );
        if (frames.length !== 3) {
          throw new Error(`Expected three authored film frames, got ${frames.length}.`);
        }
        if (fourFrames) {
          centerColumn.append(frames.at(-1).cloneNode(true));
        }
        root.dataset.exportAsset = outputAssetId;
      },
      {
        sourceAssetId,
        outputAssetId: asset.id,
        fourFrames: asset.id === "film-strip-four",
      },
    );
  }
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
    const titleFontLoaded = await page.evaluate(async () => {
      const faces = await document.fonts.load("600 45px Lora", "DECEMBER");
      return faces.some((face) =>
        face.family.replaceAll(/["']/g, "") === "Lora" &&
        face.status === "loaded"
      );
    });
    if (!titleFontLoaded) {
      fail("The approved Lora title font did not load in the design preview.");
    }
  }

  const locator = page.locator(`[data-export-asset="${asset.id}"]`);
  if (await locator.count() !== 1) {
    fail(`${asset.id} must render exactly one isolated export root.`);
  }
  const box = await locator.boundingBox();
  if (!box ||
      Math.abs(box.x) > 0.01 ||
      Math.abs(box.y) > 0.01 ||
      Math.abs(box.width - asset.width) > 0.01 ||
      Math.abs(box.height - asset.height) > 0.01) {
    fail(`${asset.id} rendered with unexpected bounds: ${JSON.stringify(box)}.`);
  }
  return locator.screenshot({
    type: "png",
    omitBackground: true,
    animations: "disabled",
    scale: "css",
  });
}

async function main() {
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
  await verifySource(
    titleFontPath,
    expectedTitleFontHashes["Lora-SemiBold.ttf"],
  );
  await verifySource(
    titleFontLicensePath,
    expectedTitleFontHashes["Lora-OFL.txt"],
  );
  const offlineRuntime = await loadOfflineRuntime();
  const manifest = readManifest(source.bytes.toString("utf8"));
  const { chromium } = loadDependency(
    "playwright",
    process.env.PLAYWRIGHT_MODULE,
  );
  const sharp = loadDependency("sharp", process.env.SHARP_MODULE);

  await mkdir(join(outputDirectory, "2.0x"), { recursive: true });
  await mkdir(join(outputDirectory, "3.0x"), { recursive: true });
  await validateNoStalePngs(manifest);
  await writeFile(
    join(outputDirectory, "manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );

  const browser = await chromium.launch({
    headless: true,
    executablePath: findChrome(),
  });
  const pageErrors = [];
  try {
    const page = await browser.newPage({
      viewport: { width: 1200, height: 2000 },
      deviceScaleFactor: 1,
    });
    page.on("pageerror", (error) => pageErrors.push(error.message));
    await page.route("**/*", async (route) => {
      const url = route.request().url();
      const runtime = offlineRuntime.get(url);
      if (runtime) {
        await route.fulfill({
          status: 200,
          body: runtime.body,
          headers: {
            "content-type": "application/javascript; charset=utf-8",
            "access-control-allow-origin": "*",
          },
        });
      } else if (url.startsWith("http://") || url.startsWith("https://")) {
        await route.abort("blockedbyclient");
      } else {
        await route.continue();
      }
    });

    const results = [];
    for (const asset of manifest.assets) {
      const captured = await renderAsset(page, asset);
      const basePath = join(outputDirectory, `${asset.id}.png`);
      const twoPath = join(outputDirectory, "2.0x", `${asset.id}.png`);
      const threePath = join(outputDirectory, "3.0x", `${asset.id}.png`);
      const base = dimensionsAtScale(asset, 1);
      const two = dimensionsAtScale(asset, 2);

      await sharp(captured)
        .resize(base.width, base.height, { kernel: "lanczos3" })
        .ensureAlpha()
        .png(pngOptions(asset))
        .toFile(basePath);
      await sharp(captured)
        .resize(two.width, two.height, { kernel: "lanczos3" })
        .ensureAlpha()
        .png(pngOptions(asset))
        .toFile(twoPath);
      await sharp(captured)
        .ensureAlpha()
        .png(pngOptions(asset))
        .toFile(threePath);

      results.push({
        id: asset.id,
        "1x": await validatePng(sharp, basePath, asset, 1),
        "2x": await validatePng(sharp, twoPath, asset, 2),
        "3x": await validatePng(sharp, threePath, asset, 3),
      });
      console.log(`exported ${asset.id}`);
    }

    if (pageErrors.length > 0) {
      fail(`The design source raised page errors: ${pageErrors.join(" | ")}`);
    }
    console.log(
      JSON.stringify(
        {
          assets: results.length,
          variants: results.length * 3,
          outputDirectory,
          sourceSha256: source.actualHash,
          supportSha256: support.actualHash,
          offlineRuntime: [...offlineRuntime.values()].map(
            ({ file, sha384 }) => ({ file, sha384 }),
          ),
        },
        null,
        2,
      ),
    );
  } finally {
    await browser.close();
  }
}

await main();
