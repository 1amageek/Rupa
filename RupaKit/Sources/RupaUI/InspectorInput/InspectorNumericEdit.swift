import Foundation

@MainActor
struct InspectorNumericEdit {
    private(set) var mapping: InspectorNumericMapping?
    private(set) var value: Double?
    private(set) var text: String?
    private var revision = 0
    private var pending = false
    private var editing = false

    mutating func begin(_ mapping: InspectorNumericMapping) {
        if self.mapping == nil { self.mapping = mapping }
        editing = true
    }

    mutating func setText(_ text: String, mapping: InspectorNumericMapping) -> Double? {
        if self.mapping == nil { self.mapping = mapping }
        self.text = text
        guard let value = self.mapping?.parse(text), value.isFinite else { return nil }
        self.value = value
        return value
    }

    mutating func setSlider(_ position: Double, mapping: InspectorNumericMapping) -> Double {
        if self.mapping == nil { self.mapping = mapping }
        let value = self.mapping!.value(position)
        self.value = value
        text = self.mapping!.format(value)
        return value
    }

    mutating func submitted() -> Int {
        revision += 1
        pending = true
        return revision
    }

    mutating func acknowledged(_ revision: Int) {
        guard revision == self.revision else { return }
        pending = false
        releaseIfIdle()
    }

    mutating func end() {
        editing = false
        releaseIfIdle()
    }

    private mutating func releaseIfIdle() {
        guard !editing, !pending else { return }
        mapping = nil
        value = nil
        text = nil
    }
}
