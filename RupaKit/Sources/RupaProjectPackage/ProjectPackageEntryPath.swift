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
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 3,
            components[0] == "adjuncts",
            components[1].isEmpty == false,
            components.dropFirst(2).allSatisfy({ $0.isEmpty == false })
        else {
            throw ProjectPackageError(
                code: .invalidEntryPath,
                message: "Opaque package entries require an adjuncts/<namespace>/... path: \(path)."
            )
        }
    }

    private static func invalid(_ path: String) -> ProjectPackageError {
        ProjectPackageError(
            code: .invalidEntryPath,
            message: "Project package entry path is invalid: \(path)."
        )
    }
}
