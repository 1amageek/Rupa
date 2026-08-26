import RupaCore

@MainActor
struct PatternArrayCurvePathPickService {
    enum Outcome: Equatable, Sendable {
        case waitingForCurve
        case submitted(PatternArrayCurvePathCandidate)
        case failed(String)
    }

    let document: DesignDocument
    let submit: (EditorCommand) -> Void
    let submitPath: ((PatternArrayCurvePath) -> Void)?
    let report: (String, EditorDiagnostic.Severity) -> Void
    let sourceID: PatternArraySourceID

    init(
        document: DesignDocument,
        submit: @escaping (EditorCommand) -> Void,
        submitPath: ((PatternArrayCurvePath) -> Void)? = nil,
        report: @escaping (String, EditorDiagnostic.Severity) -> Void,
        sourceID: PatternArraySourceID
    ) {
        self.document = document
        self.submit = submit
        self.submitPath = submitPath
        self.report = report
        self.sourceID = sourceID
    }

    @discardableResult
    func apply(targets: [SelectionTarget]) -> Outcome {
        guard let target = targets.last else {
            let message = "Pick a sketch line, circle, arc, or spline for the Curve Array path."
            report(message, .warning)
            return .waitingForCurve
        }
        guard let candidate = PatternArrayCurvePathCandidate(
            target: target,
            document: document
        ) else {
            let message = "Curve Array path pick requires a sketch line, circle, arc, or spline."
            report(message, .warning)
            return .waitingForCurve
        }
        if let submitPath {
            submitPath(candidate.path)
            return .submitted(candidate)
        }
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution else {
            let message = "Curve Array path pick requires an existing Pattern Array source."
            report(message, .warning)
            return .failed(message)
        }

        curve.path = candidate.path
        submit(
            .updatePatternArray(
                id: sourceID,
                name: nil,
                definitionID: nil,
                distribution: .curve(curve),
                outputMode: nil
            )
        )
        return .submitted(candidate)
    }
}
