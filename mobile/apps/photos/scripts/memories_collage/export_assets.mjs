#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import {
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const appDirectory = resolve(scriptDirectory, "..", "..");
const runtimeAssetDirectory = join(appDirectory, "assets", "memories_collage");
const runtimeRasterDirectory = join(runtimeAssetDirectory, "3.0x");
const runtimeManifestPath = join(runtimeAssetDirectory, "manifest.json");
const sourcePath = resolve(
  process.env.COLLAGE_SOURCE ?? join(scriptDirectory, "Memory Collage.dc.html"),
);
const supportPath = join(dirname(sourcePath), "support.js");
const provenancePath = join(scriptDirectory, "plate_provenance.json");
const vendorDirectory = join(scriptDirectory, "vendor");
const ingredientSourceDirectory = join(scriptDirectory, "source_assets");

const expectedSourceHashes = {
  "Memory Collage.dc.html":
    "54a02ed673afbc920f37bde50fb9d391c0cdeab144d44c1283c93710b4b1623f",
  "support.js":
    "8fe7df74405f3c55f49b7249c74ea1397e65d07dea2b1bd3b4a489bec2e28cbe",
};
const templateIDs = [
  "scrapbook-maximal",
  "calm-classic",
  "calm-film-trio",
  "calm-accent-print",
  "minimal-classic",
  "minimal-rows",
  "minimal-grid",
];
const backgroundIDs = [
  "paper-washi",
  "paper-cream-fiber",
  "paper-blush-stripe",
  "paper-sage-stripe",
  "paper-terracotta-mottle",
  "editorial-sand",
  "editorial-sage",
];
const finishAssetIDs = ["sun-streak", "vignette", "grain-overlay"];
const ingredientAssetIDs = [
  "paper-torn",
  "polaroid-frame",
  "film-strip-four",
  "banner-wide",
  "tape-mustard",
  "tape-blush",
  "tape-sage",
  "stamp-postmark",
  "star",
  "fern",
  "coffee-ring",
  "film-strip-four-horizontal",
  "film-strip-three-horizontal",
  "print-frame-hero",
];
const plateIDs = templateIDs.map((id) => `layout-${id}`);
const runtimeRasterIDs = [...backgroundIDs, ...finishAssetIDs, ...plateIDs];
const backingColors = new Map([
  ["polaroid-frame", "#E7E1D4"],
  ["print-frame-hero", "#E7E1D4"],
  ["film-strip-four", "#7B4A32"],
  ["film-strip-four-horizontal", "#7A5B41"],
  ["film-strip-three-horizontal", "#7A5B41"],
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

function sha384Base64(bytes) {
  return createHash("sha384").update(bytes).digest("base64");
}

function round(value) {
  const rounded = Math.round(value * 1_000_000) / 1_000_000;
  return Object.is(rounded, -0) ? 0 : rounded;
}

function assertKeys(value, expected, path) {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) {
    fail(`${path} keys are ${actual.join(", ")}; expected ${wanted.join(", ")}.`);
  }
}

async function verifyPinnedFile(path, expectedHash) {
  const bytes = await readFile(path);
  const actualHash = sha256(bytes);
  if (actualHash !== expectedHash) {
    fail(`${basename(path)} hash changed: ${actualHash}.`);
  }
  return bytes;
}

function readAuthoringManifest(source) {
  const match = source.match(
    /<script id="asset-manifest" type="application\/json">([\s\S]*?)<\/script>/,
  );
  if (!match) fail("The design source has no #asset-manifest.");
  const manifest = JSON.parse(match[1]);
  if (
    manifest.version !== 2 ||
    manifest.canvas?.width !== 1080 ||
    manifest.canvas?.height !== 1920 ||
    manifest.photoCount !== 7 ||
    manifest.defaultTemplateId !== "calm-film-trio" ||
    JSON.stringify(Object.keys(manifest.templates ?? {})) !==
      JSON.stringify(templateIDs)
  ) {
    fail("The frozen v2 authoring contract changed.");
  }
  return manifest;
}

function rotatePoint(x, y, centerX, centerY, degrees) {
  const angle = (degrees * Math.PI) / 180;
  const dx = x - centerX;
  const dy = y - centerY;
  return {
    x: centerX + dx * Math.cos(angle) - dy * Math.sin(angle),
    y: centerY + dx * Math.sin(angle) + dy * Math.cos(angle),
  };
}

function normalizeAssetWindowSlot(slot, template, assetsByID) {
  const layer = template.layers.find((entry) => entry.layerId === slot.layerId);
  if (!layer) fail(`${template.id} slot ${slot.slot} has no layer.`);
  const asset = assetsByID.get(layer.asset);
  const window = asset?.photoWindows?.[slot.windowIndex];
  if (!window) fail(`${template.id} slot ${slot.slot} has no photo window.`);
  const width = (window.width / asset.width) * layer.width;
  const height = (window.height / asset.height) * layer.height;
  const center = rotatePoint(
    layer.x + ((window.x + window.width / 2) / asset.width) * layer.width,
    layer.y + ((window.y + window.height / 2) / asset.height) * layer.height,
    layer.x + layer.width / 2,
    layer.y + layer.height / 2,
    layer.rotation ?? 0,
  );
  const backingColor = backingColors.get(layer.asset);
  if (!backingColor) fail(`${layer.asset} has no approved backing color.`);
  return {
    slot: slot.slot,
    x: round(center.x - width / 2),
    y: round(center.y - height / 2),
    width: round(width),
    height: round(height),
    z: layer.z,
    rotation: layer.rotation ?? 0,
    backingColor,
  };
}

function normalizeMattedSlot(slot) {
  const rect = slot.rect;
  const mat = slot.mat;
  const rotation = slot.rotation ?? 0;
  const center = rotatePoint(
    rect.x + rect.width / 2,
    rect.y + rect.height / 2,
    mat.x + mat.width / 2,
    mat.y + mat.height / 2,
    rotation,
  );
  return {
    slot: slot.slot,
    x: round(center.x - rect.width / 2),
    y: round(center.y - rect.height / 2),
    width: rect.width,
    height: rect.height,
    z: slot.z ?? 4,
    rotation,
    backingColor: "#E7E1D4",
  };
}

function normalizeTitle(source) {
  const family = source.fontFamily.split(",")[0].trim().replace(/^['"]|['"]$/g, "");
  const title = {
    ...source.box,
    rotation: source.rotation ?? 0,
    fontFamily: family,
    fontWeight: source.fontWeight,
    fontSize: source.fontSize,
    minFontSize: source.minFontSize ?? 27,
    lineHeight: source.lineHeight ?? 1,
    maxLines: source.maxLines ?? 1,
    letterSpacing: source.letterSpacing,
    color: source.color,
    textAlign: source.textAlign ?? source.align,
    verticalAlign:
      (source.verticalAlign ?? source.vAlign) === "middle"
        ? "center"
        : source.verticalAlign ?? source.vAlign,
  };
  if (source.shadow && source.shadow.color !== "rgba(0,0,0,0)") {
    title.shadow = source.shadow;
  }
  return title;
}

function buildRuntimeManifest(source) {
  const assetsByID = new Map(source.assets.map((asset) => [asset.id, asset]));
  const backgrounds = backgroundIDs.map((id) => {
    const asset = assetsByID.get(id);
    if (!asset || asset.width !== 1080 || asset.height !== 1920) {
      fail(`Background ${id} must remain 1080x1920.`);
    }
    return { id, width: asset.width, height: asset.height };
  });
  return {
    version: 3,
    canvas: { width: 1080, height: 1920 },
    backgrounds: { assets: backgrounds },
    defaultTemplateId: source.defaultTemplateId,
    templates: templateIDs.map((id) => {
      const template = source.templates[id];
      const minimal = id.startsWith("minimal-");
      return {
        id,
        defaultBackgroundAssetId: template.defaultBackgroundId,
        plateAssetId: `layout-${id}`,
        finishPreset: id === "scrapbook-maximal" ? "scrapbook" : minimal ? "minimal" : "calm",
        photoSlots: template.photoSlots.map((slot) =>
          slot.kind === "mattedRect"
            ? normalizeMattedSlot(slot)
            : normalizeAssetWindowSlot(slot, template, assetsByID),
        ),
        title: normalizeTitle(template.titleStyle),
      };
    }),
  };
}

function validateRuntimeManifest(manifest) {
  assertKeys(
    manifest,
    ["version", "canvas", "backgrounds", "defaultTemplateId", "templates"],
    "manifest",
  );
  if (manifest.version !== 3 || manifest.defaultTemplateId !== "calm-film-trio") {
    fail("The runtime manifest must retain v3 and calm-film-trio as the default template.");
  }
  assertKeys(manifest.canvas, ["width", "height"], "canvas");
  assertKeys(manifest.backgrounds, ["assets"], "backgrounds");
  if (
    manifest.canvas.width !== 1080 ||
    manifest.canvas.height !== 1920 ||
    JSON.stringify(manifest.backgrounds.assets.map((asset) => asset.id)) !==
      JSON.stringify(backgroundIDs) ||
    JSON.stringify(manifest.templates.map((template) => template.id)) !==
      JSON.stringify(templateIDs)
  ) {
    fail("The runtime template/background order changed.");
  }
  for (const background of manifest.backgrounds.assets) {
    assertKeys(background, ["id", "width", "height"], `background ${background.id}`);
  }
  for (const template of manifest.templates) {
    assertKeys(
      template,
      [
        "id",
        "defaultBackgroundAssetId",
        "plateAssetId",
        "finishPreset",
        "photoSlots",
        "title",
      ],
      `template ${template.id}`,
    );
    if (!backgroundIDs.includes(template.defaultBackgroundAssetId)) {
      fail(`${template.id} has an unknown default background.`);
    }
    if (template.plateAssetId !== `layout-${template.id}`) {
      fail(`${template.id} has an unexpected plate ID.`);
    }
    if (template.photoSlots.length !== 7) fail(`${template.id} must have seven slots.`);
    for (const [index, slot] of template.photoSlots.entries()) {
      assertKeys(
        slot,
        ["slot", "x", "y", "width", "height", "z", "rotation", "backingColor"],
        `${template.id} slot ${index}`,
      );
      if (
        slot.slot !== index ||
        !Number.isFinite(slot.x) ||
        !Number.isFinite(slot.y) ||
        !Number.isFinite(slot.width) ||
        !Number.isFinite(slot.height) ||
        slot.width <= 0 ||
        slot.height <= 0
      ) {
        fail(`${template.id} slot ${index} is invalid.`);
      }
    }
    const titleKeys = [
      "x",
      "y",
      "width",
      "height",
      "rotation",
      "fontFamily",
      "fontWeight",
      "fontSize",
      "minFontSize",
      "lineHeight",
      "maxLines",
      "letterSpacing",
      "color",
      "textAlign",
      "verticalAlign",
      ...(template.title.shadow ? ["shadow"] : []),
    ];
    assertKeys(template.title, titleKeys, `${template.id} title`);
  }
}

function loadDependency(name, explicitPath) {
  const candidates = [
    explicitPath,
    name,
    `/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/${name}`,
  ].filter(Boolean);
  let lastError;
  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch (error) {
      lastError = error;
    }
  }
  fail(`Could not load ${name}: ${lastError?.message}`);
}

function findChrome() {
  const candidates = [
    process.env.CHROME_BINARY,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
  ].filter(Boolean);
  const chrome = candidates.find(existsSync);
  if (!chrome) fail("Chrome/Chromium was not found; set CHROME_BINARY.");
  return chrome;
}

async function loadOfflineRuntime() {
  const result = new Map();
  for (const spec of offlineRuntimeScripts) {
    const body = await readFile(join(vendorDirectory, spec.file));
    if (sha384Base64(body) !== spec.sha384) {
      fail(`Vendored runtime hash mismatch for ${spec.file}.`);
    }
    result.set(spec.url, body);
  }
  return result;
}

async function renderIngredients(directory, source) {
  const assetsByID = new Map(source.assets.map((asset) => [asset.id, asset]));
  const offlineRuntime = await loadOfflineRuntime();
  const { chromium } = loadDependency("playwright", process.env.PLAYWRIGHT_MODULE);
  const browser = await chromium.launch({ headless: true, executablePath: findChrome() });
  const errors = [];
  try {
    const page = await browser.newPage({
      viewport: { width: 1200, height: 2000 },
      deviceScaleFactor: 1,
    });
    page.on("pageerror", (error) => errors.push(error.message));
    await page.route("**/*", async (route) => {
      const requestURL = route.request().url();
      const runtime = offlineRuntime.get(requestURL);
      if (runtime) {
        await route.fulfill({
          status: 200,
          body: runtime,
          headers: {
            "content-type": "application/javascript; charset=utf-8",
            "access-control-allow-origin": "*",
          },
        });
      } else if (requestURL.startsWith("http://") || requestURL.startsWith("https://")) {
        await route.abort("blockedbyclient");
      } else {
        await route.continue();
      }
    });
    for (const id of ingredientAssetIDs) {
      const asset = assetsByID.get(id);
      const url = new URL(pathToFileURL(sourcePath));
      url.searchParams.set("exportAsset", id);
      await page.goto(url.href, { waitUntil: "load" });
      await page.waitForFunction(
        (assetID) => document.querySelector(`[data-export-asset="${assetID}"]`),
        id,
      );
      await page.evaluate(async () => {
        await document.fonts.ready;
        await Promise.all([...document.images].map((image) => image.decode().catch(() => {})));
        await new Promise((resolveFrame) =>
          requestAnimationFrame(() => requestAnimationFrame(resolveFrame)),
        );
      });
      const locator = page.locator(`[data-export-asset="${id}"]`);
      const box = await locator.boundingBox();
      if (
        !box ||
        Math.abs(box.x) > 0.01 ||
        Math.abs(box.y) > 0.01 ||
        Math.abs(box.width - asset.width) > 0.01 ||
        Math.abs(box.height - asset.height) > 0.01
      ) {
        fail(`${id} rendered at unexpected bounds ${JSON.stringify(box)}.`);
      }
      await locator.screenshot({
        path: join(directory, `${id}.png`),
        type: "png",
        omitBackground: true,
        animations: "disabled",
        scale: "css",
      });
    }
    if (errors.length) fail(`Design source errors: ${errors.join(" | ")}`);
  } finally {
    await browser.close();
  }
}

async function ingredientInventoryDigest(directory) {
  let inventory = "";
  const actualNames = (await readdir(directory))
    .filter((name) => name.endsWith(".png"))
    .sort();
  const expectedNames = ingredientAssetIDs.map((id) => `${id}.png`).sort();
  if (JSON.stringify(actualNames) !== JSON.stringify(expectedNames)) {
    fail("The pinned authoring ingredient inventory changed.");
  }
  for (const id of ingredientAssetIDs) {
    inventory += `${id}.png:${sha256(
      await readFile(join(directory, `${id}.png`)),
    )}\n`;
  }
  return sha256(inventory);
}

async function encodedInventoryDigest(directory, ids) {
  let inventory = "";
  for (const id of ids) {
    inventory += `${id}.png:${sha256(
      await readFile(join(directory, `${id}.png`)),
    )}\n`;
  }
  return sha256(inventory);
}

async function runPlateExporter(ingredientDirectory, outputDirectory) {
  const flutter = process.env.FLUTTER_BINARY ?? "flutter";
  const result = spawnSync(
    flutter,
    ["test", "scripts/memories_collage/export_plates_test.dart", "--no-pub"],
    {
      cwd: appDirectory,
      stdio: "inherit",
      env: {
        ...process.env,
        COLLAGE_SOURCE: sourcePath,
        COLLAGE_INGREDIENT_DIRECTORY: ingredientDirectory,
        COLLAGE_PLATE_OUTPUT: outputDirectory,
      },
    },
  );
  if (result.error) fail(`Could not run Flutter plate exporter: ${result.error.message}`);
  if (result.status !== 0) fail(`Flutter plate exporter exited ${result.status}.`);
}

async function decodedRGBA(sharp, path) {
  const { data, info } = await sharp(path)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  return { data, info };
}

async function optimizePlate(sharp, source, target) {
  const before = await decodedRGBA(sharp, source);
  await sharp(source)
    .png({ compressionLevel: 9, adaptiveFiltering: true, force: true })
    .toFile(target);
  const after = await decodedRGBA(sharp, target);
  if (!before.data.equals(after.data)) {
    fail(`${basename(source)} changed decoded pixels during optimization.`);
  }
}

async function validateRaster(sharp, path, { opaque, rawHash, encodedHash } = {}) {
  const bytes = await readFile(path);
  if (encodedHash && sha256(bytes) !== encodedHash) {
    fail(`${basename(path)} encoded hash changed.`);
  }
  const { data, info } = await decodedRGBA(sharp, path);
  if (info.width !== 1080 || info.height !== 1920) {
    fail(`${basename(path)} is ${info.width}x${info.height}; expected 1080x1920.`);
  }
  let minimumAlpha = 255;
  let maximumAlpha = 0;
  for (let index = 3; index < data.length; index += 4) {
    minimumAlpha = Math.min(minimumAlpha, data[index]);
    maximumAlpha = Math.max(maximumAlpha, data[index]);
  }
  if (opaque ? minimumAlpha !== 255 : minimumAlpha === 255 || maximumAlpha === 0) {
    fail(`${basename(path)} has an invalid alpha range ${minimumAlpha}-${maximumAlpha}.`);
  }
  if (rawHash && sha256(data) !== rawHash) {
    fail(`${basename(path)} decoded RGBA hash changed.`);
  }
  return { bytes: bytes.length, rawSha256: sha256(data), encodedSha256: sha256(bytes) };
}

async function validateRuntimeAssets(sharp, manifest, provenance, root) {
  const names = (await readdir(root))
    .filter((name) => name.endsWith(".png"))
    .sort();
  const expectedNames = runtimeRasterIDs.map((id) => `${id}.png`).sort();
  if (JSON.stringify(names) !== JSON.stringify(expectedNames)) {
    fail(`Runtime PNG inventory is ${names.join(", ")}; expected ${expectedNames.join(", ")}.`);
  }
  const plateProvenance = new Map(
    provenance.plates.map((plate) => [plate.id, plate]),
  );
  const results = [];
  for (const id of runtimeRasterIDs) {
    const record = plateProvenance.get(id);
    results.push({
      id,
      ...(await validateRaster(sharp, join(root, `${id}.png`), {
        opaque: backgroundIDs.includes(id),
        rawHash: record?.decodedRgbaSha256,
        encodedHash: record?.encodedSha256,
      })),
    });
  }
  for (const template of manifest.templates) {
    const { data, info } = await decodedRGBA(
      sharp,
      join(root, `${template.plateAssetId}.png`),
    );
    for (const slot of template.photoSlots) {
      const x = Math.max(0, Math.min(info.width - 1, Math.round(slot.x + slot.width / 2)));
      const y = Math.max(0, Math.min(info.height - 1, Math.round(slot.y + slot.height / 2)));
      if (data[(y * info.width + x) * 4 + 3] !== 0) {
        fail(`${template.id} plate is not transparent at slot ${slot.slot} center.`);
      }
    }
  }
  return results;
}

async function assertScaleInventories() {
  const expected = [...backgroundIDs, ...finishAssetIDs]
    .map((id) => `${id}.png`)
    .sort();
  for (const variant of ["", "2.0x"]) {
    const directory = join(runtimeAssetDirectory, variant);
    const names = (await readdir(directory))
      .filter((name) => name.endsWith(".png"))
      .sort();
    if (JSON.stringify(names) !== JSON.stringify(expected)) {
      fail(`${variant || "base"} authoring PNG inventory still contains obsolete assets.`);
    }
  }
}

async function main() {
  const sourceBytes = await verifyPinnedFile(
    sourcePath,
    expectedSourceHashes["Memory Collage.dc.html"],
  );
  await verifyPinnedFile(supportPath, expectedSourceHashes["support.js"]);
  const authoringManifest = readAuthoringManifest(sourceBytes.toString("utf8"));
  const generatedManifest = buildRuntimeManifest(authoringManifest);
  validateRuntimeManifest(generatedManifest);
  const provenance = JSON.parse(await readFile(provenancePath, "utf8"));
  const sharp = loadDependency("sharp", process.env.SHARP_MODULE);
  const ingredientDigest = await ingredientInventoryDigest(
    ingredientSourceDirectory,
  );
  if (ingredientDigest !== provenance.authoringIngredients.inventorySha256) {
    fail(`Authoring ingredient inventory changed: ${ingredientDigest}.`);
  }
  const runtimeInputDigest = await encodedInventoryDigest(
    runtimeRasterDirectory,
    [...backgroundIDs, ...finishAssetIDs],
  );
  if (runtimeInputDigest !== provenance.runtimeInputs.inventorySha256) {
    fail(`Runtime background/effect inventory changed: ${runtimeInputDigest}.`);
  }

  const output = process.env.COLLAGE_OUTPUT
    ? resolve(process.env.COLLAGE_OUTPUT)
    : null;
  if (output && output === runtimeAssetDirectory) {
    fail("Export into staging; direct writes to the Flutter asset tree are refused.");
  }

  if (process.env.COLLAGE_REBUILD_PLATES === "1") {
    if (!output) fail("COLLAGE_REBUILD_PLATES=1 requires COLLAGE_OUTPUT.");
    await mkdir(output, { recursive: true });
    const refreshIngredients = process.env.COLLAGE_REFRESH_INGREDIENTS === "1";
    const ingredientDirectory = refreshIngredients
      ? await mkdtemp(join(tmpdir(), "collage-ingredients-"))
      : ingredientSourceDirectory;
    const rawPlateDirectory = await mkdtemp(join(tmpdir(), "collage-plates-"));
    try {
      if (refreshIngredients) {
        await renderIngredients(ingredientDirectory, authoringManifest);
      }
      await runPlateExporter(ingredientDirectory, rawPlateDirectory);
      for (const id of plateIDs) {
        await optimizePlate(
          sharp,
          join(rawPlateDirectory, `${id}.png`),
          join(output, `${id}.png`),
        );
      }
      for (const id of [...backgroundIDs, ...finishAssetIDs]) {
        await copyFile(join(runtimeRasterDirectory, `${id}.png`), join(output, `${id}.png`));
      }
      await writeFile(
        join(output, "manifest.json"),
        `${JSON.stringify(generatedManifest, null, 2)}\n`,
      );
    } finally {
      await Promise.all([
        ...(refreshIngredients
          ? [rm(ingredientDirectory, { recursive: true, force: true })]
          : []),
        rm(rawPlateDirectory, { recursive: true, force: true }),
      ]);
    }
    const results = await validateRuntimeAssets(
      sharp,
      generatedManifest,
      provenance,
      output,
    );
    console.log(JSON.stringify({ mode: "rebuild", output, assets: results }, null, 2));
    return;
  }

  const checkedInManifest = JSON.parse(await readFile(runtimeManifestPath, "utf8"));
  validateRuntimeManifest(checkedInManifest);
  if (JSON.stringify(checkedInManifest) !== JSON.stringify(generatedManifest)) {
    fail("Checked-in runtime manifest differs from the frozen authoring projection.");
  }
  await assertScaleInventories();
  const assets = await validateRuntimeAssets(
    sharp,
    checkedInManifest,
    provenance,
    runtimeRasterDirectory,
  );
  console.log(JSON.stringify({ mode: "verify", assets }, null, 2));
}

await main();
