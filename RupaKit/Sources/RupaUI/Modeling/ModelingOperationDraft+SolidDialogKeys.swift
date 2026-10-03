import RupaCore

extension ModelingOperationDraft {
    /// A key Plasticity gives the dialogs of Extrude, Revolve, Sweep and Pipe: Shift+Q Slice, Q
    /// Union, W Difference, Shift+E Intersect, B New body, T Keep tools, and the fields A (angle),
    /// Shift+T (thickness) and D (Extrude's distance, Pipe's size, Sweep's twist) take the typing.
    enum SolidDialogKey: Equatable, Sendable {
        case boolean(SolidBooleanChoice)
        case keepTools
        case angle
        case thickness
        case distance
    }

    /// Whether the dialog takes `SolidDialogKey`s: a solid Extrude, Revolve, Sweep or Pipe.
    var takesSolidDialogKeys: Bool {
        switch kind {
        case .extrude, .revolve, .sweep: isSurfaceCreation == false
        case .pipe: true
        default: false
        }
    }

    /// Applies `key`: the Boolean taken, Keep tools turned, or the field asked for focused. The
    /// change's status text, or nil when the dialog has no such option (Sweep's angle or
    /// thickness, a sheet's thickness, a custom Pipe profile's size).
    mutating func apply(_ key: SolidDialogKey) -> String? {
        guard takesSolidDialogKeys else { return nil }
        func focus(_ field: FocusField) { focusRequest = FocusRequest(field: field, serial: (focusRequest?.serial ?? 0) + 1) }
        switch key {
        case .boolean(let choice):
            solidBoolean = choice
            return "\(kind.rawValue): \(choice.rawValue)."
        case .keepTools:
            keepsTools.toggle()
            return "\(kind.rawValue): Keep tools \(keepsTools ? "on" : "off")."
        case .angle:
            guard [.extrude, .revolve, .pipe].contains(kind) else { return nil }
            focus(.angle)
            return "\(kind.rawValue): type the angle."
        case .thickness:
            guard kind == .pipe || ([.extrude, .revolve].contains(kind) && createsSheet == false) else { return nil }
            focus(.thickness)
            return "\(kind.rawValue): type the thickness."
        case .distance:
            switch kind {
            case .extrude:
                focus(.distance)
                return "Extrude: type the distance."
            case .pipe where pipeCustomProfile == false:
                focus(.distance)
                return "Pipe: type the size."
            case .sweep:
                focus(.twist)
                return "Sweep: type the twist."
            default:
                return nil
            }
        }
    }
}
