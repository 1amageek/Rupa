import ArgumentParser

public enum CLISelectionDimensionKind: String, CaseIterable, ExpressibleByArgument, Sendable {
    case distance
    case angle
}
