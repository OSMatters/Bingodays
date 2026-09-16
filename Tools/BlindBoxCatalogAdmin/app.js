const state = {
  release: emptyRelease(),
  files: new Map(),
  previewURLs: new Map()
};

const artworkFields = [
  ["lobbyCardAssetName", "Lobby card"],
  ["detailHeaderAssetName", "Detail header"],
  ["detailBoardAssetName", "9-slot board"],
  ["collectionPickerAssetName", "My Box picker"]
];

const themesElement = document.querySelector("#themes");
const statusElement = document.querySelector("#status");
const metadataInputs = document.querySelectorAll("[data-meta]");
const economyInputs = document.querySelectorAll("[data-economy]");

metadataInputs.forEach((input) => input.addEventListener("input", () => {
  state.release[input.dataset.meta] = input.type === "number" ? Number(input.value) : input.value;
  saveDraft();
}));
economyInputs.forEach((input) => input.addEventListener("input", () => {
  state.release.economyConfiguration[input.dataset.economy] =
    input.type === "checkbox" ? input.checked : Number(input.value);
  saveDraft();
}));

document.querySelector("#add-theme").addEventListener("click", () => {
  state.release.themes.push(emptyTheme());
  render();
  saveDraft();
});
document.querySelector("#reset-draft").addEventListener("click", () => {
  if (!confirm("Start over? Your browser draft and selected files will be cleared.")) return;
  state.release = emptyRelease();
  clearAttachedFiles();
  localStorage.removeItem("blind-box-catalog-draft-v1");
  render();
  setStatus("Started a new local draft.");
});
document.querySelector("#download-release").addEventListener("click", () => {
  try {
    const release = normalizedRelease();
    download("release.json", JSON.stringify(release, null, 2), "application/json");
    setStatus("Downloaded release.json. PNG artwork is saved separately with Save to checkout.", "success");
  } catch (error) {
    setStatus(error.message, "error");
  }
});
document.querySelector("#save-to-checkout").addEventListener("click", saveToCheckout);
document.querySelector("#import-release").addEventListener("change", importRelease);

loadDraft();
render();

function emptyRelease() {
  return {
    releaseID: "",
    catalogSchemaVersion: 1,
    minimumAppBuild: 47,
    publishedAt: localDateTimeValue(new Date()),
    activeThemeIDs: [],
    themes: [],
    economyConfiguration: defaultEconomyConfiguration()
  };
}

function defaultEconomyConfiguration() {
  return {
    version: 1,
    isBlindBoxOpeningEnabled: true,
    isPointExchangeEnabled: true,
    pointExchangePrice: 100,
    maximumPointExchangesPerGrantDay: 1
  };
}

function emptyTheme() {
  return {
    active: true,
    id: "",
    catalogVersion: 1,
    artwork: Object.fromEntries(artworkFields.map(([key]) => [key, ""])),
    stickers: [emptySticker(false), emptySticker(true)]
  };
}

function emptySticker(isHidden) {
  return {
    id: "",
    assetName: "",
    isHidden,
    centerX: isHidden ? 196.5 : 160,
    centerY: isHidden ? 365 : 500,
    displaySize: isHidden ? 128 : 72
  };
}

function render() {
  metadataInputs.forEach((input) => {
    const value = state.release[input.dataset.meta] ?? "";
    input.value = value;
  });
  economyInputs.forEach((input) => {
    const value = state.release.economyConfiguration?.[input.dataset.economy];
    if (input.type === "checkbox") input.checked = value === true;
    else input.value = value ?? "";
  });
  themesElement.replaceChildren(...state.release.themes.map((theme, index) => renderTheme(theme, index)));
}

