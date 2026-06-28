import RupaCore

struct SurfaceControlPointInspectorState: Equatable, Sendable {
    enum CoordinateAxis: Equatable, Sendable {
        case x
        case y
        case z
    }

    struct Entry: Equatable, Sendable, Identifiable {
        var id: String
        var sourceFeatureID: String
        var sourceName: String
        var sourceKind: String
        var patchID: Int
        var facePersistentName: String?
        var basisKind: String
        var uIndex: Int
        var vIndex: Int
        var role: String?
        var point: SurfaceSourceSummaryResult.Point
        var weight: Double
        var isBoundary: Bool
        var isEditable: Bool
        var isWeightEditable: Bool
        var selectionReference: SelectionReference
        var isPointDisplayVisible: Bool
        var isFrameDisplayVisible: Bool
        var frameDetail: SurfaceFrameInspectorState?

        var indexTitle: String {
            "u\(uIndex) / v\(vIndex)"
        }

        var roleTitle: String {
            if let role {
                return role
            }
            return isBoundary ? "Boundary" : "Interior"
        }

        var framePositionTitle: String {
            guard let frameDetail else {
                return "-"
            }
            return frameDetail.positionTitle
        }

        var frameUAxisTitle: String {
            guard let frameDetail else {
                return "-"
            }
            return frameDetail.uAxisTitle
        }

        var frameVAxisTitle: String {
            guard let frameDetail else {
                return "-"
            }
            return frameDetail.vAxisTitle
        }

        var frameNormalTitle: String {
            guard let frameDetail else {
                return "-"
            }
            return frameDetail.normalTitle
        }

        var frameHandednessTitle: String {
            guard let frameDetail else {
                return "-"
            }
            return frameDetail.handednessTitle
        }

        var frameNormalCurvatureTitle: String {
            guard let frameDetail else {
                return "-"
            }
            return frameDetail.normalCurvatureTitle
        }

        var framePrincipalCurvatureTitle: String {
            guard let frameDetail else {
                return "-"
            }
            return frameDetail.principalCurvatureTitle
        }

        var frameGaussianCurvatureTitle: String {
            guard let frameDetail else {
                return "-"
            }
            return frameDetail.gaussianCurvatureTitle
        }
    }

    var entries: [Entry]

