enum CADReferenceCandidateFactory {
    static func candidate(
        for context: CADCandidateContext
    ) throws -> any CADCandidateProtocol {
        try context.validate()
        let delegate: any CADCandidateProtocol = switch context.challenge.category {
        case .line:
            CADLineReferenceCandidate()
        case .rectangle:
            CADRectangleReferenceCandidate()
        case .circle:
            CADCircleReferenceCandidate()
        case .angle:
            CADAngleReferenceCandidate()
        case .box:
            CADBoxReferenceCandidate()
        case .cylinder:
            CADCylinderReferenceCandidate()
        case .constraint:
            CADConstraintReferenceCandidate()
        case .transform:
            CADTransformReferenceCandidate()
        case .compound:
            CADCompoundReferenceCandidate()
        case .sphere:
            CADSphereReferenceCandidate()
        }
        return CADContextCheckingReferenceCandidate(
            expectedContext: context,
            delegate: delegate
        )
    }
}

private struct CADContextCheckingReferenceCandidate: CADCandidateProtocol {
    let expectedContext: CADCandidateContext
    let delegate: any CADCandidateProtocol

    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        guard context == expectedContext else {
            throw CADBenchmarkReferenceRunError.contextMismatch(context.challenge.id)
        }
        return try await delegate.decide(for: context)
    }
}
