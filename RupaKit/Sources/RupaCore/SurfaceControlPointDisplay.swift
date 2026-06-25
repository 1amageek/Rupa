import SwiftCAD

public struct SurfaceControlPointDisplay: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Hashable, Sendable {
        case visible
        case hidden
    }

    public var id: SurfaceControlPointDisplayID
    public var target: SelectionReference
    public var mode: Mode

    public var isVisible: Bool {
        mode == .visible
    }

    public init(
        id: SurfaceControlPointDisplayID,
        target: SelectionReference,
        mode: Mode
    ) {
        self.id = id
        self.target = target
        self.mode = mode
    }

    public init(
        target: SelectionReference,
        isVisible: Bool
    ) throws {
        self.init(
            id: try SurfaceControlPointDisplayID(selectionReference: target),
            target: target,
            mode: isVisible ? .visible : .hidden
        )
    }

    public func validate(against cadDocument: CADDocument) throws {
        let expectedID = try SurfaceControlPointDisplayID(selectionReference: target)
        guard id == expectedID else {
            throw DocumentValidationError.invalidProductMetadata(
                "Surface control point display IDs must match their target references."
            )
        }
        _ = try SurfaceControlPointSelectionTargetResolver().validateDisplayTarget(
            for: target,
            in: cadDocument
        )
    }
}
