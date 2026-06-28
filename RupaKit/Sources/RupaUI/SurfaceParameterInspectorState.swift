import RupaCore
import SwiftCAD

struct SurfaceParameterInspectorState: Equatable, Sendable {
    enum ParameterKind: Equatable, Sendable {
        case address
        case knot
        case span

        var title: String {
            switch self {
            case .address:
                return "Address"
            case .knot:
                return "Knot"
            case .span:
                return "Span"
            }
        }
    }

    struct Entry: Equatable, Sendable, Identifiable {
        var id: String
        var sourceFeatureID: String
        var sourceName: String
        var sourceKind: String
        var patchID: Int
        var facePersistentName: String?
        var basisKind: String
        var direction: SurfaceParameterDirection
        var kind: ParameterKind
        var index: Int
        var u: Double?
        var v: Double?
        var value: Double?
        var lowerBound: Double?
        var upperBound: Double?
        var startKnotIndex: Int?
        var endKnotIndex: Int?
        var multiplicity: Int?
        var isBoundary: Bool
        var isEditable: Bool
        var selectionReference: SelectionReference
        var frameQuery: SurfaceFrameQuery?
        var isFrameDisplayVisible: Bool
        var frameDetail: SurfaceFrameInspectorState?

        var directionTitle: String {
            switch kind {
            case .address:
                return "UV"
            case .knot, .span:
                return direction.rawValue.uppercased()
            }
        }

        var kindTitle: String {
            kind.title
        }

        var indexTitle: String {
            switch kind {
            case .address:
                return id.split(separator: "/").last.map(String.init) ?? id
            case .knot:
                return "k\(index)"
            case .span:
                return "s\(index)"
            }
        }

        var multiplicityTitle: String {
            guard let multiplicity else {
                return "-"
            }
            return "\(multiplicity)"
        }

        var valueTitle: String {
            switch kind {
            case .address:
                guard let u, let v else {
                    return "-"
                }
                return "(\(shortNumber(u)), \(shortNumber(v)))"
            case .knot:
                guard let value else {
                    return "-"
                }
                return shortNumber(value)
            case .span:
                guard let lowerBound, let upperBound else {
                    return "-"
                }
                return "\(shortNumber(lowerBound)) ... \(shortNumber(upperBound))"
            }
        }

        var boundaryTitle: String {
            isBoundary ? "Boundary" : "Interior"
        }

        var editabilityTitle: String {
            if kind == .address {
                return frameQuery == nil ? "Reference" : "Frame Query"
            }
            return isEditable ? "Editable" : "Read Only"
        }

        var canSetKnotValue: Bool {
            guard kind == .knot,
                  isEditable,
                  let range = knotValueRange else {
                return false
            }
            return range.lowerBound < range.upperBound
        }

        var canInsertKnot: Bool {
            guard isEditable else {
                return false
            }
            switch kind {
            case .address:
                return false
            case .knot:
                return value?.isFinite == true
            case .span:
                guard let range = insertionRange else {
                    return false
                }
                return range.lowerBound < range.upperBound
            }
        }

        var knotValueRange: ClosedRange<Double>? {
            guard kind == .knot,
                  let lowerBound,
                  let upperBound,
                  lowerBound.isFinite,
                  upperBound.isFinite,
                  lowerBound < upperBound else {
                return nil
            }
            let margin = editMargin(lowerBound: lowerBound, upperBound: upperBound)
            let lowerValue = lowerBound + margin
            let upperValue = upperBound - margin
            guard lowerValue < upperValue else {
                return nil
            }
            return lowerValue ... upperValue
        }

        var insertionRange: ClosedRange<Double>? {
            switch kind {
            case .address:
                return nil
            case .knot:
                guard let value, value.isFinite else {
                    return nil
                }
                return value ... value
            case .span:
                guard let lowerBound,
                      let upperBound,
                      lowerBound.isFinite,
                      upperBound.isFinite,
                      lowerBound < upperBound else {
                    return nil
                }
                let margin = editMargin(lowerBound: lowerBound, upperBound: upperBound)
                let lowerValue = lowerBound + margin
                let upperValue = upperBound - margin
                guard lowerValue < upperValue else {
                    return nil
                }
                return lowerValue ... upperValue
            }
        }

