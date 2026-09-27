import SwiftCAD
import RupaProjectModel

/// Scene subtrees together with everything their geometry needs, independent of any document.
///
/// A fragment is extracted from one document and can be inserted into the same or another
/// document any number of times; every identity it carries is replaced on insertion.
public struct SceneFragment: Codable, Equatable, Sendable {
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
    /// The authored meshes the copied nodes present or carry as representations.
    public var authoredMeshes: [GeometrySourceID: AuthoredMeshAsset]
    /// The component instances the copied nodes present.
    public var componentInstances: [ComponentInstanceID: ComponentInstance]
    /// The definitions of those instances with their content, so the instances can be pasted into
    /// a document that does not hold them.
    public var componentDefinitions: [ComponentDefinitionID: ComponentDefinitionContent]
    /// The saved measurements whose annotation nodes are copied.
    public var measurements: [MeasurementAnnotation]
    /// The construction planes the copied construction nodes present.
    public var constructionPlanes: [ConstructionPlaneSource]

    /// A component definition carried by a fragment: its name and properties, and its root
    /// subtrees as a fragment of their own.
    public struct ComponentDefinitionContent: Codable, Equatable, Sendable {
        public var name: String
        public var properties: [String: String]
        public var content: SceneFragment

        public init(name: String, properties: [String: String], content: SceneFragment) {
            self.name = name
            self.properties = properties
            self.content = content
        }
    }

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
        joinedCurveGroupSources: [JoinedCurveGroupSource] = [],
        authoredMeshes: [GeometrySourceID: AuthoredMeshAsset] = [:],
        componentInstances: [ComponentInstanceID: ComponentInstance] = [:],
        componentDefinitions: [ComponentDefinitionID: ComponentDefinitionContent] = [:],
        measurements: [MeasurementAnnotation] = [],
        constructionPlanes: [ConstructionPlaneSource] = []
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
        self.authoredMeshes = authoredMeshes
        self.componentInstances = componentInstances
        self.componentDefinitions = componentDefinitions
        self.measurements = measurements
        self.constructionPlanes = constructionPlanes
    }

    private enum CodingKeys: String, CodingKey {
        case roots, carriedPresenters, sceneNodes, features, parameters, materials, faceMaterialBindings
        case bridgeCurveSources, joinedCurveSources, joinedCurveGroupSources, authoredMeshes, componentInstances
        case componentDefinitions, measurements, constructionPlanes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roots = try container.decode([Root].self, forKey: .roots)
        carriedPresenters = try container.decode([Root].self, forKey: .carriedPresenters)
        sceneNodes = try container.decode([SceneNodeID: SceneNode].self, forKey: .sceneNodes)
        features = try container.decode([FeatureNode].self, forKey: .features)
        parameters = try container.decode([Parameter].self, forKey: .parameters)
        materials = try container.decode([MaterialID: Material].self, forKey: .materials)
        faceMaterialBindings = try container.decode([TopologyMaterialBinding].self, forKey: .faceMaterialBindings)
        bridgeCurveSources = try container.decode([BridgeCurveSource].self, forKey: .bridgeCurveSources)
        joinedCurveSources = try container.decode([JoinedCurveSource].self, forKey: .joinedCurveSources)
        joinedCurveGroupSources = try container.decode([JoinedCurveGroupSource].self, forKey: .joinedCurveGroupSources)
        // Fragments copied before meshes and instances could be copied carry neither.
        authoredMeshes = try container.decodeIfPresent([GeometrySourceID: AuthoredMeshAsset].self, forKey: .authoredMeshes) ?? [:]
        componentInstances = try container.decodeIfPresent(
            [ComponentInstanceID: ComponentInstance].self, forKey: .componentInstances
        ) ?? [:]
        // Fragments copied before definitions and measurements could be copied carry neither.
        componentDefinitions = try container.decodeIfPresent(
            [ComponentDefinitionID: ComponentDefinitionContent].self, forKey: .componentDefinitions
        ) ?? [:]
        measurements = try container.decodeIfPresent([MeasurementAnnotation].self, forKey: .measurements) ?? []
        constructionPlanes = try container.decodeIfPresent([ConstructionPlaneSource].self, forKey: .constructionPlanes) ?? []
    }
}
