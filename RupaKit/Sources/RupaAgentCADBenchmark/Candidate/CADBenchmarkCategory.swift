public enum CADBenchmarkCategory: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case line = "LIN"
    case rectangle = "REC"
    case circle = "CIR"
    case angle = "ANG"
    case box = "BOX"
    case cylinder = "CYL"
    case constraint = "CON"
    case transform = "TRN"
    case compound = "CMP"
    case sphere = "SPH"

    public var expectedCount: Int {
        switch self {
        case .line, .rectangle, .circle:
            12
        case .angle:
            16
        case .box:
            12
        case .cylinder, .constraint, .transform:
            8
        case .compound:
            7
        case .sphere:
            5
        }
    }

    public var capabilityID: String {
        switch self {
        case .line:
            "cad.sketch.line"
        case .rectangle:
            "cad.sketch.rectangle"
        case .circle:
            "cad.sketch.circle"
        case .angle:
            "cad.sketch.intersection"
        case .box:
            "cad.solid.box"
        case .cylinder:
            "cad.solid.cylinder"
        case .constraint:
            "cad.sketch.constraint"
        case .transform:
            "cad.placement.transform"
        case .compound:
            "cad.assembly.compound"
        case .sphere:
            "cad.solid.analytic-sphere"
        }
    }
}
