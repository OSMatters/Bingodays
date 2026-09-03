#!/usr/bin/env node

import { createHash, createSign } from "node:crypto";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const POINTER_RECORD_TYPE = "BlindBoxCatalogPointer";
const POINTER_RECORD_NAME = "current";
const BUNDLE_FIELD = "bundle";
// CloudKit's upload-token endpoint caps an individual uploaded asset at 15 MB.
// The JSON bundle embeds PNG data as Base64, so enforce the limit against the
// final serialized payload rather than the original image file sizes.
const MAX_CLOUDKIT_ASSET_BYTES = 15 * 1024 * 1024;

async function main() {
  const options = readOptions(process.argv.slice(2));
  const inputPath = requireOption(options, "input");
  const artworkDirectory = requireOption(options, "artwork-dir");
  const outputPath = requireOption(options, "out");
  const shouldPublish = options.has("publish");

  const release = await readRelease(inputPath);
  const assetNames = validateRelease(release);
  const artworkFiles = await loadArtworkFiles(assetNames, artworkDirectory);
  const bundle = { release, artworkFiles };
  const bundleData = Buffer.from(JSON.stringify(bundle));
  assert(
    bundleData.byteLength <= MAX_CLOUDKIT_ASSET_BYTES,
    `Bundle is ${bundleData.byteLength} bytes; CloudKit assets are limited to 15 MB.`
  );

  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, bundleData);
  process.stdout.write(
    `Validated ${release.releaseID}: ${release.themes.length} themes, ${artworkFiles.length} PNG files, ${bundleData.byteLength} bytes.\n`
  );

  if (shouldPublish) {
    await publishBundle(bundleData, release);
  }
}

function readOptions(argv) {
  const options = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    assert(argument.startsWith("--"), `Unexpected argument: ${argument}`);
    const key = argument.slice(2);
    if (key === "publish") {
      options.set(key, true);
      continue;
    }
    const value = argv[index + 1];
    assert(value && !value.startsWith("--"), `Missing value for --${key}`);
    options.set(key, value);
    index += 1;
  }
  return options;
}

function requireOption(options, key) {
  const value = options.get(key);
  assert(typeof value === "string" && value.length > 0, `--${key} is required.`);
  return value;
}

async function readRelease(inputPath) {
  const data = await readFile(inputPath, "utf8");
  let release;
  try {
    release = JSON.parse(data);
  } catch {
    throw new Error("release.json is not valid JSON.");
  }
  if (typeof release.publishedAt === "string") {
    const timestamp = Date.parse(release.publishedAt);
    assert(Number.isFinite(timestamp), "publishedAt must be an ISO 8601 date or milliseconds.");
    release.publishedAt = timestamp / 1000;
  }
  return release;
}

