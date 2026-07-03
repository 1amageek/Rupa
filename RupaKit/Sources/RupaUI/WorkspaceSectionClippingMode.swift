import RupaCore

enum WorkspaceSectionClippingMode: String, CaseIterable, Equatable, Identifiable, Sendable {
    case off
    case front
    case behind

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .off:
            "Off"
        case .front:
            "Front"
        case .behind:
            "Behind"
        }
    }

    var statusTitle: String {
        switch self {
        case .off:
            "Section only"
        case .front:
            "Retain front"
        case .behind:
            "Retain behind"
        }
    }

    var retainedSide: SectionAnalysisRetainedSide? {
        switch self {
        case .off:
            nil
        case .front:
            .front
        case .behind:
            .behind
        }
    }

    init(retainedSide: SectionAnalysisRetainedSide?) {
        switch retainedSide {
        case .front:
            self = .front
        case .behind:
            self = .behind
        case nil:
            self = .off
        }
    }
}
