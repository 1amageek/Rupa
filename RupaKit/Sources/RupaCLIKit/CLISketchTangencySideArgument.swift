import ArgumentParser
import RupaCore

public enum CLISketchTangencySideArgument: String, CaseIterable, ExpressibleByArgument {
    case left
    case right

    var side: SketchTangencyConstraint.LineSide {
        switch self {
        case .left:
            .left
        case .right:
            .right
        }
    }
}
