import RupaCore

enum WorkspacePlaneMode: String, CaseIterable, Identifiable {
    case adaptive
    case xy
    case yz
    case zx

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .adaptive:
            return "Adaptive"
        case .xy:
            return "XY"
        case .yz:
            return "YZ"
        case .zx:
            return "ZX"
        }
    }

    var shortTitle: String {
        switch self {
        case .adaptive:
            return "AUTO"
        case .xy:
            return "XY"
        case .yz:
            return "YZ"
        case .zx:
            return "ZX"
        }
    }

    var help: String {
        switch self {
        case .adaptive:
            return "Use the hovered face as the construction plane"
        case .xy:
            return "Use the XY construction plane"
        case .yz:
            return "Use the YZ construction plane"
        case .zx:
            return "Use the ZX construction plane"
        }
    }

    var sketchPlane: SketchPlane? {
        switch self {
        case .adaptive:
            return nil
        case .xy:
            return .xy
        case .yz:
            return .yz
        case .zx:
            return .zx
        }
    }
}
