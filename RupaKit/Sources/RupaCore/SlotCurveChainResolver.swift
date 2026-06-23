import SwiftCAD

struct SlotCurveChainResolver: Sendable {
    struct PathSegment: Equatable, Sendable {
        var entityID: SketchEntityID
        var startReference: SketchReference
        var endReference: SketchReference
    }

    func resolve(
        sketch: Sketch,
        selectedEntityID: SketchEntityID
    ) throws -> [PathSegment] {
        do {
            let chain = try SketchCurveChainResolver(supportedKinds: [.line, .arc]).resolveOpenChain(
                in: sketch,
                selectedEntityID: selectedEntityID
            )
            return chain.segments.map { segment in
                PathSegment(
                    entityID: segment.entityID,
                    startReference: segment.startReference,
                    endReference: segment.endReference
                )
            }
        } catch let error as SketchCurveChainResolutionError {
            throw slotCurveChainError(for: error)
        }
    }

    private func slotCurveChainError(for error: SketchCurveChainResolutionError) -> EditorError {
        switch error {
        case .unsupportedSelectedEntity:
            return EditorError(
                code: .commandInvalid,
                message: "Slot curve-chain resolution requires a selected source line or arc target."
            )
        case .degenerateSegment:
            return EditorError(
                code: .commandInvalid,
                message: "Slot source curve segment length must be greater than zero."
            )
        case .branched:
            return EditorError(
                code: .commandInvalid,
                message: "Slot source curve chain must not branch."
            )
        case .closed:
            return EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve; closed curve chains are not supported."
            )
        case .disconnected:
            return EditorError(
                code: .commandInvalid,
                message: "Slot requires one connected open curve chain."
            )
        }
    }
}
