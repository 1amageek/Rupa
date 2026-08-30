import Foundation
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

/// Synchronous package I/O. Session ordering and dirty-state publication belong
/// to the caller that owns the editable project lifecycle.
public struct ProjectPackageStore: ProjectPackageReading, ProjectPackageWriting,
    ProjectPackageValidating, Sendable
{
    private static let manifestPath = "manifest.json"
    private static let supportedRequiredFeatures: Set<String> = []

    public let limits: ProjectPackageResourceLimits
    private let replaceFile: @Sendable (URL, URL) throws -> Void
    private let stagingFactory: @Sendable (URL) throws -> ProjectPackageStaging
    private let cleanupStaging: @Sendable (ProjectPackageStaging) throws -> Void

    public init(limits: ProjectPackageResourceLimits = .standard) {
        self.limits = limits
        replaceFile = { temporaryURL, destinationURL in
            try ProjectPackageAtomicFileReplacer.replace(
                temporaryURL: temporaryURL,
                destinationURL: destinationURL
            )
        }
        stagingFactory = { destinationURL in
            try Self.makeStaging(for: destinationURL)
        }
        cleanupStaging = { staging in
            try Self.cleanupStaging(staging)
        }
    }

    init(
        limits: ProjectPackageResourceLimits,
        replaceFile: @escaping @Sendable (URL, URL) throws -> Void
    ) {
        self.limits = limits
        self.replaceFile = replaceFile
        stagingFactory = { destinationURL in
            try Self.makeStaging(for: destinationURL)
        }
        cleanupStaging = { staging in
            try Self.cleanupStaging(staging)
        }
    }

    init(
        limits: ProjectPackageResourceLimits,
        stagingFactory: @escaping @Sendable (URL) throws -> ProjectPackageStaging,
        cleanupStaging: @escaping @Sendable (ProjectPackageStaging) throws -> Void,
        replaceFile: @escaping @Sendable (URL, URL) throws -> Void
    ) {
        self.limits = limits
        self.stagingFactory = stagingFactory
        self.cleanupStaging = cleanupStaging
        self.replaceFile = replaceFile
    }

    public func load(from url: URL) throws -> ProjectPackageDocument {
        try limits.validate()
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.alwaysMapped])
        } catch {
            throw ProjectPackageError(
                code: .ioFailure,
                message: "Project package could not be mapped for reading: \(error)."
            )
        }
        let backing = try ProjectPackageArchiveReader(limits: limits).read(data)
        return try decode(backing)
    }

    public func save(
        _ document: ProjectPackageDocument,
        to url: URL
    ) throws -> ProjectPackageSaveResult {
        try limits.validate()
        let prepared = try prepare(document)
        let staging: ProjectPackageStaging
        do {
            staging = try stagingFactory(url)
        } catch {
            throw ProjectPackageError(
                code: .ioFailure,
                message: "Project package staging location could not be created: \(error)."
            )
        }

        let output: ProjectPackageWriteOutput
        let validated: ProjectPackageDocument
        do {
            try createStagingFile(at: staging.packageURL)
            output = try write(
                prepared.entries,
                backing: document.backing,
                telemetry: prepared.telemetry,
                to: staging.packageURL
            )
            validated = try load(from: staging.packageURL)
            guard validated.documentID == document.documentID,
                validated.productSource == document.productSource,
                validated.cadSource == document.cadSource,
                validated.authoredMeshAssets == document.authoredMeshAssets,
                validated.persistedContentIdentity == prepared.manifest.documentContentIdentity
            else {
                throw ProjectPackageError(
                    code: .integrityMismatch,
                    message: "Staged project package validation did not reproduce its sources."
                )
            }
            try replaceFile(staging.packageURL, url)
        } catch {
            throw prepublicationFailure(error, staging: staging)
        }

        var warnings: [ProjectPackageSaveWarning] = []
        do {
            try cleanupStaging(staging)
        } catch {
            warnings.append(
                ProjectPackageSaveWarning(
                    code: .stagingCleanupFailed,
                    message: "Project package was published, but staging cleanup failed: \(error)."
                )
            )
        }

        let report = ProjectPackageIOReport(
            archiveByteCount: output.archiveByteCount,
            encodedSourceBlobCount: prepared.encodedBlobCount,
            encodedSourceBlobByteCount: prepared.encodedBlobByteCount,
            reusedSourceBlobCount: prepared.reusedBlobCount,
            reusedSourceBlobByteCount: prepared.reusedBlobByteCount,
            preservedAdjunctCount: prepared.preservedAdjunctCount,
            preservedAdjunctByteCount: prepared.preservedAdjunctByteCount,
            maximumReadChunkByteCount: validated.loadReport?.maximumReadChunkByteCount ?? 0,
            maximumWriteChunkByteCount: output.maximumWriteChunkByteCount,
            geometryCopyTelemetry: output.telemetry
        )
        return ProjectPackageSaveResult(
            document: validated,
            documentContentIdentity: prepared.manifest.documentContentIdentity,
            report: report,
            warnings: warnings
        )
    }

    public func validateForSave(_ document: ProjectPackageDocument) throws {
        try limits.validate()
        _ = try prepare(document)
    }

    private func decode(
        _ backing: ProjectPackageArchiveBacking
    ) throws -> ProjectPackageDocument {
        guard let manifestDescriptor = backing.entries[Self.manifestPath] else {
            throw missing(Self.manifestPath)
        }
        var maximumReadChunkByteCount = try backing.validateChecksum(
            manifestDescriptor,
            maximumChunkByteCount: limits.maximumChunkByteCount
        )
        let manifestData = try backing.materialize(
            manifestDescriptor,
            maximumByteCount: limits.maximumManifestByteCount
        )
        let manifest = try ProjectPackageCanonicalJSON.decode(
            ProjectPackageManifest.self,
            from: manifestData
        )
        let unsupportedFeatures = Set(manifest.requiredFeatures)
            .subtracting(Self.supportedRequiredFeatures)
        guard unsupportedFeatures.isEmpty else {
            throw ProjectPackageError(
                code: .unsupportedFeature,
                message: "Project package requires unsupported features: "
                    + unsupportedFeatures.sorted().joined(separator: ", ")
            )
        }
        try validateDeclaredSourcePaths(manifest, backing: backing)

        let productEntry = try requiredEntry(
            at: ProjectPackageManifest.productSourcePath,
            in: manifest,
            mediaType: ProjectPackageProductSource.mediaType,
            schemaVersion: ProjectPackageProductSource.schemaVersion,
            fingerprintAlgorithm: ProjectPackageProductSource.fingerprintAlgorithm,
            maximumByteCount: limits.maximumProductSourceByteCount
        )
        guard let productDescriptor = backing.entries[productEntry.path] else {
            throw missing(productEntry.path)
        }
        maximumReadChunkByteCount = max(
            maximumReadChunkByteCount,
            try backing.validate(
                productDescriptor,
                against: productEntry,
                maximumChunkByteCount: limits.maximumChunkByteCount
            )
        )
        let productSource = try ProjectPackageProductSource(
            data: backing.materialize(
                productDescriptor,
                maximumByteCount: limits.maximumProductSourceByteCount
            ),
            declaredEntry: productEntry
        )

        let cadSource: ProjectPackageCADSource?
        if let cadEntry = manifest.sourceEntry(at: ProjectPackageManifest.cadSourcePath) {
            try validateEntry(
                cadEntry,
                mediaType: ProjectPackageCADSource.mediaType,
                schemaVersion: ProjectPackageCADSource.schemaVersion,
                fingerprintAlgorithm: ProjectPackageCADSource.fingerprintAlgorithm,
                maximumByteCount: limits.maximumCADSourceByteCount
            )
            guard let cadDescriptor = backing.entries[cadEntry.path] else {
                throw missing(cadEntry.path)
            }
            maximumReadChunkByteCount = max(
                maximumReadChunkByteCount,
                try backing.validate(
                    cadDescriptor,
                    against: cadEntry,
                    maximumChunkByteCount: limits.maximumChunkByteCount
                )
            )
            cadSource = try ProjectPackageCADSource(
                data: backing.materialize(
                    cadDescriptor,
                    maximumByteCount: limits.maximumCADSourceByteCount
                ),
                declaredEntry: cadEntry
            )
        } else {
            cadSource = nil
        }

        var telemetry = GeometryCopyTelemetry()
        var meshSources: [GeometrySourceID: MeshSource] = [:]
        var referencedBlobPaths: Set<String> = []
        let catalog: ProjectPackageMeshAssetCatalog?
        if let catalogEntry = manifest.sourceEntry(at: ProjectPackageManifest.meshCatalogPath) {
            try validateEntry(
                catalogEntry,
                mediaType: ProjectPackageMeshPlanner.catalogMediaType,
                schemaVersion: ProjectPackageMeshPlanner.catalogSchemaVersion,
                fingerprintAlgorithm: ProjectPackageMeshPlanner.catalogFingerprintAlgorithm,
                maximumByteCount: limits.maximumMeshCatalogByteCount
            )
            guard let catalogDescriptor = backing.entries[catalogEntry.path] else {
                throw missing(catalogEntry.path)
            }
            maximumReadChunkByteCount = max(
                maximumReadChunkByteCount,
                try backing.validate(
                    catalogDescriptor,
                    against: catalogEntry,
                    maximumChunkByteCount: limits.maximumChunkByteCount
                )
            )
            catalog = try ProjectPackageCanonicalJSON.decode(
                ProjectPackageMeshAssetCatalog.self,
                from: backing.materialize(
                    catalogDescriptor,
                    maximumByteCount: limits.maximumMeshCatalogByteCount
                )
            )
            guard let catalog else {
                throw ProjectPackageError(
                    code: .invalidSource,
                    message: "Authored Mesh catalog could not be decoded."
                )
            }
            for record in catalog.assets {
                try validateMeshReference(record.blob)
                guard referencedBlobPaths.insert(record.blob.path).inserted,
                    let declaredEntry = manifest.sourceEntry(at: record.blob.path),
                    try declaredEntry == record.blob.sourceEntry,
                    let descriptor = backing.entries[record.blob.path]
                else {
                    throw ProjectPackageError(
                        code: .invalidManifest,
                        message: "Authored Mesh blob reference is missing or inconsistent."
                    )
                }
                maximumReadChunkByteCount = max(
                    maximumReadChunkByteCount,
                    try backing.validate(
                        descriptor,
                        against: declaredEntry,
                        maximumChunkByteCount: limits.maximumChunkByteCount
                    )
                )
                var source = ProjectPackageArchiveEntrySource(
                    backing: backing,
                    entry: descriptor,
                    maximumChunkByteCount: limits.maximumChunkByteCount
                )
                let mesh: MeshSource
                do {
                    mesh = try MeshSourceCodec.decode(
                        from: &source,
                        limits: limits.meshSource,
                        telemetry: &telemetry
                    )
                } catch let error as MeshSourceError where error.code == .resourceLimitExceeded {
                    throw ProjectPackageError(code: .resourceLimitExceeded, message: error.message)
                } catch let error as MeshSourceError where error.code == .unsupportedVersion {
                    throw ProjectPackageError(code: .unsupportedVersion, message: error.message)
                } catch {
                    throw ProjectPackageError(
                        code: .invalidSource,
                        message: "Authored Mesh blob decoding failed: \(error)."
                    )
                }
                try source.validateCompletion(against: record.blob)
                guard mesh.identity == record.id,
                    meshSources.updateValue(mesh, forKey: record.id) == nil
                else {
                    throw ProjectPackageError(
                        code: .invalidSource,
                        message: "Authored Mesh blob identity is duplicate or inconsistent."
                    )
                }
                maximumReadChunkByteCount = max(
                    maximumReadChunkByteCount,
                    source.maximumReadChunkByteCount
                )
            }
        } else {
            catalog = nil
        }

        for sourceEntry in manifest.sourceEntries
        where sourceEntry.path != ProjectPackageManifest.productSourcePath
            && sourceEntry.path != ProjectPackageManifest.cadSourcePath
            && sourceEntry.path != ProjectPackageManifest.meshCatalogPath
            && !referencedBlobPaths.contains(sourceEntry.path)
        {
            let reference = try ProjectSourceBlobReference(entry: sourceEntry)
            try validateMeshReference(reference)
            guard let descriptor = backing.entries[sourceEntry.path] else {
                throw missing(sourceEntry.path)
            }
            maximumReadChunkByteCount = max(
                maximumReadChunkByteCount,
                try backing.validate(
                    descriptor,
                    against: sourceEntry,
                    maximumChunkByteCount: limits.maximumChunkByteCount
                )
            )
        }

        let authoredMeshAssets = try catalog?.makeAssets(meshSources: meshSources) ?? [:]
        var adjunctByteCount: UInt64 = 0
        var adjunctCount = 0
        for descriptor in backing.entries.values
        where descriptor.path != Self.manifestPath
            && !descriptor.path.hasPrefix("source/")
        {
            try validateAdjunctPath(descriptor.path)
            let addition = adjunctByteCount.addingReportingOverflow(UInt64(descriptor.byteCount))
            guard !addition.overflow,
                addition.partialValue <= limits.maximumPreservedAdjunctByteCount
            else {
                throw ProjectPackageError(
                    code: .resourceLimitExceeded,
                    message: "Preserved project package adjuncts exceed their configured limit."
                )
            }
            adjunctByteCount = addition.partialValue
            adjunctCount += 1
            maximumReadChunkByteCount = max(
                maximumReadChunkByteCount,
                try backing.validateChecksum(
                    descriptor,
                    maximumChunkByteCount: limits.maximumChunkByteCount
                )
            )
        }
        let report = ProjectPackageIOReport(
            archiveByteCount: UInt64(backing.data.count),
            encodedSourceBlobCount: 0,
            encodedSourceBlobByteCount: 0,
            reusedSourceBlobCount: 0,
            reusedSourceBlobByteCount: 0,
            preservedAdjunctCount: adjunctCount,
            preservedAdjunctByteCount: adjunctByteCount,
            maximumReadChunkByteCount: maximumReadChunkByteCount,
            maximumWriteChunkByteCount: 0,
            geometryCopyTelemetry: telemetry
        )
        return ProjectPackageDocument(
            documentID: manifest.documentID,
            productSource: productSource,
            cadSource: cadSource,
            authoredMeshAssets: authoredMeshAssets,
            manifest: manifest,
            backing: backing,
            loadReport: report
        )
    }

    private func prepare(
        _ document: ProjectPackageDocument
    ) throws -> ProjectPackagePreparedOutput {
        let meshPlan = try ProjectPackageMeshPlanner(limits: limits).plan(
            document.authoredMeshAssets
        )
        guard document.productSource.data.count <= limits.maximumProductSourceByteCount else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project Product source exceeds its configured limit."
            )
        }
        if let cadSource = document.cadSource,
            cadSource.data.count > limits.maximumCADSourceByteCount
        {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project CAD source exceeds its configured limit."
            )
        }

        var sourceEntries = [document.productSource.sourceEntry]
        if let cadSource = document.cadSource {
            sourceEntries.append(cadSource.sourceEntry)
        }
        if let catalogEntry = meshPlan.catalogEntry {
            sourceEntries.append(catalogEntry)
        }
        sourceEntries.append(contentsOf: try meshPlan.blobs.map { try $0.reference.sourceEntry })
        let activePaths = Set(sourceEntries.map(\.path))
        if document.retainsUnreferencedSourceBlobs,
            let oldManifest = document.manifest
        {
            for entry in oldManifest.sourceEntries
            where isBlobPath(entry.path) && !activePaths.contains(entry.path)
            {
                sourceEntries.append(entry)
            }
        }
        let manifest = try ProjectPackageManifest(
            documentID: document.documentID,
            sourceEntries: sourceEntries
        )
        let manifestData = try ProjectPackageCanonicalJSON.encode(manifest)
        guard manifestData.count <= limits.maximumManifestByteCount else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project package manifest exceeds its configured limit."
            )
        }

        let oldSourceEntries = Dictionary(
            uniqueKeysWithValues: (document.manifest?.sourceEntries ?? []).map {
                ($0.path, $0)
            }
        )
        var entries: [ProjectPackageOutputEntry] = [
            .data(path: Self.manifestPath, value: manifestData),
        ]
        appendDataOrRetained(
            path: ProjectPackageManifest.productSourcePath,
            data: document.productSource.data,
            sourceEntry: document.productSource.sourceEntry,
            oldSourceEntries: oldSourceEntries,
            backing: document.backing,
            entries: &entries
        )
        if let cadSource = document.cadSource {
            appendDataOrRetained(
                path: ProjectPackageManifest.cadSourcePath,
                data: cadSource.data,
                sourceEntry: cadSource.sourceEntry,
                oldSourceEntries: oldSourceEntries,
                backing: document.backing,
                entries: &entries
            )
        }
        if let catalogEntry = meshPlan.catalogEntry,
            let catalogData = meshPlan.catalogData
        {
            appendDataOrRetained(
                path: ProjectPackageManifest.meshCatalogPath,
                data: catalogData,
                sourceEntry: catalogEntry,
                oldSourceEntries: oldSourceEntries,
                backing: document.backing,
                entries: &entries
            )
        }

        var encodedBlobCount = 0
        var encodedBlobByteCount: UInt64 = 0
        var reusedBlobCount = 0
        var reusedBlobByteCount: UInt64 = 0
        for blob in meshPlan.blobs {
            if let backing = document.backing,
                oldSourceEntries[blob.reference.path] == (try blob.reference.sourceEntry),
                let descriptor = backing.entries[blob.reference.path]
            {
                entries.append(.retained(descriptor))
                reusedBlobCount += 1
                reusedBlobByteCount += blob.reference.byteCount
            } else {
                entries.append(.mesh(blob))
                encodedBlobCount += 1
                encodedBlobByteCount += blob.reference.byteCount
            }
        }
        if document.retainsUnreferencedSourceBlobs,
            let oldManifest = document.manifest,
            let backing = document.backing
        {
            let activeBlobPaths = Set(meshPlan.blobs.map(\.reference.path))
            for entry in oldManifest.sourceEntries
            where isBlobPath(entry.path) && !activeBlobPaths.contains(entry.path)
            {
                guard let descriptor = backing.entries[entry.path] else {
                    throw missing(entry.path)
                }
                entries.append(.retained(descriptor))
                reusedBlobCount += 1
                reusedBlobByteCount += UInt64(descriptor.byteCount)
            }
        }

        var preservedAdjunctCount = 0
        var preservedAdjunctByteCount: UInt64 = 0
        if let backing = document.backing {
            for descriptor in backing.entries.values
            where descriptor.path != Self.manifestPath
                && !descriptor.path.hasPrefix("source/")
            {
                try validateAdjunctPath(descriptor.path)
                entries.append(.retained(descriptor))
                preservedAdjunctCount += 1
                preservedAdjunctByteCount += UInt64(descriptor.byteCount)
            }
        }
        guard entries.count <= limits.maximumEntryCount else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project package output entry count exceeds its configured limit."
            )
        }
        return ProjectPackagePreparedOutput(
            manifest: manifest,
            entries: entries.sorted { $0.path < $1.path },
            telemetry: meshPlan.telemetry,
            encodedBlobCount: encodedBlobCount,
            encodedBlobByteCount: encodedBlobByteCount,
            reusedBlobCount: reusedBlobCount,
            reusedBlobByteCount: reusedBlobByteCount,
            preservedAdjunctCount: preservedAdjunctCount,
            preservedAdjunctByteCount: preservedAdjunctByteCount
        )
    }

    private func appendDataOrRetained(
        path: String,
        data: Data,
        sourceEntry: ProjectPackageSourceEntry,
        oldSourceEntries: [String: ProjectPackageSourceEntry],
        backing: ProjectPackageArchiveBacking?,
        entries: inout [ProjectPackageOutputEntry]
    ) {
        if let backing,
            oldSourceEntries[path] == sourceEntry,
            let descriptor = backing.entries[path]
        {
            entries.append(.retained(descriptor))
        } else {
            entries.append(.data(path: path, value: data))
        }
    }

    private func write(
        _ entries: [ProjectPackageOutputEntry],
        backing: ProjectPackageArchiveBacking?,
        telemetry: GeometryCopyTelemetry,
        to url: URL
    ) throws -> ProjectPackageWriteOutput {
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forWritingTo: url)
        } catch {
            throw ProjectPackageError(
                code: .ioFailure,
                message: "Project package temporary file could not be opened: \(error)."
            )
        }
        var didAttemptClose = false
        do {
            var writer = try ProjectPackageArchiveWriter(
                sink: ProjectPackageFileSink(fileHandle: fileHandle),
                limits: limits
            )
            var updatedTelemetry = telemetry
            for entry in entries {
                switch entry {
                case .data(let path, let data):
                    try writer.writeDataEntry(path: path, data: data)
                case .mesh(let plan):
                    try writer.writeMeshEntry(plan, telemetry: &updatedTelemetry)
                case .retained(let descriptor):
                    guard let backing else {
                        throw ProjectPackageError(
                            code: .ioFailure,
                            message: "Retained project package entry lost its mapped owner."
                        )
                    }
                    try writer.writeRetainedEntry(descriptor, from: backing)
                }
            }
            try writer.finish()
            try fileHandle.synchronize()
            didAttemptClose = true
            try fileHandle.close()
            return ProjectPackageWriteOutput(
                archiveByteCount: writer.sink.writtenByteCount,
                maximumWriteChunkByteCount: writer.sink.maximumWrittenChunkByteCount,
                telemetry: updatedTelemetry
            )
        } catch {
            if !didAttemptClose {
                do {
                    try fileHandle.close()
                } catch let closeError {
                    throw ProjectPackageError(
                        code: .ioFailure,
                        message: "Project package write and descriptor close failed: "
                            + "\(error); \(closeError)."
                    )
                }
            }
            if let packageError = error as? ProjectPackageError {
                throw packageError
            }
            if let meshError = error as? MeshSourceError {
                let code: ProjectPackageError.Code
                switch meshError.code {
                case .resourceLimitExceeded:
                    code = .resourceLimitExceeded
                case .ioFailure:
                    code = .ioFailure
                default:
                    code = .invalidSource
                }
                throw ProjectPackageError(code: code, message: meshError.message)
            }
            throw ProjectPackageError(
                code: .ioFailure,
                message: "Project package file output failed: \(error)."
            )
        }
    }

    private func prepublicationFailure(
        _ error: Error,
        staging: ProjectPackageStaging
    ) -> ProjectPackageError {
        do {
            try cleanupStaging(staging)
        } catch let cleanupError {
            return ProjectPackageError(
                code: .atomicSaveFailure,
                message: "Project package save failed before publication and staging cleanup also failed: "
                    + "\(error); \(cleanupError)."
            )
        }
        if let packageError = error as? ProjectPackageError {
            return packageError
        }
        return ProjectPackageError(
            code: .atomicSaveFailure,
            message: "Project package save failed before publication: \(error)."
        )
    }

    private func createStagingFile(at url: URL) throws {
        do {
            try Data().write(to: url, options: [.withoutOverwriting])
        } catch {
            throw ProjectPackageError(
                code: .ioFailure,
                message: "Project package staging file could not be created: \(error)."
            )
        }
    }

    private static func makeStaging(
        for destinationURL: URL
    ) throws -> ProjectPackageStaging {
        #if canImport(Darwin)
        let directoryURL = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destinationURL,
            create: true
        )
        let packageURL = directoryURL.appendingPathComponent(
            ".rupa-staging-\(UUID().uuidString).rupa",
            isDirectory: false
        )
        return ProjectPackageStaging(
            packageURL: packageURL,
            directoryURL: directoryURL
        )
        #else
        let packageURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        return ProjectPackageStaging(packageURL: packageURL)
        #endif
    }

    private static func cleanupStaging(
        _ staging: ProjectPackageStaging
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: staging.packageURL.path) {
            try fileManager.removeItem(at: staging.packageURL)
        }
        if let directoryURL = staging.directoryURL,
            fileManager.fileExists(atPath: directoryURL.path)
        {
            try fileManager.removeItem(at: directoryURL)
        }
    }

}