function renderTheme(theme, themeIndex) {
  const card = document.querySelector("#theme-template").content.firstElementChild.cloneNode(true);
  const input = (field) => card.querySelector(`[data-field="${field}"]`);
  input("active").checked = theme.active;
  input("id").value = theme.id;
  input("catalogVersion").value = theme.catalogVersion;
  input("active").addEventListener("change", () => updateTheme(themeIndex, "active", input("active").checked));
  input("id").addEventListener("input", () => updateTheme(themeIndex, "id", input("id").value));
  input("catalogVersion").addEventListener("input", () => updateTheme(themeIndex, "catalogVersion", Number(input("catalogVersion").value)));
  card.querySelector('[data-action="remove-theme"]').addEventListener("click", () => {
    state.release.themes.splice(themeIndex, 1);
    render(); saveDraft();
  });

  const artworkContainer = card.querySelector("[data-artwork-fields]");
  for (const [key, label] of artworkFields) {
    const field = document.querySelector("#artwork-template").content.firstElementChild.cloneNode(true);
    field.querySelector("[data-label]").textContent = label;
    const assetInput = field.querySelector("[data-asset-name]");
    const fileInput = field.querySelector("[data-asset-file]");
    assetInput.value = theme.artwork[key];
    assetInput.addEventListener("input", () => updateArtwork(themeIndex, key, assetInput.value));
    fileInput.addEventListener("change", () => recordFile(fileInput.files[0], assetInput.value));
    artworkContainer.append(field);
  }

  card.querySelector('[data-action="add-sticker"]').addEventListener("click", () => {
    theme.stickers.push(emptySticker(false));
    render(); saveDraft();
  });
  const stickersContainer = card.querySelector("[data-stickers]");
  theme.stickers.forEach((sticker, stickerIndex) => stickersContainer.append(renderSticker(themeIndex, stickerIndex, sticker)));
  renderPlacementPreview(card.querySelector("[data-placement-preview]"), themeIndex);
  return card;
}

function renderSticker(themeIndex, stickerIndex, sticker) {
  const row = document.querySelector("#sticker-template").content.firstElementChild.cloneNode(true);
  for (const field of ["id", "assetName", "centerX", "centerY", "displaySize"]) {
    const input = row.querySelector(`[data-field="${field}"]`);
    input.value = sticker[field];
    input.addEventListener("input", () => updateSticker(themeIndex, stickerIndex, field,
      input.type === "number" ? Number(input.value) : input.value));
    if (["centerX", "centerY", "displaySize"].includes(field)) {
      input.addEventListener("change", render);
    }
  }
  const hiddenInput = row.querySelector('[data-field="isHidden"]');
  hiddenInput.checked = sticker.isHidden;
  hiddenInput.addEventListener("change", () => updateSticker(themeIndex, stickerIndex, "isHidden", hiddenInput.checked));
  row.querySelector("[data-asset-file]").addEventListener("change", (event) => recordFile(event.target.files[0], sticker.assetName));
  row.querySelector('[data-action="remove-sticker"]').addEventListener("click", () => {
    state.release.themes[themeIndex].stickers.splice(stickerIndex, 1);
    render(); saveDraft();
  });
  return row;
}

function updateTheme(themeIndex, key, value) { state.release.themes[themeIndex][key] = value; saveDraft(); }
function updateArtwork(themeIndex, key, value) { state.release.themes[themeIndex].artwork[key] = value; saveDraft(); }
function updateSticker(themeIndex, stickerIndex, key, value) { state.release.themes[themeIndex].stickers[stickerIndex][key] = value; saveDraft(); }

function recordFile(file, assetName) {
  if (!file) return;
  if (!isIdentifier(assetName)) {
    setStatus("Enter a safe asset key before choosing its PNG.", "error");
    return;
  }
  if (file.type !== "image/png" && !file.name.toLowerCase().endsWith(".png")) {
    setStatus(`${file.name} is not a PNG.`, "error");
    return;
  }
  if (state.previewURLs.has(assetName)) URL.revokeObjectURL(state.previewURLs.get(assetName));
  state.files.set(assetName, file);
  state.previewURLs.set(assetName, URL.createObjectURL(file));
  render();
  setStatus(`Attached ${file.name} to ${assetName}.`, "success");
}

