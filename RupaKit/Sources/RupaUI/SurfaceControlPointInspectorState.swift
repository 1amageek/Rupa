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
        var isBoundary: Bool
        var isEditable: Bool
        var selectionReference: SelectionReference
        var isPointDisplayVisible: Bool

        var indexTitle: String {
            "u\(uIndex) / v\(vIndex)"
        }

        var roleTitle: String {
            if let role {
                return role
            }
            return isBoundary ? "Boundary" : "Interior"
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

    private static func entriesByReference(
        from summary: SurfaceSourceSummaryResult
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
                        isBoundary: controlPoint.isBoundary,
                        isEditable: controlPoint.isEditable,
                        selectionReference: controlPoint.selectionReference,
                        isPointDisplayVisible: controlPoint.isPointDisplayVisible
                    )
                }
            }
        }

        return entries
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
