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

After reviewing the Git diff, commit the catalog source and manually run the
**Publish Blind Box Catalog** workflow. That workflow validates the same
constraints again. Its default mode does not write to CloudKit.
