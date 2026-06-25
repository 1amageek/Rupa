import SwiftCAD

public struct SurfaceSourceSummaryResult: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var sourceCount: Int
        public var patchCount: Int
        public var controlVertexCount: Int
        public var trimLoopCount: Int
        public var adjacencyCount: Int

        public init(
            sourceCount: Int = 0,
            patchCount: Int = 0,
            controlVertexCount: Int = 0,
            trimLoopCount: Int = 0,
            adjacencyCount: Int = 0
        ) {
            self.sourceCount = sourceCount
            self.patchCount = patchCount
            self.controlVertexCount = controlVertexCount
            self.trimLoopCount = trimLoopCount
            self.adjacencyCount = adjacencyCount
        }
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

    public struct MeshCounts: Codable, Equatable, Sendable {
        public var vertexCount: Int
        public var usedVertexCount: Int
        public var triangleCount: Int
        public var indexedElementCount: Int
        public var boundaryEdgeCount: Int
        public var internalEdgeCount: Int

        public init(
            vertexCount: Int,
            usedVertexCount: Int,
            triangleCount: Int,
            indexedElementCount: Int,
            boundaryEdgeCount: Int,
            internalEdgeCount: Int
        ) {
            self.vertexCount = vertexCount
            self.usedVertexCount = usedVertexCount
            self.triangleCount = triangleCount
            self.indexedElementCount = indexedElementCount
            self.boundaryEdgeCount = boundaryEdgeCount
            self.internalEdgeCount = internalEdgeCount
        }
    }

    public struct PolySplineOptionsSummary: Codable, Equatable, Sendable {
        public var roundedCorners: Bool
        public var mergePatches: Bool
        public var interpolateBoundaryExactly: Bool

        public init(
            roundedCorners: Bool,
            mergePatches: Bool,
            interpolateBoundaryExactly: Bool
        ) {
            self.roundedCorners = roundedCorners
            self.mergePatches = mergePatches
            self.interpolateBoundaryExactly = interpolateBoundaryExactly
        }
    }

    public struct SupportSummary: Codable, Equatable, Sendable {
        public var isSupported: Bool
        public var candidateKind: String?
        public var supportedPatchCount: Int
        public var candidatePatchCount: Int
        public var failureMessage: String?

        public init(
            isSupported: Bool,
            candidateKind: String?,
            supportedPatchCount: Int,
            candidatePatchCount: Int,
            failureMessage: String?
        ) {
            self.isSupported = isSupported
            self.candidateKind = candidateKind
            self.supportedPatchCount = supportedPatchCount
            self.candidatePatchCount = candidatePatchCount
            self.failureMessage = failureMessage
        }
    }

    public struct Basis: Codable, Equatable, Sendable {
        public var kind: String
        public var uDegree: Int
        public var vDegree: Int
        public var uOrder: Int
        public var vOrder: Int
        public var uKnots: [Double]
        public var vKnots: [Double]
        public var uSpanCount: Int
        public var vSpanCount: Int
        public var isRational: Bool

        public init(
            kind: String,
            uDegree: Int,
            vDegree: Int,
            uOrder: Int,
            vOrder: Int,
            uKnots: [Double],
            vKnots: [Double],
            uSpanCount: Int,
            vSpanCount: Int,
            isRational: Bool
        ) {
            self.kind = kind
            self.uDegree = uDegree
            self.vDegree = vDegree
            self.uOrder = uOrder
            self.vOrder = vOrder
            self.uKnots = uKnots
            self.vKnots = vKnots
            self.uSpanCount = uSpanCount
            self.vSpanCount = vSpanCount
            self.isRational = isRational
        }
    }

    public struct ParameterRange: Codable, Equatable, Sendable {
        public var lowerBound: Double
        public var upperBound: Double

        public init(lowerBound: Double, upperBound: Double) {
            self.lowerBound = lowerBound
            self.upperBound = upperBound
        }
    }

    public struct ParameterAddress: Codable, Equatable, Sendable {
        public var id: String
        public var u: Double
        public var v: Double
        public var selectionReference: SelectionReference?

        public init(
            id: String,
            u: Double,
            v: Double,
            selectionReference: SelectionReference? = nil
        ) {
            self.id = id
            self.u = u
            self.v = v
            self.selectionReference = selectionReference
        }
    }

    public struct ControlVertex: Codable, Equatable, Sendable {
        public var id: String
        public var role: String
        public var sourceVertexIndex: Int
        public var point: Point
        public var generatedVertexPersistentName: String
        public var selectionComponentID: String
        public var selectionReference: SelectionReference

        public init(
            id: String,
            role: String,
            sourceVertexIndex: Int,
            point: Point,
            generatedVertexPersistentName: String,
            selectionComponentID: String,
            selectionReference: SelectionReference
        ) {
            self.id = id
            self.role = role
            self.sourceVertexIndex = sourceVertexIndex
            self.point = point
            self.generatedVertexPersistentName = generatedVertexPersistentName
            self.selectionComponentID = selectionComponentID
            self.selectionReference = selectionReference
        }
    }

    public struct TrimLoop: Codable, Equatable, Sendable {
        public var role: String
        public var parameterAddresses: [ParameterAddress]
        public var sourceVertexIndices: [Int]
        public var edgePersistentNames: [String]
        public var selectionReferences: [SelectionReference]

        public init(
            role: String,
            parameterAddresses: [ParameterAddress],
            sourceVertexIndices: [Int],
            edgePersistentNames: [String],
            selectionReferences: [SelectionReference] = []
        ) {
            self.role = role
            self.parameterAddresses = parameterAddresses
            self.sourceVertexIndices = sourceVertexIndices
            self.edgePersistentNames = edgePersistentNames
            self.selectionReferences = selectionReferences
        }
    }

    public struct Patch: Codable, Equatable, Sendable {
        public var patchID: Int
        public var facePersistentName: String?
        public var faceSelectionComponentID: String?
        public var faceSelectionReference: SelectionReference?
        public var uDomain: ParameterRange
        public var vDomain: ParameterRange
        public var basis: Basis
        public var controlVertices: [ControlVertex]
        public var trimLoops: [TrimLoop]
        public var parameterAddresses: [ParameterAddress]

        public init(
            patchID: Int,
            facePersistentName: String?,
            faceSelectionComponentID: String?,
            faceSelectionReference: SelectionReference?,
            uDomain: ParameterRange,
            vDomain: ParameterRange,
            basis: Basis,
            controlVertices: [ControlVertex],
            trimLoops: [TrimLoop],
            parameterAddresses: [ParameterAddress]
        ) {
            self.patchID = patchID
            self.facePersistentName = facePersistentName
            self.faceSelectionComponentID = faceSelectionComponentID
            self.faceSelectionReference = faceSelectionReference
            self.uDomain = uDomain
            self.vDomain = vDomain
            self.basis = basis
            self.controlVertices = controlVertices
            self.trimLoops = trimLoops
            self.parameterAddresses = parameterAddresses
        }
    }

    public struct Adjacency: Codable, Equatable, Sendable {
        public var firstPatchID: Int
        public var secondPatchID: Int
        public var sharedVertexIndices: [Int]
        public var sharedEdgePersistentName: String?
        public var continuityLevel: String
        public var normalAngleRadians: Double
        public var requiresCurvatureContinuitySolve: Bool

        public init(
            firstPatchID: Int,
            secondPatchID: Int,
            sharedVertexIndices: [Int],
            sharedEdgePersistentName: String?,
            continuityLevel: String,
            normalAngleRadians: Double,
            requiresCurvatureContinuitySolve: Bool
        ) {
            self.firstPatchID = firstPatchID
            self.secondPatchID = secondPatchID
            self.sharedVertexIndices = sharedVertexIndices
            self.sharedEdgePersistentName = sharedEdgePersistentName
            self.continuityLevel = continuityLevel
            self.normalAngleRadians = normalAngleRadians
            self.requiresCurvatureContinuitySolve = requiresCurvatureContinuitySolve
        }
    }

    public struct Diagnostic: Codable, Equatable, Sendable {
        public var severity: String
        public var code: String
        public var message: String
        public var vertexIndices: [Int]
        public var triangleIndices: [Int]

        public init(
            severity: String,
            code: String,
            message: String,
            vertexIndices: [Int] = [],
            triangleIndices: [Int] = []
        ) {
            self.severity = severity
            self.code = code
            self.message = message
            self.vertexIndices = vertexIndices
            self.triangleIndices = triangleIndices
        }
    }

    public struct Source: Codable, Equatable, Sendable {
        public var featureID: String
        public var name: String
        public var sceneNodeID: String?
        public var kind: String
        public var meshCounts: MeshCounts
        public var options: PolySplineOptionsSummary
        public var support: SupportSummary
        public var patches: [Patch]
        public var adjacencies: [Adjacency]
        public var diagnostics: [Diagnostic]

        public init(
            featureID: String,
            name: String,
            sceneNodeID: String?,
            kind: String,
            meshCounts: MeshCounts,
            options: PolySplineOptionsSummary,
            support: SupportSummary,
            patches: [Patch],
            adjacencies: [Adjacency],
            diagnostics: [Diagnostic]
        ) {
            self.featureID = featureID
            self.name = name
            self.sceneNodeID = sceneNodeID
            self.kind = kind
            self.meshCounts = meshCounts
            self.options = options
            self.support = support
            self.patches = patches
            self.adjacencies = adjacencies
            self.diagnostics = diagnostics
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var counts: Counts
    public var sources: [Source]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        counts: Counts = Counts(),
        sources: [Source] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.displayUnit = displayUnit
        self.counts = counts
        self.sources = sources
        self.diagnostics = diagnostics
    }
}