function validateRelease(release) {
  assert(isObject(release), "Catalog release must be an object.");
  assert(isNonEmptyString(release.releaseID), "releaseID is required.");
  assert(Number.isInteger(release.catalogSchemaVersion) && release.catalogSchemaVersion > 0,
    "catalogSchemaVersion must be a positive integer.");
  assert(Number.isInteger(release.minimumAppBuild) && release.minimumAppBuild >= 0,
    "minimumAppBuild must be a non-negative integer.");
  assert(Number.isFinite(release.publishedAt), "publishedAt must be a Unix timestamp in seconds.");
  assert(Array.isArray(release.activeThemeIDs), "activeThemeIDs must be an array.");
  assert(Array.isArray(release.themes), "themes must be an array.");

  const themeIDs = new Set();
  const activeThemeIDs = new Set();
  const stickerIDs = new Set();
  const assetNames = new Set();

  for (const activeThemeID of release.activeThemeIDs) {
    assert(isIdentifier(activeThemeID?.rawValue), "Every activeThemeID.rawValue must be a safe identifier.");
    assert(!activeThemeIDs.has(activeThemeID.rawValue), `Duplicate active theme: ${activeThemeID.rawValue}`);
    activeThemeIDs.add(activeThemeID.rawValue);
  }

  for (const theme of release.themes) {
    assert(isObject(theme) && isIdentifier(theme.id?.rawValue), "Every theme needs a safe id.rawValue.");
    const themeID = theme.id.rawValue;
    assert(!themeIDs.has(themeID), `Duplicate theme: ${themeID}`);
    themeIDs.add(themeID);
    assert(Number.isInteger(theme.catalogVersion) && theme.catalogVersion > 0,
      `${themeID}.catalogVersion must be a positive integer.`);
    assert(Array.isArray(theme.stickers) && theme.stickers.length >= 2,
      `${themeID} needs at least one normal sticker and one hidden sticker.`);
    assert(isObject(theme.artwork), `${themeID} requires artwork.`);
    for (const key of [
      "lobbyCardAssetName",
      "detailHeaderAssetName",
      "detailBoardAssetName",
      "collectionPickerAssetName"
    ]) {
      const assetName = theme.artwork[key];
      assert(isIdentifier(assetName), `${themeID}.artwork.${key} must be a safe identifier.`);
      assert(!assetNames.has(assetName), `Duplicate artwork asset name: ${assetName}`);
      assetNames.add(assetName);
    }

    let hiddenCount = 0;
    let normalCount = 0;
    const themeStickerIDs = new Set();
    for (const sticker of theme.stickers) {
      assert(isIdentifier(sticker.id?.rawValue), `${themeID} has an invalid sticker id.`);
      assert(isIdentifier(sticker.assetName), `${themeID} has an invalid sticker asset name.`);
      assert(!stickerIDs.has(sticker.id.rawValue), `Sticker ID is reused: ${sticker.id.rawValue}`);
      assert(!themeStickerIDs.has(sticker.id.rawValue), `${themeID} repeats a sticker ID.`);
      assert(!assetNames.has(sticker.assetName), `Artwork asset name is reused: ${sticker.assetName}`);
      stickerIDs.add(sticker.id.rawValue);
      themeStickerIDs.add(sticker.id.rawValue);
      assetNames.add(sticker.assetName);
      if (sticker.isHidden === true) hiddenCount += 1;
      else normalCount += 1;
    }
    assert(hiddenCount === 1, `${themeID} must have exactly one hidden sticker.`);
    assert(normalCount >= 1 && normalCount <= 18, `${themeID} must have 1–18 normal stickers.`);

    assert(Array.isArray(theme.presentation?.collectionPlacements),
      `${themeID} requires collection presentation positions.`);
    const placements = theme.presentation.collectionPlacements;
    assert(placements.length === theme.stickers.length,
      `${themeID} needs exactly one collection placement per sticker.`);
    const placementStickerIDs = new Set();
    let specialCount = 0;
    for (const placement of placements) {
      const stickerID = placement.stickerID?.rawValue;
      assert(themeStickerIDs.has(stickerID), `${themeID} has a placement for an unknown sticker.`);
      assert(!placementStickerIDs.has(stickerID), `${themeID} repeats a collection placement.`);
      placementStickerIDs.add(stickerID);
      assert(Number.isFinite(placement.centerX) && placement.centerX >= 0 && placement.centerX <= 393,
        `${themeID} has an invalid placement x coordinate.`);
      assert(Number.isFinite(placement.centerY) && placement.centerY >= 0 && placement.centerY <= 852,
        `${themeID} has an invalid placement y coordinate.`);
      assert(Number.isFinite(placement.displaySize) && placement.displaySize > 0,
        `${themeID} has an invalid placement size.`);
      if (placement.isSpecialSlot === true) {
        specialCount += 1;
        const sticker = theme.stickers.find((item) => item.id.rawValue === stickerID);
        assert(sticker?.isHidden === true, `${themeID} special slot must be the hidden sticker.`);
      }
    }
    assert(specialCount === 1, `${themeID} needs exactly one hidden special slot.`);
  }

  for (const activeThemeID of activeThemeIDs) {
    assert(themeIDs.has(activeThemeID), `Active theme is missing a definition: ${activeThemeID}`);
  }
  return [...assetNames].sort();
}

async function loadArtworkFiles(assetNames, artworkDirectory) {
  const artworkFiles = [];
  for (const assetName of assetNames) {
    const filePath = path.join(artworkDirectory, `${assetName}.png`);
    const fileInfo = await stat(filePath).catch(() => null);
    assert(fileInfo?.isFile(), `Missing artwork file: ${filePath}`);
    const data = await readFile(filePath);
    assert(isPNG(data), `Artwork is not a PNG: ${filePath}`);
    artworkFiles.push({
      assetName,
      contentType: "image/png",
      sha256: sha256Hex(data),
      data: data.toString("base64")
    });
  }
  return artworkFiles;
}

