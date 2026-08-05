import ArgumentParser
import RupaCore

public enum CLISketchCircularContactArgument: String, CaseIterable, ExpressibleByArgument {
    case external
    case firstContainsSecond
    case secondContainsFirst

    var contact: SketchTangencyConstraint.CircularContact {
        switch self {
        case .external:
            .external
        case .firstContainsSecond:
            .firstContainsSecond
        case .secondContainsFirst:
            .secondContainsFirst
        }
    }
}
