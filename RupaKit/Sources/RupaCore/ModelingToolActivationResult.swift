import Foundation

public struct ModelingToolActivationResult: Equatable, Sendable {
    public var tool: ModelingTool
    public var commandName: String?
    public var didMutate: Bool
    public var selectedSceneNodeID: SceneNodeID?
    public var revealsDiagnostics: Bool

    public init(
        tool: ModelingTool,
        commandName: String? = nil,
        didMutate: Bool = false,
        selectedSceneNodeID: SceneNodeID? = nil,
        revealsDiagnostics: Bool = false
    ) {
        self.tool = tool
        self.commandName = commandName
        self.didMutate = didMutate
        self.selectedSceneNodeID = selectedSceneNodeID
        self.revealsDiagnostics = revealsDiagnostics
    }
}
