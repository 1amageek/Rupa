import ArgumentParser
import RupaCore

public enum CLISketchTangentOrientationArgument: String, CaseIterable, ExpressibleByArgument {
    case aligned
    case opposed

    var orientation: SketchTangentOrientation {
        switch self {
        case .aligned:
            .aligned
        case .opposed:
            .opposed
        }
    }
}
