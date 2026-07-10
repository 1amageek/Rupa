import Foundation

extension DesignDocument {
    public mutating func rename(_ name: String, updatedAt: Date = Date()) {
        cadDocument.metadata.name = name
        cadDocument.metadata.updatedAt = updatedAt
    }
}