function renderPlacementPreview(preview, themeIndex) {
  const theme = state.release.themes[themeIndex];
  if (!preview || !theme) return;
  preview.replaceChildren();
  theme.stickers.forEach((sticker, stickerIndex) => {
    const item = document.createElement("div");
    item.className = `placement-preview-sticker${sticker.isHidden ? " special" : ""}`;
    item.style.left = `${clamp(Number(sticker.centerX), 0, 393) / 393 * 100}%`;
    item.style.top = `${clamp(Number(sticker.centerY), 0, 852) / 852 * 100}%`;
    const displayedSize = clamp(Number(sticker.displaySize), 22, 180) * 0.5;
    item.style.width = `${displayedSize}px`;
    item.style.height = `${displayedSize}px`;
    item.title = `${sticker.id || "Sticker"} — drag to position`;

    const previewURL = state.previewURLs.get(sticker.assetName);
    if (previewURL) {
      const image = document.createElement("img");
      image.src = previewURL;
      image.alt = sticker.id || "Sticker preview";
      item.append(image);
    } else {
      const label = document.createElement("span");
      label.textContent = sticker.isHidden ? "Hidden" : (sticker.id || "PNG");
      item.append(label);
    }

    item.addEventListener("pointerdown", (event) => {
      beginPlacementDrag(event, preview, themeIndex, stickerIndex, item);
    });
    preview.append(item);
  });
}

function beginPlacementDrag(event, preview, themeIndex, stickerIndex, item) {
  event.preventDefault();
  item.setPointerCapture?.(event.pointerId);
  const move = (moveEvent) => {
    const bounds = preview.getBoundingClientRect();
    const x = clamp((moveEvent.clientX - bounds.left) / bounds.width * 393, 0, 393);
    const y = clamp((moveEvent.clientY - bounds.top) / bounds.height * 852, 0, 852);
    const sticker = state.release.themes[themeIndex]?.stickers[stickerIndex];
    if (!sticker) return;
    sticker.centerX = roundCoordinate(x);
    sticker.centerY = roundCoordinate(y);
    item.style.left = `${x / 393 * 100}%`;
    item.style.top = `${y / 852 * 100}%`;
  };
  const end = () => {
    preview.removeEventListener("pointermove", move);
    preview.removeEventListener("pointerup", end);
    preview.removeEventListener("pointercancel", end);
    saveDraft();
    render();
  };
  preview.addEventListener("pointermove", move);
  preview.addEventListener("pointerup", end);
  preview.addEventListener("pointercancel", end);
}

function clearAttachedFiles() {
  state.previewURLs.forEach((url) => URL.revokeObjectURL(url));
  state.previewURLs.clear();
  state.files.clear();
}

function normalizedRelease() {
  const release = structuredClone(state.release);
  validateRelease(release);
  release.publishedAt = Date.parse(release.publishedAt) / 1000;
  release.activeThemeIDs = release.themes.filter((theme) => theme.active).map((theme) => ({ rawValue: theme.id }));
  release.themes = release.themes.map((theme) => ({
    id: { rawValue: theme.id },
    catalogVersion: Number(theme.catalogVersion),
    stickers: theme.stickers.map((sticker) => ({
      id: { rawValue: sticker.id },
      assetName: sticker.assetName,
      isHidden: sticker.isHidden
    })),
    presentation: {
      collectionPlacements: theme.stickers.map((sticker) => ({
        stickerID: { rawValue: sticker.id },
        centerX: Number(sticker.centerX),
        centerY: Number(sticker.centerY),
        displaySize: Number(sticker.displaySize),
        isSpecialSlot: sticker.isHidden
      }))
    },
    artwork: theme.artwork
  }));
  return release;
}

