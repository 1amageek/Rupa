import SwiftCAD

struct SlotLineChainResolver: Sendable {
    struct PathVertex: Equatable, Sendable {
        var reference: SketchReference
        var connectedLineEndpointReferences: [SketchReference]
    }

    func resolve(
        sketch: Sketch,
        selectedLineID: SketchEntityID
    ) throws -> [PathVertex] {
        do {
            let chain = try SketchCurveChainResolver(supportedKinds: [.line]).resolveOpenChain(
                in: sketch,
                selectedEntityID: selectedLineID
            )
            return chain.vertices.map { vertex in
                PathVertex(
                    reference: vertex.reference,
                    connectedLineEndpointReferences: vertex.connectedEndpointReferences
                )
            }
        } catch let error as SketchCurveChainResolutionError {
            throw slotLineChainError(for: error)
        }
    }

    private func slotLineChainError(for error: SketchCurveChainResolutionError) -> EditorError {
        switch error {
        case .unsupportedSelectedEntity:
            return EditorError(
                code: .commandInvalid,
                message: "Slot line-chain resolution requires a selected source line target."
            )
        case .degenerateSegment:
            return EditorError(
                code: .commandInvalid,
                message: "Slot source line length must be greater than zero."
            )
        case .branched:
            return EditorError(
                code: .commandInvalid,
                message: "Slot source line chain must not branch."
            )
        case .closed:
            return EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve; closed line chains are not supported."
            )
        case .disconnected:
            return EditorError(
                code: .commandInvalid,
                message: "Slot requires one connected open line chain."
            )
        }
    }
}
