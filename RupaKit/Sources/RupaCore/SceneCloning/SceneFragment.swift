import SwiftCAD

/// Scene subtrees together with everything their geometry needs, independent of any document.
///
/// A fragment is extracted from one document and can be inserted into the same or another
/// document any number of times; every identity it carries is replaced on insertion.
public struct SceneFragment: Codable, Hashable, Sendable {
    /// A node inserted as a copy root, with its placement in the fragment's reference frame.
    public struct Root: Codable, Hashable, Sendable {
        public var sceneNodeID: SceneNodeID
        public var placement: Transform3D

        public init(sceneNodeID: SceneNodeID, placement: Transform3D) {
            self.sceneNodeID = sceneNodeID
            self.placement = placement
        }
    }

    /// The selected roots, in scene order.
    public var roots: [Root]
    /// Hidden presenters of closure features that no root subtree presents, inserted under the
    /// first copied root so every copied feature keeps exactly one presenting node.
    public var carriedPresenters: [Root]
    /// Every node of the root subtrees and the carried presenters (carried nodes have no children).
    public var sceneNodes: [SceneNodeID: SceneNode]
    /// The feature closure, in source graph order.
    public var features: [FeatureNode]
    /// Every parameter the features reference, transitively through parameter expressions.
    public var parameters: [Parameter]
    /// Every material a node or face binding refers to.
    public var materials: [MaterialID: Material]
    public var faceMaterialBindings: [TopologyMaterialBinding]
    public var bridgeCurveSources: [BridgeCurveSource]
    public var joinedCurveSources: [JoinedCurveSource]
    public var joinedCurveGroupSources: [JoinedCurveGroupSource]

    public init(
        roots: [Root],
        carriedPresenters: [Root] = [],
        sceneNodes: [SceneNodeID: SceneNode],
        features: [FeatureNode],
        parameters: [Parameter] = [],
        materials: [MaterialID: Material] = [:],
        faceMaterialBindings: [TopologyMaterialBinding] = [],
        bridgeCurveSources: [BridgeCurveSource] = [],
        joinedCurveSources: [JoinedCurveSource] = [],
        joinedCurveGroupSources: [JoinedCurveGroupSource] = []
    ) {
        self.roots = roots
        self.carriedPresenters = carriedPresenters
        self.sceneNodes = sceneNodes
        self.features = features
        self.parameters = parameters
        self.materials = materials
        self.faceMaterialBindings = faceMaterialBindings
        self.bridgeCurveSources = bridgeCurveSources
        self.joinedCurveSources = joinedCurveSources
        self.joinedCurveGroupSources = joinedCurveGroupSources
    }
}
