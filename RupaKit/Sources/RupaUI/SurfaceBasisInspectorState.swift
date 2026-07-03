import RupaCore
import SwiftCAD

struct SurfaceBasisInspectorState: Equatable, Sendable {
    struct Entry: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            case span
            case knot

            var title: String {
                switch self {
                case .span:
                    return "Span"
                case .knot:
                    return "Knot"
                }
            }

            var systemImage: String {
                switch self {
                case .span:
                    return "square.split.2x1"
                case .knot:
                    return "circle.grid.cross"
                }
            }
        }

        var id: String
        var sourceID: String
        var sourceName: String
        var patchID: Int
        var facePersistentName: String?
        var direction: SurfaceParameterDirection
        var kind: Kind
        var index: Int
        var valueTitle: String
        var editabilityTitle: String
        var selectionReference: SelectionReference
        var isEditable: Bool

        var title: String {
            "\(direction.rawValue.uppercased()) \(kind.title) \(indexTitle)"
        }

        var indexTitle: String {
            switch kind {
            case .span:
                return "s\(index)"
            case .knot:
                return "k\(index)"
            }
        }
    }

    var sourceCount: Int
    var patchCount: Int
    var spanCount: Int
    var knotCount: Int
    var editableSpanCount: Int
    var editableKnotCount: Int
    var entries: [Entry]

    init?(
        summaryResult: SurfaceSourceSummaryResult,
        selectedSceneNodeIDs: Set<String>,
        selectedFeatureIDs: Set<String>,
        selectedFacePersistentNames: Set<String>
    ) {
        var sourceIDs = Set<String>()
        var patchIDs = Set<String>()
        var nextEntries: [Entry] = []

        for source in summaryResult.sources {
            let matchingPatches = Self.matchingPatches(
                in: source,
                selectedSceneNodeIDs: selectedSceneNodeIDs,
                selectedFeatureIDs: selectedFeatureIDs,
                selectedFacePersistentNames: selectedFacePersistentNames
            )
            guard !matchingPatches.isEmpty else {
                continue
            }
            sourceIDs.insert(source.featureID)
            for patch in matchingPatches {
                patchIDs.insert("\(source.featureID):\(patch.patchID)")
                nextEntries.append(contentsOf: Self.spanEntries(source: source, patch: patch, direction: .u))
                nextEntries.append(contentsOf: Self.spanEntries(source: source, patch: patch, direction: .v))
                nextEntries.append(contentsOf: Self.knotEntries(source: source, patch: patch, direction: .u))
                nextEntries.append(contentsOf: Self.knotEntries(source: source, patch: patch, direction: .v))
            }
        }

        guard !nextEntries.isEmpty else {
            return nil
        }

        self.sourceCount = sourceIDs.count
        self.patchCount = patchIDs.count
        self.spanCount = nextEntries.filter { $0.kind == .span }.count
        self.knotCount = nextEntries.filter { $0.kind == .knot }.count
        self.editableSpanCount = nextEntries.filter { $0.kind == .span && $0.isEditable }.count
        self.editableKnotCount = nextEntries.filter { $0.kind == .knot && $0.isEditable }.count
        self.entries = nextEntries.sorted(by: Self.entrySort)
    }

    var canSelectBasisReference: Bool {
        !entries.isEmpty
    }

    var firstEditableSpanReference: SelectionReference? {
        entries.first { $0.kind == .span && $0.isEditable }?.selectionReference
    }

    var firstEditableKnotReference: SelectionReference? {
        entries.first { $0.kind == .knot && $0.isEditable }?.selectionReference
    }

    var firstSelectableReference: SelectionReference? {
        firstEditableSpanReference
            ?? firstEditableKnotReference
            ?? entries.first?.selectionReference
    }

    var sourceTitle: String {
        sourceCount == 1 ? entries.first?.sourceName ?? "Surface" : "\(sourceCount) sources"
    }

    var patchTitle: String {
        patchCount == 1 ? "1 patch" : "\(patchCount) patches"
    }

    var basisTitle: String {
        "\(spanCount) spans, \(knotCount) knots"
    }

    var editableTitle: String {
        "\(editableSpanCount) spans, \(editableKnotCount) knots"
    }

    var previewEntries: [Entry] {
        Array(entries.prefix(6))
    }

    var hiddenEntryCount: Int {
        max(0, entries.count - previewEntries.count)
    }

    private static func matchingPatches(
        in source: SurfaceSourceSummaryResult.Source,
        selectedSceneNodeIDs: Set<String>,
        selectedFeatureIDs: Set<String>,
        selectedFacePersistentNames: Set<String>
    ) -> [SurfaceSourceSummaryResult.Patch] {
        if !selectedFacePersistentNames.isEmpty {
            return source.patches.filter { patch in
                guard let facePersistentName = patch.facePersistentName else {
                    return false
                }
                return selectedFacePersistentNames.contains(facePersistentName)
            }
        }

        let sourceMatchesScene = source.sceneNodeID.map(selectedSceneNodeIDs.contains) == true
        let sourceMatchesFeature = selectedFeatureIDs.contains(source.featureID)
        guard sourceMatchesScene || sourceMatchesFeature else {
            return []
        }
        return source.patches
    }

    private static func spanEntries(
        source: SurfaceSourceSummaryResult.Source,
        patch: SurfaceSourceSummaryResult.Patch,
        direction: SurfaceParameterDirection
    ) -> [Entry] {
        let spans = direction == .u ? patch.basis.uSpans : patch.basis.vSpans
        return spans.compactMap { span in
            guard let selectionReference = span.selectionReference else {
                return nil
            }
            return Entry(
                id: "feature:\(source.featureID)/patch:\(patch.patchID)/\(direction.rawValue)/span:\(span.index)",
                sourceID: source.featureID,
                sourceName: source.name,
                patchID: patch.patchID,
                facePersistentName: patch.facePersistentName,
                direction: direction,
                kind: .span,
                index: span.index,
                valueTitle: "\(shortBasisNumber(span.lowerBound)) ... \(shortBasisNumber(span.upperBound))",
                editabilityTitle: span.isEditable ? "Editable" : "Read Only",
                selectionReference: selectionReference,
                isEditable: span.isEditable
            )
        }
    }

    private static func knotEntries(
        source: SurfaceSourceSummaryResult.Source,
        patch: SurfaceSourceSummaryResult.Patch,
        direction: SurfaceParameterDirection
    ) -> [Entry] {
        let knots = direction == .u ? patch.basis.uKnotVector : patch.basis.vKnotVector
        return knots.compactMap { knot in
            guard let selectionReference = knot.selectionReference else {
                return nil
            }
            return Entry(
                id: "feature:\(source.featureID)/patch:\(patch.patchID)/\(direction.rawValue)/knot:\(knot.index)",
                sourceID: source.featureID,
                sourceName: source.name,
                patchID: patch.patchID,
                facePersistentName: patch.facePersistentName,
                direction: direction,
                kind: .knot,
                index: knot.index,
                valueTitle: shortBasisNumber(knot.value),
                editabilityTitle: knot.isEditable ? "Editable" : "Read Only",
                selectionReference: selectionReference,
                isEditable: knot.isEditable
            )
        }
    }

    private static func entrySort(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.sourceID != rhs.sourceID {
            return lhs.sourceID < rhs.sourceID
        }
        if lhs.patchID != rhs.patchID {
            return lhs.patchID < rhs.patchID
        }
        if lhs.direction != rhs.direction {
            return lhs.direction.rawValue < rhs.direction.rawValue
        }
        if lhs.kind != rhs.kind {
            return lhs.kind == .span
        }
        return lhs.index < rhs.index
    }
}

private func shortBasisNumber(_ value: Double) -> String {
    let normalizedValue = abs(value) < 1.0e-12 ? 0.0 : value
    return normalizedValue.formatted(.number.precision(.fractionLength(0...6)))
}
