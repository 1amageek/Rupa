import RupaCore
import SwiftCAD

struct SurfaceParameterInspectorState: Equatable, Sendable {
    enum ParameterKind: Equatable, Sendable {
        case knot
        case span

        var title: String {
            switch self {
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
        var value: Double?
        var lowerBound: Double?
        var upperBound: Double?
        var startKnotIndex: Int?
        var endKnotIndex: Int?
        var multiplicity: Int?
        var isBoundary: Bool
        var isEditable: Bool
        var selectionReference: SelectionReference

        var directionTitle: String {
            direction.rawValue.uppercased()
        }

        var kindTitle: String {
            kind.title
        }

        var indexTitle: String {
            switch kind {
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
            isEditable ? "Editable" : "Read Only"
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
            case .knot:
                return value
            case .span:
                guard let lowerBound, let upperBound else {
                    return nil
                }
                return (lowerBound + upperBound) * 0.5
            }
        }
    }

    var entries: [Entry]

    init?(
        selectedReferences: [SelectionReference],
        summaryResult: SurfaceSourceSummaryResult
    ) {
        guard !selectedReferences.isEmpty else {
            return nil
        }

        let entriesByReference = Self.entriesByReference(from: summaryResult)
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
        from summary: SurfaceSourceSummaryResult
    ) -> [SelectionReference: Entry] {
        var entries: [SelectionReference: Entry] = [:]

        for source in summary.sources {
            for patch in source.patches {
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
        case .surface(.knot), .surface(.span):
            return true
        default:
            return false
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
                value: knot.value,
                lowerBound: lowerBound,
                upperBound: upperBound,
                startKnotIndex: nil,
                endKnotIndex: nil,
                multiplicity: knot.multiplicity,
                isBoundary: knot.isBoundary,
                isEditable: knot.isEditable,
                selectionReference: selectionReference
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
                value: nil,
                lowerBound: span.lowerBound,
                upperBound: span.upperBound,
                startKnotIndex: span.startKnotIndex,
                endKnotIndex: span.endKnotIndex,
                multiplicity: nil,
                isBoundary: false,
                isEditable: span.isEditable,
                selectionReference: selectionReference
            )
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
}

private func shortNumber(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...6)))
}

private func editMargin(lowerBound: Double, upperBound: Double) -> Double {
    max((upperBound - lowerBound) * 1.0e-6, 1.0e-9)
}