    init?(
        selectedReferences: [SelectionReference],
        summaryResult: SurfaceSourceSummaryResult,
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay] = [:]
    ) {
        guard !selectedReferences.isEmpty else {
            return nil
        }

        let entriesByReference = Self.entriesByReference(
            from: summaryResult,
            surfaceFrameDisplays: surfaceFrameDisplays
        )
        var selectedEntries: [Entry] = []
        var seenReferences: Set<SelectionReference> = []
        selectedEntries.reserveCapacity(selectedReferences.count)

        for reference in selectedReferences {
            guard case .surface(.controlPoint) = reference else {
                return nil
            }
            guard seenReferences.insert(reference).inserted else {
                continue
            }
            guard let entry = entriesByReference[reference] else {
                return nil
            }
            selectedEntries.append(entry)
        }

        guard !selectedEntries.isEmpty else {
            return nil
        }
        self.entries = selectedEntries
    }

    var selectedReferences: [SelectionReference] {
        entries.map(\.selectionReference)
    }

    var selectedFrameQueries: [SurfaceFrameQuery] {
        entries.map { entry in
            SurfaceFrameQuery(selectionReference: entry.selectionReference)
        }
    }

    var selectionCount: Int {
        entries.count
    }

    var canEditCoordinates: Bool {
        entries.count == 1 && entries.allSatisfy(\.isEditable)
    }

    var canSlide: Bool {
        entries.allSatisfy(\.isEditable)
    }

    var canMoveInFrame: Bool {
        entries.allSatisfy(\.isEditable) && frameMoveQuery != nil
    }

    var canEditWeight: Bool {
        entries.allSatisfy(\.isWeightEditable)
    }

    var frameMoveQuery: SurfaceFrameQuery? {
        guard let reference = entries.first?.selectionReference else {
            return nil
        }
        return SurfaceFrameQuery(selectionReference: reference)
    }

    var frameTitle: String {
        guard let entry = entries.first else {
            return "None"
        }
        if entries.count == 1 {
            return entry.indexTitle
        }
        return "\(entry.indexTitle) + \(entries.count - 1)"
    }

    var frameDisplayTitle: String {
        commonBoolTitle(entries.map(\.isFrameDisplayVisible), trueTitle: "Visible", falseTitle: "Hidden")
    }

    var sourceTitle: String {
        commonTitle(entries.map(\.sourceName)) ?? "Mixed"
    }

    var patchTitle: String {
        guard let patchID = commonValue(entries.map(\.patchID)) else {
            return "Mixed"
        }
        return "Patch \(patchID)"
    }

    var basisTitle: String {
        commonTitle(entries.map(\.basisKind)) ?? "Mixed"
    }

    var indexTitle: String {
        commonTitle(entries.map(\.indexTitle)) ?? "Mixed"
    }

    var roleTitle: String {
        commonTitle(entries.map(\.roleTitle)) ?? "Mixed"
    }

    var editabilityTitle: String {
        commonBoolTitle(entries.map(\.isEditable), trueTitle: "Editable", falseTitle: "Read Only")
    }

    var boundaryTitle: String {
        commonBoolTitle(entries.map(\.isBoundary), trueTitle: "Boundary", falseTitle: "Interior")
    }

    var displayTitle: String {
        commonBoolTitle(entries.map(\.isPointDisplayVisible), trueTitle: "Visible", falseTitle: "Hidden")
    }

    var pointTitle: String {
        guard entries.count == 1,
              let point = entries.first?.point else {
            return "Mixed"
        }
        return "(\(shortNumber(point.x)), \(shortNumber(point.y)), \(shortNumber(point.z)))"
    }

    var weightTitle: String {
        guard let weight = commonValue(entries.map(\.weight)) else {
            return "Mixed"
        }
        return shortNumber(weight)
    }

    var hasResolvedFrames: Bool {
        !entries.isEmpty && entries.allSatisfy { $0.frameDetail != nil }
    }

    var framePositionTitle: String {
        commonTitle(entries.map(\.framePositionTitle)) ?? "Mixed"
    }

    var frameUAxisTitle: String {
        commonTitle(entries.map(\.frameUAxisTitle)) ?? "Mixed"
    }

    var frameVAxisTitle: String {
        commonTitle(entries.map(\.frameVAxisTitle)) ?? "Mixed"
    }

    var frameNormalTitle: String {
        commonTitle(entries.map(\.frameNormalTitle)) ?? "Mixed"
    }

    var frameHandednessTitle: String {
        commonTitle(entries.map(\.frameHandednessTitle)) ?? "Mixed"
    }

    var frameNormalCurvatureTitle: String {
        commonTitle(entries.map(\.frameNormalCurvatureTitle)) ?? "Mixed"
    }

    var framePrincipalCurvatureTitle: String {
        commonTitle(entries.map(\.framePrincipalCurvatureTitle)) ?? "Mixed"
    }

    var frameGaussianCurvatureTitle: String {
        commonTitle(entries.map(\.frameGaussianCurvatureTitle)) ?? "Mixed"
    }

    func resolvingFrames(
        _ framesByReference: [SelectionReference: SurfaceFrameResult.Frame]
    ) -> SurfaceControlPointInspectorState {
        var nextState = self
        nextState.entries = entries.map { entry in
            var nextEntry = entry
            nextEntry.frameDetail = framesByReference[entry.selectionReference].map {
                SurfaceFrameInspectorState(frame: $0)
            }
            return nextEntry
        }
        return nextState
    }

    private static func entriesByReference(
        from summary: SurfaceSourceSummaryResult,
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay]
    ) -> [SelectionReference: Entry] {
        var entries: [SelectionReference: Entry] = [:]

        for source in summary.sources {
            for patch in source.patches {
                let rolesByReference = Dictionary(
                    patch.controlVertices.map { ($0.selectionReference, $0.role) },
                    uniquingKeysWith: { first, _ in first }
                )

                for controlPoint in patch.controlPoints {
                    entries[controlPoint.selectionReference] = Entry(
                        id: controlPoint.id,
                        sourceFeatureID: source.featureID,
                        sourceName: source.name,
                        sourceKind: source.kind,
                        patchID: patch.patchID,
                        facePersistentName: patch.facePersistentName,
                        basisKind: patch.basis.kind,
                        uIndex: controlPoint.uIndex,
                        vIndex: controlPoint.vIndex,
                        role: rolesByReference[controlPoint.selectionReference],
                        point: controlPoint.point,
                        weight: controlPoint.weight,
                        isBoundary: controlPoint.isBoundary,
                        isEditable: controlPoint.isEditable,
                        isWeightEditable: isWeightEditable(
                            sourceKind: source.kind,
                            controlPoint: controlPoint
                        ),
                        selectionReference: controlPoint.selectionReference,
                        isPointDisplayVisible: controlPoint.isPointDisplayVisible,
                        isFrameDisplayVisible: frameDisplayVisible(
                            for: controlPoint.selectionReference,
                            surfaceFrameDisplays: surfaceFrameDisplays
                        ),
                        frameDetail: nil
                    )
                }
            }
        }

        return entries
    }

    private static func isWeightEditable(
        sourceKind: String,
        controlPoint: SurfaceSourceSummaryResult.ControlPoint
    ) -> Bool {
        switch sourceKind {
        case "bSplineSurface":
            return controlPoint.isEditable
        default:
            return controlPoint.isEditable && controlPoint.isBoundary == false
        }
    }

    private static func frameDisplayVisible(
        for selectionReference: SelectionReference,
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay]
    ) -> Bool {
        do {
            let displayID = try SurfaceFrameDisplayID(
                query: SurfaceFrameQuery(selectionReference: selectionReference)
            )
            return surfaceFrameDisplays[displayID]?.isVisible == true
        } catch {
            return false
        }
    }

    private func commonValue<T: Equatable>(_ values: [T]) -> T? {
        guard let first = values.first else {
            return nil
        }
        guard values.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }

    private func commonTitle(_ values: [String]) -> String? {
        commonValue(values)
    }

    private func commonBoolTitle(
        _ values: [Bool],
        trueTitle: String,
        falseTitle: String
    ) -> String {
        guard let value = commonValue(values) else {
            return "Mixed"
        }
        return value ? trueTitle : falseTitle
    }

    private func shortNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }
}
