import ArgumentParser
import RupaCore

public enum CLISketchTangencyKind: String, CaseIterable, ExpressibleByArgument, Sendable {
    case lineCircular
    case circularCircular
}

public enum CLISketchTangentSide: String, CaseIterable, ExpressibleByArgument, Sendable {
    case left
    case right

    var constraintSide: SketchTangencyConstraint.LineSide {
        switch self {
        case .left: .left
        case .right: .right
        }
    }
}

public enum CLISketchCircularContact: String, CaseIterable, ExpressibleByArgument, Sendable {
    case external
    case firstContainsSecond
    case secondContainsFirst

    var constraintContact: SketchTangencyConstraint.CircularContact {
        switch self {
        case .external: .external
        case .firstContainsSecond: .firstContainsSecond
        case .secondContainsFirst: .secondContainsFirst
        }
    }
}

public enum CLISketchTangentOrientation: String, CaseIterable, ExpressibleByArgument, Sendable {
    case aligned
    case opposed

    var constraintOrientation: SketchTangentOrientation {
        switch self {
        case .aligned: .aligned
        case .opposed: .opposed
        }
    }
}
