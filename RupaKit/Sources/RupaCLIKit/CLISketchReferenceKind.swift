import ArgumentParser

public enum CLISketchReferenceKind: String, CaseIterable, ExpressibleByArgument {
    case entity
    case lineStart
    case lineEnd
    case circleCenter
    case circleRadius
    case arcCenter
    case arcStart
    case arcEnd
    case arcRadius
    case splineControlPoint
}