function validateRelease(release) {
  assert(isIdentifier(release.releaseID), "Release ID may use letters, numbers, _ and - only.");
  assert(Number.isInteger(Number(release.catalogSchemaVersion)) && Number(release.catalogSchemaVersion) > 0, "Schema version must be positive.");
  assert(Number.isInteger(Number(release.minimumAppBuild)) && Number(release.minimumAppBuild) >= 0, "Minimum build must be a non-negative integer.");
  assert(Number.isFinite(Date.parse(release.publishedAt)), "Published at is required.");
  const economy = release.economyConfiguration;
  assert(economy && typeof economy === "object", "Economy configuration is required.");
  assert(Number.isInteger(Number(economy.version)) && Number(economy.version) > 0, "Economy configuration version must be positive.");
  assert(typeof economy.isBlindBoxOpeningEnabled === "boolean", "Opening switch must be set.");
  assert(typeof economy.isPointExchangeEnabled === "boolean", "Point exchange switch must be set.");
  assert(Number.isInteger(Number(economy.pointExchangePrice)) && Number(economy.pointExchangePrice) >= 50 && Number(economy.pointExchangePrice) <= 9999,
    "Ticket price must be an integer between 50 and 9999.");
  assert(Number(economy.maximumPointExchangesPerGrantDay) === 1,
    "Daily exchange limit is locked at 1 for the first release.");
  assert(release.themes.length > 0, "Add at least one theme.");
  const themeIDs = new Set(); const stickerIDs = new Set(); const assetNames = new Set();
  for (const theme of release.themes) {
    assert(isIdentifier(theme.id), "Each theme needs a safe ID.");
    assert(!themeIDs.has(theme.id), `Theme ID is duplicated: ${theme.id}`); themeIDs.add(theme.id);
    assert(Number.isInteger(Number(theme.catalogVersion)) && Number(theme.catalogVersion) > 0, `${theme.id} needs a catalog version.`);
    for (const [, label] of artworkFields) { void label; }
    for (const [key] of artworkFields) {
      assert(isIdentifier(theme.artwork[key]), `${theme.id} needs ${key}.`);
      assert(!assetNames.has(theme.artwork[key]), `Artwork key is duplicated: ${theme.artwork[key]}`);
      assetNames.add(theme.artwork[key]);
    }
    const hidden = theme.stickers.filter((sticker) => sticker.isHidden);
    const normal = theme.stickers.filter((sticker) => !sticker.isHidden);
    assert(hidden.length === 1, `${theme.id} needs exactly one Hidden sticker.`);
    assert(normal.length >= 1 && normal.length <= 18, `${theme.id} needs 1–18 normal stickers.`);
    for (const sticker of theme.stickers) {
      assert(isIdentifier(sticker.id) && isIdentifier(sticker.assetName), `${theme.id} has an invalid sticker ID or asset key.`);
      assert(!stickerIDs.has(sticker.id), `Sticker ID is duplicated: ${sticker.id}`); stickerIDs.add(sticker.id);
      assert(!assetNames.has(sticker.assetName), `Artwork key is duplicated: ${sticker.assetName}`); assetNames.add(sticker.assetName);
      assert(Number(sticker.centerX) >= 0 && Number(sticker.centerX) <= 393 && Number(sticker.centerY) >= 0 && Number(sticker.centerY) <= 852 && Number(sticker.displaySize) > 0,
        `${sticker.id} has an invalid My Box placement.`);
    }
  }
}

async function saveToCheckout() {
  try {
    assert("showDirectoryPicker" in window, "Use Chrome or Edge for Save to checkout. Safari can still download release.json.");
    const release = normalizedRelease();
    const root = await window.showDirectoryPicker({ mode: "readwrite" });
    const catalogDirectory = await root.getDirectoryHandle("blindbox-catalog", { create: true });
    const artworkDirectory = await catalogDirectory.getDirectoryHandle("artwork", { create: true });
    await writeTextFile(catalogDirectory, "release.json", JSON.stringify(release, null, 2));
    const requiredAssetNames = release.themes.flatMap((theme) => [
      ...Object.values(theme.artwork),
      ...theme.stickers.map((sticker) => sticker.assetName)
    ]);
    for (const assetName of requiredAssetNames) {
      const selectedFile = state.files.get(assetName);
      if (selectedFile) await writeFile(artworkDirectory, `${assetName}.png`, selectedFile);
      else await assertExistingPNG(artworkDirectory, assetName);
    }
    setStatus("Saved release.json and verified all required PNG files in blindbox-catalog/artwork.", "success");
  } catch (error) {
    setStatus(error.message, "error");
  }
}

