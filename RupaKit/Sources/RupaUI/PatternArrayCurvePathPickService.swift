import RupaCore

@MainActor
struct PatternArrayCurvePathPickService {
    enum Outcome: Equatable, Sendable {
        case waitingForCurve
        case applied(PatternArrayCurvePathCandidate)
        case failed(String)
    }

    let session: EditorSession
    let sourceID: PatternArraySourceID

    @discardableResult
    func apply(targets: [SelectionTarget]) -> Outcome {
        guard let target = targets.last else {
            let message = "Pick a sketch line, circle, arc, or spline for the Curve Array path."
            session.reportToolStatus(message, severity: .warning)
            return .waitingForCurve
        }
        guard let candidate = PatternArrayCurvePathCandidate(
            target: target,
            document: session.document
        ) else {
            let message = "Curve Array path pick requires a sketch line, circle, arc, or spline."
            session.reportToolStatus(message, severity: .warning)
            return .waitingForCurve
        }
        guard session.document.productMetadata.patternArrays[sourceID] != nil else {
            let message = "Curve Array path pick requires an existing Pattern Array source."
            session.reportToolStatus(message, severity: .warning)
            return .failed(message)
        }

        let result = PatternArrayEditingService(
            session: session,
            sourceID: sourceID
        ).setCurvePath(candidate.path)
        guard result != nil else {
            let message = "Curve Array path pick could not update the selected Pattern Array."
            session.reportToolStatus(message, severity: .warning)
            return .failed(message)
        }

        session.reportToolStatus("Curve Array path set to \(candidate.title).")
        return .applied(candidate)
    }
}
