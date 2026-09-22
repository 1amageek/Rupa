import Foundation
import RupaCore

enum ViewportEdgeTreatmentPreviewRequest: Equatable, Sendable {
    case chamfer(target: SelectionTarget, distance: Double)
    case fillet(target: SelectionTarget, radius: Double)

    var target: SelectionTarget {
        switch self {
        case .chamfer(let target, _), .fillet(let target, _): return target
        }
    }
}

struct ViewportEdgeTreatmentPreviewDocumentBuilder: Sendable {
    private let objectRegistry: ObjectTypeRegistry

    init(objectRegistry: ObjectTypeRegistry = .builtIn) {
        self.objectRegistry = objectRegistry
    }

    func previewDocument(
        for request: ViewportEdgeTreatmentPreviewRequest,
        in document: DesignDocument,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> DesignDocument {
        var preview = document
        let treatment: BodyEdgeTreatment
        switch request {
        case .chamfer(_, let distance): treatment = .chamfer(distance: .length(distance, .meter))
        case .fillet(_, let radius): treatment = .fillet(radius: .length(radius, .meter))
        }
        let transaction = try preview.prepareBodyEdgeTreatment(
            name: "Edge treatment", target: request.target, treatment: treatment, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration)
        try preview.appendTopologyEdit(transaction, replacing: request.target, objectRegistry: objectRegistry)
        return preview
    }
}
