import Foundation

public struct TopologySummaryResult: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var bodyCount: Int
        public var faceCount: Int
        public var edgeCount: Int
        public var vertexCount: Int

        public init(
            bodyCount: Int = 0,
            faceCount: Int = 0,
            edgeCount: Int = 0,
            vertexCount: Int = 0
        ) {
            self.bodyCount = bodyCount
            self.faceCount = faceCount
            self.edgeCount = edgeCount
            self.vertexCount = vertexCount
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Equatable, Sendable {
            case body
            case face
            case edge
            case vertex
        }

        public struct Point: Codable, Equatable, Sendable {
            public var x: Double
            public var y: Double
            public var z: Double

            public init(x: Double, y: Double, z: Double) {
                self.x = x
                self.y = y
                self.z = z
            }
        }

        public struct ParameterRange: Codable, Equatable, Sendable {
            public var start: Double
            public var end: Double

            public init(start: Double, end: Double) {
                self.start = start
                self.end = end
            }
        }

        public var persistentName: String
        public var kind: Kind
        public var referenceID: String
        public var sourceFeatureID: String?
        public var sceneNodeID: String?
        public var generatedRole: String?
        public var subshapeRole: String?
        public var index: Int?
        public var selectionComponentID: String?
        public var curveKind: String?
        public var surfaceKind: String?
        public var curveOrigin: Point?
        public var curveDirection: Point?
        public var curveCenter: Point?
        public var curveNormal: Point?
        public var curveRadius: Double?
        public var curveParameterXAxis: Point?
        public var curveParameterYAxis: Point?
        public var curveDegree: Int?
        public var curveControlPointCount: Int?
        public var curveIsRational: Bool?
        public var edgeParameterRange: ParameterRange?
        public var surfaceOrigin: Point?
        public var surfaceNormal: Point?
        public var surfaceAxis: Point?
        public var surfaceRadius: Double?
        public var surfaceUDegree: Int?
        public var surfaceVDegree: Int?
        public var surfaceUControlPointCount: Int?
        public var surfaceVControlPointCount: Int?
        public var center: Point?
        public var normal: Point?
        public var start: Point?
        public var end: Point?
        public var loopCount: Int?
        public var edgeCount: Int?
        public var shellCount: Int?

        public init(
            persistentName: String,
            kind: Kind,
            referenceID: String,
            sourceFeatureID: String? = nil,
            sceneNodeID: String? = nil,
            generatedRole: String? = nil,
            subshapeRole: String? = nil,
            index: Int? = nil,
            selectionComponentID: String? = nil,
            curveKind: String? = nil,
            surfaceKind: String? = nil,
            curveOrigin: Point? = nil,
            curveDirection: Point? = nil,
            curveCenter: Point? = nil,
            curveNormal: Point? = nil,
            curveRadius: Double? = nil,
            curveParameterXAxis: Point? = nil,
            curveParameterYAxis: Point? = nil,
            curveDegree: Int? = nil,
            curveControlPointCount: Int? = nil,
            curveIsRational: Bool? = nil,
            edgeParameterRange: ParameterRange? = nil,
            surfaceOrigin: Point? = nil,
            surfaceNormal: Point? = nil,
            surfaceAxis: Point? = nil,
            surfaceRadius: Double? = nil,
            surfaceUDegree: Int? = nil,
            surfaceVDegree: Int? = nil,
            surfaceUControlPointCount: Int? = nil,
            surfaceVControlPointCount: Int? = nil,
            center: Point? = nil,
            normal: Point? = nil,
            start: Point? = nil,
            end: Point? = nil,
            loopCount: Int? = nil,
            edgeCount: Int? = nil,
            shellCount: Int? = nil
        ) {
            self.persistentName = persistentName
            self.kind = kind
            self.referenceID = referenceID
            self.sourceFeatureID = sourceFeatureID
            self.sceneNodeID = sceneNodeID
            self.generatedRole = generatedRole
            self.subshapeRole = subshapeRole
            self.index = index
            self.selectionComponentID = selectionComponentID
            self.curveKind = curveKind
            self.surfaceKind = surfaceKind
            self.curveOrigin = curveOrigin
            self.curveDirection = curveDirection
            self.curveCenter = curveCenter
            self.curveNormal = curveNormal
            self.curveRadius = curveRadius
            self.curveParameterXAxis = curveParameterXAxis
            self.curveParameterYAxis = curveParameterYAxis
            self.curveDegree = curveDegree
            self.curveControlPointCount = curveControlPointCount
            self.curveIsRational = curveIsRational
            self.edgeParameterRange = edgeParameterRange
            self.surfaceOrigin = surfaceOrigin
            self.surfaceNormal = surfaceNormal
            self.surfaceAxis = surfaceAxis
            self.surfaceRadius = surfaceRadius
            self.surfaceUDegree = surfaceUDegree
            self.surfaceVDegree = surfaceVDegree
            self.surfaceUControlPointCount = surfaceUControlPointCount
            self.surfaceVControlPointCount = surfaceVControlPointCount
            self.center = center
            self.normal = normal
            self.start = start
            self.end = end
            self.loopCount = loopCount
            self.edgeCount = edgeCount
            self.shellCount = shellCount
        }

        public func selectionTarget() -> SelectionTarget? {
            guard let sceneNodeID,
                  let sceneNodeUUID = UUID(uuidString: sceneNodeID) else {
                return nil
            }
            let nodeID = SceneNodeID(sceneNodeUUID)
            guard let selectionComponentID else {
                return SelectionTarget(sceneNodeID: nodeID)
            }
            let componentID = SelectionComponentID(rawValue: selectionComponentID)
            switch kind {
            case .body:
                return SelectionTarget(sceneNodeID: nodeID)
            case .face:
                return SelectionTarget(sceneNodeID: nodeID, component: .face(componentID))
            case .edge:
                return SelectionTarget(sceneNodeID: nodeID, component: .edge(componentID))
            case .vertex:
                return SelectionTarget(sceneNodeID: nodeID, component: .vertex(componentID))
            }
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var counts: Counts
    public var entries: [Entry]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        counts: Counts = Counts(),
        entries: [Entry] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.displayUnit = displayUnit
        self.counts = counts
        self.entries = entries
        self.diagnostics = diagnostics
    }
}
