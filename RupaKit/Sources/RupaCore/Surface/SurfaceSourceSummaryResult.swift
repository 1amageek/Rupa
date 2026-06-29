import SwiftCAD
import RupaCoreTypes

public struct SurfaceSourceSummaryResult: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var sourceCount: Int
        public var patchCount: Int
        public var controlVertexCount: Int
        public var controlPointCount: Int
        public var frameSampleCount: Int
        public var trimLoopCount: Int
        public var adjacencyCount: Int

        public init(
            sourceCount: Int = 0,
            patchCount: Int = 0,
            controlVertexCount: Int = 0,
            controlPointCount: Int = 0,
            frameSampleCount: Int = 0,
            trimLoopCount: Int = 0,
            adjacencyCount: Int = 0
        ) {
            self.sourceCount = sourceCount
            self.patchCount = patchCount
            self.controlVertexCount = controlVertexCount
            self.controlPointCount = controlPointCount
            self.frameSampleCount = frameSampleCount
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

    public struct Vector: Codable, Equatable, Sendable {
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
        public struct Knot: Codable, Equatable, Sendable {
            public var id: String
            public var index: Int
            public var value: Double
            public var multiplicity: Int
            public var isBoundary: Bool
            public var isEditable: Bool
            public var selectionReference: SelectionReference?

            public init(
                id: String,
                index: Int,
                value: Double,
                multiplicity: Int,
                isBoundary: Bool,
                isEditable: Bool = false,
                selectionReference: SelectionReference? = nil
            ) {
                self.id = id
                self.index = index
                self.value = value
                self.multiplicity = multiplicity
                self.isBoundary = isBoundary
                self.isEditable = isEditable
                self.selectionReference = selectionReference
            }
        }

        public struct Span: Codable, Equatable, Sendable {
            public var id: String
            public var index: Int
            public var lowerBound: Double
            public var upperBound: Double
            public var startKnotIndex: Int
            public var endKnotIndex: Int
            public var isEditable: Bool
            public var selectionReference: SelectionReference?

            public init(
                id: String,
                index: Int,
                lowerBound: Double,
                upperBound: Double,
                startKnotIndex: Int,
                endKnotIndex: Int,
                isEditable: Bool = false,
                selectionReference: SelectionReference? = nil
            ) {
                self.id = id
                self.index = index
                self.lowerBound = lowerBound
                self.upperBound = upperBound
                self.startKnotIndex = startKnotIndex
                self.endKnotIndex = endKnotIndex
                self.isEditable = isEditable
                self.selectionReference = selectionReference
            }
        }

        public var kind: String
        public var uDegree: Int
        public var vDegree: Int
        public var uOrder: Int
        public var vOrder: Int
        public var uKnots: [Double]
        public var vKnots: [Double]
        public var uKnotVector: [Knot]
        public var vKnotVector: [Knot]
        public var uSpans: [Span]
        public var vSpans: [Span]
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
            uKnotVector: [Knot],
            vKnotVector: [Knot],
            uSpans: [Span],
            vSpans: [Span],
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
            self.uKnotVector = uKnotVector
            self.vKnotVector = vKnotVector
            self.uSpans = uSpans
            self.vSpans = vSpans
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

    public struct FrameSample: Codable, Equatable, Sendable {
        public var id: String
        public var uSpanID: String?
        public var vSpanID: String?
        public var u: Double
        public var v: Double
        public var position: Point
        public var uAxis: Vector
        public var vAxis: Vector
        public var normal: Vector
        public var handedness: Double
        public var normalCurvatureU: Double
        public var normalCurvatureV: Double
        public var meanCurvature: Double
        public var gaussianCurvature: Double
        public var minimumPrincipalCurvature: Double
        public var maximumPrincipalCurvature: Double
        public var minimumPrincipalDirection: Vector
        public var maximumPrincipalDirection: Vector
        public var selectionReference: SelectionReference
        public var isFrameDisplayVisible: Bool

        public init(
            id: String,
            uSpanID: String?,
            vSpanID: String?,
            u: Double,
            v: Double,
            position: Point,
            uAxis: Vector,
            vAxis: Vector,
            normal: Vector,
            handedness: Double,
            normalCurvatureU: Double,
            normalCurvatureV: Double,
            meanCurvature: Double,
            gaussianCurvature: Double,
            minimumPrincipalCurvature: Double,
            maximumPrincipalCurvature: Double,
            minimumPrincipalDirection: Vector,
            maximumPrincipalDirection: Vector,
            selectionReference: SelectionReference,
            isFrameDisplayVisible: Bool = false
        ) {
            self.id = id
            self.uSpanID = uSpanID
            self.vSpanID = vSpanID
            self.u = u
            self.v = v
            self.position = position
            self.uAxis = uAxis
            self.vAxis = vAxis
            self.normal = normal
            self.handedness = handedness
            self.normalCurvatureU = normalCurvatureU
            self.normalCurvatureV = normalCurvatureV
            self.meanCurvature = meanCurvature
            self.gaussianCurvature = gaussianCurvature
            self.minimumPrincipalCurvature = minimumPrincipalCurvature
            self.maximumPrincipalCurvature = maximumPrincipalCurvature
            self.minimumPrincipalDirection = minimumPrincipalDirection
            self.maximumPrincipalDirection = maximumPrincipalDirection
            self.selectionReference = selectionReference
            self.isFrameDisplayVisible = isFrameDisplayVisible
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
        public var isPointDisplayVisible: Bool

        public init(
            id: String,
            role: String,
            sourceVertexIndex: Int,
            point: Point,
            generatedVertexPersistentName: String,
            selectionComponentID: String,
            selectionReference: SelectionReference,
            isPointDisplayVisible: Bool = false
        ) {
            self.id = id
            self.role = role
            self.sourceVertexIndex = sourceVertexIndex
            self.point = point
            self.generatedVertexPersistentName = generatedVertexPersistentName
            self.selectionComponentID = selectionComponentID
            self.selectionReference = selectionReference
            self.isPointDisplayVisible = isPointDisplayVisible
        }
    }

    public struct ControlPoint: Codable, Equatable, Sendable {
        public var id: String
        public var uIndex: Int
        public var vIndex: Int
        public var point: Point
        public var weight: Double
        public var isBoundary: Bool
        public var isEditable: Bool
        public var selectionReference: SelectionReference
        public var isPointDisplayVisible: Bool

        public init(
            id: String,
            uIndex: Int,
            vIndex: Int,
            point: Point,
            weight: Double,
            isBoundary: Bool,
            isEditable: Bool,
            selectionReference: SelectionReference,
            isPointDisplayVisible: Bool = false
        ) {
            self.id = id
            self.uIndex = uIndex
            self.vIndex = vIndex
            self.point = point
            self.weight = weight
            self.isBoundary = isBoundary
            self.isEditable = isEditable
            self.selectionReference = selectionReference
            self.isPointDisplayVisible = isPointDisplayVisible
        }
    }

    public struct TrimLoop: Codable, Equatable, Sendable {
        public struct Edge: Codable, Equatable, Sendable {
            public struct ParameterCurve: Codable, Equatable, Sendable {
                public struct Knot: Codable, Equatable, Sendable {
                    public var id: String
                    public var index: Int
                    public var value: Double
                    public var multiplicity: Int
                    public var isBoundary: Bool
                    public var isValueEditable: Bool
                    public var isMultiplicityEditable: Bool
                    public var isInsertionSupported: Bool
                    public var unsupportedReason: String?
                    public var selectionReference: SelectionReference?

                    public init(
                        id: String,
                        index: Int,
                        value: Double,
                        multiplicity: Int,
                        isBoundary: Bool,
                        isValueEditable: Bool = false,
                        isMultiplicityEditable: Bool = false,
                        isInsertionSupported: Bool = false,
                        unsupportedReason: String? = nil,
                        selectionReference: SelectionReference? = nil
                    ) {
                        self.id = id
                        self.index = index
                        self.value = value
                        self.multiplicity = multiplicity
                        self.isBoundary = isBoundary
                        self.isValueEditable = isValueEditable
                        self.isMultiplicityEditable = isMultiplicityEditable
                        self.isInsertionSupported = isInsertionSupported
                        self.unsupportedReason = unsupportedReason
                        self.selectionReference = selectionReference
                    }
                }

                public struct Span: Codable, Equatable, Sendable {
                    public var id: String
                    public var index: Int
                    public var lowerBound: Double
                    public var upperBound: Double
                    public var startKnotIndex: Int
                    public var endKnotIndex: Int
                    public var isInsertionSupported: Bool
                    public var unsupportedReason: String?
                    public var selectionReference: SelectionReference?

                    public init(
                        id: String,
                        index: Int,
                        lowerBound: Double,
                        upperBound: Double,
                        startKnotIndex: Int,
                        endKnotIndex: Int,
                        isInsertionSupported: Bool = false,
                        unsupportedReason: String? = nil,
                        selectionReference: SelectionReference? = nil
                    ) {
                        self.id = id
                        self.index = index
                        self.lowerBound = lowerBound
                        self.upperBound = upperBound
                        self.startKnotIndex = startKnotIndex
                        self.endKnotIndex = endKnotIndex
                        self.isInsertionSupported = isInsertionSupported
                        self.unsupportedReason = unsupportedReason
                        self.selectionReference = selectionReference
                    }
                }

                public var kind: String
                public var degree: Int?
                public var order: Int?
                public var domainLowerBound: Double?
                public var domainUpperBound: Double?
                public var knots: [Double]
                public var knotVector: [Knot]
                public var spans: [Span]
                public var spanCount: Int
                public var isRational: Bool
                public var supportsKnotInsertion: Bool
                public var unsupportedReason: String?

                public init(
                    kind: String,
                    degree: Int? = nil,
                    order: Int? = nil,
                    domainLowerBound: Double? = nil,
                    domainUpperBound: Double? = nil,
                    knots: [Double] = [],
                    knotVector: [Knot] = [],
                    spans: [Span] = [],
                    spanCount: Int = 0,
                    isRational: Bool = false,
                    supportsKnotInsertion: Bool = false,
                    unsupportedReason: String? = nil
                ) {
                    self.kind = kind
                    self.degree = degree
                    self.order = order
                    self.domainLowerBound = domainLowerBound
                    self.domainUpperBound = domainUpperBound
                    self.knots = knots
                    self.knotVector = knotVector
                    self.spans = spans
                    self.spanCount = spanCount
                    self.isRational = isRational
                    self.supportsKnotInsertion = supportsKnotInsertion
                    self.unsupportedReason = unsupportedReason
                }
            }

            public struct ParameterCurveControlPoint: Codable, Equatable, Sendable {
                public var index: Int
                public var parameter: ParameterAddress
                public var weight: Double?
                public var isEndpoint: Bool
                public var isEditable: Bool
                public var unsupportedReason: String?
                public var isWeightEditable: Bool
                public var weightUnsupportedReason: String?

                public init(
                    index: Int,
                    parameter: ParameterAddress,
                    weight: Double? = nil,
                    isEndpoint: Bool,
                    isEditable: Bool,
                    unsupportedReason: String? = nil,
                    isWeightEditable: Bool = false,
                    weightUnsupportedReason: String? = nil
                ) {
                    self.index = index
                    self.parameter = parameter
                    self.weight = weight
                    self.isEndpoint = isEndpoint
                    self.isEditable = isEditable
                    self.unsupportedReason = unsupportedReason
                    self.isWeightEditable = isWeightEditable
                    self.weightUnsupportedReason = weightUnsupportedReason
                }
            }

            public var index: Int
            public var role: String
            public var persistentName: String?
            public var selectionReference: SelectionReference?
            public var startParameter: ParameterAddress
            public var endParameter: ParameterAddress
            public var parameterCurve: ParameterCurve
            public var parameterCurveControlPoints: [ParameterCurveControlPoint]
            public var boundaryDirection: SurfaceParameterDirection
            public var inwardDirection: SurfaceParameterDirection
            public var boundaryControlPointReferences: [SelectionReference]
            public var firstInwardControlPointReferences: [SelectionReference]
            public var secondInwardControlPointReferences: [SelectionReference]
            public var supportedBoundaryContinuityLevels: [SurfaceBoundaryContinuityLevel]
            public var supportsBoundaryContinuityMatching: Bool
            public var unsupportedReason: String?

            public init(
                index: Int,
                role: String,
                persistentName: String?,
                selectionReference: SelectionReference?,
                startParameter: ParameterAddress,
                endParameter: ParameterAddress,
                parameterCurve: ParameterCurve = ParameterCurve(
                    kind: "unknown",
                    unsupportedReason: "Trim p-curve metadata was not provided."
                ),
                parameterCurveControlPoints: [ParameterCurveControlPoint] = [],
                boundaryDirection: SurfaceParameterDirection,
                inwardDirection: SurfaceParameterDirection,
                boundaryControlPointReferences: [SelectionReference],
                firstInwardControlPointReferences: [SelectionReference] = [],
                secondInwardControlPointReferences: [SelectionReference] = [],
                supportedBoundaryContinuityLevels: [SurfaceBoundaryContinuityLevel] = [],
                supportsBoundaryContinuityMatching: Bool,
                unsupportedReason: String? = nil
            ) {
                self.index = index
                self.role = role
                self.persistentName = persistentName
                self.selectionReference = selectionReference
                self.startParameter = startParameter
                self.endParameter = endParameter
                self.parameterCurve = parameterCurve
                self.parameterCurveControlPoints = parameterCurveControlPoints
                self.boundaryDirection = boundaryDirection
                self.inwardDirection = inwardDirection
                self.boundaryControlPointReferences = boundaryControlPointReferences
                self.firstInwardControlPointReferences = firstInwardControlPointReferences
                self.secondInwardControlPointReferences = secondInwardControlPointReferences
                self.supportedBoundaryContinuityLevels = supportedBoundaryContinuityLevels
                self.supportsBoundaryContinuityMatching = supportsBoundaryContinuityMatching
                self.unsupportedReason = unsupportedReason
            }
        }

        public var role: String
        public var parameterAddresses: [ParameterAddress]
        public var sourceVertexIndices: [Int]
        public var edgePersistentNames: [String]
        public var selectionReferences: [SelectionReference]
        public var edges: [Edge]

        public init(
            role: String,
            parameterAddresses: [ParameterAddress],
            sourceVertexIndices: [Int],
            edgePersistentNames: [String],
            selectionReferences: [SelectionReference] = [],
            edges: [Edge] = []
        ) {
            self.role = role
            self.parameterAddresses = parameterAddresses
            self.sourceVertexIndices = sourceVertexIndices
            self.edgePersistentNames = edgePersistentNames
            self.selectionReferences = selectionReferences
            self.edges = edges
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
        public var controlPoints: [ControlPoint]
        public var trimLoops: [TrimLoop]
        public var frameSamples: [FrameSample]
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
            controlPoints: [ControlPoint] = [],
            trimLoops: [TrimLoop],
            frameSamples: [FrameSample] = [],
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
            self.controlPoints = controlPoints
            self.trimLoops = trimLoops
            self.frameSamples = frameSamples
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
