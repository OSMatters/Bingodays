# Blind Box remote catalog

This folder is the reviewed source of truth for a remotely published Blind Box
release. The app does not read these files directly. GitHub Actions validates
them, combines the JSON and PNG files into one checked content bundle, then—
only after an explicit manual confirmation—uploads that bundle to the public
CloudKit pointer record.

## Folder layout

```text
blindbox-catalog/
├── release.json
└── artwork/
    ├── pets_lobby.png
    ├── pets_header.png
    ├── pets_board.png
    ├── pets_picker.png
    └── pets_01.png
```

`release.json` uses the Swift `BlindBoxCatalogRelease` field names. `publishedAt`
may be an ISO 8601 date; the publisher turns it into the numeric timestamp used
by the iOS decoder. Every artwork key in a theme and every sticker `assetName`
must have a same-named PNG in `artwork/`.

Every source release also has an `economyConfiguration` object. It requires a
positive `version`, Boolean `isBlindBoxOpeningEnabled` and
`isPointExchangeEnabled` switches, an integer `pointExchangePrice` from 50 to
9999, and `maximumPointExchangesPerGrantDay: 1`. Increase `version` whenever a
price or switch changes; the app uses it to invalidate an already displayed
ticket-exchange confirmation before it can charge the old price.
The complete published bundle, including Base64 encoding of those PNGs, must
remain below CloudKit's 15 MB asset-upload limit. Optimize the PNGs before
committing them; the publisher reports the exact packaged size during its
validation-only run.

Each release must include retired theme definitions and their artwork for as
long as any user may own them. Retire a theme by removing its ID from
`activeThemeIDs`; do not delete its definition or files. This stops new
candidates while preserving My Box and historical boxes.

## Immutable published content

Once a release has been published, treat every existing theme ID, sticker ID,
and referenced PNG as immutable. In particular, do not rename a sticker,
delete it from a theme, or reuse a theme ID with a different sticker set:
existing user batches already store those IDs and must remain renderable.

To replace a theme's content, create a new theme ID and retire the prior one
by removing only its ID from `activeThemeIDs`. You may change which themes are
active, add new themes, and add entirely new IDs without an app release.

## First CloudKit setup

Before a real publish, create the public-database record type
`BlindBoxCatalogPointer` in CloudKit Dashboard with an Asset field named
`bundle`. The publisher also writes `releaseID`, `publishedAt`, and
`contentSHA256` metadata fields. Lock the public record type so app users can
read it but cannot create or modify it.

Create a CloudKit server-to-server key in the same container and put only its
private PEM and dashboard key ID in these GitHub Secrets:

- `CLOUDKIT_PRIVATE_KEY_PEM`
- `CLOUDKIT_KEY_ID`

Do not commit the PEM file or paste it into the local catalog tool.

## Publishing

Run **Publish Blind Box Catalog** manually in GitHub Actions. The default is a
validation-only run. Review that output first, then run it again with
**Upload the validated bundle** enabled. Use `development` until the CloudKit
schema and a physical-device test have been verified; choose `production` only
when the catalog is ready for users.
