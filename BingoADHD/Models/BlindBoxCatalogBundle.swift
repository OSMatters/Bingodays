import CryptoKit
import Foundation

/// One artwork file carried by a remotely published catalog bundle. The
/// bundle itself is stored as a CloudKit asset, so the base64 JSON encoding of
/// `data` never competes with normal CloudKit record-field size limits.
struct BlindBoxCatalogArtworkFile: Codable, Equatable, Sendable {
    let assetName: String
    let contentType: String
    let sha256: String
    let data: Data

    init(assetName: String, contentType: String = "image/png", data: Data) {
        self.assetName = assetName
        self.contentType = contentType
        self.sha256 = Self.sha256Hex(for: data)
        self.data = data
    }

    func validationError() -> BlindBoxCatalogArtworkFileValidationError? {
        guard BlindBoxAssetName.isValid(assetName) else {
            return .invalidAssetName
        }
        guard contentType == "image/png" else {
            return .unsupportedContentType(contentType)
        }
        guard !data.isEmpty else {
            return .emptyData
        }
        guard Self.sha256Hex(for: data) == sha256.lowercased() else {
            return .checksumMismatch
        }
        return nil
    }

    static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum BlindBoxCatalogArtworkFileValidationError: Equatable, Sendable {
    case invalidAssetName
    case unsupportedContentType(String)
    case emptyData
    case checksumMismatch
}

/// The atomic payload uploaded by the Mac-only catalog manager. It contains a
/// complete catalog release plus every image the release references. A device
/// validates the entire object before moving either the JSON or its artwork
/// into the last-known-good local cache.
struct BlindBoxCatalogBundle: Codable, Equatable, Sendable {
    let release: BlindBoxCatalogRelease
    let artworkFiles: [BlindBoxCatalogArtworkFile]

    init(release: BlindBoxCatalogRelease, artworkFiles: [BlindBoxCatalogArtworkFile]) {
        self.release = release
        self.artworkFiles = artworkFiles
    }

    var artworkByName: [String: BlindBoxCatalogArtworkFile] {
        Dictionary(
            artworkFiles.map { ($0.assetName, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func validationError() -> BlindBoxCatalogBundleValidationError? {
        if let releaseError = release.validationError() {
            return .invalidRelease(releaseError)
        }
        guard Set(artworkFiles.map(\.assetName)).count == artworkFiles.count else {
            return .duplicateArtworkAssetName
        }
        for artworkFile in artworkFiles {
            if let error = artworkFile.validationError() {
                return .invalidArtworkFile(assetName: artworkFile.assetName, error: error)
            }
        }

        let availableAssetNames = Set(artworkFiles.map(\.assetName))
        let requiredAssetNames = Set(release.themes.flatMap { theme in
            theme.stickers.map(\.assetName) + (theme.artwork?.assetNames ?? [])
        })
        if let missingAssetName = requiredAssetNames.subtracting(availableAssetNames).sorted().first {
            return .missingArtworkFile(missingAssetName)
        }
        return nil
    }
}

enum BlindBoxCatalogBundleValidationError: Equatable, Sendable {
    case invalidRelease(BlindBoxCatalogReleaseValidationError)
    case duplicateArtworkAssetName
    case invalidArtworkFile(assetName: String, error: BlindBoxCatalogArtworkFileValidationError)
    case missingArtworkFile(String)
}
