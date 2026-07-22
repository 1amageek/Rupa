import Foundation

public struct MeshSelectionSet: Codable, Equatable, Sendable {
    public private(set) var elements: [MeshSelectionElement]

    private init(uncheckedElements elements: [MeshSelectionElement]) {
        self.elements = elements
    }

    public init(elements: [MeshSelectionElement] = []) throws {
        self.elements = Self.normalized(elements)
        try validateUnique()
    }

    public var isEmpty: Bool {
        elements.isEmpty
    }

    public func contains(_ element: MeshSelectionElement) -> Bool {
        elements.contains(element)
    }

    public func validated(in source: MeshSource) throws -> MeshSelectionSet {
        for element in elements {
            let exists: Bool
            switch element {
            case .vertex(let id):
                exists = source.vertexIDs.contains(id)
            case .edge(let id):
                exists = source.edgeIDs.contains(id)
            case .face(let id):
                exists = source.faceIDs.contains(id)
            case .corner(let id):
                exists = source.cornerIDs.contains(id)
            }
            guard exists else {
                throw MeshSourceError(
                    code: .invalidReference,
                    message: "Mesh selection references an element that is not present in the source."
                )
            }
        }
        return self
    }

    public func selecting(_ element: MeshSelectionElement) throws -> MeshSelectionSet {
        try MeshSelectionSet(elements: elements + [element])
    }

    public func deselecting(_ element: MeshSelectionElement) throws -> MeshSelectionSet {
        try MeshSelectionSet(elements: elements.filter { $0 != element })
    }

    public func toggling(_ element: MeshSelectionElement) throws -> MeshSelectionSet {
        contains(element) ? try deselecting(element) : try selecting(element)
    }

    public func removingAll() -> MeshSelectionSet {
        MeshSelectionSet(uncheckedElements: [])
    }

    private func validateUnique() throws {
        guard Set(elements).count == elements.count else {
            throw MeshSourceError(
                code: .duplicateID,
                message: "Mesh selection elements must be unique."
            )
        }
    }

    private static func normalized(_ elements: [MeshSelectionElement]) -> [MeshSelectionElement] {
        Array(Set(elements)).sorted { lhs, rhs in
            sortKey(lhs) < sortKey(rhs)
        }
    }

    private static func sortKey(_ element: MeshSelectionElement) -> String {
        switch element {
        case .vertex(let id):
            "vertex.\(id.rawValue)"
        case .edge(let id):
            "edge.\(id.rawValue)"
        case .face(let id):
            "face.\(id.rawValue)"
        case .corner(let id):
            "corner.\(id.rawValue)"
        }
    }
}