async function writeTextFile(directory, name, text) { await writeFile(directory, name, new Blob([text], { type: "application/json" })); }
async function writeFile(directory, name, content) { const handle = await directory.getFileHandle(name, { create: true }); const writer = await handle.createWritable(); await writer.write(content); await writer.close(); }
async function assertExistingPNG(directory, assetName) { try { const file = await (await directory.getFileHandle(`${assetName}.png`)).getFile(); assert(file.size > 0, `Existing ${assetName}.png is empty.`); } catch { throw new Error(`Attach or retain ${assetName}.png before saving.`); } }

async function importRelease(event) {
  const file = event.target.files[0]; if (!file) return;
  try {
    const release = JSON.parse(await file.text());
    state.release = editorRelease(release);
    clearAttachedFiles(); render(); saveDraft();
    setStatus("Imported JSON. Reattach changed PNG files before saving.", "success");
  } catch { setStatus("Could not import that release.json.", "error"); }
}

function editorRelease(release) {
  return {
    releaseID: release.releaseID ?? "",
    catalogSchemaVersion: release.catalogSchemaVersion ?? 1,
    minimumAppBuild: release.minimumAppBuild ?? 47,
    publishedAt: localDateTimeValue(new Date((release.publishedAt ?? Date.now() / 1000) * 1000)),
    activeThemeIDs: [],
    economyConfiguration: {
      ...defaultEconomyConfiguration(),
      ...(release.economyConfiguration ?? {})
    },
    themes: (release.themes ?? []).map((theme) => ({
      active: (release.activeThemeIDs ?? []).some((id) => id.rawValue === theme.id?.rawValue),
      id: theme.id?.rawValue ?? "", catalogVersion: theme.catalogVersion ?? 1,
      artwork: theme.artwork ?? Object.fromEntries(artworkFields.map(([key]) => [key, ""])),
      stickers: (theme.stickers ?? []).map((sticker) => {
        const placement = theme.presentation?.collectionPlacements?.find((item) => item.stickerID?.rawValue === sticker.id?.rawValue) ?? {};
        return { id: sticker.id?.rawValue ?? "", assetName: sticker.assetName ?? "", isHidden: sticker.isHidden === true,
          centerX: placement.centerX ?? 160, centerY: placement.centerY ?? 500, displaySize: placement.displaySize ?? 72 };
      })
    }))
  };
}

function saveDraft() { localStorage.setItem("blind-box-catalog-draft-v1", JSON.stringify(state.release)); }
function loadDraft() {
  try {
    const draft = JSON.parse(localStorage.getItem("blind-box-catalog-draft-v1"));
    if (!draft) return;
    state.release = {
      ...emptyRelease(),
      ...draft,
      economyConfiguration: {
        ...defaultEconomyConfiguration(),
        ...(draft.economyConfiguration ?? {})
      }
    };
  } catch {
    // Ignore malformed local drafts and leave the new default release intact.
  }
}
function download(name, content, type) { const url = URL.createObjectURL(new Blob([content], { type })); const link = document.createElement("a"); link.href = url; link.download = name; link.click(); URL.revokeObjectURL(url); }
function localDateTimeValue(date) { const offset = date.getTimezoneOffset() * 60_000; return new Date(date.getTime() - offset).toISOString().slice(0, 16); }
function isIdentifier(value) { return typeof value === "string" && /^[A-Za-z0-9_-]{1,120}$/.test(value); }
function clamp(value, lowerBound, upperBound) { return Math.min(Math.max(Number.isFinite(value) ? value : lowerBound, lowerBound), upperBound); }
function roundCoordinate(value) { return Math.round(value * 2) / 2; }
function assert(condition, message) { if (!condition) throw new Error(message); }
function setStatus(message, kind = "") { statusElement.textContent = message; statusElement.parentElement.className = `status-bar ${kind}`; }
