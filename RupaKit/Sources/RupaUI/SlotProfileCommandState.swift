struct SlotProfileCommandState: Equatable {
    enum InputMode: Equatable {
        case inactive
        case width
    }

    var inputMode: InputMode

    init(inputMode: InputMode = .inactive) {
        self.inputMode = inputMode
    }

    static var inactive: SlotProfileCommandState {
        SlotProfileCommandState()
    }

    var isActive: Bool {
        inputMode != .inactive
    }

    var inputModeTitle: String {
        switch inputMode {
        case .inactive:
            return "Inactive"
        case .width:
            return "Width"
        }
    }

    mutating func activateWidthInput() {
        inputMode = .width
    }

    mutating func deactivate() {
        inputMode = .inactive
    }
}
