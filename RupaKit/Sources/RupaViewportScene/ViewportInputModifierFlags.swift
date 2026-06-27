public struct ViewportInputModifierFlags: Equatable, Sendable {
    public var containsShift: Bool
    public var containsControl: Bool
    public var containsCommand: Bool
    public var containsOption: Bool

    public init(
        containsShift: Bool = false,
        containsControl: Bool = false,
        containsCommand: Bool = false,
        containsOption: Bool = false
    ) {
        self.containsShift = containsShift
        self.containsControl = containsControl
        self.containsCommand = containsCommand
        self.containsOption = containsOption
    }
}
