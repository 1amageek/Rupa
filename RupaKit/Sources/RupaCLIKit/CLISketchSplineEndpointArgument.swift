import ArgumentParser
import RupaCore

public enum CLISketchSplineEndpointArgument: String, CaseIterable, ExpressibleByArgument {
    case start
    case end

    var endpoint: SketchSplineEndpoint {
        switch self {
        case .start:
            .start
        case .end:
            .end
        }
    }
}
