public protocol SemanticCompilationCancellation: Sendable {
    var isCancelled: Bool { get }
}

public struct NeverSemanticCompilationCancellation: SemanticCompilationCancellation, Sendable {
    public init() {}

    public var isCancelled: Bool { false }
}
