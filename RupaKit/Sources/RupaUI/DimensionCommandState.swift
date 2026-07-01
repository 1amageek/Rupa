import Foundation
import RupaCore

struct DimensionCommandEntry: Equatable {
    enum Source: Equatable {
        case object(ObjectDimensionKind)
        case sketch(SketchEntityDimensionKind)
    }

    enum ValueKind: Equatable {
        case length
        case angle
    }

    var target: SelectionTarget
    var source: Source
    var label: String
    var sourceTitle: String
    var resolvedValue: Double
    var valueKind: ValueKind
    var isPrimaryForTarget: Bool

    init(
        target: SelectionTarget,
        source: Source,
        label: String,
        sourceTitle: String,
        resolvedValue: Double,
        valueKind: ValueKind,
        isPrimaryForTarget: Bool
    ) {
        self.target = target
        self.source = source
        self.label = label
        self.sourceTitle = sourceTitle
        self.resolvedValue = resolvedValue
        self.valueKind = valueKind
        self.isPrimaryForTarget = isPrimaryForTarget
    }

    init(object entry: ObjectDimensionSummaryResult.Entry) {
        self.target = entry.target
        self.source = .object(entry.kind)
        self.label = entry.label
        self.sourceTitle = switch entry.sourceKind {
        case .box:
            "Box"
        case .cylinder:
            "Cylinder"
        }
        self.resolvedValue = entry.resolvedMeters
        self.valueKind = .length
        self.isPrimaryForTarget = entry.isPrimaryForTarget
    }

    init(sketch entry: SketchDimensionSummaryResult.Entry) {
        self.target = entry.target
        self.source = .sketch(entry.kind)
        self.label = entry.label
        self.sourceTitle = entry.entityKind.capitalized
        self.resolvedValue = entry.resolvedValue
        self.valueKind = entry.kind == .angle ? .angle : .length
        self.isPrimaryForTarget = entry.isPrimaryForTarget
    }
}

struct DimensionCommandState: Equatable {
    var entries: [DimensionCommandEntry]
    var activeIndex: Int
    var draftValue: Double?
    var isInputModeActive: Bool

    init(
        entries: [DimensionCommandEntry] = [],
        activeIndex: Int = 0,
        draftValue: Double? = nil,
        isInputModeActive: Bool = false
    ) {
        self.entries = entries
        self.activeIndex = activeIndex
        self.draftValue = draftValue
        self.isInputModeActive = isInputModeActive
        normalize()
    }

    static var inactive: DimensionCommandState {
        DimensionCommandState()
    }

    var isActive: Bool {
        !entries.isEmpty
    }

    var activeEntry: DimensionCommandEntry? {
        guard entries.indices.contains(activeIndex) else {
            return nil
        }
        return entries[activeIndex]
    }

    var activeOrdinal: Int {
        guard isActive else {
            return 0
        }
        return activeIndex + 1
    }

    var activeCount: Int {
        entries.count
    }

    var currentValue: Double? {
        draftValue ?? activeEntry?.resolvedValue
    }

    var canCommit: Bool {
        guard let entry = activeEntry,
              let value = currentValue,
              value.isFinite else {
            return false
        }
        switch entry.valueKind {
        case .length:
            return value > 0.0
        case .angle:
            return true
        }
    }

    mutating func activate(entries nextEntries: [DimensionCommandEntry]) {
        entries = nextEntries.filter { entry in
            guard entry.resolvedValue.isFinite else {
                return false
            }
            switch entry.valueKind {
            case .length:
                return entry.resolvedValue > 0.0
            case .angle:
                return true
            }
        }
        guard !entries.isEmpty else {
            deactivate()
            return
        }
        activeIndex = entries.firstIndex { $0.isPrimaryForTarget } ?? entries.startIndex
        draftValue = entries[activeIndex].resolvedValue
        isInputModeActive = false
    }

    mutating func activateInputMode() {
        guard let activeEntry else {
            deactivate()
            return
        }
        if draftValue == nil {
            draftValue = activeEntry.resolvedValue
        }
        isInputModeActive = true
    }

    mutating func handleTab() {
        guard isActive else {
            return
        }
        if !isInputModeActive {
            activateInputMode()
            return
        }
        focusNext()
    }

    mutating func focusNext() {
        guard entries.count > 1 else {
            activateInputMode()
            return
        }
        activeIndex = entries.index(after: activeIndex)
        if activeIndex == entries.endIndex {
            activeIndex = entries.startIndex
        }
        resetDraftForActiveEntry()
    }

    mutating func focusPrevious() {
        guard entries.count > 1 else {
            activateInputMode()
            return
        }
        if activeIndex == entries.startIndex {
            activeIndex = entries.index(before: entries.endIndex)
        } else {
            activeIndex = entries.index(before: activeIndex)
        }
        resetDraftForActiveEntry()
    }

    mutating func setDraftValue(_ value: Double) {
        guard let activeEntry,
              value.isFinite else {
            return
        }
        if activeEntry.valueKind == .length, value <= 0.0 {
            return
        }
        draftValue = value
        isInputModeActive = true
    }

    mutating func setDraftText(
        _ text: String,
        displayUnit: LengthDisplayUnit
    ) {
        guard let activeEntry else {
            return
        }
        switch activeEntry.valueKind {
        case .length:
            guard let meters = workspaceLengthMeters(
                fromFieldText: text,
                defaultUnit: displayUnit
            ) else {
                return
            }
            setDraftValue(meters)
        case .angle:
            guard let degrees = WorkspaceInspectorNumberText.value(from: text) else {
                return
            }
            setDraftValue(degrees * Double.pi / 180.0)
        }
    }

    mutating func deactivate() {
        entries = []
        activeIndex = 0
        draftValue = nil
        isInputModeActive = false
    }

    private mutating func resetDraftForActiveEntry() {
        guard let activeEntry else {
            deactivate()
            return
        }
        draftValue = activeEntry.resolvedValue
        isInputModeActive = true
    }

    private mutating func normalize() {
        entries = entries.filter { entry in
            guard entry.resolvedValue.isFinite else {
                return false
            }
            switch entry.valueKind {
            case .length:
                return entry.resolvedValue > 0.0
            case .angle:
                return true
            }
        }
        guard !entries.isEmpty else {
            activeIndex = 0
            draftValue = nil
            isInputModeActive = false
            return
        }
        activeIndex = min(max(activeIndex, entries.startIndex), entries.index(before: entries.endIndex))
        if let draftValue, !draftValue.isFinite {
            self.draftValue = entries[activeIndex].resolvedValue
        }
    }
}
