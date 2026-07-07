import Foundation
import RupaCore

enum ViewportEdgeTreatmentPreviewRequest: Equatable, Sendable {
    case chamfer(target: SelectionTarget, distance: Double)
    case fillet(target: SelectionTarget, radius: Double, segmentCount: Int)
}

struct ViewportEdgeTreatmentPreviewDocumentBuilder: Sendable {
    private let objectRegistry: ObjectTypeRegistry

    init(objectRegistry: ObjectTypeRegistry = .builtIn) {
        self.objectRegistry = objectRegistry
    }

    func previewDocument(
        for request: ViewportEdgeTreatmentPreviewRequest,
        in document: DesignDocument
    ) throws -> DesignDocument {
        var preview = document
        switch request {
        case .chamfer(let target, let distance):
            try preview.chamferBodyEdges(
                targets: [target],
                distance: .length(distance, .meter),
                objectRegistry: objectRegistry
            )
        case .fillet(let target, let radius, let segmentCount):
            try preview.filletBodyEdges(
                targets: [target],
                radius: .length(radius, .meter),
                segmentCount: segmentCount,
                objectRegistry: objectRegistry
            )
        }
        return preview
    }
}
