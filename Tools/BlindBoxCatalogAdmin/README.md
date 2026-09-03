# Blind Box Catalog Admin

This is a local-only visual editor for the remote Blind Box catalog. It does
not connect to CloudKit, GitHub, or any network service.

Open it on your Mac from a local server (Chrome or Edge is recommended because
the **Save to checkout** button uses the File System Access API):

```sh
cd Tools/BlindBoxCatalogAdmin
python3 -m http.server 8765
open http://localhost:8765
```

Choose your local repository folder when saving. The tool writes
`blindbox-catalog/release.json`, writes newly attached PNG files under
`blindbox-catalog/artwork/`, and checks that existing required PNGs are still
present. It never deletes old artwork; this is intentional because retired
themes remain needed for users who already collected them.

For each theme, attach the sticker PNGs and use the **My Box placement preview**
to drag them into place. Dragging updates the same 393 × 852 X/Y values written
to `collectionPlacements`; the numeric inputs remain available for fine tuning.

After reviewing the Git diff, commit the catalog source and manually run the
**Publish Blind Box Catalog** workflow. That workflow validates the same
constraints again. Its default mode does not write to CloudKit.

After a theme has been published, its theme ID, sticker IDs, and PNG asset
keys are immutable. To replace a theme, add a new theme ID and uncheck Active
on the old one; do not delete or rename the old definition.
