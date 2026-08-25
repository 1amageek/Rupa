extension ProjectPackageStore {
    func requiredEntry(
        at path: String,
        in manifest: ProjectPackageManifest,
        mediaType: String,
        schemaVersion: UInt32,
        fingerprintAlgorithm: String,
        maximumByteCount: Int
    ) throws -> ProjectPackageSourceEntry {
        guard let entry = manifest.sourceEntry(at: path) else {
            throw missing(path)
        }
        try validateEntry(
            entry,
            mediaType: mediaType,
            schemaVersion: schemaVersion,
            fingerprintAlgorithm: fingerprintAlgorithm,
            maximumByteCount: maximumByteCount
        )
        return entry
    }

    func validateEntry(
        _ entry: ProjectPackageSourceEntry,
        mediaType: String,
        schemaVersion: UInt32,
        fingerprintAlgorithm: String,
        maximumByteCount: Int
    ) throws {
        guard entry.mediaType == mediaType,
            entry.schemaVersion == schemaVersion,
            entry.fingerprint.algorithm == fingerprintAlgorithm
        else {
            throw ProjectPackageError(
                code: .unsupportedSchema,
                message: "Project package source contract is unsupported: \(entry.path)."
            )
        }
        guard entry.byteCount <= UInt64(maximumByteCount) else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project package source exceeds its configured limit: \(entry.path)."
            )
        }
    }

    func validateDeclaredSourcePaths(
        _ manifest: ProjectPackageManifest,
        backing: ProjectPackageArchiveBacking
    ) throws {
        let declaredPaths = Set(manifest.sourceEntries.map(\.path))
        for entry in manifest.sourceEntries {
            guard entry.byteCount <= limits.maximumSourceBlobByteCount,
                backing.entries[entry.path] != nil
            else {
                throw ProjectPackageError(
                    code: backing.entries[entry.path] == nil
                        ? .missingEntry : .resourceLimitExceeded,
                    message: "Declared project source entry is missing or exceeds limits: "
                        + entry.path
                )
            }
        }
        for path in backing.entries.keys where path.hasPrefix("source/") {
            guard declaredPaths.contains(path) else {
                throw ProjectPackageError(
                    code: .invalidManifest,
                    message: "Project package contains an undeclared source entry: \(path)."
                )
            }
        }
    }

    func validateMeshReference(
        _ reference: ProjectSourceBlobReference
    ) throws {
        guard reference.mediaType == ProjectPackageMeshDigestSink.mediaType,
            reference.schemaVersion == ProjectPackageMeshDigestSink.schemaVersion,
            reference.fingerprint.algorithm == ProjectPackageMeshDigestSink.fingerprintAlgorithm
        else {
            throw ProjectPackageError(
                code: .unsupportedVersion,
                message: "Project Mesh blob contract is unsupported."
            )
        }
        guard reference.byteCount <= limits.maximumSourceBlobByteCount else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project Mesh blob exceeds its configured limit."
            )
        }
    }

    func isBlobPath(_ path: String) -> Bool {
        path.hasPrefix(ProjectSourceBlobReference.pathPrefix)
    }

    func validateAdjunctPath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 3,
            components[0] == "adjuncts",
            components[1].isEmpty == false,
            components.dropFirst(2).allSatisfy({ $0.isEmpty == false })
        else {
            throw ProjectPackageError(
                code: .invalidEntryPath,
                message: "Unknown project package entries require an adjuncts/<namespace>/... path."
            )
        }
    }

    func missing(_ path: String) -> ProjectPackageError {
        ProjectPackageError(
            code: .missingEntry,
            message: "Project package entry is missing: \(path)."
        )
    }
}
