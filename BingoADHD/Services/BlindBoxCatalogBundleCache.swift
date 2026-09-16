import Foundation

enum BlindBoxCatalogBundleCacheInstallResult: Equatable, Sendable {
    case installed
    case rejectedInvalidBundle(BlindBoxCatalogBundleValidationError)
    case rejectedIncompatibleBuild(required: Int, current: Int)
    case persistenceFailed
}

/// Stores the active and immediately previous remote catalog bundles on disk.
/// A release is promoted only after every declared image has been written and
/// revalidated in a staging directory. Keeping the previous directory gives a
/// device a safe fallback if storage is later corrupted or interrupted.
enum BlindBoxCatalogBundleCache {
    struct Entry: Equatable {
        let release: BlindBoxCatalogRelease
        let directoryURL: URL
    }

    private struct Manifest: Codable {
        let release: BlindBoxCatalogRelease
        let artworkFiles: [ArtworkFile]
    }

    private struct ArtworkFile: Codable {
        let assetName: String
        let contentType: String
        let sha256: String
    }

    private static let currentDirectoryName = "current"
    private static let previousDirectoryName = "previous"
    private static let manifestFileName = "catalog-manifest.json"

    static func load(
        currentBuild: Int,
        rootDirectory: URL = defaultRootDirectory()
    ) -> Entry? {
        for directoryName in [currentDirectoryName, previousDirectoryName] {
            let directory = rootDirectory.appendingPathComponent(directoryName, isDirectory: true)
            if let entry = validatedEntry(at: directory, currentBuild: currentBuild) {
                return entry
            }
        }
        return nil
    }

    static func artworkURL(
        named assetName: String,
        currentBuild: Int,
        rootDirectory: URL = defaultRootDirectory()
    ) -> URL? {
        guard BlindBoxAssetName.isValid(assetName),
              let entry = load(currentBuild: currentBuild, rootDirectory: rootDirectory) else {
            return nil
        }
        let assetURL = entry.directoryURL.appendingPathComponent("\(assetName).png")
        return FileManager.default.fileExists(atPath: assetURL.path) ? assetURL : nil
    }

    @discardableResult
    static func install(
        _ bundle: BlindBoxCatalogBundle,
        currentBuild: Int,
        rootDirectory: URL = defaultRootDirectory(),
        fileManager: FileManager = .default
    ) -> BlindBoxCatalogBundleCacheInstallResult {
        if let error = bundle.validationError() {
            return .rejectedInvalidBundle(error)
        }
        guard bundle.release.minimumAppBuild <= currentBuild else {
            return .rejectedIncompatibleBuild(
                required: bundle.release.minimumAppBuild,
                current: currentBuild
            )
        }

        let stagingDirectory = rootDirectory.appendingPathComponent(
            "staging-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: stagingDirectory) }

            for artworkFile in bundle.artworkFiles {
                let fileURL = stagingDirectory.appendingPathComponent("\(artworkFile.assetName).png")
                try artworkFile.data.write(to: fileURL, options: .atomic)
            }
            let manifest = Manifest(
                release: bundle.release,
                artworkFiles: bundle.artworkFiles.map {
                    ArtworkFile(
                        assetName: $0.assetName,
                        contentType: $0.contentType,
                        sha256: $0.sha256
                    )
                }
            )
            let manifestData = try JSONEncoder.catalog.encode(manifest)
            try manifestData.write(
                to: stagingDirectory.appendingPathComponent(manifestFileName),
                options: .atomic
            )

            guard validatedEntry(at: stagingDirectory, currentBuild: currentBuild) != nil else {
                return .persistenceFailed
            }
            try promoteStagedDirectory(
                stagingDirectory,
                rootDirectory: rootDirectory,
                fileManager: fileManager
            )
            return .installed
        } catch {
            return .persistenceFailed
        }
    }

    private static func promoteStagedDirectory(
        _ stagingDirectory: URL,
        rootDirectory: URL,
        fileManager: FileManager
    ) throws {
        let currentDirectory = rootDirectory.appendingPathComponent(currentDirectoryName, isDirectory: true)
        let previousDirectory = rootDirectory.appendingPathComponent(previousDirectoryName, isDirectory: true)

        if fileManager.fileExists(atPath: previousDirectory.path) {
            try fileManager.removeItem(at: previousDirectory)
        }
        if fileManager.fileExists(atPath: currentDirectory.path) {
            try fileManager.moveItem(at: currentDirectory, to: previousDirectory)
        }

        do {
            try fileManager.moveItem(at: stagingDirectory, to: currentDirectory)
        } catch {
            if !fileManager.fileExists(atPath: currentDirectory.path),
               fileManager.fileExists(atPath: previousDirectory.path) {
                try? fileManager.moveItem(at: previousDirectory, to: currentDirectory)
            }
            throw error
        }
    }

    private static func validatedEntry(at directory: URL, currentBuild: Int) -> Entry? {
        let fileManager = FileManager.default
        let manifestURL = directory.appendingPathComponent(manifestFileName)
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder.catalog.decode(Manifest.self, from: manifestData),
              manifest.release.validationError() == nil,
              manifest.release.minimumAppBuild <= currentBuild,
              Set(manifest.artworkFiles.map(\.assetName)).count == manifest.artworkFiles.count else {
            return nil
        }

        let requiredAssetNames = Set(manifest.release.themes.flatMap { theme in
            theme.stickers.map(\.assetName) + (theme.artwork?.assetNames ?? [])
        })
        let manifestAssetNames = Set(manifest.artworkFiles.map(\.assetName))
        guard requiredAssetNames.isSubset(of: manifestAssetNames) else {
            return nil
        }

        for artworkFile in manifest.artworkFiles {
            guard BlindBoxAssetName.isValid(artworkFile.assetName),
                  artworkFile.contentType == "image/png" else {
                return nil
            }
            let assetURL = directory.appendingPathComponent("\(artworkFile.assetName).png")
            guard fileManager.fileExists(atPath: assetURL.path),
                  let data = try? Data(contentsOf: assetURL),
                  !data.isEmpty,
                  BlindBoxCatalogArtworkFile.sha256Hex(for: data) == artworkFile.sha256.lowercased() else {
                return nil
            }
        }
        return Entry(release: manifest.release, directoryURL: directory)
    }

    private static func defaultRootDirectory() -> URL {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Bingodays", isDirectory: true)
            .appendingPathComponent("BlindBoxCatalogBundles", isDirectory: true)
    }
}

private extension JSONEncoder {
    static let catalog: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let catalog = JSONDecoder()
}