async function publishBundle(bundleData, release) {
  const configuration = readCloudKitConfiguration();
  const basePath = `/database/1/${configuration.container}/${configuration.environment}/public`;
  const uploadTokenResponse = await signedJSONRequest(
    configuration,
    `${basePath}/assets/upload`,
    {
      tokens: [{
        recordName: POINTER_RECORD_NAME,
        recordType: POINTER_RECORD_TYPE,
        fieldName: BUNDLE_FIELD
      }]
    }
  );
  const uploadURL = uploadTokenResponse.tokens?.[0]?.url;
  assert(isNonEmptyString(uploadURL), "CloudKit did not provide an asset upload URL.");

  const uploadResponse = await fetch(uploadURL, {
    method: "POST",
    headers: { "content-type": "application/octet-stream" },
    body: bundleData
  });
  const uploadedAsset = await readJSONResponse(uploadResponse, "CloudKit asset upload");
  const assetValue = uploadedAsset.singleFile;
  assert(isObject(assetValue), "CloudKit did not return an uploaded asset receipt.");

  const response = await signedJSONRequest(
    configuration,
    `${basePath}/records/modify`,
    {
      operations: [{
        operationType: "forceReplace",
        record: {
          recordType: POINTER_RECORD_TYPE,
          recordName: POINTER_RECORD_NAME,
          fields: {
            [BUNDLE_FIELD]: { value: assetValue },
            releaseID: { value: release.releaseID },
            publishedAt: { value: release.publishedAt },
            contentSHA256: { value: sha256Hex(bundleData) }
          }
        }
      }]
    }
  );
  assert(!response.serverErrorCode, `CloudKit publish failed: ${response.reason ?? response.serverErrorCode}`);
  process.stdout.write(`Published ${release.releaseID} to ${configuration.environment} CloudKit.\n`);
}

function readCloudKitConfiguration() {
  const privateKey = process.env.CLOUDKIT_PRIVATE_KEY_PEM?.replace(/\\n/g, "\n");
  const configuration = {
    container: process.env.CLOUDKIT_CONTAINER,
    environment: process.env.CLOUDKIT_ENVIRONMENT,
    keyID: process.env.CLOUDKIT_KEY_ID,
    privateKey
  };
  for (const [name, value] of Object.entries(configuration)) {
    assert(isNonEmptyString(value), `Missing required environment variable: ${name}`);
  }
  assert(["development", "production"].includes(configuration.environment),
    "CLOUDKIT_ENVIRONMENT must be development or production.");
  return configuration;
}

async function signedJSONRequest(configuration, subpath, body) {
  const bodyText = JSON.stringify(body);
  const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const bodyHash = createHash("sha256").update(bodyText).digest("base64");
  const message = `${date}:${bodyHash}:${subpath}`;
  const signature = createSign("sha256")
    .update(message, "utf8")
    .end()
    .sign(configuration.privateKey)
    .toString("base64");
  const response = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Apple-CloudKit-Request-KeyID": configuration.keyID,
      "X-Apple-CloudKit-Request-ISO8601Date": date,
      "X-Apple-CloudKit-Request-SignatureV1": signature
    },
    body: bodyText
  });
  return readJSONResponse(response, `CloudKit ${subpath}`);
}

async function readJSONResponse(response, label) {
  const responseText = await response.text();
  let body;
  try {
    body = JSON.parse(responseText);
  } catch {
    throw new Error(`${label} returned non-JSON HTTP ${response.status}.`);
  }
  if (!response.ok || body.serverErrorCode) {
    throw new Error(`${label} failed: ${body.reason ?? body.serverErrorCode ?? response.status}`);
  }
  return body;
}

function sha256Hex(data) {
  return createHash("sha256").update(data).digest("hex");
}

function isIdentifier(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,120}$/.test(value);
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isPNG(data) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  return data.length >= signature.length && signature.every((byte, index) => data[index] === byte);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

main().catch((error) => {
  process.stderr.write(`Blind Box catalog publish failed: ${error.message}\n`);
  process.exitCode = 1;
});
