import SwiftCAD

/// Shares cumulative preparation and retained output allowances across actual occurrences.
public struct DrawingOccurrenceSectioner: DrawingOccurrenceSectioning {
    private let placements: any DrawingOccurrencePlacementResolving
    private let sectioner: any DocumentDrawingSectioning

    public init(placements: any DrawingOccurrencePlacementResolving = DefaultDrawingOccurrencePlacementResolver(),
                sectioner: any DocumentDrawingSectioning = DocumentDrawingSectioner()) {
        self.placements = placements; self.sectioner = sectioner
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The actual public scene route retains original
    // affine world laws, but complete bounded originalImage/world-plane SSI remains a
    // lower prerequisite for all-domain section/material publication.
    public func sections(document: DesignDocument, evaluated: EvaluatedDocument, savedView: SavedView,
                         on frame: OrthographicProjectionFrame, maximumOccurrences: Int, maximumSections: Int,
                         maximumSourceFaces: Int, maximumComponents: Int, maximumSourceEntities: Int,
                         maximumPreparationWork: Int) throws -> DrawingOccurrenceSections {
        guard maximumSections > 0, maximumComponents > 0, maximumSourceFaces > 0,
              maximumSourceEntities > 0, maximumPreparationWork > 0 else {
            throw EditorError(code: .commandInvalid, message: "Placed section capacities must be positive.")
        }
        let resolved = try placements.placements(document: document, evaluated: evaluated, savedView: savedView,
            maximumOccurrences: maximumOccurrences, maximumPlacements: maximumSections)
        var work = 0, entities = 0, components = 0
        var output: [DrawingOccurrenceSection] = []
        for occurrence in resolved {
            try Task.checkCancellation()
            guard work < maximumPreparationWork, entities < maximumSourceEntities,
                  components <= maximumComponents, output.count < maximumSections else {
                throw EditorError(code: .commandInvalid, message: "Cumulative placed section capacity is exhausted.")
            }
            let result = try sectioner.section(document: document.cadDocument, currentEvaluation: evaluated,
                placement: occurrence.original, on: frame, maximumSourceFaces: maximumSourceFaces,
                maximumComponents: maximumComponents - components,
                maximumSourceEntities: maximumSourceEntities - entities,
                maximumPreparationWork: maximumPreparationWork - work)
            guard result.consumedPreparationWork >= 0,
                  result.consumedPreparationWork <= maximumPreparationWork - work,
                  result.retainedPreparationEntities >= 0,
                  result.retainedPreparationEntities <= maximumSourceEntities - entities,
                  result.components.count <= maximumComponents - components,
                  result.placement == occurrence.original else {
                throw EditorError(code: .evaluationFailed, message: "Placed section producer exceeded its original allowance or changed placement.")
            }
            try result.validateCurrent(evaluated)
            work += result.consumedPreparationWork; entities += result.retainedPreparationEntities
            components += result.components.count
            output.append(DrawingOccurrenceSection(occurrence: occurrence, original: result))
        }
        return DrawingOccurrenceSections(document: document, evaluated: evaluated, savedView: savedView, values: output,
            consumedPreparationWork: work, retainedPreparationEntities: entities)
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Original selected-plane/body words and UV
    // authority are retained. Full SSI, hierarchy callbacks and aggregate body/sewing
    // bytes remain mandatory before whole selected-section completion.
    public func sections(document: DesignDocument, evaluated: EvaluatedDocument, savedView: SavedView,
                         on supports: [BRepDrawingCuttingSupport], projectionFrame: OrthographicProjectionFrame,
                         maximumOccurrences: Int, maximumSections: Int, maximumSourceFaces: Int, maximumComponents: Int,
                         maximumSourceEntities: Int, maximumPreparationWork: Int, maximumPreparationBytes: Int,
                         maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int) throws -> DrawingOccurrenceSections {
        guard maximumSections > 0, maximumSourceFaces > 0, maximumComponents > 0,
              maximumSourceEntities > 0, maximumPreparationWork > 0, maximumPreparationBytes > 0, supports.count <= maximumSections else {
            throw EditorError(code: .commandInvalid, message: "Original selected section capacities or support identities are invalid.")
        }
        var identities: Set<String> = []
        for support in supports {
            guard identities.insert(support.sourceIdentity).inserted else {
                throw EditorError(code: .commandInvalid, message: "Original cutting support identities are duplicated.")
            }
        }
        let resolved = try placements.placements(document: document, evaluated: evaluated, savedView: savedView,
            maximumOccurrences: maximumOccurrences, maximumPlacements: maximumSections)
        var work = 0, entities = 0, bytes = 0, components = 0
        var output: [DrawingOccurrenceSection] = []
        for support in supports {
            for occurrence in resolved {
                try Task.checkCancellation()
                guard work < maximumPreparationWork, entities < maximumSourceEntities, bytes < maximumPreparationBytes,
                      components <= maximumComponents, output.count < maximumSections else {
                    throw EditorError(code: .commandInvalid, message: "Cumulative original selected section allowance is exhausted.")
                }
                let result = try sectioner.section(document: document.cadDocument, currentEvaluation: evaluated,
                    placement: occurrence.original, on: support, projectionFrame: projectionFrame,
                    maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents - components,
                    maximumSourceEntities: maximumSourceEntities - entities, maximumPreparationWork: maximumPreparationWork - work,
                    maximumPreparationBytes: maximumPreparationBytes - bytes, maximumSourceDepth: maximumSourceDepth,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth)
                guard result.consumedPreparationWork >= 0, result.consumedPreparationWork <= maximumPreparationWork - work,
                      result.retainedPreparationEntities >= 0, result.retainedPreparationEntities <= maximumSourceEntities - entities,
                      result.retainedPreparationBytes >= 0, result.retainedPreparationBytes <= maximumPreparationBytes - bytes,
                      result.components.count <= maximumComponents - components,
                      result.placement == occurrence.original, result.cuttingSupport == support else {
                    throw EditorError(code: .evaluationFailed, message: "Original selected section changed source authority or exceeded its allowance.")
                }
                try result.validateCurrent(evaluated)
                work += result.consumedPreparationWork; entities += result.retainedPreparationEntities
                bytes += result.retainedPreparationBytes; components += result.components.count
                output.append(DrawingOccurrenceSection(occurrence: occurrence, original: result))
            }
        }
        return DrawingOccurrenceSections(document: document, evaluated: evaluated, savedView: savedView, values: output,
            consumedPreparationWork: work, retainedPreparationEntities: entities, retainedPreparationBytes: bytes)
    }

}
