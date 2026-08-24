import Foundation

public protocol ProjectPackageWriting: Sendable {
    func save(
        _ document: ProjectPackageDocument,
        to url: URL
    ) throws -> ProjectPackageSaveResult
}