        var recommendedInsertionValue: Double? {
            switch kind {
            case .address:
                return nil
            case .knot:
                return value
            case .span:
                guard let lowerBound, let upperBound else {
                    return nil
                }
                return (lowerBound + upperBound) * 0.5
            }
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
            guard Self.isSurfaceParameterReference(reference) else {
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

    var selectionCount: Int {
        entries.count
    }

    var canSetKnotValue: Bool {
        entries.count == 1 && entries.allSatisfy(\.canSetKnotValue)
    }

    var canInsertKnot: Bool {
        entries.count == 1 && entries.allSatisfy(\.canInsertKnot)
    }

    var canToggleFrameDisplay: Bool {
        !entries.isEmpty && entries.allSatisfy { $0.frameQuery != nil }
    }

    var selectedFrameQueries: [SurfaceFrameQuery] {
        entries.compactMap(\.frameQuery)
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

    var kindTitle: String {
        commonTitle(entries.map(\.kindTitle)) ?? "Mixed"
    }

    var directionTitle: String {
        commonTitle(entries.map(\.directionTitle)) ?? "Mixed"
    }

    var indexTitle: String {
        commonTitle(entries.map(\.indexTitle)) ?? "Mixed"
    }

    var valueTitle: String {
        commonTitle(entries.map(\.valueTitle)) ?? "Mixed"
    }

    var multiplicityTitle: String {
        commonTitle(entries.map(\.multiplicityTitle)) ?? "Mixed"
    }

    var boundaryTitle: String {
        commonTitle(entries.map(\.boundaryTitle)) ?? "Mixed"
    }

    var editabilityTitle: String {
        commonTitle(entries.map(\.editabilityTitle)) ?? "Mixed"
    }

    var frameDisplayTitle: String {
        commonBoolTitle(entries.map(\.isFrameDisplayVisible), trueTitle: "Visible", falseTitle: "Hidden")
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
    ) -> SurfaceParameterInspectorState {
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

    func clampedKnotValue(_ value: Double) -> Double? {
        guard canSetKnotValue,
              let range = entries.first?.knotValueRange,
              value.isFinite else {
            return nil
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    func clampedInsertionValue(_ value: Double) -> Double? {
        guard canInsertKnot,
              let entry = entries.first else {
            return nil
        }
        switch entry.kind {
        case .address:
            return nil
        case .knot:
            return entry.value
        case .span:
            guard let range = entry.insertionRange,
                  value.isFinite else {
                return nil
            }
            return min(max(value, range.lowerBound), range.upperBound)
        }
    }

    func defaultInsertionValue(fallback: Double) -> Double {
        guard let entry = entries.first else {
            return fallback
        }
        let candidate = entry.recommendedInsertionValue ?? fallback
        return clampedInsertionValue(candidate) ?? fallback
    }

    private static func entriesByReference(
        from summary: SurfaceSourceSummaryResult,
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay]
    ) -> [SelectionReference: Entry] {
        var entries: [SelectionReference: Entry] = [:]

        for source in summary.sources {
            for patch in source.patches {
                addParameterAddresses(
                    patch.parameterAddresses,
                    source: source,
                    patch: patch,
                    surfaceFrameDisplays: surfaceFrameDisplays,
                    to: &entries
                )
                addFrameSamples(
                    patch.frameSamples,
                    source: source,
                    patch: patch,
                    to: &entries
                )
                addKnots(
                    patch.basis.uKnotVector,
                    knotValues: patch.basis.uKnots,
                    direction: .u,
                    source: source,
                    patch: patch,
                    to: &entries
                )
                addKnots(
                    patch.basis.vKnotVector,
                    knotValues: patch.basis.vKnots,
                    direction: .v,
                    source: source,
                    patch: patch,
                    to: &entries
                )
                addSpans(
                    patch.basis.uSpans,
                    direction: .u,
                    source: source,
                    patch: patch,
                    to: &entries
                )
                addSpans(
                    patch.basis.vSpans,
                    direction: .v,
                    source: source,
                    patch: patch,
                    to: &entries
                )
            }
        }

        return entries
    }

    private static func isSurfaceParameterReference(_ reference: SelectionReference) -> Bool {
        switch reference {
        case .surface(.parameter), .surface(.knot), .surface(.span):
            return true
        default:
            return false
        }
    }

    private static func addParameterAddresses(
        _ addresses: [SurfaceSourceSummaryResult.ParameterAddress],
        source: SurfaceSourceSummaryResult.Source,
        patch: SurfaceSourceSummaryResult.Patch,
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay],
        to entries: inout [SelectionReference: Entry]
    ) {
        for address in addresses {
            guard let selectionReference = address.selectionReference else {
                continue
            }
            let frameQuery = SurfaceFrameQuery(selectionReference: selectionReference)
            entries[selectionReference] = Entry(
                id: address.id,
                sourceFeatureID: source.featureID,
                sourceName: source.name,
                sourceKind: source.kind,
                patchID: patch.patchID,
                facePersistentName: patch.facePersistentName,
                basisKind: patch.basis.kind,
                direction: .u,
                kind: .address,
                index: 0,
                u: address.u,
                v: address.v,
                value: nil,
                lowerBound: nil,
                upperBound: nil,
                startKnotIndex: nil,
                endKnotIndex: nil,
                multiplicity: nil,
                isBoundary: isBoundaryAddress(address, patch: patch),
                isEditable: false,
                selectionReference: selectionReference,
                frameQuery: frameQuery,
                isFrameDisplayVisible: frameDisplayVisible(
                    for: frameQuery,
                    surfaceFrameDisplays: surfaceFrameDisplays
                ),
                frameDetail: nil
            )
        }
    }

    private static func addFrameSamples(
        _ samples: [SurfaceSourceSummaryResult.FrameSample],
        source: SurfaceSourceSummaryResult.Source,
        patch: SurfaceSourceSummaryResult.Patch,
        to entries: inout [SelectionReference: Entry]
    ) {
        for sample in samples {
            let frameQuery = SurfaceFrameQuery(selectionReference: sample.selectionReference)
            entries[sample.selectionReference] = Entry(
                id: sample.id,
                sourceFeatureID: source.featureID,
                sourceName: source.name,
                sourceKind: source.kind,
                patchID: patch.patchID,
                facePersistentName: patch.facePersistentName,
                basisKind: patch.basis.kind,
                direction: .u,
                kind: .address,
                index: 0,
                u: sample.u,
                v: sample.v,
                value: nil,
                lowerBound: nil,
                upperBound: nil,
                startKnotIndex: nil,
                endKnotIndex: nil,
                multiplicity: nil,
                isBoundary: isBoundaryUV(u: sample.u, v: sample.v, patch: patch),
                isEditable: false,
                selectionReference: sample.selectionReference,
                frameQuery: frameQuery,
                isFrameDisplayVisible: sample.isFrameDisplayVisible,
                frameDetail: nil
            )
        }
    }

    private static func addKnots(
        _ knots: [SurfaceSourceSummaryResult.Basis.Knot],
        knotValues: [Double],
        direction: SurfaceParameterDirection,
        source: SurfaceSourceSummaryResult.Source,
        patch: SurfaceSourceSummaryResult.Patch,
        to entries: inout [SelectionReference: Entry]
    ) {
        for knot in knots {
            guard let selectionReference = knot.selectionReference else {
                continue
            }
            let lowerBound = previousKnotValue(before: knot.index, in: knotValues)
            let upperBound = nextKnotValue(after: knot.index, in: knotValues)
            entries[selectionReference] = Entry(
                id: "feature:\(source.featureID)/patch:\(patch.patchID)/\(knot.id)",
                sourceFeatureID: source.featureID,
                sourceName: source.name,
                sourceKind: source.kind,
                patchID: patch.patchID,
                facePersistentName: patch.facePersistentName,
                basisKind: patch.basis.kind,
                direction: direction,
                kind: .knot,
                index: knot.index,
                u: nil,
                v: nil,
                value: knot.value,
                lowerBound: lowerBound,
                upperBound: upperBound,
                startKnotIndex: nil,
                endKnotIndex: nil,
                multiplicity: knot.multiplicity,
                isBoundary: knot.isBoundary,
                isEditable: knot.isEditable,
                selectionReference: selectionReference,
                frameQuery: nil,
                isFrameDisplayVisible: false,
                frameDetail: nil
            )
        }
    }

    private static func addSpans(
        _ spans: [SurfaceSourceSummaryResult.Basis.Span],
        direction: SurfaceParameterDirection,
        source: SurfaceSourceSummaryResult.Source,
        patch: SurfaceSourceSummaryResult.Patch,
        to entries: inout [SelectionReference: Entry]
    ) {
        for span in spans {
            guard let selectionReference = span.selectionReference else {
                continue
            }
            entries[selectionReference] = Entry(
                id: "feature:\(source.featureID)/patch:\(patch.patchID)/\(span.id)",
                sourceFeatureID: source.featureID,
                sourceName: source.name,
                sourceKind: source.kind,
                patchID: patch.patchID,
                facePersistentName: patch.facePersistentName,
                basisKind: patch.basis.kind,
                direction: direction,
                kind: .span,
                index: span.index,
                u: nil,
                v: nil,
                value: nil,
                lowerBound: span.lowerBound,
                upperBound: span.upperBound,
                startKnotIndex: span.startKnotIndex,
                endKnotIndex: span.endKnotIndex,
                multiplicity: nil,
                isBoundary: false,
                isEditable: span.isEditable,
                selectionReference: selectionReference,
                frameQuery: nil,
                isFrameDisplayVisible: false,
                frameDetail: nil
            )
        }
    }

    private static func isBoundaryAddress(
        _ address: SurfaceSourceSummaryResult.ParameterAddress,
        patch: SurfaceSourceSummaryResult.Patch
    ) -> Bool {
        isBoundaryUV(u: address.u, v: address.v, patch: patch)
    }

    private static func isBoundaryUV(
        u: Double,
        v: Double,
        patch: SurfaceSourceSummaryResult.Patch
    ) -> Bool {
        isBoundaryValue(u, range: patch.uDomain)
            || isBoundaryValue(v, range: patch.vDomain)
    }

    private static func isBoundaryValue(
        _ value: Double,
        range: SurfaceSourceSummaryResult.ParameterRange
    ) -> Bool {
        let tolerance = max(abs(range.upperBound - range.lowerBound), 1.0) * 1.0e-9
        return abs(value - range.lowerBound) <= tolerance
            || abs(value - range.upperBound) <= tolerance
    }

    private static func frameDisplayVisible(
        for query: SurfaceFrameQuery,
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay]
    ) -> Bool {
        do {
            let displayID = try SurfaceFrameDisplayID(query: query)
            return surfaceFrameDisplays[displayID]?.isVisible == true
        } catch {
            return false
        }
    }

    private static func previousKnotValue(before index: Int, in knots: [Double]) -> Double? {
        let previousIndex = index - 1
        guard knots.indices.contains(previousIndex) else {
            return nil
        }
        return knots[previousIndex]
    }

    private static func nextKnotValue(after index: Int, in knots: [Double]) -> Double? {
        let nextIndex = index + 1
        guard knots.indices.contains(nextIndex) else {
            return nil
        }
        return knots[nextIndex]
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
}

private func shortNumber(_ value: Double) -> String {
    let normalizedValue = abs(value) < 1.0e-12 ? 0.0 : value
    return normalizedValue.formatted(.number.precision(.fractionLength(0...6)))
}

private func editMargin(lowerBound: Double, upperBound: Double) -> Double {
    max((upperBound - lowerBound) * 1.0e-6, 1.0e-9)
}
