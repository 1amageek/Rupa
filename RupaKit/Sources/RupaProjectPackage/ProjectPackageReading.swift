import Foundation

public protocol ProjectPackageReading: Sendable {
    func load(from url: URL) throws -> ProjectPackageDocument
}
