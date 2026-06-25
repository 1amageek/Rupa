import ArgumentParser
import RupaCore

public enum CLISelectionDimensionKind: String, CaseIterable, ExpressibleByArgument, Sendable {
    case distance
    case angle

    var selectionDimensionKind: SelectionDimensionKind {
        switch self {
        case .distance:
            .distance
        case .angle:
            .angle
        }
    }
}
