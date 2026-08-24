enum ProjectPackageEntryPath {
    static let maximumUTF8ByteCount = 4_096

    static func validate(_ path: String) throws {
        guard !path.isEmpty,
            path.utf8.count <= maximumUTF8ByteCount,
            !path.hasPrefix("/"),
            !path.hasSuffix("/"),
            !path.contains("\\"),
            path.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F })
        else {
            throw invalid(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw invalid(path)
        }
    }

    static func validateSourcePath(_ path: String) throws {
        try validate(path)
        guard path.hasPrefix("source/") else {
            throw ProjectPackageError(
                code: .invalidEntryPath,
                message: "Project source entries must live below source/: \(path)."
            )
        }
    }

    static func validatePreservedAdjunctPath(_ path: String) throws {
        try validate(path)
        let isAllowed = path.hasPrefix("records/")
            || path.hasPrefix("artifacts/")
            || path.hasPrefix("extensions/")
        guard isAllowed else {
            throw ProjectPackageError(
                code: .invalidEntryPath,
                message: "Opaque package entries must use records/, artifacts/, or extensions/: \(path)."
            )
        }
        if path.hasPrefix("extensions/") {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count >= 3 else {
                throw invalid(path)
            }
        }
    }

    private static func invalid(_ path: String) -> ProjectPackageError {
        ProjectPackageError(
            code: .invalidEntryPath,
            message: "Project package entry path is invalid: \(path)."
        )
    }
}
