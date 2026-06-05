import Foundation
import SwiftCAD

public struct DocumentFileService: Sendable {
    private let packageStore: DocumentPackageStore

    public init(packageStore: DocumentPackageStore = DocumentPackageStore()) {
        self.packageStore = packageStore
    }

    public func load(from url: URL) throws -> DesignDocument {
        do {
            return try packageStore.load(from: url)
        } catch {
            throw EditorError(
                code: .documentLoadFailed,
                message: error.localizedDescription
            )
        }
    }

    public func save(_ document: DesignDocument, to url: URL) throws {
        do {
            try packageStore.save(document, to: url)
        } catch {
            throw EditorError(
                code: .documentSaveFailed,
                message: error.localizedDescription
            )
        }
    }
}
