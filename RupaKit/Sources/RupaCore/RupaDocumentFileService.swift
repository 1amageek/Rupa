import Foundation
import SwiftCAD

public struct RupaDocumentFileService: Sendable {
    private let packageStore: RupaDocumentPackageStore

    public init(packageStore: RupaDocumentPackageStore = RupaDocumentPackageStore()) {
        self.packageStore = packageStore
    }

    public func load(from url: URL) throws -> RupaDocument {
        do {
            return try packageStore.load(from: url)
        } catch {
            throw RupaError(
                code: .documentLoadFailed,
                message: error.localizedDescription
            )
        }
    }

    public func save(_ document: RupaDocument, to url: URL) throws {
        do {
            try packageStore.save(document, to: url)
        } catch {
            throw RupaError(
                code: .documentSaveFailed,
                message: error.localizedDescription
            )
        }
    }
}
